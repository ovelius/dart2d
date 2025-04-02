import 'package:dart2d/net/peer.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:injectable/injectable.dart';

import 'connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'dart:convert';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

import 'helpers.dart';

// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0 / 2;
const PROBLEMATIC_FRAMES_BEHIND = 2;

@Singleton(scope: 'world')
class Network {
  final Logger log = new Logger('Network');
  late WormWorld world;
  GameState gameState;
  late HudMessages _hudMessages;
  late SpriteIndex _spriteIndex;
  GaReporter _gaReporter;
  ConnectionFactory _connectionFactory;
  late KeyState _localKeyState;
  late PeerWrapper peer;
  PacketListenerBindings _packetListenerBindings;
  late FpsCounter _drawFps;
  // If we are client, this indicates that the server
  // is unable to ack our data.
  int serverFramesBehind = 0;
  // How many times we trigger a frame while being very slow at doing so.
  // We may choose to give up our commanding role if this happens too much.
  int _slowCommandingFrames = 0;
  String? _pendingCommandTransfer = null;

  Network(
      this._gaReporter,
      this._connectionFactory,
      HudMessages hudMessages,
      this.gameState,
      this._packetListenerBindings,
      FpsCounter serverFrameCounter,
      ServerChannel serverChannel,
      ConfigParams configParams,
      SpriteIndex spriteIndex,
      KeyState localKeyState) {
    this._hudMessages = hudMessages;
    this._spriteIndex = spriteIndex;
    this._drawFps = serverFrameCounter;
    this._localKeyState = localKeyState;
    peer = new PeerWrapper(_connectionFactory, this, hudMessages, configParams,
        serverChannel, _packetListenerBindings, _gaReporter);

    _packetListenerBindings.bindHandler(StateUpdate_Update.gameState, _handleGameState);
    _packetListenerBindings.bindHandler(StateUpdate_Update.clientStatusData,
        (ConnectionWrapper connection, StateUpdate stateUpdate) {
      ClientStatusData data = stateUpdate.clientStatusData;
      /// Update the list of connections for this player.
      PlayerInfoProto? info = gameState.playerInfoByConnectionId(connection.id);
      info?.fps = data.fps;
      info?.connectionInfo.clear();
      info?.connectionInfo.addAll(data.connectionInfo);
    });

    _packetListenerBindings.bindHandler(StateUpdate_Update.commanderGameReply,
        (ConnectionWrapper connection, StateUpdate stateUpdate) {
      CommanderGameReply reply = stateUpdate.commanderGameReply;
      if (reply.challengeReply == CommanderGameReply_ChallengeReply.REJECT_FULL) {
        hudMessages.display("Game is full :/");
        gameState.reset();
        connection.close("Game full");
      }
    });

    _packetListenerBindings.bindHandler(StateUpdate_Update.transferCommand,
        (ConnectionWrapper connection, _) {
      if (!world.loaderCompleted()) {
        log.warning(
            "Can not transfer command to us before loading has completed. Dropping request.");
        return;
      }
      // Server wants us to take command.
      log.info("Converting self ${peer.id} to commander");
      this.convertToCommander(this.safeActiveConnections(), null);
      _gaReporter.reportEvent(
          "convert_self_to_commander_on_request", "Commander");
    });
  }

  /**
   * Our goal is to always have a connection to a commander.
   * This is checked when a connection is dropped.
   * Potentially this method will elect a new commander.
   * returns the id of the new commander, or null if no new commander was needed.
   *  peers.
   */
  String? findNewCommander(Map connections, [bool ignoreSelf = false]) {
    if (!isCommander()) {
      if (!gameState.isInGame(peer.id!)) {
        log.info("No active game found for us, no commander role to transfer.");
        return null;
      }
    }
    List<String> validKeys = [];
    for (String key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (connection.id == gameState.gameStateProto.actingCommanderId) {
        log.info("${peer.id} has a client to server connection using ${key}");
        return null;
      }
      if (connection.isValidGameConnection()) {
        validKeys.add(key);
      }
    }
    // Don't count our own id.
    if (!ignoreSelf) {
      return _naturalOrderPeerId(validKeys);
    } else {
      return _bestCommanderPeerId(validKeys);
    }
  }

