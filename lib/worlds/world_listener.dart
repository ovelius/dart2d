import 'package:di/di.dart';
import 'package:dart2d/net/net.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/util/hud_messages.dart';
import 'package:dart2d/util/mobile_controls.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/util/gamestate.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';

@Injectable()
class WorldListener {
  final Logger log = new Logger('WorldListener');
  WormWorld _world;
  ByteWorld _byteWorld;
  GameState _gameState;
  PacketListenerBindings _packetListenerBindings;
  Network _network;
  MobileControls _mobileControls;
  HudMessages hudMessages;

  WorldListener(this._packetListenerBindings, this._byteWorld, this._gameState, this._network, this.hudMessages, this._mobileControls) {
    _packetListenerBindings.bindHandler(SERVER_PLAYER_REPLY, _handleServerReply);
    _packetListenerBindings.bindHandler(CLIENT_PLAYER_SPEC, _handleClientConnect);
    _packetListenerBindings.bindHandler(REMOVE_KEY, (ConnectionWrapper c, List removals) {
      if (c.isValidGameConnection()) {
        for (int id in removals) {
          _world.removeSprite(id);
        }
      }
    });
    _packetListenerBindings.bindHandler(WORLD_DESTRUCTION, (ConnectionWrapper c, List data) {
      if (c.isValidGameConnection()) {
        if (_world.byteWorld.initialized()) {
          _world.clearFromNetworkUpdate(data);
        } else {
          log.warning("TODO buffer byteworld data sent when world is loading!");
        }
      }
    });
    _packetListenerBindings.bindHandler(WORLD_DRAW, (ConnectionWrapper c, List data) {
      if (c.isValidGameConnection()) {
        if (_world.byteWorld.initialized()) {
          _world.drawFromNetworkUpdate(data);
        } else {
          log.warning("TODO buffer byteworld data sent when world is loading!");
        }
      }
    });
    _packetListenerBindings.bindHandler(WORLD_PARTICLE, (ConnectionWrapper c, List data) {
      if (c.isValidGameConnection()) {
        for (List particleData in data) {
          _world.addParticlesFromNetworkData(particleData);
        }
      }
    });
    _packetListenerBindings.bindHandler(CLIENT_PLAYER_ENTER, (ConnectionWrapper c, dynamic) {
      assert(_network.isCommander());
      GameState game = _gameState;
      PlayerInfo info = game.playerInfoByConnectionId(c.id);
      if (info == null) {
        throw new StateError("Client for ${c.id} can't enter game, missing from GameState?");
      }
      info.inGame = true;
      game.markAsUrgent();
    });

  }

  setWorld(WormWorld world) {
    _world = world;
  }

  _handleServerReply(ConnectionWrapper connection, Map data) {
    if (!connection.isValidGameConnection()) {
      assert(!_network.isCommander());
      hudMessages.display("Got server challenge from ${connection.id}");
      _gameState.updateFromMap(data[GAME_STATE]);
      Vec2 position = new Vec2(data['x'], data['y']);
      _world.createLocalClient(data["spriteId"], position);
      connection.setHandshakeReceived();
    } else {
      log.warning("Duplicate handshake received from ${connection}!");
    }
  }

  _handleClientConnect(ConnectionWrapper connection, List data) {
    String name = data[0];
    if (connection.isValidGameConnection()) {
      log.warning("Duplicate handshake received from ${connection}!");
      return;
    }
    if (_gameState.isAtMaxPlayers()) {
      connection.sendData({
        SERVER_PLAYER_REJECT: 'Game full',
        KEY_FRAME_KEY: connection.lastRemoteKeyFrame,
        IS_KEY_FRAME_KEY: connection.currentKeyFrame()});
      // Mark as closed.
      connection.close("Game full");
      return;
    }
    if (_gameState.hasWinner()) {
      connection.sendData({
        SERVER_PLAYER_REJECT: 'Game already completed',
        KEY_FRAME_KEY: connection.lastRemoteKeyFrame,
        IS_KEY_FRAME_KEY: connection.currentKeyFrame()});
      // Mark as closed.
      connection.close("Game over");
      return;
    }
    // Consider the client CLIENT_PLAYER_SPEC as the client having seen
    // the latest keyframe.
    // It will anyway get the keyframe from our response.
    int spriteId = _network.gameState.getNextUsablePlayerSpriteId(_world);
    int spriteIndex = data[1];
    PlayerInfo info = new PlayerInfo(name, connection.id, spriteId);
    _network.gameState.addPlayerInfo(info);
    assert(info.connectionId != null);

    Vec2 position = _byteWorld.randomNotSolidPoint(LocalPlayerSprite.DEFAULT_PLAYER_SIZE);

    LocalPlayerSprite sprite = new LocalPlayerSprite(_world, _world.imageIndex(), _mobileControls, info, position, spriteIndex);
    _world.adjustPlayerSprite(sprite, spriteIndex);

    sprite.networkType = NetworkType.REMOTE_FORWARD;
    sprite.networkId = spriteId;
    sprite.ownerId = connection.id;
    _world.addSprite(sprite);

    _world.displayHudMessageAndSendToNetwork("${name} connected.");
    // Send updates gamestate here.
    Map serverData = {"spriteId": spriteId,
      'x': position.x.toInt(), 'y': position.y.toInt(),
      GAME_STATE: _network.getGameState().toMap()};
    connection.sendData({
      SERVER_PLAYER_REPLY: serverData,
      KEY_FRAME_KEY:connection.lastRemoteKeyFrame,
      IS_KEY_FRAME_KEY: connection.currentKeyFrame()});

    connection.setHandshakeReceived();
    // We don't expect any more players, disconnect the peer.
    if (_network.peer.connectedToServer() && _gameState.isAtMaxPlayers()) {
      _network.peer.disconnect();
    }
  }
}
