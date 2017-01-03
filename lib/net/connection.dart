library connection;

import 'package:dart2d/keystate.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'dart:convert';
import 'dart:core';

enum ConnectionType {
  BOOTSTRAP, // No game yet initialized for connection.
  CLIENT_TO_SERVER,
  SERVER_TO_CLIENT,
  CLIENT_TO_CLIENT,
}

class ConnectionWrapper {
  // How many keyframes the connection can be behind before it is dropped.
  static int ALLOWED_KEYFRAMES_BEHIND = 5 ~/  KEY_FRAME_DEFAULT;
  // How long until connection attempt times out.
  static const Duration DEFAULT_TIMEOUT = const Duration(seconds:8);

  ConnectionType connectionType;
  WormWorld world;
  Network _network;
  HudMessages _hudMessages;
  ChunkHelper _chunkHelper;
  final String id;
  var connection;
  // True if connection was successfully opened.
  bool opened = false;
  bool closed = false;
  bool _handshakeReceived = false;
  // The last keyframe we successfully received from our peer.
  int lastKeyFrameFromPeer = 0;
  // The last keyframe the peer said it received from us.
  int lastLocalPeerKeyFrameVerified = 0;
  // How many keyframes our remote part has not verified on time.
  int droppedKeyFrames = 0; 
  // Keystate for the remote connection, will only be set if
  // the remote peer is a client.
  KeyState remoteKeyState = new KeyState(null);
  // Storage of our reliable key data.
  Map keyFrameData = {};
  // Keep track of how long connection has been open.
  Stopwatch _connectionTimer = new Stopwatch();
  // When we time out.
  Duration _timeout;
  // The monitored latency of the connection.
  Duration _latency = DEFAULT_TIMEOUT;

