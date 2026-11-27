import 'package:dart2d/net/peer.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:injectable/injectable.dart';

import 'connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'package:logging/logging.dart' show Logger;

import 'helpers.dart';

// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0 / 2;

@Singleton(scope: 'world')
class Network {
  final Logger log = new Logger('Network');
  late WormWorld world;
  GameState gameState;
  late HudMessages _hudMessages;
  late SpriteIndex _spriteIndex;
  GaReporter _gaReporter;
  ConnectionFactory _connectionFactory;
  ConnectionFactory get connectionFactory => _connectionFactory;
  late KeyState _localKeyState;
  late PeerWrapper peer;
  PacketListenerBindings _packetListenerBindings;
  late FpsCounter _drawFps;
  double getCurrentFps() => _drawFps.fps();
  // If we are client, this indicates that the commander
  // is unable to ack our data.
  int commanderFramesBehind = 0;
  // How many times we trigger a frame while being very slow at doing so.
  // We may choose to give up our commanding role if this happens too much.
  int _slowCommandingFrames = 0;
  String? _pendingCommandTransfer = null;
  // Disables automatic command role transfer when the commander's FPS is low.
  // Used in tests that step frames manually with large durations (e.g. KEY_FRAME_DEFAULT),
  // which would otherwise look like a low framerate and trigger unexpected commander handoffs.
  bool disableCommandTransferHeuristicForTest = false;

