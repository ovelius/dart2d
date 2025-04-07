library gamestate;

import 'dart:ffi';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:fixnum/src/int64.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/net/helpers.dart';

import '../net/connection.dart';
import '../net/state_updates.dart';

@Singleton(scope: 'world')
class GameState {
  static const MAX_PLAYERS = 4;
  final Logger log = new Logger('GameState');
  static final int ID_OFFSET_FOR_NEW_CLIENT = 1000;

  // Injected members.
  PacketListenerBindings _packetListenerBindings;
  SpriteIndex _spriteIndex;

  GameStateProto _gameStateProto = GameStateProto();
  GameStateProto get gameStateProto => _gameStateProto;
  void set gameStateProto(GameStateProto p) => _gameStateProto = p;
  Map<String, PlayerInfoProto> _playerInfoById = {};
  Map<String, KeyState> _playerKeyStateById = {};

  // True if we have urgent data for the network.
  bool _urgentData = false;

  void updateWithLocalKeyState(String connectionId, KeyState localState) {
    assert(!localState.remoteState);
    _playerKeyStateById[connectionId] = localState;
  }

  KeyState? getKeyStateFor(String connectionId) {
    return _playerKeyStateById[connectionId];
  }

  GameState(this._packetListenerBindings, this._spriteIndex) {
    _packetListenerBindings.bindHandler(StateUpdate_Update.keyState,
            (ConnectionWrapper connection, StateUpdate update) {
          KeyState? state = _playerKeyStateById[connection.id];
          state?.setEnabledKeys(update.keyState);
        });
    _gameStateProto.startedAtEpochMillis = Int64(new DateTime.now().millisecondsSinceEpoch);
  }

  bool retrieveAndResetUrgentData() {
    bool tUrgentData = _urgentData;
    _urgentData = false;
    return tUrgentData;
  }

  void markAsUrgent() {
    this._urgentData = true;
  }

  bool isConnected(String a, String b) =>  _playerInfoById.containsKey(a) ? _playerInfoById[a]!.isConnectedTo(b) : false;

  void reset() {
    _gameStateProto = GameStateProto();
    _playerInfoById = {};
    markAsUrgent();
  }

  bool isInGame(String id) {
    return _playerInfoById.containsKey(id);
  }

  bool hasWinner() {
    return gameStateProto.winnerPlayerId != "";
  }

  bool hasCommander() {
    return gameStateProto.actingCommanderId != "";
  }

  bool isAtMaxPlayers() {
    return gameStateProto.playerInfo.length >= MAX_PLAYERS;
  }

  List<PlayerInfoProto> playerInfoList() => new List.from(_gameStateProto.playerInfo);

  void addPlayerInfo(PlayerInfoProto info) {
    if (_playerInfoById.containsKey(info.connectionId)) {
      log.severe("Attempt to add playerInfo already in GameState! Not adding ${info}");
      return;
    }
    info.addedToGameEpochMillis = Int64(new DateTime.now().millisecondsSinceEpoch);
    _gameStateProto.playerInfo.add(info);
    _playerInfoById[info.connectionId] = info;
    _urgentData = true;
  }


  static bool updateContainsPlayerWithId(GameStateProto gameState, String id) {
    for (PlayerInfoProto info in gameState.playerInfo) {
      if (info.connectionId == id) {
        return true;
      }
    }
    return false;
  }

  updateFromMap(GameStateProto gameState) {
    Map<String, PlayerInfoProto> byId = {};
    for (PlayerInfoProto playerInfoProto in gameState.playerInfo) {
      PlayerInfoProto? info = playerInfoByConnectionId(playerInfoProto.connectionId);
      if (info == null) {
        info = playerInfoProto;
      }
      byId[info.connectionId] = info;
    }
    _playerInfoById = byId;
    _gameStateProto = gameState;
  }

  PlayerInfoProto? removeByConnectionId(WormWorld world, String id) {
    for (int i = _gameStateProto.playerInfo.length - 1; i >= 0; i--) {
      PlayerInfoProto info = _gameStateProto.playerInfo[i];
      if (info.connectionId == id) {
        _gameStateProto.playerInfo.removeAt(i);
        _playerInfoById.remove(info.connectionId);
        world.network().sendMessage("${info.name} disconnected :/", id);
        // This code runs under the assumption that we are acting server.
        // That means we have to do something about the dead servers sprite.
        Sprite? sprite = _spriteIndex[info.spriteId];
        // The game engine will not remove things if the REMOTE NetworkType.
        // So make the old servers sprite REMOTE_FORWARD.
        sprite?.networkType = NetworkType.REMOTE_FORWARD;
        world.removeSprite(info.spriteId);
        return info;
      }
    }
    log.info("Connection $id not in GameState, nothing to remove.");
    return null;
  }

  /**
   * Converts the world sprite state for us to become server.
   */
  convertToServer(WormWorld world, var selfConnectionId) {
    _gameStateProto.actingCommanderId = selfConnectionId;
    for (int i = _gameStateProto.playerInfo.length - 1; i >= 0; i--) {
      PlayerInfoProto info = _gameStateProto.playerInfo[i];
      // Convert self info to server.
      if (info.connectionId != selfConnectionId) {
        // Convert other players.
        ConnectionWrapper? connection =
            world.network().peer.connections[info.connectionId];
        if (connection == null) {
          // Connection isn't there :( Not much we can do but kill the playerinfo.
          removeByConnectionId(world, info.connectionId);
        }
      }
    }
  }

  PlayerInfoProto? playerInfoByConnectionId(String id) {
    return _playerInfoById[id];
  }

  PlayerInfoProto playerInfoBySpriteId(int id) {
    for (PlayerInfoProto info in playerInfoList()) {
      if (info.spriteId == id) {
        return info;
      }
    }
    throw "Can't find player for sprite $id";
  }

  int getNextUsablePlayerSpriteId(WormWorld world) {
    int id = ID_OFFSET_FOR_NEW_CLIENT +
        world.spriteNetworkId +
        _gameStateProto.playerInfo.length * ID_OFFSET_FOR_NEW_CLIENT;
    // Make sure we don't pick and ID we already use.
    while (world.spriteIndex.hasSprite(id)) {
      id = id + ID_OFFSET_FOR_NEW_CLIENT;
    }
    return id;
  }

  String toString() {
    return "GameState: ${_gameStateProto.toDebugString()}";
  }
}
