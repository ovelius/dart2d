import 'package:dart2d/net/network.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/util/util.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:convert';
import 'dart:math';
import 'dart:core';
import 'helpers.dart';

class ConnectionWrapper {
  static bool THROW_SEND_ERRORS_FOR_TEST = false;
  final Logger log = new Logger('Connection');
  // How many keyframes the connection can be behind before it is dropped.
  static const int ALLOWED_KEYFRAMES_BEHIND = 5 ~/ KEY_FRAME_DEFAULT;

  Network _network;
  ConfigParams _configParams;
  HudMessages _hudMessages;
  LeakyBucket? _ingressLimit = null;
  LeakyBucket? _egressLimit = null;
  PacketListenerBindings _packetListenerBindings;
  final String id;
  var _dataChannel;
  var _rtcConnection;
  int _sendFailures = 0;
  // True if connection was successfully opened.
  bool _opened = false;
  bool closed = false;
  bool _initialPingSent = false;
  bool _initialPongReceived = false;
  bool _handshakeReceived = false;
  // The last keyframe we successfully received from our peer.
  int lastRemoteKeyFrame = 0;
  DateTime? _lastRemoteKeyFrameTime = null;
  // The last keyframe the peer said it received from us.
  int lastDeliveredKeyFrame = 0;
  DateTime? _keyFrameIncrementLatencyTime = null;

  late ConnectionStats _connectionStats;
  late ReliableHelper _reliableHelper;
  ConnectionFrameHandler _connectionFrameHandler;

  // Buffered sprite removals.
  List<int> _removals = [];

  ConnectionWrapper(this._network, this._hudMessages, this.id,
      this._packetListenerBindings, this._configParams,
      this._connectionFrameHandler) {
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

  int currentKeyFrame() => _connectionFrameHandler.currentKeyFrame();

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
    _opened = true;
    _connectionStats.open();
  }

  void connectToGame(String playerName, int playerSpriteId) {
    // Send out local data hello. We don't do this as part of the intial handshake but over
    // the actual connection.
    Map playerData = {
      CLIENT_PLAYER_SPEC: [playerName, playerSpriteId],
      KEY_FRAME_KEY: lastRemoteKeyFrame,
      IS_KEY_FRAME_KEY: _connectionFrameHandler.currentKeyFrame(),
    };
    sendData(playerData);
  }

  /**
   * Send command to enter game.
   */
  void sendClientEnter() {
    sendData({
      CLIENT_PLAYER_ENTER: new DateTime.now().millisecondsSinceEpoch,
      IS_KEY_FRAME_KEY: _connectionFrameHandler.currentKeyFrame(),
    });
  }

