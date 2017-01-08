import 'connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/fps_counter.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/peer.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:di/di.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('Network');
// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0/2;
const PROBLEMATIC_FRAMES_BEHIND = 2;

@Injectable()
class Network {
  WormWorld world;
  GameState gameState;
  HudMessages _hudMessages;
  PeerWrapper peer;
  String localPlayerName;
  PacketListenerBindings _packetListenerBindings;
  double untilNextKeyFrame = KEY_FRAME_DEFAULT;
  int currentKeyFrame = 0;
  // If we are client, this indicates that the server
  // is unable to ack our data.
  int serverFramesBehind = 0;

  Network(
      HudMessages hudMessages,
      this._packetListenerBindings,
      @PeerMarker() Object jsPeer,
      JsCallbacksWrapper peerWrapperCallbacks) {
    this._hudMessages = hudMessages;
    gameState = new GameState();
    peer = new PeerWrapper(this, hudMessages, _packetListenerBindings, jsPeer, peerWrapperCallbacks);

    _packetListenerBindings.bindHandler(SERVER_PLAYER_REJECT,
            (ConnectionWrapper connection, Map data) {
      hudMessages.display("Game is full :/");
      connection.close(null);
    });
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

  PeerWrapper getPeer() => peer;
  GameState getGameState() => gameState;

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
        SpriteConstructor constructor = SpriteConstructor.values[bundle[networkId][0]];
        MovingSprite sprite = world.getOrCreateSprite(parsedNetworkId, constructor, connection);
        if (sprite == null) {
          log.warning("Not creating sprite from update ${networkId}");
          continue;
        }
        // TODO(erik) Prio data for the owner of the sprite instead.
        if (!sprite.remoteControlled()) {
          if (isServer()) {
            log.warning("Warning: Attempt to update local sprite ${sprite
                .networkId} from network ${connection.id}.");
            continue;
          }
          // Since we are not remote controlled, parse as Server to owner data.
          List data = bundle[networkId];
          sprite.parseServerToOwnerData(data);
        } else {
          intListToSpriteProperties(bundle[networkId], sprite);
          // Forward sprite to others.
          if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
            Map data = {networkId: bundle[networkId]};
            peer.sendDataWithKeyFramesToAll(data, connection.id);
          }
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
      } else if (isServer() && sprite.hasServerToOwnerData()) {
        List dataAsList = [SpriteConstructor.DO_NOT_CREATE.index];
        sprite.addServerToOwnerData(dataAsList);
        allData[sprite.networkId.toString()] = dataAsList;
      }
    }
    return allData;
  }
}

DateTime lastNetworkFrameReceived = new DateTime.now();
FpsCounter networkFps = new FpsCounter();

void dataReceived() {
  DateTime now = new DateTime.now();
  int millis = now.millisecondsSinceEpoch - lastNetworkFrameReceived.millisecondsSinceEpoch;
  networkFps.timeWithFrames(millis / 1000.0, 1);
  lastNetworkFrameReceived = now;
}
