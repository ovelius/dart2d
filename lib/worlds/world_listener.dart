import 'package:dart2d/net/state_updates.pb.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/util/hud_messages.dart';
import 'package:dart2d/util/mobile_controls.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/util/gamestate.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/worlds/byteworld.dart';

@Injectable()
class WorldListener {
  final Logger log = new Logger('WorldListener');
  late WormWorld _world;
  ByteWorld _byteWorld;
  GameState _gameState;
  PacketListenerBindings _packetListenerBindings;
  Network _network;
  MobileControls _mobileControls;
  HudMessages hudMessages;

  WorldListener(this._packetListenerBindings, this._byteWorld, this._gameState, this._network, this.hudMessages, this._mobileControls) {
    _packetListenerBindings.bindHandler(StateUpdate_Update.commanderGameReply, _handleServerReply);
    _packetListenerBindings.bindHandler(StateUpdate_Update.clientPlayerSpec, _handleClientConnect);
    _packetListenerBindings.bindHandler(StateUpdate_Update.spriteRemoval, (ConnectionWrapper c, StateUpdate update) {
      if (c.isValidGameConnection()) {
        _world.removeSprite(update.spriteRemoval);
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.byteWorldDestruction, (ConnectionWrapper c, StateUpdate update) {
      if (c.isValidGameConnection()) {
        if (_world.byteWorld.byteWorldReady()) {
          _world.clearFromNetworkUpdate(update.byteWorldDestruction);
        } else {
          log.info("Buffering byteworld destruction");
          _world.loader.bufferDestruction.add(update.byteWorldDestruction);
        }
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.byteWorldDraw, (ConnectionWrapper c, StateUpdate data) {
      if (c.isValidGameConnection()) {
        if (_world.byteWorld.byteWorldReady()) {
          _byteWorld.drawFromNetworkUpdate(data.byteWorldDraw);
        } else {
          _world.loader.bufferDraws.add(data.byteWorldDraw);
          log.info("Buffering byteworld draw");
        }
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.particleEffects, (ConnectionWrapper c, StateUpdate data) {
      if (c.isValidGameConnection()) {
        _world.addParticlesFromNetworkData(data);
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.clientEnter, (ConnectionWrapper c, StateUpdate data) {
      if (!_network.isCommander()) {
        log.info("Ignoring clientEnter from ${c.id} because we are not commander.");
        return;
      }
      GameState game = _gameState;
      PlayerInfoProto? info = game.playerInfoByConnectionId(c.id);
      if (info == null) {
        log.info("Ignoring clientEnter from ${c.id} not yet in GameState.");
        return;
      }
      info.inGame = true;
      final Sprite? playerSprite = _world.spriteIndex[info.spriteId] ??
          _world.spriteIndex.getPendingSprite(info.spriteId);
      // `playerSprite` is `Sprite?` (may be null if not yet spawned or another
      // sprite type), so narrow to `LocalPlayerSprite` before resetting health,
      // shield, and collision when the client enters the game.
      if (playerSprite is LocalPlayerSprite) {
        playerSprite.health = LocalPlayerSprite.MAX_HEALTH;
        playerSprite.shieldPoints = 0;
        playerSprite.collision = true;
      }
      game.markAsUrgent();
    });

  }

  setWorld(WormWorld world) {
    _world = world;
  }

  _handleServerReply(ConnectionWrapper connection, StateUpdate data) {
    if (!connection.isValidGameConnection()) {
      CommanderGameReply reply = data.commanderGameReply;
      switch (reply.challengeReply) {
        case CommanderGameReply_ChallengeReply.REJECT_ENDED:
        case CommanderGameReply_ChallengeReply.REJECT_FULL:
          connection.close("Rejected by commander ${reply.challengeReply}");
          return;
        default:
      }
      if (_network.isCommander()) {
        log.info("Ignoring stale server reply from ${connection.id} while commander.");
        return;
      }
      hudMessages.display("Got server challenge from ${connection.id}");
      _gameState.updateFromMap(reply.gameState);
      Vec2 position = Vec2.fromProto(reply.startingPosition);
      _world.createLocalClient(reply.spriteIndexStart, position);
      connection.setHandshakeReceived();
      _world.connectToAllPeersInGameState();
    } else {
      log.warning("Duplicate handshake received from ${connection}!");
    }
  }

  _handleClientConnect(ConnectionWrapper connection, StateUpdate data) {
    ClientPlayerSpec spec = data.clientPlayerSpec;
    CommanderGameReply reply = CommanderGameReply();
    StateUpdate updateReply = StateUpdate()
      ..commanderGameReply = reply
      ..attachUniqueDataReceipt(connection);
    if (!_world.loader.completed()) {
      log.warning("Got client enter before loading completed, dropping");
      return;
    }
    if (!_network.isCommander() || _network.pendingCommandTransfer() != null) {
      log.info("Ignoring client connect from ${connection.id} while not active commander.");
      return;
    }
    final PlayerInfoProto? existingInfo =
        _gameState.playerInfoByConnectionId(connection.id);
    if (existingInfo != null && !existingInfo.inGame) {
      // Joining client was already registered in GameState by a previous
      // commander before command transferred, but still needs CommanderGameReply.
      final int spriteId = existingInfo.spriteId;
      final int spriteIndex = spec.playerImageId;
      existingInfo.name = spec.name;
      Sprite? existingSprite = _world.spriteIndex[spriteId] ??
          _world.spriteIndex.getPendingSprite(spriteId);
      Vec2 position;
      if (existingSprite is LocalPlayerSprite) {
        position = existingSprite.position;
        existingSprite.networkType = NetworkType.REMOTE_FORWARD;
        existingSprite.ownerId = connection.id;
      } else {
        position =
            _byteWorld.randomNotSolidPoint(LocalPlayerSprite.DEFAULT_PLAYER_SIZE);
        LocalPlayerSprite sprite = new LocalPlayerSprite(
            _world, _world.imageIndex(), _mobileControls, existingInfo, position, spriteIndex);
        _world.adjustPlayerSprite(sprite, spriteIndex);
        sprite.networkType = NetworkType.REMOTE_FORWARD;
        sprite.networkId = spriteId;
        sprite.ownerId = connection.id;
        _world.addSprite(sprite);
      }
      reply.spriteIndexStart = spriteId;
      reply.startingPosition = position.toProto();
      reply.gameState = _gameState.gameStateProto;
      connection.sendSingleUpdate(updateReply);
      connection.setHandshakeReceived();
      return;
    }
    if (connection.isValidGameConnection()) {
      log.warning("Duplicate handshake received from ${connection}!");
      return;
    }
    if (_gameState.isAtMaxPlayers()) {
      reply.challengeReply = CommanderGameReply_ChallengeReply.REJECT_FULL;
      connection.sendSingleUpdate(updateReply);
      // Mark as closed.
      connection.close("Game full");
      return;
    }
    if (_gameState.hasWinner()) {
      reply.challengeReply = CommanderGameReply_ChallengeReply.REJECT_ENDED;
      connection.sendSingleUpdate(updateReply);
      // Mark as closed.
      // TODO: We should not close connection here but rather allow the player to join next game.
      connection.close("Game over");
      return;
    }
    // Consider the client CLIENT_PLAYER_SPEC as the client having seen
    // the latest keyframe.
    // It will anyway get the keyframe from our response.
    int spriteId = _network.gameState.getNextUsablePlayerSpriteId(_world);
    int spriteIndex = spec.playerImageId;
    PlayerInfoProto info = new PlayerInfoProto()
      ..name = spec.name
      ..connectionId = connection.id
      ..spriteId = spriteId;
    _network.gameState.addPlayerInfo(info);

    Vec2 position = _byteWorld.randomNotSolidPoint(LocalPlayerSprite.DEFAULT_PLAYER_SIZE);

    LocalPlayerSprite sprite = new LocalPlayerSprite(_world, _world.imageIndex(), _mobileControls, info, position, spriteIndex);
    _world.adjustPlayerSprite(sprite, spriteIndex);

    sprite.networkType = NetworkType.REMOTE_FORWARD;
    sprite.networkId = spriteId;
    sprite.ownerId = connection.id;
    _world.addSprite(sprite);

    _world.displayHudMessageAndSendToNetwork("${spec.name} connected.");
    // Send updates gamestate here.
    reply.spriteIndexStart = spriteId;
    reply.startingPosition = position.toProto();
    reply.gameState = _gameState.gameStateProto;

    connection.sendSingleUpdate(updateReply);

    connection.setHandshakeReceived();
    // We don't expect any more players, disconnect the peer.
    if (_network.peer.connectedToServer() && _gameState.isAtMaxPlayers()) {
      _network.peer.disconnect();
    }
  }
}
