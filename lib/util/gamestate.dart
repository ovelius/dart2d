library gamestate;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:di/di.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

class ConnectionInfo {
  String to;
  int latencyMillis;
}

class PlayerInfo {
  String name;
  String connectionId;
  int spriteId;
  int score = 0;
  int deaths = 0;
  bool inGame = false;
  // How many frames per second this client has.
  int fps = 45;
  // What conenctions this player has.
  List<String> connections = [];
  // Keystate for the remote player, will only be set if
  // the remote peer is a client.
  KeyState _remoteKeyState = new KeyState.remote();

  PlayerInfo(this.name, this.connectionId, this.spriteId);

  PlayerInfo.fromMap(Map map) {
    name = map["n"];
    spriteId = map["sid"];
    fps = map['f'];
    connectionId = map["cid"];
    score = map["s"];
    deaths = map["d"];
    connections = map['c'];
    inGame = map.containsKey("g");
  }

  KeyState remoteKeyState() => _remoteKeyState;

  void updateWithLocalKeyState(KeyState localState) {
    assert(!localState.remoteState);
    _remoteKeyState = localState;
  }

  Map toMap() {
    Map map = new Map();
    map["n"] = name;
    map["sid"] = spriteId;
    map["cid"] = connectionId;
    map['c'] = connections;
    map['f'] = fps;
    map["s"] = score;
    map["d"] = deaths;
    if (inGame) {
      map["g"] = inGame;
    }
    return map;
  }

  String toString() =>
      "${spriteId} ${name} InGame: ${inGame} Remote Keystate: ${_remoteKeyState.remoteState}";
}

@Injectable()
class GameState {
  final Logger log = new Logger('GameState');
  static final int ID_OFFSET_FOR_NEW_CLIENT = 1000;
  static final List<String> USEABLE_SPRITES = [
    "duck.png",
    "cock.png",
    "donkey.png",
    "dragon.png"
  ];

  // Injected members.
  PacketListenerBindings _packetListenerBindings;
  SpriteIndex _spriteIndex;

  DateTime startedAt;
  List<PlayerInfo> _playerInfo = [];
  Map<String, PlayerInfo> _playerInfoById = {};
  int mapId = 0;
  // Who has the bridge.
  String actingCommanderId = null;
  // True if we have urgent data for the network.
  bool _urgentData = false;

  bool retrieveAndResetUrgentData() {
    bool tUrgentData = _urgentData;
    _urgentData = false;
    return tUrgentData;
  }

  void markAsUrgent() {
    this._urgentData = true;
  }

  void reset() {
    actingCommanderId = null;
    _playerInfo = [];
    _playerInfoById = {};
    startedAt = new DateTime.now();
  }

  bool isInGame(String id) {
    return _playerInfoById.containsKey(id);
  }

  bool hasCommander() {
    return this.actingCommanderId != null;
  }

  bool isAtMaxPlayers() {
    return _playerInfo.length >= 4;
  }

  List<PlayerInfo> playerInfoList() => new List.from(_playerInfo);

  void addPlayerInfo(PlayerInfo info) {
    assert(info.connectionId != null);
    _playerInfo.add(info);
    _playerInfoById[info.connectionId] = info;
  }

  GameState(this._packetListenerBindings, this._spriteIndex) {
    _packetListenerBindings.bindHandler(KEY_STATE_KEY,
        (ConnectionWrapper connection, Map keyState) {
      PlayerInfo info = playerInfoByConnectionId(connection.id);
      if (info == null) {
        log.warning(
            "Received KeyState for Player that doesn't exist? ${connection.id}");
        return;
      }
      info._remoteKeyState.setEnabledKeys(keyState);
    });
    startedAt = new DateTime.now();
  }

  updateFromMap(Map map) {
    List<Map> players = map["p"];
    List<PlayerInfo> newInfo = [];
    Map<String, PlayerInfo> byId = {};
    for (Map playerMap in players) {
      PlayerInfo info = new PlayerInfo.fromMap(playerMap);
      assert(info.remoteKeyState().remoteState);
      PlayerInfo oldInfo = playerInfoByConnectionId(info.connectionId);
      if (oldInfo != null) {
        info._remoteKeyState = oldInfo._remoteKeyState;
      }
      newInfo.add(info);
      byId[info.connectionId] = info;
    }
    _playerInfo = newInfo;
    _playerInfoById = byId;
    mapId = map["m"];
    actingCommanderId = map["e"];
    startedAt = new DateTime.fromMillisecondsSinceEpoch(map["s"]);
  }

  Map toMap() {
    Map map = new Map();
    map["m"] = mapId;
    map["e"] = actingCommanderId;
    map["s"] = startedAt.millisecondsSinceEpoch;
    List<Map> players = [];
    for (PlayerInfo info in _playerInfo) {
      players.add(info.toMap());
    }
    map["p"] = players;
    return map;
  }

  removeByConnectionId(WormWorld world, var id) {
    for (int i = _playerInfo.length - 1; i >= 0; i--) {
      PlayerInfo info = _playerInfo[i];
      if (info.connectionId == id) {
        _playerInfo.removeAt(i);
        _playerInfoById.remove(info.connectionId);
        world.network().sendMessage("${info.name} disconnected :/");
        // This code runs under the assumption that we are acting server.
        // That means we have to do something about the dead servers sprite.
        Sprite sprite = _spriteIndex[info.spriteId];
        if (sprite != null) {
          // The game engine will not remove things if the REMOTE NetworkType.
          // So make the old servers sprite REMOTE_FORWARD.
          sprite.networkType = NetworkType.REMOTE_FORWARD;
        }
        world.removeSprite(info.spriteId);
        return;
      }
    }
  }

  /**
   * Converts the world sprite state for us to become server.
   */
  convertToServer(WormWorld world, var selfConnectionId) {
    this.actingCommanderId = selfConnectionId;
    for (int i = _playerInfo.length - 1; i >= 0; i--) {
      PlayerInfo info = _playerInfo[i];
      // Convert self info to server.
      if (info.connectionId != selfConnectionId) {
        // Convert other players.
        ConnectionWrapper connection =
            world.network().peer.connections[info.connectionId];
        if (connection == null) {
          // Connection isn't there :( Not much we can do but kill the playerinfo.
          removeByConnectionId(world, info.connectionId);
        }
      }
    }
  }

  PlayerInfo playerInfoByConnectionId(var id) {
    return _playerInfoById[id];
  }

  bool gameIsFull() {
    return _playerInfo.length >= USEABLE_SPRITES.length;
  }

  int getNextUsablePlayerSpriteId(WormWorld world) {
    int id = ID_OFFSET_FOR_NEW_CLIENT +
        world.spriteNetworkId +
        _playerInfo.length * ID_OFFSET_FOR_NEW_CLIENT;
    // Make sure we don't pick and ID we already use.
    while (world.spriteIndex.hasSprite(id)) {
      id = id + ID_OFFSET_FOR_NEW_CLIENT;
    }
    return id;
  }

  String toString() {
    return "GameState with map ${mapId} commander ${actingCommanderId} ${_playerInfo} started ${startedAt}";
  }
}
