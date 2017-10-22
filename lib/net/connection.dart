import 'package:dart2d/net/network.dart';
import 'package:dart2d/util/util.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/net/state_updates.dart';
import 'dart:convert';
import 'dart:math';
import 'package:di/di.dart';
import 'dart:core';

@Injectable()
class PacketListenerBindings {

  static Set<String> _ignoreListeners = new Set.from([
    IS_KEY_FRAME_KEY,
    KEY_FRAME_KEY,
    DATA_RECEIPTS,
    CONTAINED_DATA_RECEIPTS,
    PING,
    PONG,
    KEY_FRAME_DELAY,
  ]);

  Map<String, List<dynamic>> _handlers = {};

  bindHandler(String key, dynamic handler) {
    if (!_handlers.containsKey(key)) {
      _handlers[key] = [];
    }
    _handlers[key].add(handler);
  }

  List<dynamic> handlerFor(String key) {
    assert(_handlers.containsKey(key));
    return _handlers[key];
  }

  // Transition method. Eventually there will be handler everywhere.
  bool hasHandler(String key) {
    return _handlers.containsKey(key);
  }
}

class ConnectionStats {
  // How long until connection attempt times out.
  static const Duration OPEN_TIMEOUT = const Duration(seconds: 6);

  int rxBytes = 0;
  int txBytes = 0;
  // Keep track of how long connection has been open.
  Stopwatch _connectionOpenTimer = new Stopwatch();
  // The monitored latency of the connection.
  Duration _latency = OPEN_TIMEOUT;

  ConnectionStats() {
    _connectionOpenTimer.start();
  }

  bool OpenTimeout() {
    return _connectionOpenTimer.elapsedMilliseconds > ConnectionStats.OPEN_TIMEOUT.inMilliseconds;
  }

  String stats() => "rx/tx: ${formatBytes(rxBytes)}/${formatBytes(txBytes)}";
}

class ReliableHelper {
  // How many items the reliable buffer can contain before we consider the connection dead.
  static const int MAX_RELIABLE_BUFFER_SIZE = 80;
  PacketListenerBindings _packetListenerBindings;
  // Storage of our reliable key data.
  Map reliableDataBuffer = {};
  // Reliable verifications.
  List<int> reliableDataToVerify = [];

  ReliableHelper(this._packetListenerBindings) {
    _packetListenerBindings.bindHandler(CONTAINED_DATA_RECEIPTS, (ConnectionWrapper c, List data) {
      reliableDataToVerify.addAll(data);
    });
    _packetListenerBindings.bindHandler(DATA_RECEIPTS, (ConnectionWrapper c, List data) {
      for (int receipt in data) {
        reliableDataBuffer.remove(receipt);
      }
    });
  }

  bool reliableBufferOverFlow() => reliableDataBuffer.length > MAX_RELIABLE_BUFFER_SIZE;

  /**
   * Append any previously received data receipts before sending.
   */
  void updateWithDataReceipts(Map data) {
    if (reliableDataToVerify.isNotEmpty) {
      data[DATA_RECEIPTS] = reliableDataToVerify;
      reliableDataToVerify = [];
    }
  }

  /**
   * Maybe add reliable data that needs to be resent.
   */
  void alsoSendWithStoredData(Map dataMap) {
    storeAwayReliableData(dataMap);
    for (int hash in new List.from(reliableDataBuffer.keys)) {
      List tuple = reliableDataBuffer[hash];
      String reliableKey = tuple[0];
      // There is more data of the same type. Merge.
      if (dataMap.containsKey(reliableKey)) {
        // Merge data with previously saved data for this key.
        dynamic mergeFunction = RELIABLE_KEYS[reliableKey];
        dataMap[reliableKey] = mergeFunction(dataMap[reliableKey], tuple[1]);
        _addContainedReceipt(dataMap, hash);
      } else {
        dataMap[reliableKey] = tuple[1];
        _addContainedReceipt(dataMap, hash);
      }
    }
  }

  void _addContainedReceipt(Map dataMap, int receipt) {
    if (dataMap[CONTAINED_DATA_RECEIPTS] == null) {
      dataMap[CONTAINED_DATA_RECEIPTS] = [];
    }
    if (!dataMap[CONTAINED_DATA_RECEIPTS].contains(receipt)) {
      dataMap[CONTAINED_DATA_RECEIPTS].add(receipt);
    }
  }

  /**
   * Take data considered reliable and store away in case we need to resend.
   */
  void storeAwayReliableData(Map dataMap) {
    for (String reliableKey in RELIABLE_KEYS.keys) {
      if (dataMap.containsKey(reliableKey)) {
        Object data = dataMap[reliableKey];
        int jsonHash = JSON.encode(data).hashCode;
        reliableDataBuffer[jsonHash] = [reliableKey, data];
        _addContainedReceipt(dataMap, jsonHash);
      }
    }
  }
}