  /**
    * Send command to enter game.
    */
  void sendCommandTransfer() {
    sendData(
        {TRANSFER_COMMAND: 'y', IS_KEY_FRAME_KEY: _connectionFrameHandler.currentKeyFrame()});
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
      IS_KEY_FRAME_KEY: _connectionFrameHandler.currentKeyFrame(),
    });
  }

  bool lastReceiveActivityOlderThan(int millis) {
    return _connectionStats.lastReceiveTime.millisecondsSinceEpoch < millis;
  }

  bool lastSendActivityOlderThan(int millis) {
    return _connectionStats.lastSendTime.millisecondsSinceEpoch < millis;
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
    lastDeliveredKeyFrame = _connectionFrameHandler.currentKeyFrame();
  }

  void error(error) {
    _hudMessages.display("Connection ${id}: ${error} closing!");
    closed = true;
  }

  Random r = new Random();

  void receiveData(data) {
    if (_ingressLimit?.removeTokens(data.length) == true) {
      log.fine("Dropping due to ingress bandwidth limitation");
      return;
    }
      DateTime now = new DateTime.now();
    _connectionStats.lastReceiveTime = now;
    _connectionStats.rxBytes += data.length as int;
    Map<String, dynamic> dataMap = jsonDecode(data);
    assert(dataMap.containsKey(KEY_FRAME_KEY));
    if (Logger.root.isLoggable(Level.FINE)) {
      log.fine("${id} -> ${_network.getPeer().getId()} data ${data}");
    }
    // Tickle connection with some data in case it's about to go cold.
    if (_connectionStats.keepAlive()) {
      sendPing();
    }

    bool oldData = false;
    if (dataMap[KEY_FRAME_KEY] > lastDeliveredKeyFrame) {
      lastDeliveredKeyFrame = dataMap[KEY_FRAME_KEY];
    } else if (dataMap[KEY_FRAME_KEY] < lastDeliveredKeyFrame) {
      oldData = true;
    }

    // Fast return piNG messages.
    if (dataMap.containsKey(PING)) {
      Map data = {PONG: dataMap[PING]};
      if (_network.isCommander()) {
        data[GAME_STATE] = _network.gameState.toMap();
      }
      sendData(data);
    }
    if (dataMap.containsKey(PONG)) {
      num latencyMillis = now.millisecondsSinceEpoch - dataMap[PONG];
      sampleLatency(new Duration(milliseconds: latencyMillis.toInt()));
      _initialPongReceived = true;
    }
    if (_keyFrameIncrementLatencyTime != null  && dataMap.containsKey(KEY_FRAME_DELAY)) {
      // How long time passed since we sent the keyframe?
      int sinceSendTime = now.millisecondsSinceEpoch - _keyFrameIncrementLatencyTime!.millisecondsSinceEpoch;
      // How long time before the sender responded?
      int waitMillis = dataMap[KEY_FRAME_DELAY];
      sampleLatency(new Duration(milliseconds: (sinceSendTime - waitMillis)));
      _keyFrameIncrementLatencyTime = null;
    }

    // New path.
    for (String key in dataMap.keys) {
      if (SPECIAL_KEYS.contains(key)) {
        if (_packetListenerBindings.hasHandler(key)) {
          for (dynamic handler in _packetListenerBindings.handlerFor(key)) {
            try {
              handler(this, dataMap[key]);
            } catch (e) {
              log.severe("Error handling data for key ${key} error: $e");
            }
          }
          // TODO remove special cases!
        } else if (!PacketListenerBindings.IgnoreListeners.contains(key)) {
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
      if (_network.getGameState().isInGame(_network.peer.id!) &&
          !_network.isCommander()) {
        // TODO figure out why this hack is needed...
        log.warning(
            "This is odd since connections is in the gamestate. Overriding!");
        _handshakeReceived = true;
      } else {
        return;
      }
    }

    if (!oldData) {
      _network.parseBundle(this, dataMap);
    }
  }

  void checkIfShouldClose(int keyFrame) {
    if (keyFramesBehind() > ALLOWED_KEYFRAMES_BEHIND) {
      log.warning(
          "Connection to $id too many keyframes behind current: ${keyFrame} connection:${lastDeliveredKeyFrame}, dropping");
      close("Not responding");
      return;
    }
  }

  /**
   * Advance connection time. Maybe send data. Maybe send keyframe.
   */
  void tick(double duration, Map frameData, Map keyFrameData, List<int> removals) {
    Map data = frameData;
    _removals.addAll(removals);
    if (!_connectionFrameHandler.tick(duration)) {
      // Don't send any data this tick.
      return;
    }
    if (_connectionFrameHandler.keyFrame()) {
      // Send keyframe data.
      data = keyFrameData;
      if (data.isEmpty) {
        _network.stateBundle(true, data, _removals);
      }
      data[IS_KEY_FRAME_KEY] = _connectionFrameHandler.currentKeyFrame();
      // Maybe adjust connection framerate.
      _connectionFrameHandler.reportConnectionMetrics(keyFramesBehind(),
          _connectionStats.latency.inMilliseconds);
    } else if(data.isEmpty) {
      // Send regular data.
      _network.stateBundle(false, data, _removals);
    }

    if (!_handshakeReceived && !_connectionFrameHandler.keyFrame()) {
      // Don't send delta updates if not a valid game connection.
      return;
    }
    // Reset removals buffer.
    _removals = [];
    sendData(data);
  }
  void sendData(Map data) {
    if (_reliableHelper.reliableBufferOverFlow()) {
      log.warning(
          "Connection to $id too many reliable packets behind ${_reliableHelper.reliableDataBuffer.length}, dropping!");
      close("Reliable overflow");
      return;
    }
    if (_connectionStats.ReceiveTimeout()) {
      log.warning(
          "Connection to $id not responsive, dropping!");
      close("Not responding receive timeout");
    }

    DateTime now = new DateTime.now();
    _connectionStats.lastSendTime = now;
    _reliableHelper.updateWithDataReceipts(data);

    if (_lastRemoteKeyFrameTime != null) {
      int millis = now.millisecondsSinceEpoch - _lastRemoteKeyFrameTime!.millisecondsSinceEpoch;
      data[KEY_FRAME_DELAY] = millis;
      _lastRemoteKeyFrameTime = null;
    }
    if (data.containsKey(IS_KEY_FRAME_KEY)) {
      // The keyframe is incremented.
      if (data[IS_KEY_FRAME_KEY] > lastDeliveredKeyFrame) {
        if (_keyFrameIncrementLatencyTime == null) {
          _keyFrameIncrementLatencyTime = new DateTime.now();
        }
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
    String jsonData = jsonEncode(data);


    if (_egressLimit?.removeTokens(jsonData.length) == true) {
      log.fine("Dropping due to egress bandswith limitation");
      return;
    }
    _connectionStats.txBytes += jsonData.length;
    try {
      if (Logger.root.isLoggable(Level.FINE)) {
        log.fine("${id} -> ${_network.getPeer().getId()} data ${data}");
      }
      _dataChannel.send(jsonData);
      _sendFailures = 0;
    } catch (e, _) {
      if (THROW_SEND_ERRORS_FOR_TEST) {
        throw "Failed to send data ${this._network.peer.id} -> ${this.id} $jsonData \nerror: $e";
      }
      if (++_sendFailures > 2) {
        log.severe("Failed to send to $id: $e, closing connection");
        close("Failed to send data");
      }
    }
  }

  void readyDataChannel(var dataChannel) {
    _dataChannel = dataChannel;
  }

  bool hasReadyDataChannel() => _dataChannel != null;

  void setRtcConnection(var rtcConnection) {
    _rtcConnection = rtcConnection;
  }

  int keyFramesBehind() {
    return _connectionFrameHandler.currentKeyFrame() - lastDeliveredKeyFrame;
  }

  bool isActiveConnection() {
    return _opened && !closed && _dataChannel != null && _rtcConnection != null;
  }

  bool wasOpen() => _opened;

  bool isClosedConnection() {
    if (closed) {
      return true;
    }
    // Timed out waiting to become open.
    if (!_opened && _connectionStats.OpenTimeout()) {
      return true;
    }

    return _connectionStats.ReceiveTimeout();
  }

  bool isValidGameConnection() {
    return !isClosedConnection() && this._handshakeReceived;
  }

  void sampleLatency(Duration latency) {
    if (latency.inMilliseconds < 0) {
      log.warning("None positive latency of $latency ignored");
      return;
    }
    this._connectionStats.latency = latency;
  }

  Duration expectedLatency() => _connectionStats.latency;

  ReliableHelper reliableHelper() => _reliableHelper;

  dynamic rtcConnection() => _rtcConnection;

  int currentFrameRate() => _connectionFrameHandler.currentFrameRate();

  toString() => "Connection to ${id} FR:${_connectionFrameHandler.currentFrameRate()} ms:${_connectionStats.latency}  GC: ${isValidGameConnection()} pi/Po ${_initialPingSent}/${_initialPongReceived}";

  String stats() => _connectionStats.stats();
}
