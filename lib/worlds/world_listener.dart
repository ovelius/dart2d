import 'package:di/di.dart';
import 'package:dart2d/net/net.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/mobile_controls.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';

@Injectable()
class WorldListener {
  final Logger log = new Logger('WorldListener');
  WormWorld _world;
  ImageIndex _imageIndex;
  PacketListenerBindings _packetListenerBindings;
  Network _network;
  MobileControls _mobileControls;
  HudMessages hudMessages;

  WorldListener(this._packetListenerBindings, this._network, this.hudMessages, this._imageIndex, this._mobileControls) {
    _packetListenerBindings.bindHandler(GAME_STATE, _handleGameState);
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
    _packetListenerBindings.bindHandler(WORLD_PARTICLE, (ConnectionWrapper c, List data) {
      if (c.isValidGameConnection()) {
        _world.addParticlesFromNetworkData(data);
      }
    });
    _packetListenerBindings.bindHandler(CLIENT_PLAYER_ENTER, (ConnectionWrapper c, dynamic) {
      assert(_network.isServer());
      GameState game = _network.gameState;
      PlayerInfo info = game.playerInfoByConnectionId(c.id);
      info.inGame = true;
      game.urgentData = true;
    });

  }

  setWorld(WormWorld world) {
    _world = world;
  }

  _handleGameState(ConnectionWrapper connection, Map data) {
    assert(!_network.isServer());
    if (!connection.isValidGameConnection()) {
      return;
    }
    GameState newGameState = new GameState.fromMap(data);
    _network.gameState = newGameState;
    _world.connectToAllPeersInGameState();
    if (_network.peer.connectedToServer() && newGameState.isAtMaxPlayers()) {
      _network.peer.disconnect();
    }
  }

  _handleServerReply(ConnectionWrapper connection, Map data) {
    if (!connection.isValidGameConnection()) {
      assert(connection.connectionType == ConnectionType.CLIENT_TO_SERVER);
      assert(!_network.isServer());
      hudMessages.display("Got server challenge from ${connection.id}");
      _world.createLocalClient(data["spriteId"], data["spriteIndex"]);
      connection.setHandshakeReceived();
    } else {
      log.warning("Duplicate handshake received from ${connection}!");
    }
  }

  _handleClientConnect(ConnectionWrapper connection, String name) {
    if (connection.isValidGameConnection()) {
      log.warning("Duplicate handshake received from ${connection}!");
      return;
    }
    if (_network.gameState.gameIsFull()) {
      connection.sendData({
        SERVER_PLAYER_REJECT: 'Game full',
        KEY_FRAME_KEY: connection.lastKeyFrameFromPeer,
        IS_KEY_FRAME_KEY: _network.currentKeyFrame});
      // Mark as closed.
      connection.close(null);
      return;
    }
    // Consider the client CLIENT_PLAYER_SPEC as the client having seen
    // the latest keyframe.
    // It will anyway get the keyframe from our response.
    connection.lastLocalPeerKeyFrameVerified = _network.currentKeyFrame;
    assert(connection.connectionType == ConnectionType.SERVER_TO_CLIENT);
    int spriteId = _network.gameState.getNextUsablePlayerSpriteId(_world);
    int spriteIndex = _network.gameState.getNextUsableSpriteImage(_imageIndex);
    PlayerInfo info = new PlayerInfo(name, connection.id, spriteId);
    _network.gameState.playerInfo.add(info);
    assert(info.connectionId != null);

    LocalPlayerSprite sprite = new RemotePlayerServerSprite(
        _world, _mobileControls, connection.remoteKeyState, info, 0.0, 0.0, spriteIndex);
    sprite.networkType =  NetworkType.REMOTE_FORWARD;
    sprite.networkId = spriteId;
    sprite.ownerId = connection.id;
    _world.addSprite(sprite);

    _world.displayHudMessageAndSendToNetwork("${name} connected.");
    Map serverData = {"spriteId": spriteId, "spriteIndex": spriteIndex};
    connection.sendData({
      SERVER_PLAYER_REPLY: serverData,
      KEY_FRAME_KEY:connection.lastKeyFrameFromPeer,
      IS_KEY_FRAME_KEY: _network.currentKeyFrame});

    connection.setHandshakeReceived();
    // We don't expect any more players, disconnect the peer.
    if (_network.peer.connectedToServer() && _network.gameState.gameIsFull()) {
      _network.peer.disconnect();
    }
  }
}