class ConnectionWrapper {
  final Logger log = new Logger('Connection');
  // How many keyframes the connection can be behind before it is dropped.
  static const int ALLOWED_KEYFRAMES_BEHIND = 5 ~/ KEY_FRAME_DEFAULT;

  Network _network;
  ConfigParams _configParams;
  HudMessages _hudMessages;
  LeakyBucket _ingressLimit;
  LeakyBucket _egressLimit;
  PacketListenerBindings _packetListenerBindings;
  final String id;
  var _dataChannel;
  var _rtcConnection;
  // True if connection was successfully opened.
  bool _opened = false;
  bool closed = false;
  bool _initialPingSent = false;
  bool _initialPongReceived = false;
  bool _handshakeReceived = false;
  // The last keyframe we successfully received from our peer.
  int lastRemoteKeyFrame = 0;
  DateTime _lastRemoteKeyFrameTime = null;
  // The last keyframe the peer said it received from us.
  int lastDeliveredKeyFrame = 0;
  DateTime _keyFrameIncrementTime = null;
  // How many keyframes our remote part has not verified on time.
  int droppedKeyFrames = 0;
  ConnectionStats _connectionStats;
  ReliableHelper _reliableHelper;

  ConnectionWrapper(this._network, this._hudMessages, this.id,
      this._packetListenerBindings, this._configParams) {
    assert(id != null);
    _connectionStats = new ConnectionStats();
    _reliableHelper = new ReliableHelper(_packetListenerBindings);
    // Start the connection timer.
    if (_configParams.getInt(ConfigParam.INGRESS_BANDWIDTH) > 0) {
      _ingressLimit = new LeakyBucket(
          _configParams.getInt(ConfigParam.INGRESS_BANDWIDTH));
      log.info("Limit ingress bandwidth to ${_configParams.getInt(ConfigParam.INGRESS_BANDWIDTH)  / 1000 } ~kB/s");
    }
    if (_configParams.getInt(ConfigParam.EGRESS_BANDWIDTH) > 0) {
      _egressLimit = new LeakyBucket(
          _configParams.getInt(ConfigParam.EGRESS_BANDWIDTH));
      log.info("Limit egress bandwidth to ${_configParams.getInt(ConfigParam.EGRESS_BANDWIDTH)  / 1000 } ~kB/s");
    }
    log.fine("Opened connection to $id");
  }

  bool hasReceivedFirstKeyFrame(Map dataMap) {
    if (dataMap.containsKey(IS_KEY_FRAME_KEY)) {
      if (dataMap[IS_KEY_FRAME_KEY] > lastRemoteKeyFrame) {
        lastRemoteKeyFrame = dataMap[IS_KEY_FRAME_KEY];
        _lastRemoteKeyFrameTime = new DateTime.now();
      }
    }
    // The server does not need to wait for keyframes.
    return lastRemoteKeyFrame > 0 || _network.isCommander();
  }

  void verifyLastKeyFrameHasBeenReceived(Map dataMap) {
    int receivedKeyFrameAck = dataMap[KEY_FRAME_KEY];
    if (receivedKeyFrameAck > lastDeliveredKeyFrame) {
      lastDeliveredKeyFrame = receivedKeyFrameAck;

    }
  }

  void close(String reason) {
    if (!closed) {
      _hudMessages.display("Connection to ${id} closed: $reason");
    }
    log.info("Closed connection to ${id} reason: ${reason}");
    closed = true;
  }

  void open() {
    _hudMessages.display("Connection to ${id} open :)");
    // Set the connection to current keyframe.
    // A faulty connection will be dropped quite fast if it lags behind in keyframes.
    lastDeliveredKeyFrame = _network.currentKeyFrame;
    _opened = true;
    _connectionStats._connectionOpenTimer.stop();
  }

  void connectToGame(String playerName, int playerSpriteId) {
    // Send out local data hello. We don't do this as part of the intial handshake but over
    // the actual connection.
    Map playerData = {
      CLIENT_PLAYER_SPEC: [playerName, playerSpriteId],
      KEY_FRAME_KEY: lastRemoteKeyFrame,
      IS_KEY_FRAME_KEY: _network.currentKeyFrame,
    };
    sendData(playerData);
  }

  /**
   * Send command to enter game.
   */
  void sendClientEnter() {
    sendData({
      CLIENT_PLAYER_ENTER: new DateTime.now().millisecondsSinceEpoch,
      IS_KEY_FRAME_KEY: _network.currentKeyFrame
    });
  }