  /**
   * When the commander dies unexpectedly we need to make a collective decision on
   * who will be the next commander. The peer ID should be the most consistent item
   * so we pick the remaining host with the highest naturual order peerId.
   * Should this turn out to be unsuitable, it will automatically select a better
   * commander in time.
   */
  String _naturalOrderPeerId(List<String> validKeys) {
    // We always elect the peer with the highest natural order id.
    var maxPeerKey = null;
    if (!validKeys.isEmpty) {
      maxPeerKey = validKeys.reduce(
          (value, element) => value.compareTo(element) < 0 ? value : element);
    }
    if (maxPeerKey != null && maxPeerKey.compareTo(peer.id) < 0) {
      return maxPeerKey;
    } else {
      return peer.id!;
    }
  }

  /**
   * Select the best next commander.
   * TODO also count the number of connections?
   */
  String? _bestCommanderPeerId(List<String> validKeys) {
    int bestFps = -1;
    String? bestFpsKey = null;
    for (String peerId in validKeys) {
      // pick commander with highest FPS.
      PlayerInfoProto? info = gameState.playerInfoByConnectionId(peerId);
      if (info != null && info.fps > bestFps) {
        bestFps = info.fps;
        bestFpsKey = peerId;
      }
    }
    log.info(
        "Identified ${bestFpsKey} as best suitable commander with fps ${bestFps}");
    return bestFpsKey;
  }

  void resetGameConnections() {
    for (ConnectionWrapper connection in safeActiveConnections().values) {
      connection.resetHandshakeReceived();
    }
  }

  /**
   * Set this peer as the commander.
   */
  void convertToCommander(
      Map<String, ConnectionWrapper> connections, PlayerInfo? previousCommanderPlayerInfo) {
    _hudMessages.display("Commander role transfered to you :)");
    String oldCommanderId = gameState.gameStateProto.actingCommanderId;
    gameState.convertToServer(world, this.peer.id);
    List<int> spriteIds = new List.from(_spriteIndex.spriteIds());
    for (int id in spriteIds) {
      Sprite sprite = _spriteIndex[id]!;
      // Transfer ownership of the old commanders sprites to us.
      if (!(sprite is LocalPlayerSprite)) {
        if (sprite.ownerId == oldCommanderId &&
            sprite.networkType == NetworkType.REMOTE) {
          sprite.ownerId = null;
          sprite.networkType = NetworkType.LOCAL;
        }
      }
      // Remove any projectiles without owner.
      if (previousCommanderPlayerInfo != null && sprite is MovingSprite &&
          sprite.owner?.networkId == previousCommanderPlayerInfo.spriteId) {
        sprite.remove = true;
        sprite.collision = false;
      }
    }

    for (String id in connections.keys) {
      ConnectionWrapper connection = connections[id]!;
      connection.sendPing();
      if (connection.isValidGameConnection()) {
        PlayerInfoProto info = gameState.playerInfoByConnectionId(id)!;
        // Make it our responsibility to forward data from other players.
        Sprite? sprite = _spriteIndex[info.spriteId];
        if (sprite?.networkType == NetworkType.REMOTE) {
          sprite?.networkType = NetworkType.REMOTE_FORWARD;
        }
      }
    }
    gameState.markAsUrgent();
  }

  PeerWrapper getPeer() => peer;
  GameState getGameState() => gameState;

  /**
   * Return a map of connections garantueed to be active.
   */
  Map<String, ConnectionWrapper> safeActiveConnections() {
    Map<String, ConnectionWrapper> activeConnections = {};
    for (ConnectionWrapper wrapper in new List.from(peer.connections.values)) {
      if (wrapper.isActiveConnection()) {
        activeConnections[wrapper.id] = wrapper;
      } else {
        this.peer.healthCheckConnection(wrapper.id);
      }
    }
    return activeConnections;
  }

  /**
   * Return the connection to the server.
   */
  ConnectionWrapper? getServerConnection() {
    if (peer.connections.containsKey(gameState.gameStateProto.actingCommanderId)) {
      return peer.connections[gameState.gameStateProto.actingCommanderId];
    }
    return null;
  }

