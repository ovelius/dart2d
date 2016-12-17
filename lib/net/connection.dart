library connection;

import 'package:dart2d/keystate.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'dart:convert';
import 'dart:core';

class ConnectionType {
  final value;
  const ConnectionType._internal(this.value);

  static const CLIENT_TO_SERVER = const ConnectionType._internal(0);
  static const SERVER_TO_CLIENT = const ConnectionType._internal(1);
  static const CLIENT_TO_CLIENT = const ConnectionType._internal(2);
  
  ConnectionType.fromInt(this.value);
  operator ==(ConnectionType other) {
    return value == other.value; 
  }
  
  toString() {
    switch (value) {
      case 0:
        return "CLIENT_TO_SERVER";
      case 1:
        return "SERVER_TO_CLIENT";
      case 2:
        return "CLIENT_TO_CLIENT";
      default:
        throw new StateError("ConnectionType with invalid value");
    }
  }
}

class ConnectionWrapper {
  // How many keyframes the connection can be behind before it is dropped.
  static int ALLOWED_KEYFRAMES_BEHIND = 5 ~/  KEY_FRAME_DEFAULT;
  // How long until connection attempt times out.
  static const Duration DEFAULT_TIMEOUT = const Duration(seconds:5);

  ConnectionType connectionType;
  WormWorld world;
  var id;
  var connection;
  // True if connection was successfully opened.
  bool opened = false;
  bool closed = false;
  bool handshakeReceived = false;
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
  Stopwatch _connectionTimer;
  // When we time out.
  Duration _timeout;

  ConnectionWrapper(this.world, this.id, this.connection, this.connectionType,
      JsCallbacksWrapper peerWrapperCallbacks,[_timeout = DEFAULT_TIMEOUT]) {
    assert(id != null);
    // Client to client connections to not need to shake hands :)
    // Server knows about both clients anyway.
    // Changing handshakeReceived should be the first assignment in the constructor.
    if (connectionType == ConnectionType.CLIENT_TO_CLIENT) {
      this.handshakeReceived = true;
      // Mark connection as having recieved our keyframes up to this point.
      // This is required since CLIENT_TO_CLIENT connections to not do a handshake.
      lastLocalPeerKeyFrameVerified = world.network.currentKeyFrame;
    }
    peerWrapperCallbacks
       ..bindOnFunction(connection, 'data', receiveData)
       ..bindOnFunction(connection, 'close', close)
       ..bindOnFunction(connection, 'close', close)
       ..bindOnFunction(connection, 'error', error);
    // Start the connection timer.
    _connectionTimer = new Stopwatch();
    _connectionTimer.start();
  }

