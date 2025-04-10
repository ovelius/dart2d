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
        if (_world.byteWorld.initialized()) {
          _world.clearFromNetworkUpdate(update.byteWorldDestruction);
        } else {
          log.warning("TODO buffer byteworld data sent when world is loading!");
        }
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.byteWorldDraw, (ConnectionWrapper c, StateUpdate data) {
      if (c.isValidGameConnection()) {
        if (_world.byteWorld.initialized()) {
          _world.drawFromNetworkUpdate(data.byteWorldDraw);
        } else {
          log.warning("TODO buffer byteworld data sent when world is loading!");
        }
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.particleEffects, (ConnectionWrapper c, StateUpdate data) {
      if (c.isValidGameConnection()) {
        _world.addParticlesFromNetworkData(data);
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.clientEnter, (ConnectionWrapper c, StateUpdate data) {
      assert(_network.isCommander());
      GameState game = _gameState;
      PlayerInfoProto info = game.playerInfoByConnectionId(c.id)!;
      info.inGame = true;
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
      assert(!_network.isCommander());
      hudMessages.display("Got server challenge from ${connection.id}");
      _gameState.updateFromMap(reply.gameState);
      Vec2 position = Vec2.fromProto(reply.startingPosition);
      _world.createLocalClient(reply.spriteIndexStart, position);
      connection.setHandshakeReceived();
    } else {
      log.warning("Duplicate handshake received from ${connection}!");
    }
  }

  _handleClientConnect(ConnectionWrapper connection, StateUpdate data) {
    ClientPlayerSpec spec = data.clientPlayerSpec;
    CommanderGameReply reply = CommanderGameReply();
    StateUpdate updateReply = StateUpdate()
      ..commanderGameReply = reply;
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