  _handleGameState(ConnectionWrapper connection, StateUpdate stateUpdate) {
    GameStateProto newGameState = stateUpdate.gameState;
    if (isCommander() && pendingCommandTransfer() == null) {
      log.warning(
          "Not parsing gamestate from ${connection.id} because we are commander!");
      if (!GameState.updateContainsPlayerWithId(newGameState, peer.id!)) {
        // We are not even in the received GameState..grr..
        if (gameState.gameStateProto.actingCommanderId == connection.id) {
          connection.close("two commanders talking to eachother");
          _gaReporter.reportEvent("network", "two_commander_connection");
        }
      }
      return;
    }
    if (gameState.playerInfoByConnectionId(peer.id!) != null &&
      !GameState.updateContainsPlayerWithId(newGameState, peer.id!)) {
      // We are in the old GameState, but the new GameState does not have us :(
      if (gameState.gameStateProto.actingCommanderId != newGameState.actingCommanderId &&
          newGameState.actingCommanderId == connection.id) {
        // Also this GameState doesn't match out expected CommanderId.
        // So we don't want to listen to this connection.
        connection.close("multiple commander connections");
        _gaReporter.reportEvent(
            "network", "multiple_commanders_connection_closed");
        return;
      }
    }
    gameState.updateFromMap(newGameState);

    // Command transfer successful.
    if (_pendingCommandTransfer != null &&
       gameState.gameStateProto.actingCommanderId == _pendingCommandTransfer) {
      log.info("Succcesfully transfered command to ${gameState.gameStateProto.actingCommanderId}");
      _pendingCommandTransfer = null;
    }

    world.connectToAllPeersInGameState();
    if (peer.connectedToServer() && gameState.isAtMaxPlayers()) {
      peer.disconnect();
    }
  }

  /**
   * Try and find a connection to another peer with an active game.
   * Returns true if we got one.
   */
  bool findActiveGameConnection() {
    Map<String, ConnectionWrapper> connections = safeActiveConnections();
    List<String> closeAbleNotServer = [];
    if (connections.containsKey(gameState..gameStateProto.actingCommanderId)) {
      if (gameState.isAtMaxPlayers()) {
         connections[gameState.gameStateProto.actingCommanderId]!.close("Full game connection!");
         return false;
      }
      return true;
    }
    int activityMillis = new DateTime.now().millisecondsSinceEpoch - 3000;
    for (ConnectionWrapper connection in connections.values) {
      if (connection.initialPongReceived()) {
        closeAbleNotServer.add(connection.id);
      }
      if (!connection.initialPingSent()) {
        connection.sendPing(true);
      } else if (connection.lastReceiveActivityOlderThan(activityMillis) &&
          connection.lastSendActivityOlderThan(activityMillis)) {
        connection.sendPing();
      }
    }
    // We examined all connections and found no server. Time to take action.
    if (new Set.from(closeAbleNotServer).containsAll(connections.keys)) {
      if (peer.hasMaxAutoConnections()) {
        for (int i = 0; i < closeAbleNotServer.length; i++) {
          // TODO close by some heuristic here?
          if (i > 1) break;
          ConnectionWrapper connection = connections[closeAbleNotServer[i]]!;
          log.info("Closing connection $connection in search for server.");
          connection.close("No game found");

          // Remove right away, so autoConnectToPeers doesn't count this connection.
          // TODO: Should we instead clean connections in autoConnectToPeers?
          peer.removeClosedConnection(connection.id);

          if (!peer.autoConnectToPeers()) {
            // We didn't add any new peers. Bail.
            log.warning(
                "didn't find any servers, and not able to connect to any more peers. Giving up.");
            return true;
          }
        }
      } else if (peer.noMoreConnectionsAvailable()) {
        return true;
      } else {
        peer.autoConnectToPeers();
      }
    }
    if (connections.isEmpty) {
      if (!peer.autoConnectToPeers()) {
        // We didn't add any new peers. Bail.
        return true;
      }
    }
    return false;
  }