  /**
    * Send command to enter game.
    */
  void sendCommandTransfer() {
    sendData(
        {TRANSFER_COMMAND: 'y', IS_KEY_FRAME_KEY: _network.currentKeyFrame});
  }

  /**
   * Send ping message with metadata about the connection.
   */
  void sendPing([bool gameStatePing = false]) {
    if (gameStatePing) {
      _initialPingSent = true;
      _initialPongReceived = false;
    }
    sendData({
      PING: new DateTime.now().millisecondsSinceEpoch,
      IS_KEY_FRAME_KEY: _network.currentKeyFrame
    });
  }

  bool initialPongReceived() => _initialPongReceived;
  bool initialPingSent() => _initialPingSent;

  void setHandshakeReceived() {
    _handshakeReceived = true;
  }

  void resetHandshakeReceived() {
    _handshakeReceived = false;
  }

  /**
   * Client to client connections to not need to shake hands :)
   * Server knows about both clients anyway.
   * Mark connection as having recieved our keyframes up to this point.
   * This is required since CLIENT_TO_CLIENT connections do not do a handshake.
   */
  void markAsClientToClientConnection() {
    setHandshakeReceived();
    lastDeliveredKeyFrame = _network.currentKeyFrame;
  }

  void error(error) {
    _hudMessages.display("Connection ${id}: ${error} closing!");
    closed = true;
  }

  Random r = new Random();

  void receiveData(data) {
    if (_ingressLimit != null) {
      if (!_ingressLimit.removeTokens(data.length)) {
        log.fine("Dropping due to ingress bandswith limitation");
        return;
      }
    }
    _connectionStats.rxBytes += data.length;
    Map dataMap = JSON.decode(data);
    assert(dataMap.containsKey(KEY_FRAME_KEY));
    if (Logger.root.isLoggable(Level.FINE)) {
      log.fine("${id} -> ${_network.getPeer().getId()} data ${data}");
    }
    verifyLastKeyFrameHasBeenReceived(dataMap);

    // Fast return PING messages.
    if (dataMap.containsKey(PING)) {
      Map data = {PONG: dataMap[PING]};
      if (_network.isCommander()) {
        data[GAME_STATE] = _network.gameState.toMap();
      }
      sendData(data);
    }
    if (dataMap.containsKey(PONG)) {
      DateTime now = new DateTime.now();
      int latencyMillis = now.millisecondsSinceEpoch - dataMap[PONG];
      sampleLatency(new Duration(milliseconds: latencyMillis));
      _initialPongReceived = true;
    }
    if (_keyFrameIncrementTime != null && dataMap.containsKey(KEY_FRAME_DELAY)) {
      DateTime now = new DateTime.now();
      // How long time passed since we sent the keyframe?
      int sinceSendTime = now.millisecondsSinceEpoch - _keyFrameIncrementTime.millisecondsSinceEpoch;
      // How long time before the sender responded?
      int waitMillis = dataMap[KEY_FRAME_DELAY];
      sampleLatency(new Duration(milliseconds: (sinceSendTime - waitMillis)));
    }

    // New path.
    for (String key in dataMap.keys) {
      if (SPECIAL_KEYS.contains(key)) {
        if (_packetListenerBindings.hasHandler(key)) {
          for (dynamic handler in _packetListenerBindings.handlerFor(key)) {
            handler(this, dataMap[key]);
          }
          // TODO remove special cases!
        } else if (!PacketListenerBindings._ignoreListeners.contains(key)) {
          throw new ArgumentError("No bound network listener for ${key}");
        }
      }
    }

    // Wait for a first keyframe from this connection.
    if (!hasReceivedFirstKeyFrame(dataMap)) {
      return;
    }
    // Don't continue handling data if handshake is not finished.
    if (!_handshakeReceived) {
      log.fine("not handling data ${dataMap}, handshake not received.");
      if (_network.getGameState().isInGame(_network.peer.id) &&
          _network.getGameState().playerInfoByConnectionId(this.id) != null &&
          !_network.isCommander()) {
        // TODO figure out why this hack is needed...
        log.warning(
            "This is odd since connections is in the gamestate. Overriding!");
        _handshakeReceived = true;
      } else {
        return;
      }
    }
    _network.parseBundle(this, dataMap);
  }

  void checkIfShouldClose(int keyFrame) {
    if (keyFramesBehind(keyFrame) > ALLOWED_KEYFRAMES_BEHIND) {
      log.warning(
          "Connection to $id too many keyframes behind current: ${keyFrame} connection:${lastDeliveredKeyFrame}, dropping");
      close("Not responding");
      return;
    }
  }

