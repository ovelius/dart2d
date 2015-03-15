library dart2d;

import 'sprite.dart';
import 'movingsprite.dart';
import 'playersprite.dart';
import 'connection.dart';
import 'gamestate.dart';
import 'state_updates.dart';
import 'dart2d.dart';
import 'rtc.dart';
import 'vec2.dart';
import 'world.dart';
import 'keystate.dart';
import 'dart:math';

// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0/2;

class Client extends Network {
  Client(world, peer) : super(world, peer);
  bool isServer() {
    return false;
  }
}

class Server extends Network {
  Server(world, peer) : super(world, peer);
  bool isServer() {
    return true;
  }
}

abstract class Network {
  GameState gameState;
  World world;
  String localPlayerName;
  PeerWrapper peer;
  double untilNextKeyFrame = KEY_FRAME_DEFAULT;
  int currentKeyFrame = 0;

  Network(this.world, this.peer) {
    gameState = new GameState(world);
  }

  void connectToAllPeersInGameState() {
    for (PlayerInfo info in gameState.playerInfo) {
      if (!peer.hasConnectionTo(info.connectionId)) {
        world.hudMessages.display("Creating neighbour connection to ${info.name}");
        peer.connectTo(info.connectionId);
      }
    }
  }

  bool checkForKeyFrame(bool forceKeyFrame, double duration) {
    untilNextKeyFrame -= duration;
    if (forceKeyFrame) {
      currentKeyFrame++;
      untilNextKeyFrame = KEY_FRAME_DEFAULT;
      return true;
    }
    if (untilNextKeyFrame < 0) {
      currentKeyFrame++;
      untilNextKeyFrame += KEY_FRAME_DEFAULT;
      return true;
    }
    return false;
  }

  void registerDroppedFrames(var data) {
    for (ConnectionWrapper connection in peer.connections.values) {
      connection.registerDroppedKeyFrames(currentKeyFrame - 1);
    }
  }

  void sendMessage(String message) {
    Map data = {
      MESSAGE_KEY: [message],
      IS_KEY_FRAME_KEY: world.network.currentKeyFrame};
    peer.sendDataWithKeyFramesToAll(data);    
  }

  void maybeSendLocalKeyStateUpdate() {
    if (!isServer()) {
      Map data = {};
      data[KEY_STATE_KEY] = world.localKeyState.getEnabledState();
      peer.sendDataWithKeyFramesToAll(data);
    }
  }

  void frame(double duration, List<int> removals) {
    if (!hasReadyConnection()) {
      return;
    }
    bool keyFrame = checkForKeyFrame(!removals.isEmpty, duration);
    Map data = stateBundle(world.sprites, keyFrame);
    // A keyframe indicates that we are sending data with garantueed delivery.
    if (keyFrame) {
      registerDroppedFrames(data);
      data[IS_KEY_FRAME_KEY] = currentKeyFrame;
    }
    if (removals.length > 0) {
      data[REMOVE_KEY] = new List.from(removals, growable:false);
      removals.clear();
    }
    if (!isServer()) {
      data[KEY_STATE_KEY] = world.localKeyState.getEnabledState();
    } else if (keyFrame) {
      data[GAME_STATE] = gameState.toMap();
    }

    if (data.length > 0) {
      peer.sendDataWithKeyFramesToAll(data);
    }
  }

  bool isServer();

  bool hasReadyConnection() {
    if (peer != null && peer.connections.length > 0) {
      return true;
    }
    return false;
  }
  
  String keyFrameDebugData() {
    if (!hasReadyConnection()) {
      return "No connections";
    }
    String debugString = "";
    for (ConnectionWrapper connection in peer.connections.values) {
      debugString += "${connection.id} R/X/D: ${connection.lastLocalPeerKeyFrameVerified}/${currentKeyFrame}/${connection.droppedKeyFrames}";
    }
    return debugString;
  }
}

Map<String, List<int>> stateBundle(Map<int, Sprite> sprites, bool keyFrame) {
  Map<String, List<int>> allData = {};
  for (int networkId in sprites.keys) {
    Sprite sprite = sprites[networkId];
    if (sprite.networkType == NetworkType.LOCAL) {
      List<int> dataAsList = propertiesToIntList(sprite, keyFrame);
      allData[sprite.networkId.toString()] = dataAsList; 
    }
  }
  return allData;
}

DateTime lastNetworkFrameReceived = new DateTime.now();
FpsCounter networkFps = new FpsCounter();

void dataReceived() {
  DateTime now = new DateTime.now();
  int millis = now.millisecondsSinceEpoch - lastNetworkFrameReceived.millisecondsSinceEpoch;
  networkFps.timeWithFrames(millis / 1000.0, 1);
  lastNetworkFrameReceived = now;
}

void parseBundle(World world,
    ConnectionWrapper connection, Map<String, List<int>> bundle) {
  dataReceived();
  for (String networkId in bundle.keys) {
    if (!SPECIAL_KEYS.contains(networkId)) {
      int parsedNetworkId = int.parse(networkId);
      Sprite sprite = world.getOrCreateSprite(parsedNetworkId, bundle[networkId][0], connection);
      if (!sprite.networkType.remoteControlled()) {
        print("Warning: Attempt to update local sprite ${sprite.networkId} from network.");
        continue;
      }
      intListToSpriteProperties(bundle[networkId], sprite);
      // Forward sprite to others.
      if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
        assert(world.network.isServer());
        Map data = {networkId: bundle[networkId]};
        world.network.peer.sendDataWithKeyFramesToAll(data, connection.id);
      }
    }
  }
  if (bundle.containsKey(REMOVE_KEY)) {
    assert(world.network.isServer());
    List<int> removals = bundle[REMOVE_KEY];
    for (int id in removals) {
      world.removeSprite(id);
    }
  }
  if (bundle.containsKey(MESSAGE_KEY)) {
    for (String message in bundle[MESSAGE_KEY]) {
      world.hudMessages.display(message);
    }
  }
  if (bundle.containsKey(GAME_STATE)) {
    assert(!world.network.isServer());
    Map gameStateMap = bundle[GAME_STATE];
    world.network.gameState = new GameState.fromMap(world, gameStateMap);
    world.network.connectToAllPeersInGameState();
  }
}
