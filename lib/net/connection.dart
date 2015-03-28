library connection;

import 'dart:js';
import 'dart:html';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/world.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/playersprite.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/net/state_updates.dart';
import 'dart:convert';

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
  ConnectionType connectionType;
  World world;
  PeerWrapper peerWrapper;
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
  
  ConnectionWrapper(this.world, this.id, this.connection, this.connectionType) {
    assert(id != null);
    // Client to client connections to not need to shake hands :)
    // Server knows about both clients anyway.
    // Changing handshakeReceived should be the first assignment in the constructor.
    if ( connectionType == ConnectionType.CLIENT_TO_CLIENT) {
      this.handshakeReceived = true;
      // Mark connection as having recieved our keyframes up to this point.
      // This is required since CLIENT_TO_CLIENT connections to not do a handshake.
      lastLocalPeerKeyFrameVerified = world.network.currentKeyFrame;
    }
    connection.callMethod('on',
        new JsObject.jsify(
            ['data', new JsFunction.withThis(this.receiveData)]));
    connection.callMethod('on',
        new JsObject.jsify(
            ['close', new JsFunction.withThis(this.close)]));
    connection.callMethod('on',
        new JsObject.jsify(
            ['open', new JsFunction.withThis(this.open)]));
    connection.callMethod('on',
        new JsObject.jsify(
            ['error', new JsFunction.withThis(this.error)]));
  }

  bool hasReceivedFirstKeyFrame(Map dataMap) {
    if (dataMap.containsKey(IS_KEY_FRAME_KEY)) {
      lastKeyFrameFromPeer = dataMap[IS_KEY_FRAME_KEY];
    }
    // The server does not need to wait for keyframes.
    return lastKeyFrameFromPeer > 0 || world.network.isServer();
  }
  
  void verifyLastKeyFrameHasBeenReceived(Map dataMap) {
    lastLocalPeerKeyFrameVerified = dataMap[KEY_FRAME_KEY];
    if (lastLocalPeerKeyFrameVerified >= world.network.currentKeyFrame) {
      // Cool we just got some reliable data verified :)
      keyFrameData = {};
    }
  }
  
  void checkForHandshakeData(Map dataMap) {
    if (dataMap.containsKey(CLIENT_PLAYER_SPEC)) {
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

      world.hudMessages.displayAndSendToNetwork("${name} connected.");
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
      world.createLocalClient(dataMap[SERVER_PLAYER_REPLY]);
    }
    if (!handshakeReceived) {
      handshakeReceived = dataMap.containsKey(CLIENT_PLAYER_SPEC)
          || dataMap.containsKey(SERVER_PLAYER_REPLY);
    }
  }

  void close(unusedThis) {
    opened = false;
    closed = true;
  }
  
  void open(unusedThis) {
    world.hudMessages.display("Connection to ${id} open :)");
    // Set the connection to current keyframe.
    // A faulty connection will be dropped quite fast if it lags behind in keyframes.
    lastLocalPeerKeyFrameVerified = world.network.currentKeyFrame;
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
    opened = true;
  }
  
  void error(unusedThis, error) {
    print("error ${error}");
    world.hudMessages.display("Connection: ${error}");
    opened = false;
    closed = true;
  }

  void receiveData(unusedThis, data) {
    Map dataMap = JSON.decode(data);
    assert(dataMap.containsKey(KEY_FRAME_KEY));
    verifyLastKeyFrameHasBeenReceived(dataMap);
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

  void mergeWithStoredData(var data) {
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
  
  void sendData(data) {
    data[KEY_FRAME_KEY] = lastKeyFrameFromPeer;
    if (data.containsKey(IS_KEY_FRAME_KEY)) {
      // Check how many keyframes the remote peer is currenlty behind.
      // We might decide to close the connection because of this.
      if (keyFramesBehind(data[IS_KEY_FRAME_KEY]) > ALLOWED_KEYFRAMES_BEHIND) {
        opened = false;
        closed = true;
        print("${world}: Connection to $id too many keyframes behind current: ${data[IS_KEY_FRAME_KEY]} connection:${lastLocalPeerKeyFrameVerified}, dropping");
        return;
      }
      // Make a defensive copy in case of keyframe.
      data = new Map.from(data);
      mergeWithStoredData(data);
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
  
  toString() => "${connectionType} to ${id}";
}