  Network(
      this._gaReporter,
      this._connectionFactory,
      HudMessages hudMessages,
      this.gameState,
      this._packetListenerBindings,
      FpsCounter clientFrameCounter,
      ServerChannel serverChannel,
      ConfigParams configParams,
      SpriteIndex spriteIndex,
      KeyState localKeyState) {
    this._hudMessages = hudMessages;
    this._spriteIndex = spriteIndex;
    this._drawFps = clientFrameCounter;
    this._localKeyState = localKeyState;
    peer = new PeerWrapper(_connectionFactory, this, hudMessages, configParams,
        serverChannel, _packetListenerBindings, _gaReporter);

    _packetListenerBindings.bindHandler(StateUpdate_Update.gameState, _handleGameState);
    _packetListenerBindings.bindHandler(StateUpdate_Update.clientStatusData,
        (ConnectionWrapper connection, StateUpdate stateUpdate) {
        _handleClientStatusData(connection.id, stateUpdate.clientStatusData);
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.userMessage,
        (ConnectionWrapper connection, StateUpdate stateUpdate) {
      _forwardUpdateToDisconnectedPeers(connection, stateUpdate);
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.particleEffects,
        (ConnectionWrapper connection, StateUpdate stateUpdate) {
      _forwardUpdateToDisconnectedPeers(connection, stateUpdate);
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
      // Commander wants us to take command.
      log.info("Converting self ${peer.id} to commander");
      this.convertToCommander(this.safeActiveConnections(), null);
      _gaReporter.reportEvent(
          "convert_self_to_commander_on_request", "Commander");
    });

    _packetListenerBindings.bindHandler(StateUpdate_Update.commanderSwitchFromClosedConnection,
            (ConnectionWrapper connection, StateUpdate update) {
      String ourCommanderId = getGameState().gameStateProto.actingCommanderId;
      if (ourCommanderId == update.commanderSwitchFromClosedConnection) {
        // We have the same view of the world, nothing to do here.
        return;
      }
      if (update.commanderSwitchFromClosedConnection == peer.id) {
        // Someone elected us a commander.
        log.info("${connection.id} elected us ${peer.id} as commander but we have ${getGameState().gameStateProto.actingCommanderId}");
        if (hasNetworkProblem()) {
          // This is transient, we'll probably also switch commander soon.
          // Probably it's going to be us.
          // Ignore this.
          return;
        }
        // Suggest to commander we should be the commander.
        peer.sendSingleStateUpdate(StateUpdate()
          ..suggestSelfCommander = _createClientStatusData()
          ..attachSingleTonUniqueDataReceipt(), onlySendTo: ourCommanderId);
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.suggestSelfCommander,
            (ConnectionWrapper connection, StateUpdate update) {
      if (!isCommander()) {
        log.warning("Got suggested command transfer from ${connection.id} without being commander");
      }
      ClientStatusData clientStatusData = update.suggestSelfCommander;

      int stableConnections = 0;
      for (ConnectionWrapper connection in safeActiveConnections().values) {
        if (!connection.isProblematicFramesBehind()) {
          stableConnections++;
        }
      }

      log.info("Command transfer request by ${connection.id} with ${clientStatusData.connectionInfo.length} connections we have ${stableConnections}");

      if (stableConnections < clientStatusData.connectionInfo.length) {
        _sendPendingCommandTransfer(connection, "better connections");
      }
    });
  }

  _handleClientStatusData(String connectionId, ClientStatusData data) {
    /// Update the list of connections for this player.
    PlayerInfoProto? info = gameState.playerInfoByConnectionId(connectionId);
    info?.fps = data.fps;
    info?.connectionInfo.clear();
    info?.connectionInfo.addAll(data.connectionInfo);
  }

  /**
   * Our goal is to always have a connection to a commander.
   * This is checked when a connection is dropped.
   * Potentially this method will elect a new commander.
   * returns the id of the new commander, or null if no new commander was needed.
   *  peers.
   */
  String? findNewCommander(Map connections, {bool ignoreSelf = false}) {
    if (!isCommander()) {
      if (!gameState.isInGame(peer.id!)) {
        log.info("No active game found for us, no commander role to transfer.");
        return null;
      }
    }
    List<String> validKeys = [];
    for (String key in connections.keys) {
      // Someone not in GameState or never opened is not valid...
      ConnectionWrapper connection = connections[key];
      if (!connection.isActiveConnection()) {
        continue;
      }
      if (connection.id == gameState.gameStateProto.actingCommanderId) {
        log.info("${peer.id} has a commander connection using ${key}");
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
   * Counts confirmed mutual direct connections in GameState for [candidateId]
   * to other in-game peers (excluding [excludePeerId], such as a departing or
   * dropped commander).
   */
  int _countConfirmedPeerConnections(
      String candidateId, {String? excludePeerId}) {
    PlayerInfoProto? info = gameState.playerInfoByConnectionId(candidateId);
    if (info == null) {
      return 0;
    }
    Set<String> connectedPeers = {};
    for (ConnectionInfoProto conn in info.connectionInfo) {
      String otherId = conn.id;
      if (otherId == candidateId || otherId == excludePeerId) {
        continue;
      }
      if (!gameState.isInGame(otherId)) {
        continue;
      }
      if (_hasMutualDirectConnection(candidateId, otherId)) {
        connectedPeers.add(otherId);
      }
    }
    return connectedPeers.length;
  }

  bool _isCandidateReadyToCommand(String candidateId) {
    final PlayerInfoProto? info = gameState.playerInfoByConnectionId(candidateId);
    if (candidateId == peer.id) {
      return safeLoaderCompleted() && (info?.inGame ?? false);
    }
    return info?.inGame ?? false;
  }

  /**
   * When the commander dies unexpectedly we need to make a collective decision on
   * who will be the next commander. Prefer in-game peers over still-loading
   * peers, then the reachable peer with the most confirmed peer-to-peer
   * connections in GameState, breaking ties deterministically by natural order
   * peerId.
   */
  String _naturalOrderPeerId(List<String> validKeys) {
    String oldCommanderId = gameState.gameStateProto.actingCommanderId;
    List<String> candidates = [peer.id!, ...validKeys];
    String bestPeerKey = peer.id!;
    bool bestReady = _isCandidateReadyToCommand(bestPeerKey);
    int bestConnections = -1;
    for (String candidateId in candidates) {
      bool ready = _isCandidateReadyToCommand(candidateId);
      int connCount = _countConfirmedPeerConnections(
          candidateId, excludePeerId: oldCommanderId);
      bool betterReady = ready && !bestReady;
      bool sameReady = ready == bestReady;
      if (betterReady ||
          (sameReady && connCount > bestConnections) ||
          (sameReady &&
              connCount == bestConnections &&
              candidateId.compareTo(bestPeerKey) < 0)) {
        bestReady = ready;
        bestConnections = connCount;
        bestPeerKey = candidateId;
      }
    }
    return bestPeerKey;
  }

  /**
   * Select the best next commander when handing off command: prioritize
   * in-game peers first, then the candidate with the most confirmed peer
   * connections, breaking ties by highest FPS and then natural peerId order.
   */
  String? _bestCommanderPeerId(List<String> validKeys) {
    bool bestReady = false;
    bool hasAnyCandidate = false;
    int bestConnections = -1;
    double bestFps = -1;
    String? bestKey = null;
    for (String peerId in validKeys) {
      PlayerInfoProto? info = gameState.playerInfoByConnectionId(peerId);
      if (info == null) {
        continue;
      }
      bool ready = info.inGame;
      int connCount =
          _countConfirmedPeerConnections(peerId, excludePeerId: peer.id);
      bool betterReady = !hasAnyCandidate || (ready && !bestReady);
      bool sameReady = hasAnyCandidate && (ready == bestReady);
      bool betterConnections = sameReady && connCount > bestConnections;
      bool tiedConnectionsBetterFps =
          sameReady && connCount == bestConnections && info.fps > bestFps;
      bool tiedBothBetterOrder = sameReady &&
          connCount == bestConnections &&
          info.fps == bestFps &&
          bestKey != null &&
          peerId.compareTo(bestKey) < 0;
      if (betterReady ||
          betterConnections ||
          tiedConnectionsBetterFps ||
          tiedBothBetterOrder) {
        hasAnyCandidate = true;
        bestReady = ready;
        bestConnections = connCount;
        bestFps = info.fps;
        bestKey = peerId;
      }
    }
    log.info(
        "Identified ${bestKey} as best suitable commander with ${bestConnections} peer connections and fps ${bestFps}");
    return bestKey;
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
      Map<String, ConnectionWrapper> connections, PlayerInfoProto? previousCommanderPlayerInfo) {
    _hudMessages.display("Commander role transferred to you :)");
    String oldCommanderId = gameState.gameStateProto.actingCommanderId;
    gameState.convertToServer(world, this.peer.id);
    List<Sprite> allSprites = [
      for (int id in new List.from(_spriteIndex.spriteIds()))
        if (_spriteIndex.isPendingRemoval(id) != true) _spriteIndex[id]!,
      for (Sprite pending in (_spriteIndex.pendingSprites() ?? const <Sprite>[]))
        if (pending.networkId == null ||
            _spriteIndex.isPendingRemoval(pending.networkId!) != true)
          pending,
    ];
    for (Sprite sprite in allSprites) {
      // Transfer ownership of commander-owned world sprites (such as Powerups
      // and projectiles) to us, keeping their exact state as is.
      if (sprite is! LocalPlayerSprite && sprite is! Rope) {
        if ((sprite is Powerup || sprite.ownerId == oldCommanderId) &&
            sprite.networkType == NetworkType.REMOTE) {
          sprite.ownerId = null;
          sprite.networkType = NetworkType.LOCAL;
          sprite.fullFramesOverNetwork = 6;
        }
      }
      // Remove any projectiles/ropes belonging to a departed commander player.
      if (previousCommanderPlayerInfo != null && sprite is MovingSprite &&
          sprite.owner?.networkId == previousCommanderPlayerInfo.spriteId) {
        sprite.remove = true;
        sprite.collision = false;
      }
    }
    for (String id in connections.keys) {
      ConnectionWrapper connection = connections[id]!;
      // `connections` comes from PeerWrapper.connections before remaining closed
      // or still-opening peers in the same tick are pruned; skip inactive ones
      // so we don't send pings on closed channels or recycle dead peers.
      if (!connection.isActiveConnection()) {
        continue;
      }
      connection.sendPing();
      PlayerInfoProto? info = gameState.playerInfoByConnectionId(id);
      if (info == null && connection.isValidGameConnection()) {
        info = gameState.getRemovedPlayerInfo(id);
        if (info != null) {
          log.info("Recycling player ${id} back into GameState");
          gameState.addPlayerInfo(info);
        }
      }
      if (info != null) {
        // Ensure connections to peers already in GameState (including clients
        // mid-join with inGame == false) are marked handshake-ready.
        connection.setHandshakeReceived();
        // Make it our responsibility to forward data from other players.
        Sprite? sprite = _spriteIndex[info.spriteId];
        if (sprite == null) {
          sprite = world.spriteIndex.maybeResurrectPlayerSprite(info.spriteId);
        }
        if (sprite?.networkType == NetworkType.REMOTE) {
          sprite?.networkType = NetworkType.REMOTE_FORWARD;
        }
        // Also promote any client-owned auxiliary sprites (e.g. Rope) from
        // active peers so the new commander forwards them across missing P2P links.
        for (int spriteId in _spriteIndex.spriteIds()) {
          Sprite? s = _spriteIndex[spriteId];
          if (s != null &&
              s.ownerId == id &&
              s.networkType == NetworkType.REMOTE) {
            s.networkType = NetworkType.REMOTE_FORWARD;
          }
        }
      } else {
        // Peer is not in GameState yet (e.g. a joining client still in
        // CONNECTING_TO_GAME); keep handshake false so we accept their
        // ClientPlayerSpec!
        connection.resetHandshakeReceived();
      }
    }
    world.powerupManager()?.syncWithSpriteIndex();
    gameState.markAsUrgent();
    for (ConnectionWrapper connection in connections.values) {
      if (connection.isActiveConnection()) {
        connection.sendSingleUpdate(
            StateUpdate()..gameState = gameState.gameStateProto);
      }
    }
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
    CommanderTieBreakOutcome tieBreakOutcome = CommanderTieBreakOutcome.none;
    try {
      tieBreakOutcome = world.loader.playerWorldSelector
          .resolveIncomingCommanderGameState(connection, newGameState);
    } catch (_) {}
    if (tieBreakOutcome == CommanderTieBreakOutcome.localWinsIgnoreRemote) {
      log.info(
          "Ignoring simultaneous commander GameState from ${connection.id} after winning map tie-break.");
      return;
    }
    if (isCommander() && pendingCommandTransfer() == null) {
      log.warning(
          "Not parsing gamestate from ${connection.id} because we are commander!");
      if (!GameState.updateContainsPlayerWithId(newGameState, peer.id!)) {
        // We are not even in the received GameState..grr..
        if (newGameState.actingCommanderId == connection.id) {
          connection.close("two commanders talking to eachother");
          _gaReporter.reportEvent("network", "two_commander_connection");
        }
      }
      return;
    }
    final String oldCommanderId = gameState.gameStateProto.actingCommanderId;
    if (gameState.playerInfoByConnectionId(peer.id!) != null &&
      !GameState.updateContainsPlayerWithId(newGameState, peer.id!)) {
      // We are in the old GameState, but the new GameState does not have us :(
      if (oldCommanderId != newGameState.actingCommanderId &&
          newGameState.actingCommanderId == connection.id) {
        final bool oldCommanderStillActive = oldCommanderId.isNotEmpty &&
            safeActiveConnections().containsKey(oldCommanderId);
        final bool newCommanderWasPeerInOurGame =
            gameState.playerInfoByConnectionId(connection.id) != null ||
                gameState.getRemovedPlayerInfo(connection.id) != null;
        if (!safeLoaderCompleted() &&
            (!oldCommanderStillActive || newCommanderWasPeerInOurGame)) {
          log.info(
              "Commander changed from $oldCommanderId to ${connection.id} mid-join before our join synced; re-handshaking.");
          world.resetPartialJoinForNewCommander(connection);
        } else {
          // Also this GameState doesn't match out expected CommanderId.
          // So we don't want to listen to this connection.
          connection.close("multiple commander connections");
          _gaReporter.reportEvent(
              "network", "multiple_commanders_connection_closed");
          return;
        }
      }
    }
    gameState.updateFromMap(newGameState);

    if (!safeLoaderCompleted() && !isCommander()) {
      ConnectionWrapper? serverConn = getServerConnection();
      if (serverConn != null) {
        bool hasLocalSprite = false;
        try {
          hasLocalSprite = world.playerSprite != null;
        } catch (_) {}
        if (hasLocalSprite && gameState.isInGame(peer.id!)) {
          serverConn.setHandshakeReceived();
        } else if (!hasLocalSprite) {
          serverConn.resetHandshakeReceived();
        }
      }
    }

    // Command transfer successful.
    if (_pendingCommandTransfer != null &&
       gameState.gameStateProto.actingCommanderId == _pendingCommandTransfer) {
      final String newCommanderId = gameState.gameStateProto.actingCommanderId;
      List<Sprite> allSprites = [
        for (int spriteId in _spriteIndex.spriteIds()) _spriteIndex[spriteId]!,
        ...(_spriteIndex.pendingSprites() ?? const <Sprite>[]),
      ];
      // Change sprite types. We are no longer commander.
      for (Sprite sprite in allSprites) {
        if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
          sprite.networkType = NetworkType.REMOTE;
        } else if (sprite.networkType == NetworkType.LOCAL &&
            sprite is! LocalPlayerSprite &&
            !(sprite is Rope &&
                sprite.owner?.networkId == world.playerSprite?.networkId)) {
          sprite.networkType = NetworkType.REMOTE;
          sprite.ownerId = newCommanderId;
        }
      }
      world.powerupManager()?.syncWithSpriteIndex();
      log.info("Successfully command transfer to ${newCommanderId}");
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
    if (peer.id == null) {
      return false;
    }
    Map<String, ConnectionWrapper> connections = safeActiveConnections();
    List<String> closeAbleNotServer = [];
    if (connections.containsKey(gameState.gameStateProto.actingCommanderId)) {
      if (gameState.isAtMaxPlayers() && !gameState.isInGame(peer.id!)) {
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
          log.info("Closing connection $connection in search for game.");
          connection.close("No game found");

          // Remove right away, so autoConnectToPeers doesn't count this connection.
          // TODO: Should we instead clean connections in autoConnectToPeers?
          peer.removeClosedConnection(connection.id);

          if (!peer.autoConnectToPeers()) {
            // We didn't add any new peers. Bail.
            log.warning(
                "didn't find any commanders, and not able to connect to any more peers. Giving up.");
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
      final bool hasOpeningConnection = peer.connections.values
          .any((c) => !c.isClosedConnection() && !c.isActiveConnection());
      if (hasOpeningConnection) {
        return false;
      }
      if (!peer.autoConnectToPeers()) {
        // We didn't add any new peers. Bail.
        return true;
      }
    }
    return false;
  }

  /**
   * Returns true if the network is in such a problematic state we should notify the user.
   */
  bool hasNetworkProblem() {
    return commanderFramesBehind >= ConnectionWrapper.PROBLEMATIC_FRAMES_BEHIND && !isCommander();
  }

  void sendMessage(String message, [String? dontSendTo]) {
    StateUpdate update = new StateUpdate()
      ..dataReceipt = message.hashCode
      ..userMessage = message;
    GameStateUpdates state = GameStateUpdates()
      ..stateUpdate.add(update);
    peer.sendDataWithKeyFramesToAll(state, dontSendTo: dontSendTo);
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
      commanderFramesBehind = 0;
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
        commanderFramesBehind = serverConnection.recipientFramesBehind();
      }
    }

    // Transfer our commanding role to someone else!
    if (!disableCommandTransferHeuristicForTest && isCommander() && isTooSlowForCommanding()) {
      log.info("Self framerate is too low ${_slowCommandingFrames} attempting to transfer command role");
      Map connections = safeActiveConnections();
      String? newCommander = findNewCommander(connections, ignoreSelf: true);
      if (newCommander != null) {
        _sendPendingCommandTransfer(connections[newCommander], "slow self framerate");
      }
    }
  }

  /**
   * Immediately transfer the commander role to the best connected peer
   * (e.g. when the browser tab is closing or moved to the background).
   * Returns true if a command transfer was initiated.
   */
  bool transferCommander(String reason) {
    if (peer.id == null || !isCommander() || _pendingCommandTransfer != null) {
      return false;
    }
    Map<String, ConnectionWrapper> connections = safeActiveConnections();
    String? newCommander = findNewCommander(connections, ignoreSelf: true);
    if (newCommander == null) {
      return false;
    }
    log.info("Transferring command role to $newCommander ($reason)");
    _sendPendingCommandTransfer(connections[newCommander]!, reason);
    return true;
  }

  /**
   * Gracefully closes all active peer connections, sending a goodbye message
   * on each before closing the underlying WebRTC transport.
   */
  void sendGoodbye(String reason) {
    if (isCommander() && _pendingCommandTransfer != null) {
      // Notify other active clients of the chosen successor before closing our
      // channels so they don't run a competing election upon seeing goodbye.
      gameState.gameStateProto.actingCommanderId = _pendingCommandTransfer!;
      for (ConnectionWrapper connection in safeActiveConnections().values) {
        if (connection.id != _pendingCommandTransfer &&
            connection.isValidGameConnection()) {
          connection.sendSingleUpdate(
              StateUpdate()..gameState = gameState.gameStateProto);
        }
      }
    }
    for (ConnectionWrapper connection in List.of(peer.connections.values)) {
      if (!connection.closed) {
        connection.close(reason);
      }
    }
  }

  _sendPendingCommandTransfer(ConnectionWrapper connection, String reason) {
    connection.sendCommandTransfer();
    _slowCommandingFrames = 0;
    log.info("Attempting to transfer command rule due to $reason");
    _pendingCommandTransfer = connection.id;
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
          "${connection.id} FR:${connection.currentFrameRate()} "
              "ms:${connection.expectedLatency().inMilliseconds} by: "
              "${connection.stats()} frames: ${connection.frameStats()}");
    }
    return debugStrings;
  }

  void parseBundle(ConnectionWrapper connection, GameStateUpdates data) {
  for (SpriteUpdate update in data.spriteUpdates) {
      if (update.flags & Sprite.FLAG_COMMANDER_DATA ==
          Sprite.FLAG_COMMANDER_DATA) {
        assert(update.hasSpriteId());
        // parse as commander data update.
        MovingSprite? sprite = (world.spriteIndex[update.spriteId] ??
            world.spriteIndex.getPendingSprite(update.spriteId)) as MovingSprite?;
        if (sprite == null) {
          final PlayerInfoProto? ownerInfo =
              gameState.maybePlayerInfoBySpriteId(update.spriteId);
          if (world.loaderCompleted() &&
              peer.id != null &&
              (gameState.playerInfoByConnectionId(peer.id!)?.inGame ?? false) &&
              (ownerInfo?.inGame ?? true)) {
            log.warning(
                "Commander data update for missing sprite ${update.spriteId}");
          }
          continue;
        }
        if (isCommander()) {
          log.warning("Warning: Attempt to update local sprite ${sprite
              .networkId} from network ${connection.id}.");
          continue;
        }
        sprite.commanderToOwnerData(update.commanderToOwnerData);
      } else {
        // Parse as generic update.
        SpriteConstructor constructor = SpriteConstructor.DO_NOT_CREATE;
        // Only try and construct sprite if this is a full frame - we have all
        // the data.
        if (update.flags & Sprite.FLAG_FULL_FRAME == Sprite.FLAG_FULL_FRAME) {
          constructor = SpriteConstructor.values[update.remoteRepresentation];
        }
        MovingSprite? sprite = (_spriteIndex[update.spriteId] ??
            _spriteIndex.getPendingSprite(update.spriteId)) as MovingSprite?;
        if (sprite == null && constructor != SpriteConstructor.DO_NOT_CREATE) {
          sprite = _spriteIndex.CreateSpriteFromNetwork(
              world, update.spriteId, constructor, connection, update);
        }
        if (sprite == null) {
          log.fine("Sprite ${update.toDebugString()} can't be created, constructor: ${constructor}");
          continue;
        }
        if (sprite.networkType == NetworkType.LOCAL) {
          // Never let a remote generic update overwrite our own local sprite.
          continue;
        }
        intListToSpriteProperties(update, sprite);
        if (sprite.networkType == NetworkType.REMOTE &&
            sprite is! LocalPlayerSprite &&
            sprite is! Rope &&
            connection.id == gameState.gameStateProto.actingCommanderId) {
          sprite.ownerId = connection.id;
        }
        // Forward sprite to others.
        if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
          for (ConnectionWrapper receipientConnection
              in safeActiveConnections().values) {
            if (connection.id == receipientConnection.id) {
              // Don't send back from where it came.
              continue;
            }
            // Don't forward if BOTH peers confirm a direct connection between
            // them; checking only one direction drops updates on asymmetric or
            // half-open client-to-client connections.
            if (!_hasMutualDirectConnection(
                connection.id, receipientConnection.id)) {
              GameStateUpdates g = GameStateUpdates()
                 ..spriteUpdates.add(update);
              peer.sendDataWithKeyFramesToAll(
                  g, onlySendTo: receipientConnection.id);
            }
          }
        }
      }
    }
  }

  void _forwardUpdateToDisconnectedPeers(
      ConnectionWrapper source, StateUpdate update) {
    if (!isCommander() || !source.isValidGameConnection()) {
      return;
    }
    for (ConnectionWrapper recipient in safeActiveConnections().values) {
      if (recipient.id == source.id || !recipient.isValidGameConnection()) {
        continue;
      }
      if (!_hasMutualDirectConnection(source.id, recipient.id)) {
        GameStateUpdates forwarded = GameStateUpdates()
          ..stateUpdate.add(update);
        peer.sendDataWithKeyFramesToAll(forwarded, onlySendTo: recipient.id);
      }
    }
  }

  bool _hasMutualDirectConnection(String a, String b) {
    return gameState.isConnected(a, b) && gameState.isConnected(b, a);
  }

  void stateBundle(bool keyFrame, GameStateUpdates updates, {String? recipientId}) {
    for (int networkId in _spriteIndex.spriteIds()) {
      Sprite sprite = _spriteIndex[networkId]!;
      if (sprite.networkType == NetworkType.LOCAL) {
        updates.spriteUpdates.add(
            toSpriteUpdate(sprite as MovingSprite, keyFrame));
      } else if (isCommander()) {
        if (keyFrame &&
            recipientId != null &&
            sprite is MovingSprite &&
            sprite.networkType == NetworkType.REMOTE_FORWARD &&
            sprite.ownerId != null &&
            sprite.ownerId != recipientId &&
            !_hasMutualDirectConnection(sprite.ownerId!, recipientId)) {
          // Guarantee non-commanders without a confirmed mutual direct P2P
          // link receive full-frame client-owned sprites (player sprites,
          // ropes) on the commander's regular monotonic keyframes.
          updates.spriteUpdates.add(toSpriteUpdate(sprite, true));
        }
        if (_pendingCommandTransfer == null &&
            sprite.hasCommanderToOwnerData()) {
          SpriteUpdate update = SpriteUpdate()
            ..spriteId = networkId
            ..flags = Sprite.FLAG_COMMANDER_DATA
            ..commanderToOwnerData = sprite.getCommanderToOwnerData();
          updates.spriteUpdates.add(update);
        }
      }
    }
    if (!isCommander()) {
      updates.stateUpdate.add(StateUpdate()
        ..keyState = _localKeyState.toKeyStateProto());
    } else if (keyFrame || gameState.retrieveAndResetUrgentData()) {
      gameState
          .playerInfoByConnectionId(peer.id!)
          ?.fps = _drawFps.fps();
      updates.stateUpdate.add(StateUpdate()
        ..gameState = gameState.gameStateProto);
    }
    if (keyFrame) {
      ClientStatusData clientData = _createClientStatusData();
      _handleClientStatusData(peer.id!, clientData);
      if (!isCommander()) {
        updates.stateUpdate.add(StateUpdate()
          ..clientStatusData = clientData);
      }
    }
  }

  ClientStatusData _createClientStatusData() {
    ClientStatusData clientStatusData = ClientStatusData()
      ..fps = _drawFps.fps();
    for (ConnectionWrapper c in safeActiveConnections().values) {
      if (!c.isValidGameConnection()) {
        continue;
      }
      clientStatusData.connectionInfo.add(ConnectionInfoProto()
        ..id = c.id
        ..latencyMillis = c
            .expectedLatency()
            .inMilliseconds);
    }
    return clientStatusData;
  }

  final Map<String, PerformanceGovernor> _remotePeerGovernors =
      <String, PerformanceGovernor>{};

  /// Bridges [WormWorld.performanceGovernor] (and per-peer governors) into
  /// [ConnectionFrameHandler] so visual detail is lowered first and network FPS
  /// is only reduced once visual quality has already stepped down.
  double governedSelfFpsForNetwork() {
    try {
      return world.performanceGovernor.equivalentDrawFpsForNetwork(
        minRate: ConnectionFrameHandler.MIN_FRAMERATE,
        maxRate: ConnectionFrameHandler.MAX_FRAMERATE,
      );
    } catch (_) {
      final double raw = getCurrentFps();
      return raw > 0.0 ? raw : 60.0;
    }
  }

  double governedRemoteFpsForNetwork(
    String peerId,
    double reportedPeerFps,
    double keyFrameStepSeconds,
  ) {
    // Before a peer has reported its first 1s FPS sample (`<= 0.0`), keep full
    // network framerate rather than prematurely throttling to 6 Hz.
    if (reportedPeerFps <= 0.0) {
      return 60.0;
    }
    final PerformanceGovernor peerGov =
        _remotePeerGovernors.putIfAbsent(peerId, () => PerformanceGovernor());
    final bool peerIsCommander =
        getGameState().gameStateProto.actingCommanderId == peerId;
    peerGov.update(
      keyFrameStepSeconds.clamp(0.05, 1.30),
      reportedPeerFps,
      isCommander: peerIsCommander,
      maxDt: 1.50,
    );
    return peerGov.equivalentDrawFpsForNetwork(
      minRate: ConnectionFrameHandler.MIN_FRAMERATE,
      maxRate: ConnectionFrameHandler.MAX_FRAMERATE,
    );
  }

  bool safeLoaderCompleted() {
    try {
      return world.loaderCompleted();
    } catch (_) {
      return true;
    }
  }

  void handleCommanderLostWhileJoining(
    String droppedCommanderId,
    Map<String, ConnectionWrapper> remainingConnections,
  ) {
    final String? selfId = peer.id;
    // Clear the dropped actingCommanderId FIRST so any fresh WebRTC OFFERs to
    // surviving peers go over serverChannel rather than routing via the dead
    // commander.
    if (gameState.gameStateProto.actingCommanderId == droppedCommanderId) {
      gameState.gameStateProto.actingCommanderId = "";
    }

    // Connect (or re-initiate never-opened commander-relayed attempts) to any
    // surviving peers we knew from GameState so we can discover the new commander.
    for (PlayerInfoProto p in gameState.playerInfoList()) {
      final String pid = p.connectionId;
      if (pid.isEmpty || pid == droppedCommanderId || pid == selfId) {
        continue;
      }
      final ConnectionWrapper? existing = peer.connections[pid];
      if (existing != null &&
          !existing.wasOpen() &&
          !existing.isActiveConnection()) {
        // Previous OFFER was likely relayed via the dead commander and never
        // reached `pid`; re-initiate cleanly over serverChannel.
        peer.connections.remove(pid);
      }
      if (!peer.hasConnectionTo(pid) && !peer.hasHadConnectionTo(pid)) {
        try {
          peer.connectTo(pid);
        } catch (_) {}
      }
    }

    bool anyOtherOpenOrOpening = false;
    for (ConnectionWrapper c in peer.connections.values) {
      if (!c.isClosedConnection()) {
        anyOtherOpenOrOpening = true;
        c.resetInitialPingForCommanderSearch();
      }
    }

    if (anyOtherOpenOrOpening) {
      world.resetPartialJoinForNewCommander(null);
    } else {
      gameState.reset();
      world.resetPartialJoinForNewCommander(null);
    }
  }
}
