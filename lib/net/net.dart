library net;

import 'connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/fps_counter.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('Network');
// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0/2;
const PROBLEMATIC_FRAMES_BEHIND = 2;

class Network {
  GameState gameState;
  WormWorld world;
  String localPlayerName;
  PeerWrapper peer;
  double untilNextKeyFrame = KEY_FRAME_DEFAULT;
  int currentKeyFrame = 0;
  // If we are client, this indicates that the server
  // is unable to ack our data.
  int serverFramesBehind = 0;

  Network(this.world, this.peer) {
    gameState = new GameState(world);
  }
  
  /**
   * Ensures that we have a connection to all clients in the game.
   * This is to be able to elect a new server in case the current server dies.
   * 
   * We also ensure the sprites in the world have consitent owners.
   */
  void connectToAllPeersInGameState() {
    for (PlayerInfo info in gameState.playerInfo) {
      LocalPlayerSprite sprite = world.spriteIndex[info.spriteId];
      if (sprite != null) {
        // Make sure the ownerId is consistent with the connectionId.
        sprite.ownerId = info.connectionId;
        sprite.info = info;
      } else {
        log.warning("No matching sprite found for ${info}");
      }
      if (!peer.hasConnectionTo(info.connectionId)) {
        // Decide if I'm responsible for the connection.
        if (peer.id.compareTo(info.connectionId) < 0) {
          world.hudMessages.display("Creating neighbour connection to ${info.name}");
          peer.connectTo(info.connectionId, ConnectionType.CLIENT_TO_CLIENT);
        }
      }
    }
  }
  
  /**
   * Our goal is to always have a connection to a server.
   * This is checked when a connection is dropped. 
   * Potentially this method will elect a new server.
   * returns true if we became the new server.
   * TODO(Erik): Conside more factors when electing servers, like number of connected
   *  peers.
   */
  bool verifyOrTransferServerRole(Map connections) {
    for (var key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (connection.connectionType == ConnectionType.CLIENT_TO_SERVER) {
        print("${peer.id} has a client to server connection using ${key}");
        return false;  
      }
    }
    // We don't have a server connection. We need to elect a new one.
    // We always elect the peer with the highest natural order id.
    var maxPeerKey = null;
    if (!connections.keys.isEmpty) {
      maxPeerKey = connections.keys.reduce(
          (value, element) => value.compareTo(element) < 0 ? value : element);
    }
    if (maxPeerKey != null && maxPeerKey.compareTo(peer.id) < 0) {
      PlayerInfo info = gameState.playerInfoByConnectionId(maxPeerKey);
      // Start treating the other peer as server.
      ConnectionWrapper connection = connections[maxPeerKey];
      connection.connectionType = ConnectionType.CLIENT_TO_SERVER;
      gameState.actingServerId = maxPeerKey;
      world.hudMessages.display("Elected new server ${info.name}");
    } else {
      // We are becoming server. Gosh.
      for (var id in connections.keys) {
        ConnectionWrapper connection = connections[id];
        connection.connectionType = ConnectionType.SERVER_TO_CLIENT;
        PlayerInfo info = gameState.playerInfoByConnectionId(id);
        // Make it our responsibility to foward data from other players.
        Sprite sprite = world.spriteIndex[info.spriteId];
        if (sprite.networkType == NetworkType.REMOTE) {
          sprite.networkType = NetworkType.REMOTE_FORWARD;
        }
      }
      world.hudMessages.display("Server role tranferred to you :)");
      // TODO: Add self sprite.
      return true;
    }
    return false;
  }

