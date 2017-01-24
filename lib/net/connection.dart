import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/util/gamestate.dart';
import 'package:dart2d/net/network.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/util/hud_messages.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'dart:convert';
import 'package:di/di.dart';
import 'dart:core';

@Deprecated(
    "Connections types are irellevant, only in game and command role is relevant")
enum ConnectionType {
  BOOTSTRAP, // No game yet initialized for connection.
  // This is a connection to a server.
  CLIENT_TO_SERVER,
  // This is a connection to a client.
  SERVER_TO_CLIENT,
  // This is a connection between clients.
  CLIENT_TO_CLIENT,
}

@Injectable()
class PacketListenerBindings {
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

class ConnectionWrapper {
  final Logger log = new Logger('Connection');
  // How many keyframes the connection can be behind before it is dropped.
  static int ALLOWED_KEYFRAMES_BEHIND = 5 ~/ KEY_FRAME_DEFAULT;
  // How long until connection attempt times out.
  static const Duration DEFAULT_TIMEOUT = const Duration(seconds: 6);

  ConnectionType _connectionType;
  Network _network;
  HudMessages _hudMessages;
  PacketListenerBindings _packetListenerBindings;
  final String id;
  var connection;
  // True if connection was successfully opened.
  bool opened = false;
  bool closed = false;
  bool _initialPingSent = false;
  bool _initialPongReceived = false;
  bool _handshakeReceived = false;
  // The last keyframe we successfully received from our peer.
  int lastKeyFrameFromPeer = 0;
  // The last keyframe the peer said it received from us.
  int lastLocalPeerKeyFrameVerified = 0;
  // How many keyframes our remote part has not verified on time.
  int droppedKeyFrames = 0;
  // Storage of our reliable key data.
  Map keyFrameData = {};
  // Keep track of how long connection has been open.
  Stopwatch _connectionTimer = new Stopwatch();
  // When we time out.
  Duration _timeout;
  // The monitored latency of the connection.
  Duration _latency = DEFAULT_TIMEOUT;

  ConnectionWrapper(
      this._network,
      this._hudMessages,
      this.id,
      this.connection,
      this._connectionType,
      this._packetListenerBindings,
      JsCallbacksWrapper peerWrapperCallbacks,
      [timeout = DEFAULT_TIMEOUT]) {
    assert(id != null);
    // Client to client connections to not need to shake hands :)
    // Server knows about both clients anyway.
    // Changing handshakeReceived should be the first assignment in the constructor.
    if (_connectionType == ConnectionType.CLIENT_TO_CLIENT) {
      print("Client connection marking as handshake received");
      this._handshakeReceived = true;
      // Mark connection as having recieved our keyframes up to this point.
      // This is required since CLIENT_TO_CLIENT connections do not do a handshake.
      lastLocalPeerKeyFrameVerified = _network.currentKeyFrame;
    }
    peerWrapperCallbacks
      ..bindOnFunction(connection, 'data', receiveData)
      ..bindOnFunction(connection, 'close', close)
      ..bindOnFunction(connection, 'open', open)
      ..bindOnFunction(connection, 'error', error);
    // Start the connection timer.
    _connectionTimer.start();
    _timeout = timeout;
    log.fine("Opened connection to $id of type ${_connectionType}");
  }

  bool hasReceivedFirstKeyFrame(Map dataMap) {
    if (dataMap.containsKey(IS_KEY_FRAME_KEY)) {
      lastKeyFrameFromPeer = dataMap[IS_KEY_FRAME_KEY];
    }
    // The server does not need to wait for keyframes.
    return lastKeyFrameFromPeer > 0 || _network.isCommander();
  }

  void verifyLastKeyFrameHasBeenReceived(Map dataMap) {
    int receivedKeyFrameAck = dataMap[KEY_FRAME_KEY];
    if (receivedKeyFrameAck > lastLocalPeerKeyFrameVerified) {
      // Cool we just got some reliable data verified :)
      lastLocalPeerKeyFrameVerified = receivedKeyFrameAck;
      keyFrameData = {};
    }
  }

  void updateConnectionType(ConnectionType type) {
    if (type == ConnectionType.CLIENT_TO_CLIENT) {
      print("update connection type set handshake boom       ${StackTrace.current.toString()}");
      _handshakeReceived = true;
    }
    this._connectionType = type;
  }

  void close(unusedThis) {
    _hudMessages.display("Connection to ${id} closed :(");
    closed = true;
  }

