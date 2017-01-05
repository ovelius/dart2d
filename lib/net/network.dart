import 'connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/fps_counter.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/peer.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('Network');
// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0/2;
const PROBLEMATIC_FRAMES_BEHIND = 2;

class Network {
  GameState gameState;
  WormWorld world;
  PeerWrapper peer;
  String localPlayerName;
  PacketListenerBindings _packetListenerBindings;
  double untilNextKeyFrame = KEY_FRAME_DEFAULT;
  int currentKeyFrame = 0;
  // If we are client, this indicates that the server
  // is unable to ack our data.
  int serverFramesBehind = 0;

  Network(
      this.world, this._packetListenerBindings,
      @PeerMarker() Object jsPeer,
      JsCallbacksWrapper peerWrapperCallbacks) {
    gameState = new GameState(world);
    peer = new PeerWrapper(this, world.hudMessages, _packetListenerBindings, jsPeer, peerWrapperCallbacks);

    _packetListenerBindings.bindHandler(SERVER_PLAYER_REPLY,
            (ConnectionWrapper connection, Map data) {
      if (!connection.isValidGameConnection()) {
        assert(connection.connectionType == ConnectionType.CLIENT_TO_SERVER);
        assert(!isServer());
        world.hudMessages.display("Got server challenge from ${connection.id}");
        world.createLocalClient(data["spriteId"], data["spriteIndex"]);
        connection.setHandshakeReceived();
      } else {
        log.warning("Duplicate handshake received from ${connection}!");
      }
    });

    _packetListenerBindings.bindHandler(SERVER_PLAYER_REJECT,
            (ConnectionWrapper connection, Map data) {
      world.hudMessages.display("Game is full :/");
      connection.close(null);
    });

    _packetListenerBindings.bindHandler(CLIENT_PLAYER_SPEC, _handleClientConnect);
  }

  _handleClientConnect(ConnectionWrapper connection, String name) {
    if (connection.isValidGameConnection()) {
      log.warning("Duplicate handshake received from ${connection}!");
      return;
    }
    if (gameState.gameIsFull()) {
      connection.sendData({
        SERVER_PLAYER_REJECT: 'Game full',
        KEY_FRAME_KEY: connection.lastKeyFrameFromPeer,
        IS_KEY_FRAME_KEY: currentKeyFrame});
      // Mark as closed.
      connection.close(null);
      return;
    }
    // Consider the client CLIENT_PLAYER_SPEC as the client having seen
    // the latest keyframe.
    // It will anyway get the keyframe from our response.
    connection.lastLocalPeerKeyFrameVerified = currentKeyFrame;
    assert(connection.connectionType == ConnectionType.SERVER_TO_CLIENT);
    int spriteId = gameState.getNextUsablePlayerSpriteId();
    int spriteIndex = gameState.getNextUsableSpriteImage();
    PlayerInfo info = new PlayerInfo(name, connection.id, spriteId);
    gameState.playerInfo.add(info);
    assert(info.connectionId != null);

    LocalPlayerSprite sprite = new RemotePlayerServerSprite(
        world, connection.remoteKeyState, info, 0.0, 0.0, spriteIndex);
    sprite.networkType =  NetworkType.REMOTE_FORWARD;
    sprite.networkId = spriteId;
    sprite.ownerId = connection.id;
    world.addSprite(sprite);

    world.displayHudMessageAndSendToNetwork("${name} connected.");
    Map serverData = {"spriteId": spriteId, "spriteIndex": spriteIndex};
    connection.sendData({
      SERVER_PLAYER_REPLY: serverData,
      KEY_FRAME_KEY:connection.lastKeyFrameFromPeer,
      IS_KEY_FRAME_KEY: currentKeyFrame});

    connection.setHandshakeReceived();
    // We don't expect any more players, disconnect the peer.
    if (peer.connectedToServer() && gameState.gameIsFull()) {
      peer.disconnect();
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
    if (gameState.actingServerId == null) {
      log.info("No active game found, no server to transfer.");
      return false;
    }
    for (var key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (connection.connectionType == ConnectionType.CLIENT_TO_SERVER) {
        log.info("${peer.id} has a client to server connection using ${key}");
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
    return serverFramesBehind >= PROBLEMATIC_FRAMES_BEHIND && !isServer();
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
    // If we have any connetions, consider them to be SERVER_TO_CLIENT now.
    for (ConnectionWrapper connection in safeActiveConnections().values) {
      connection.connectionType = ConnectionType.SERVER_TO_CLIENT;
      // Announce change in type.
      connection.sendPing();
    }
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
      debugString += "${connection.id} ${connection.expectedLatency().inMilliseconds}ms R/X/D: ${connection.lastLocalPeerKeyFrameVerified}/${currentKeyFrame}/${connection.droppedKeyFrames}";
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
      print("${this.peer.id} get removals of ${bundle}");
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