  bool checkForKeyFrame(double duration) {
    untilNextKeyFrame -= duration;
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
      if (connection.connectionType == ConnectionType.CLIENT_TO_SERVER) {
        serverFramesBehind = connection.keyFramesBehind(currentKeyFrame - 1);
      }
    }
  }
  
  /**
   * Return a map of connections garantueed to be active.
   */
  Map<String, ConnectionWrapper> safeActiveConnections() {
    Map<String, ConnectionWrapper> activeConnections = {};
    for (ConnectionWrapper wrapper in new List.from(peer.connections.values)) {
      if (wrapper.isActiveConnection()) {
        activeConnections[wrapper.id] = wrapper;
      } else {
        print("health checking ${wrapper.id}");
        this.peer.healthCheckConnection(wrapper.id);
      }
    }
    return activeConnections;
  }
  
  /**
   * Return the connection to the server.
   */
  ConnectionWrapper getServerConnection() {
    for (ConnectionWrapper wrapper in new List.from(peer.connections.values)) {
      if (!wrapper.closed && wrapper.opened
          && wrapper.connectionType == ConnectionType.CLIENT_TO_SERVER) {
        return wrapper;
      }
    }
    return null;
  }
  
  /**
   * Returns true if the network is in such a problemetic state we should notify the user.
   */
  bool hasNetworkProblem() {
    return serverFramesBehind >= PROBLEMATIC_FRAMES_BEHIND;
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
      serverFramesBehind = 0;
      return;
    }
    // This doesnät make sense.
    bool keyFrame = checkForKeyFrame(duration);
    Map data = stateBundle(world.spriteIndex, keyFrame);
    // A keyframe indicates that we are sending data with garantueed delivery.
    if (keyFrame) {
      registerDroppedFrames(data);
      data[IS_KEY_FRAME_KEY] = currentKeyFrame;
    }
    if (removals.length > 0) {
      data[REMOVE_KEY] = removals;
    }
    if (!isServer()) {
      data[KEY_STATE_KEY] = world.localKeyState.getEnabledState();
    } else if (keyFrame || gameState.retrieveAndResetUrgentData()) {
      data[GAME_STATE] = gameState.toMap();
    }
    if (data.length > 0) {
      peer.sendDataWithKeyFramesToAll(data);
    }
  }

  bool isServer() {
    return gameState.actingServerId == this.peer.id;
  }

  void setActingServer() {
    gameState.actingServerId = peer.id;
    // TODO select me!
    this.gameState.mapId = 1;
  }

  bool hasReadyConnection() {
    if (peer != null && peer.connections.length > 0) {
      return true;
    }
    return false;
  }
  
  bool hasOpenConnection() {
    if (hasReadyConnection()) {
      return safeActiveConnections().length > 0;
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


  void parseBundle(ConnectionWrapper connection, Map<String, dynamic> bundle) {
    dataReceived();
    for (String networkId in bundle.keys) {
      if (!SPECIAL_KEYS.contains(networkId)) {
        int parsedNetworkId = int.parse(networkId);
        // TODO(erik) Prio data for the owner of the sprite instead.
        SpriteConstructor constructor = SpriteConstructor.values[bundle[networkId][0]];
        MovingSprite sprite = world.getOrCreateSprite(parsedNetworkId, constructor, connection);
        if (!sprite.remoteControlled()) {
          log.warning("Warning: Attempt to update local sprite ${sprite.networkId} from network ${connection.id}.");
          continue;
        }
        intListToSpriteProperties(bundle[networkId], sprite);
        // Forward sprite to others.
        if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
          Map data = {networkId: bundle[networkId]};
          peer.sendDataWithKeyFramesToAll(data, connection.id);
        }
      }
    }
    if (bundle.containsKey(REMOVE_KEY)) {
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
    if (bundle.containsKey(WORLD_DESTRUCTION)) {
      world.clearFromNetworkUpdate(bundle[WORLD_DESTRUCTION]);
    }
    if (bundle.containsKey(WORLD_PARTICLE)) {
      world.addParticlesFromNetworkData(bundle[WORLD_PARTICLE]);
    }
    if (bundle.containsKey(GAME_STATE)) {
      assert(!world.network.isServer());
      Map gameStateMap = bundle[GAME_STATE];
      GameState newGameState =  new GameState.fromMap(world, gameStateMap);
      world.network.gameState = newGameState;
      world.network.connectToAllPeersInGameState();
      if (world.network.peer.connectedToServer() && newGameState.isAtMaxPlayers()) {
        world.network.peer.disconnect();
      }
    }
  }

}

Map<String, List<int>> stateBundle(SpriteIndex spriteIndex, bool keyFrame) {
  Map<String, List<int>> allData = {};
  for (int networkId in spriteIndex.spriteIds()) {
    Sprite sprite = spriteIndex[networkId];
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