  ConnectionWrapper(this.world, this._network, this._hudMessages,
      this._chunkHelper, this.id, this.connection, this.connectionType,
      JsCallbacksWrapper peerWrapperCallbacks,[timeout = DEFAULT_TIMEOUT]) {
    assert(id != null);
    // Client to client connections to not need to shake hands :)
    // Server knows about both clients anyway.
    // Changing handshakeReceived should be the first assignment in the constructor.
    if (connectionType == ConnectionType.CLIENT_TO_CLIENT) {
      this._handshakeReceived = true;
      // Mark connection as having recieved our keyframes up to this point.
      // This is required since CLIENT_TO_CLIENT connections to not do a handshake.
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
  }

  bool hasReceivedFirstKeyFrame(Map dataMap) {
    if (dataMap.containsKey(IS_KEY_FRAME_KEY)) {
      lastKeyFrameFromPeer = dataMap[IS_KEY_FRAME_KEY];
    }
    // The server does not need to wait for keyframes.
    return lastKeyFrameFromPeer > 0 || _network.isServer();
  }
  
  void verifyLastKeyFrameHasBeenReceived(Map dataMap) {
    int receivedKeyFrameAck = dataMap[KEY_FRAME_KEY];
    if (receivedKeyFrameAck > lastLocalPeerKeyFrameVerified) {
      // Cool we just got some reliable data verified :)
      lastLocalPeerKeyFrameVerified = receivedKeyFrameAck;
      keyFrameData = {};
    }
  }
  
  /**
   * Covers server <-> client handshake.
   */
  void checkForHandshakeData(Map dataMap) {
    if (dataMap.containsKey(CLIENT_PLAYER_SPEC)) {
      if (_network.gameState.gameIsFull()) {
        sendData({
          SERVER_PLAYER_REJECT: 'Game full',
          KEY_FRAME_KEY: lastKeyFrameFromPeer, 
          IS_KEY_FRAME_KEY: _network.currentKeyFrame});
        // Mark as closed.
        this.closed = true;
        return;
      }
      // Consider the client CLIENT_PLAYER_SPEC as the client having seen
      // the latest keyframe.
      // It will anyway get the keyframe from our response.
      lastLocalPeerKeyFrameVerified = _network.currentKeyFrame;
      assert(connectionType == ConnectionType.SERVER_TO_CLIENT);
      String name = dataMap[CLIENT_PLAYER_SPEC];
      int spriteId = _network.gameState.getNextUsablePlayerSpriteId();
      int spriteIndex = _network.gameState.getNextUsableSpriteImage();
      PlayerInfo info = new PlayerInfo(name, id, spriteId);
      _network.gameState.playerInfo.add(info);
      assert(info.connectionId != null);
      
      LocalPlayerSprite sprite = new RemotePlayerServerSprite(
          world, remoteKeyState, info, 0.0, 0.0, spriteIndex);
      sprite.networkType =  NetworkType.REMOTE_FORWARD;
      sprite.networkId = spriteId;
      sprite.ownerId = id;
      world.addSprite(sprite);

      world.displayHudMessageAndSendToNetwork("${name} connected.");
      Map serverData = {"spriteId": spriteId, "spriteIndex": spriteIndex};
      sendData({
        SERVER_PLAYER_REPLY: serverData,
        KEY_FRAME_KEY:lastKeyFrameFromPeer, 
        IS_KEY_FRAME_KEY: _network.currentKeyFrame});

      // We don't expect any more players, disconnect the peer.
      if (_network.peer.connectedToServer() && _network.gameState.gameIsFull()) {
        _network.peer.disconnect();
      }
    }
    if (dataMap.containsKey(SERVER_PLAYER_REPLY)) {
      assert(connectionType == ConnectionType.CLIENT_TO_SERVER);
      _hudMessages.display("Got server challenge from ${id}");
      assert(!_network.isServer());
      Map receivedServerData = dataMap[SERVER_PLAYER_REPLY];
      world.createLocalClient(receivedServerData["spriteId"],
          receivedServerData["spriteIndex"]);
    }
    if (dataMap.containsKey(SERVER_PLAYER_REJECT)) {
      _hudMessages.display("Game is full :/");
      this.closed = true;
      return;
    }
    if (!_handshakeReceived) {
      _handshakeReceived = dataMap.containsKey(CLIENT_PLAYER_SPEC)
          || dataMap.containsKey(SERVER_PLAYER_REPLY);
    }
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
    assert (connectionType == ConnectionType.CLIENT_TO_SERVER);
    // Send out local data hello. We don't do this as part of the intial handshake but over
    // the actual connection.
    Map playerData = {
        CLIENT_PLAYER_SPEC: _network.localPlayerName,
        KEY_FRAME_KEY:lastKeyFrameFromPeer,
        IS_KEY_FRAME_KEY: _network.currentKeyFrame,
    };
    sendData(playerData);
  }

  /**
   * Send ping message.
   */
  void sendPing() {
    sendData(
        {PING: new DateTime.now().millisecond.toString(),
          CONNECTION_TYPE: this.connectionType.index,
          IS_KEY_FRAME_KEY: _network.currentKeyFrame});
  }

  void error(unusedThis, error) {
    print("Connection ${id}error ${error} ${opened}");
    _hudMessages.display("Connection ${id}: ${error}");
    closed = true;
  }

  void receiveData(unusedThis, data) {
    Map dataMap = JSON.decode(data);
    assert(dataMap.containsKey(KEY_FRAME_KEY));
    verifyLastKeyFrameHasBeenReceived(dataMap);
    // Fast return PING messages.
    if (dataMap.containsKey(PING)) {
      this.sendData({PONG: "y"});
      return;
    }

    // Allow sending and parsing imageData regardless of state.
    if (dataMap.containsKey(IMAGE_DATA_REQUEST)) {
      _chunkHelper.replyWithImageData(dataMap, this);
    }
    if (dataMap.containsKey(IMAGE_DATA_RESPONSE)) {
      _chunkHelper.parseImageChunkResponse(dataMap, this);
      // Request new data right away.
      _chunkHelper.requestNetworkData(
          // No time has passed.
          {this.id : this}, 0.0);
    }
    
    if (!_handshakeReceived) {
      // Try to handle the intial connection handshake.
      checkForHandshakeData(dataMap);
    }
    // Wait for a first keyframe from this connection.
    if (!hasReceivedFirstKeyFrame(dataMap)) {
      return;
    }
    // Don't continue handling data if handshake is not finished.
    if (!_handshakeReceived) {
      return;
    }
    // We got a remote key state.
    if (dataMap.containsKey(KEY_STATE_KEY)) {
      remoteKeyState.setEnabledKeys(dataMap[KEY_STATE_KEY]);
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
        var mergedData = RELIABLE_KEYS[reliableKey](data[reliableKey], keyFrameData[reliableKey]);
        if (mergedData != null) {
          keyFrameData[reliableKey] = mergedData;
        }
      }
    }); 
  }

  void checkIfShouldClose(int keyFrame) {
    if (keyFramesBehind(keyFrame) > ALLOWED_KEYFRAMES_BEHIND) {
      print("${world}: Connection to $id too many keyframes behind current: ${keyFrame} connection:${lastLocalPeerKeyFrameVerified}, dropping");
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
    return new Duration(milliseconds:_connectionTimer.elapsedMilliseconds);
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
    assert(latency.inMicroseconds > 0);
    this._latency = latency;
  }

  Duration expectedLatency() => _latency;

  toString() => "${connectionType} to ${id} latency ${_latency}";
}