  /**
   * Returns true if the network is in such a problemetic state we should notify the user.
   */
  bool hasNetworkProblem() {
    return serverFramesBehind >= PROBLEMATIC_FRAMES_BEHIND && !isCommander();
  }

  void sendMessage(String message, [String? dontSendTo]) {
    StateUpdate message = new StateUpdate();
    GameStateUpdates state = GameStateUpdates();
    state.stateUpdate.add(message);
    peer.sendDataWithKeyFramesToAll(state, dontSendTo);
  }

  void maybeSendLocalKeyStateUpdate() {
    if (!isCommander()) {
      StateUpdate keyUpdate = StateUpdate();
      keyUpdate.keyState = _localKeyState.toKeyStateProto();
      peer.sendSingleStateUpdate(keyUpdate);
    }
  }

  void frame(double duration, List<int> removals) {
    if (!hasReadyConnection()) {
      serverFramesBehind = 0;
      return;
    }
    if (isCommander()) {
      if (_drawFps.fps() > 0.0 &&
          _drawFps.fps() < (TARGET_SERVER_FRAMES_PER_SECOND / 2)) {
        // We are running at a very low server framerate. Are we really suitable
        // as commander?
        log.fine(
            "Commander ${peer.id} below FPS threshold! Is ${_drawFps.fps()}");
        _slowCommandingFrames++;
      } else {
        _slowCommandingFrames = 0;
      }
    }
    peer.tickConnections(duration, removals);

    if (!isCommander()) {
      ConnectionWrapper? serverConnection = getServerConnection();
      if (serverConnection != null) {
        serverFramesBehind = serverConnection.keyFramesBehind() - 1;
      }
    }

    // Transfer our commanding role to someone else!
    if (isCommander() && isTooSlowForCommanding()) {
      log.info("Self framerate is too low${_slowCommandingFrames} attempting to transfer command role");
      Map connections = safeActiveConnections();
      String? newCommander = findNewCommander(connections, true);
      if (newCommander != null) {
        ConnectionWrapper connection = connections[newCommander];
        connection.sendCommandTransfer();
        _slowCommandingFrames = 0;
        log.info(
            "Attempting to transfer command rule due to slow framerate from us");
        _pendingCommandTransfer = newCommander;
      }
    }
  }

  String? pendingCommandTransfer() => _pendingCommandTransfer;
  void setPendingCommandTransferForTest(String pendingCommandTransfer) {
    _pendingCommandTransfer = pendingCommandTransfer;
  }

  bool isCommander() {
    return gameState.gameStateProto.actingCommanderId == this.peer.id;
  }

  void setAsActingCommander() {
    log.info("Setting ${peer.id} as acting commander.");
    gameState.gameStateProto.actingCommanderId = peer.id!;
    gameState.markAsUrgent();
    gameState.gameStateProto.mapName = "";
    // If we have any connections, consider them to be SERVER_TO_CLIENT now.
    for (ConnectionWrapper connection in safeActiveConnections().values) {
      // Announce change in GameState.
      connection.sendPing();
    }
  }

  int slowCommandingFrames() => _slowCommandingFrames;
  bool isTooSlowForCommanding() => _slowCommandingFrames > 5;