  void sendData(Map data) {
    if (_reliableHelper.reliableBufferOverFlow()) {
      log.warning(
          "Connection to $id too many reliable packets behind ${_reliableHelper.reliableDataBuffer.length}, dropping!");
      close("Not responding");
      return;
    }

    _reliableHelper.updateWithDataReceipts(data);

    if (_lastRemoteKeyFrameTime != null) {
      DateTime now = new DateTime.now();
      int millis = now.millisecondsSinceEpoch - _lastRemoteKeyFrameTime.millisecondsSinceEpoch;
      data[KEY_FRAME_DELAY] = millis;
      _lastRemoteKeyFrameTime = null;
    }
    if (data.containsKey(IS_KEY_FRAME_KEY)) {
      if (data[IS_KEY_FRAME_KEY] > lastDeliveredKeyFrame) {
        _keyFrameIncrementTime = new DateTime.now();
      }
    }
    assert(_dataChannel != null);
    data[KEY_FRAME_KEY] = lastRemoteKeyFrame;
    if (data.containsKey(IS_KEY_FRAME_KEY)) {
      // Check how many keyframes the remote peer is currenlty behind.
      // We might decide to close the connection because of this.
      checkIfShouldClose(data[IS_KEY_FRAME_KEY]);
      // Make a defensive copy in case of keyframe.
      // Then add previous data to it.
      data = new Map.from(data);
      _reliableHelper.alsoSendWithStoredData(data);
    } else {
      // Store away any reliable data sent.
      _reliableHelper.storeAwayReliableData(data);
    }
    String jsonData = JSON.encode(data);

    if (_egressLimit != null) {
      if (!_egressLimit.removeTokens(jsonData.length)) {
        log.fine("Dropping due to egress bandswith limitation");
        return;
      }
    }
    _connectionStats.txBytes += jsonData.length;
    try {
      if (Logger.root.isLoggable(Level.FINE)) {
        log.fine("${id} -> ${_network.getPeer().getId()} data ${data}");
      }
      _dataChannel.sendString(jsonData);
    } catch (e, _) {
      log.severe("Failed to send to $id: $e, closing connection");
      close("Failed to send data");
    }
  }

  void readyDataChannel(var dataChannel) {
    _dataChannel = dataChannel;
  }

  bool hasReadyDataChannel() => _dataChannel != null;

  void setRtcConnection(var rtcConnection) {
    _rtcConnection = rtcConnection;
  }

  void registerDroppedKeyFrames(int expectedKeyFrame) {
    droppedKeyFrames += keyFramesBehind(expectedKeyFrame);
  }

  int keyFramesBehind(int expectedKeyFrame) {
    return expectedKeyFrame - lastDeliveredKeyFrame;
  }

  bool isActiveConnection() {
    return _opened && !closed && _dataChannel != null && _rtcConnection != null;
  }

  bool wasOpen() => _opened;

  bool isValidConnection() {
    if (closed) {
      return false;
    }
    // Timed out waiting to become open.
    if (!_opened && _connectionStats.OpenTimeout()) {
      return false;
    }

    return true;
  }

  bool isValidGameConnection() {
    return this.isValidConnection() && this._handshakeReceived;
  }

  void sampleLatency(Duration latency) {
    if (latency.inMilliseconds < 0) {
      log.warning("None positive latency of $latency ignored");
      return;
    }
    this._connectionStats._latency = latency;
  }

  Duration expectedLatency() => _connectionStats._latency;

  ReliableHelper reliableHelper() => _reliableHelper;

  dynamic rtcConnection() => _rtcConnection;

  toString() => "Connection to ${id} latency ${_connectionStats._latency}";

  String stats() => _connectionStats.stats();
}

class LeakyBucket {
  int _fillRatePerMillis;
  int _tokenBuffer;

  DateTime _lastCall;

  LeakyBucket(this._fillRatePerMillis, [int startBuffer]) {
    _tokenBuffer = _fillRatePerMillis;
    if (startBuffer != null) {
      _tokenBuffer = startBuffer;
    }
    _lastCall = new DateTime.now();
  }

  bool removeTokens(int tokens) {
    DateTime now = new DateTime.now();
    int durationMillis =
        (now.millisecondsSinceEpoch - _lastCall.millisecondsSinceEpoch);
    _lastCall = now;

    _tokenBuffer += (_fillRatePerMillis  * durationMillis).toInt();
    // Max out to one second of buffer.
    _tokenBuffer = min(_fillRatePerMillis * 1000, _tokenBuffer);

    if (_tokenBuffer < tokens) {
      return false;
    }
    _tokenBuffer -= tokens;
    return true;
  }
}