  void open(unusedThis) {
    _hudMessages.display("Connection to ${id} open :)");
    // Set the connection to current keyframe.
    // A faulty connection will be dropped quite fast if it lags behind in keyframes.
    lastLocalPeerKeyFrameVerified = _network.currentKeyFrame;
    opened = true;
    _connectionTimer.stop();
  }

  void connectToGame() {
    // Send out local data hello. We don't do this as part of the intial handshake but over
    // the actual connection.
    Map playerData = {
      CLIENT_PLAYER_SPEC: _network.localPlayerName,
      KEY_FRAME_KEY: lastKeyFrameFromPeer,
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
    print("set recieved hs");
    _handshakeReceived = true;
  }

  void error(unusedThis, error) {
    _hudMessages.display("Connection ${id}: ${error}");
    closed = true;
  }

  Set<String> _ignoreListeners = new Set.from([
    IS_KEY_FRAME_KEY,
    KEY_FRAME_KEY,
    PING,
    PONG,
  ]);

  void receiveData(unusedThis, data) {
    Map dataMap = JSON.decode(data);
    assert(dataMap.containsKey(KEY_FRAME_KEY));
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

    // New path.
    for (String key in dataMap.keys) {
      if (SPECIAL_KEYS.contains(key)) {
        if (_packetListenerBindings.hasHandler(key)) {
          for (dynamic handler in _packetListenerBindings.handlerFor(key)) {
            handler(this, dataMap[key]);
          }
          // TODO remove special cases!
        } else if (!_ignoreListeners.contains(key)) {
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
      return;
    }
    _network.parseBundle(this, dataMap);
  }

  void alsoSendWithStoredData(var data) {
    for (String key in RELIABLE_KEYS.keys) {
      // Use the merge function specified to merge any previosly stored data
      // with the data being sent in this frame.
      var mergedData = RELIABLE_KEYS[key](data[key], keyFrameData[key]);
      if (mergedData != null) {
        data[key] = mergedData;
        keyFrameData[key] = mergedData;
      }
    }
  }

  void storeAwayReliableData(var data) {
    RELIABLE_KEYS.keys.forEach((String reliableKey) {
      if (data.containsKey(reliableKey)) {
        var mergedData = RELIABLE_KEYS[reliableKey](
            data[reliableKey], keyFrameData[reliableKey]);
        if (mergedData != null) {
          keyFrameData[reliableKey] = mergedData;
        }
      }
    });
  }

  void checkIfShouldClose(int keyFrame) {
    if (keyFramesBehind(keyFrame) > ALLOWED_KEYFRAMES_BEHIND) {
      log.warning(
          "Connection to $id too many keyframes behind current: ${keyFrame} connection:${lastLocalPeerKeyFrameVerified}, dropping");
      close(null);
      return;
    }
  }

  void sendData(Map data) {
    data[KEY_FRAME_KEY] = lastKeyFrameFromPeer;
    if (data.containsKey(IS_KEY_FRAME_KEY)) {
      // Check how many keyframes the remote peer is currenlty behind.
      // We might decide to close the connection because of this.
      checkIfShouldClose(data[IS_KEY_FRAME_KEY]);
      // Make a defensive copy in case of keyframe.
      // Then add previous data to it.
      data = new Map.from(data);
      alsoSendWithStoredData(data);
    } else {
      // Store away any reliable data sent.
      storeAwayReliableData(data);
    }
    var jsonData = JSON.encode(data);
    connection.callMethod('send', [jsonData]);
  }

  void registerDroppedKeyFrames(int expectedKeyFrame) {
    droppedKeyFrames += keyFramesBehind(expectedKeyFrame);
  }

  int keyFramesBehind(int expectedKeyFrame) {
    return expectedKeyFrame - lastLocalPeerKeyFrameVerified;
  }

  Duration sinceCreated() {
    return new Duration(milliseconds: _connectionTimer.elapsedMilliseconds);
  }

  bool _timedOut() {
    return sinceCreated().compareTo(_timeout) > 0;
  }

  bool isActiveConnection() {
    return opened && !closed;
  }

  bool isValidConnection() {
    if (closed) {
      return false;
    }
    // Timed out waiting to become open.
    if (!opened && _timedOut()) {
      return false;
    }

    return true;
  }

  bool isValidGameConnection() {
    return this.isValidConnection() && this._handshakeReceived;
  }

  void sampleLatency(Duration latency) {
    assert(latency.inMilliseconds >= 0);
    this._latency = latency;
  }

  Duration expectedLatency() => _latency;
  ConnectionType getConnectionType() => _connectionType;

  toString() => "${_connectionType} to ${id} latency ${_latency}";
}