  bool hasReadyConnection() {
    if (peer.connections.length > 0) {
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

  List<String> keyFrameDebugData() {
    List<String> debugStrings = [
      "Connected to signal server: ${peer.connectedToServer()}"
    ];
    if (!hasReadyConnection()) {
      return debugStrings;
    }
    for (ConnectionWrapper connection in peer.connections.values) {
      debugStrings.add(
          "${connection.id} FR:${connection.currentFrameRate()} ms:${connection.expectedLatency().inMilliseconds} by: ${connection.stats()} kf: ${connection.lastDeliveredKeyFrame}/${connection.currentKeyFrame()}");
    }
    return debugStrings;
  }

  void parseBundle(ConnectionWrapper connection, Map<String, dynamic> bundle) {
    for (String networkId in bundle.keys) {
      if (!SPECIAL_KEYS.contains(networkId)) {
        int parsedNetworkId = int.parse(networkId);
        List<dynamic> data = bundle[networkId];
        if (data[0] & Sprite.FLAG_COMMANDER_DATA ==
            Sprite.FLAG_COMMANDER_DATA) {
          // parse as commander data update.
          MovingSprite? sprite = world.spriteIndex[parsedNetworkId] as MovingSprite?;
          if (sprite == null) {
            log.warning("Commander data update for missing sprite $parsedNetworkId");
            continue;
          }
          if (isCommander()) {
            log.warning("Warning: Attempt to update local sprite ${sprite
                .networkId} from network ${connection.id}.");
            continue;
          }
          List data = bundle[networkId];
          sprite.parseServerToOwnerData(data, 1);
        } else {
          // Parse as generic update.
          SpriteConstructor constructor = SpriteConstructor.DO_NOT_CREATE;
          // Only try and construct sprite if this is a full frame - we have all
          // the data.
          if (data[0] & Sprite.FLAG_FULL_FRAME == Sprite.FLAG_FULL_FRAME) {
            constructor = SpriteConstructor.values[data[6]];
          }
          MovingSprite? sprite = _spriteIndex[parsedNetworkId] as MovingSprite?;
          if (sprite == null && constructor != SpriteConstructor.DO_NOT_CREATE) {
            sprite = _spriteIndex.CreateSpriteFromNetwork(
                world, parsedNetworkId, constructor, connection, data);
          }
          if (sprite == null) {
            log.fine("Sprite with id ${networkId} can't be created, constructor: ${constructor}");
            continue;
          }
          intListToSpriteProperties(bundle[networkId], sprite!);
          // Forward sprite to others.
          if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
            for (ConnectionWrapper receipientConnection
                in safeActiveConnections().values) {
              if (connection.id == receipientConnection.id) {
                // Don't send back from where it came.
                continue;
              }
              // Don't forward if we know there is a direct connection between these
              // two peers already.
              // TODO: Forward if latency is better this path?
              if (!gameState.isConnected(
                  connection.id, receipientConnection.id)) {
                Map data = {networkId: bundle[networkId]};
                peer.sendDataWithKeyFramesToAll(
                    data, null, receipientConnection.id);
              }
            }
          }
        }
      }
    }
  }

  void stateBundle(bool keyFrame, GameStateUpdates updates, List<int> removals) {
    for (int networkId in _spriteIndex.spriteIds()) {
      Sprite sprite = _spriteIndex[networkId]!;
      if (sprite.networkType == NetworkType.LOCAL) {
        List<dynamic> dataAsList = propertiesToIntList(sprite as MovingSprite, keyFrame);
        allData[sprite.networkId.toString()] = dataAsList;
      } else if (isCommander() && sprite.hasServerToOwnerData()) {
        List dataAsList = [Sprite.FLAG_COMMANDER_DATA];
        sprite.addServerToOwnerData(dataAsList);
        allData[sprite.networkId.toString()] = dataAsList;
      }
    }
    if (removals.length > 0) {
      allData[REMOVE_KEY] = removals;
    }
    if (!isCommander()) {
      // For none commanders, send keystate.
      allData[KEY_STATE_KEY] = _localKeyState.getEnabledState();
      if (keyFrame) {
        allData[FPS] = _drawFps.fps().toInt();
      }
    } else if (keyFrame || gameState.retrieveAndResetUrgentData()) {
      // For commander, send GameState.
      gameState.playerInfoByConnectionId(peer.id!)?.fps = _drawFps.fps().toInt();
      allData[GAME_STATE] = gameState.toMap();
    }
    if (keyFrame) {
      allData[CONNECTIONS_LIST] = [];
      Map<String, ConnectionInfo> connections = {};
      for (ConnectionWrapper wrapper in safeActiveConnections().values) {
        ConnectionInfo info = new ConnectionInfo(
            wrapper.id, wrapper.expectedLatency().inMilliseconds);
        allData[CONNECTIONS_LIST].add([info.to, info.latencyMillis]);
        connections[info.to] = info;
      }
      PlayerInfo? info = gameState.playerInfoByConnectionId(peer.id!);
      info?.connections = connections;
    }
  }
}
