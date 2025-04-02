library gamestate;

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


extension DecorateWithKeyState on PlayerInfoProto {

  KeyState _remoteKeyState = new KeyState.remote();

  void updateWithLocalKeyState(KeyState localState) {

  }
}


class PlayerInfo {
  late String name;
  late String connectionId;
  late int spriteId;
  int score = 0;
  int deaths = 0;
  bool inGame = false;
  late int addedToGameAtMillis;
  // How many frames per second this client has.
  int fps = 45;
  // What conenctions this player has.
  Map<String, ConnectionInfoProto> connections = {};
  // Keystate for the remote player, will only be set if
  // the remote peer is a client.
  KeyState _remoteKeyState = new KeyState.remote();

  PlayerInfo(this.name, this.connectionId, this.spriteId);

  PlayerInfo.fromMap(Map map) {
    updateFromMap(map);
  }

  void updateFromMap(Map map) {
    name = map["n"];
    spriteId = map["sid"];
    fps = map['f'];
    connectionId = map["cid"];
    score = map["s"];
    deaths = map["d"];
    Map<String, ConnectionInfo> newConnectionsInfo = {};
    for (List item in map['c']) {
      newConnectionsInfo[item[0]] = new ConnectionInfo(item[0], item[1]);
    }
    connections = newConnectionsInfo;
    inGame = map.containsKey("g");
    addedToGameAtMillis = map["gm"];
  }

  KeyState remoteKeyState() => _remoteKeyState;

  bool isConnectedTo(String other) => connections.containsKey(other);

  void updateWithLocalKeyState(KeyState localState) {
    assert(!localState.remoteState);
    _remoteKeyState = localState;
  }

  Map toMap() {
    Map map = new Map();
    map["n"] = name;
    map["sid"] = spriteId;
    map["cid"] = connectionId;
    map['c'] = [];
    for (ConnectionInfo info in connections.values) {
     map['c'].add([info.to, info.latencyMillis]);
    }
    map['f'] = fps;
    map["s"] = score;
    map["d"] = deaths;
    map["gm"] = addedToGameAtMillis;
    if (inGame) {
      map["g"] = inGame;
    }
    return map;
  }

  String toString() =>
      "${spriteId} ${name} InGame: ${inGame} Remote Keystate: ${_remoteKeyState.remoteState}";
}

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
  Map<String, PlayerInfoProto> _playerInfoById = {};

  // True if we have urgent data for the network.
  bool _urgentData = false;


  GameState(this._packetListenerBindings, this._spriteIndex) {
    _packetListenerBindings.bindHandler(StateUpdate_Update.keyState,
            (ConnectionWrapper connection, StateUpdate update) {
          Map<String, bool> keyState = Map.from(data);
          PlayerInfoProto? info = playerInfoByConnectionId(connection.id);
          info?._remoteKeyState.setEnabledKeys(keyState);
        });
    _gameStateProto.startedAtEpochMillis = new DateTime.now().millisecondsSinceEpoch as Int64;
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
    info.addedToGameEpochMillis = new DateTime.now().millisecondsSinceEpoch as Int64;
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