  bool hasReceivedFirstKeyFrame(Map dataMap) {
    if (dataMap.containsKey(IS_KEY_FRAME_KEY)) {
      lastKeyFrameFromPeer = dataMap[IS_KEY_FRAME_KEY];
    }
    // The server does not need to wait for keyframes.
    return lastKeyFrameFromPeer > 0 || world.network.isServer();
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
      if (world.network.gameState.gameIsFull()) {
        sendData({
          SERVER_PLAYER_REJECT: 'Game full',
          KEY_FRAME_KEY: lastKeyFrameFromPeer, 
          IS_KEY_FRAME_KEY: world.network.currentKeyFrame});
        // Mark as closed.
        this.closed = true;
        return;
      }
      // Consider the client CLIENT_PLAYER_SPEC as the client having seen
      // the latest keyframe.
      // It will anyway get the keyframe from our response.
      lastLocalPeerKeyFrameVerified = world.network.currentKeyFrame;
      assert(connectionType == ConnectionType.SERVER_TO_CLIENT);
      String name = dataMap[CLIENT_PLAYER_SPEC];
      int spriteId = world.network.gameState.getNextUsablePlayerSpriteId();
      int spriteIndex = world.network.gameState.getNextUsableSpriteImage();
      PlayerInfo info = new PlayerInfo(name, id, spriteId);
      world.network.gameState.playerInfo.add(info);
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
        IS_KEY_FRAME_KEY: world.network.currentKeyFrame});
    }
    if (dataMap.containsKey(SERVER_PLAYER_REPLY)) {
      assert(connectionType == ConnectionType.CLIENT_TO_SERVER);
      world.hudMessages.display("Got server challenge from ${id}");
      assert(!world.network.isServer());
      Map receivedServerData = dataMap[SERVER_PLAYER_REPLY];
      world.createLocalClient(receivedServerData["spriteId"],
          receivedServerData["spriteIndex"]);
    }
    if (dataMap.containsKey(SERVER_PLAYER_REJECT)) {
      world.hudMessages.display("Game is full :/");
      this.closed = true;
      return;
    }
    if (!handshakeReceived) {
      handshakeReceived = dataMap.containsKey(CLIENT_PLAYER_SPEC)
          || dataMap.containsKey(SERVER_PLAYER_REPLY);
    }
  }

  void close(unusedThis) {
    world.hudMessages.display("Connection to ${id} closed :(");
    // Connection was never open, blacklist the id.
    if (!opened) {
      world.network.blackListedIds.add(this.id);
    }
    opened = false;
    closed = true;
  }
  
  void open(unusedThis) {
    world.hudMessages.display("Connection to ${id} open :)");
    // Set the connection to current keyframe.
    // A faulty connection will be dropped quite fast if it lags behind in keyframes.
    lastLocalPeerKeyFrameVerified = world.network.currentKeyFrame;
    opened = true;
    if (world.connectOnOpenConnection) {
      connectToGame();
    }
  }
  
  void connectToGame() {
    if (connectionType == ConnectionType.CLIENT_TO_SERVER) {
      // Send out local data hello. We don't do this as part of the intial handshake but over
      // the actual connection.
      Map playerData = {
          CLIENT_PLAYER_SPEC: world.network.localPlayerName,
          KEY_FRAME_KEY:lastKeyFrameFromPeer,
          IS_KEY_FRAME_KEY: world.network.currentKeyFrame,
      };
      sendData(playerData);
    }
  }
  
  void error(unusedThis, error) {
    print("error ${error}");
    world.hudMessages.display("Connection: ${error}");
    // Connection was never open, blacklist the id.
    if (!opened) {
      world.network.blackListedIds.add(this.id);
    }
    opened = false;
    closed = true;
  }

  void receiveData(unusedThis, data) {
    Map dataMap = JSON.decode(data);
    assert(dataMap.containsKey(KEY_FRAME_KEY));
    verifyLastKeyFrameHasBeenReceived(dataMap);
    
    // Allow sending and parsing imageData regardless of state.
    if (dataMap.containsKey(IMAGE_DATA_REQUEST)) {
      world.peer.chunkHelper.replyWithImageData(dataMap, this);
    }
    if (dataMap.containsKey(IMAGE_DATA_RESPONSE)) {
      world.peer.chunkHelper.parseImageChunkResponse(dataMap);
      // Request new data right away.
      world.peer.chunkHelper.requestNetworkData(
          new List.filled(1, this));
    }
    
    if (!handshakeReceived) {
      // Try to handle the intial connection handshake.
      checkForHandshakeData(dataMap);
    }
    // Wait for a first keyframe from this connection.
    if (!hasReceivedFirstKeyFrame(dataMap)) {
      return;
    }
    // Don't continue handling data if handshake is not finished.
    if (!handshakeReceived) {
      return;
    }
    // We got a remote key state.
    if (dataMap.containsKey(KEY_STATE_KEY)) {
      remoteKeyState.setEnabledKeys(dataMap[KEY_STATE_KEY]);
    }
    parseBundle(world, this, dataMap);
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
  
  void sendData(Map data) {
    data[KEY_FRAME_KEY] = lastKeyFrameFromPeer;
    if (data.containsKey(IS_KEY_FRAME_KEY)) {
      // Check how many keyframes the remote peer is currenlty behind.
      // We might decide to close the connection because of this.
      if (keyFramesBehind(data[IS_KEY_FRAME_KEY]) > ALLOWED_KEYFRAMES_BEHIND) {
        print("${world}: Connection to $id too many keyframes behind current: ${data[IS_KEY_FRAME_KEY]} connection:${lastLocalPeerKeyFrameVerified}, dropping");
        close(null);
        return;
      }
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

  bool timedOut() {
    return sinceCreated().compareTo(_timeout) > 0;
  }

  /**
   * Checks if the connection has timed out and closes it if that is the case.
   */
  void checkForTimeout() {
    if (timedOut()) {
      close(null);
    }
  }
  
  toString() => "${connectionType} to ${id}";
}

