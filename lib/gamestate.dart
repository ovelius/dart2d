library gamestate;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/keystate.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('GameState');

class PlayerInfo {
  String name;
  var connectionId;
  int spriteId;
  int score = 0;
  int deaths = 0;
  PlayerInfo(this.name, this.connectionId, this.spriteId);

  PlayerInfo.fromMap(Map map) {
    name = map["n"];
    spriteId = map["sid"];
    connectionId = map["cid"];
    score = map["s"];
    deaths = map["d"];
  }

  Map toMap() {
    Map map = new Map();
    map["n"] = name;
    map["sid"] = spriteId;
    map["cid"] = connectionId;
    map["s"] = score;
    map["d"] = deaths;
    return map;
  }

  String toString() => "${spriteId} ${name}";  
}

class GameState {
  static final int ID_OFFSET_FOR_NEW_CLIENT = 1000;
  static final List<String> USEABLE_SPRITES =
      ["shipg01.png", "shipr01.png", "shipb01.png",  "shipy01.png"];

  DateTime startedAt;
  List<PlayerInfo> playerInfo = [];
  int level = 0;
  
  bool isAtMaxPlayers() {
    return playerInfo.length >= USEABLE_SPRITES.length;
  }

  World world;
  GameState(this.world) {
    startedAt = new DateTime.now();
  }

  GameState.fromMap(World world, Map map) {
    this.world = world;
    List<Map> players = map["p"];
    for (Map playerMap in players) {
      playerInfo.add(new PlayerInfo.fromMap(playerMap));
    }
    level = map["l"];
    startedAt = new DateTime.fromMillisecondsSinceEpoch(map["s"]);
  }
  
  Map toMap() {
    Map map = new Map();
    map["l"] = level;
    map["s"] = startedAt.millisecondsSinceEpoch;
    List<Map> players = [];
    for (PlayerInfo info in playerInfo) {
      players.add(info.toMap());
    }
    map["p"] = players;
    return map;
  }
  
  removeByConnectionId(var id) {
    assert(world.network.isServer());
    for (int i = playerInfo.length -1; i >= 0; i--) {
      PlayerInfo info = playerInfo[i];
      if (info.connectionId == id) {
        playerInfo.removeAt(i);
        world.network.sendMessage("${info.name} disconnected :/");
        // This code runs under the assumption that we are acting server.
        // That means we have to do something about the dead servers sprite.
        Sprite sprite = world.sprites[info.spriteId];
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
  convertToServer(var selfConnectionId) {
    for (PlayerInfo info in playerInfo) {
      if (info.connectionId == selfConnectionId) {
        RemotePlayerSprite oldSprite = world.sprites[info.spriteId];
        LocalPlayerSprite playerSprite =
            new LocalPlayerSprite.copyFromRemotePlayerSprite(oldSprite);
        playerSprite.setImage(oldSprite.imageIndex);
        world.replaceSprite(info.spriteId, playerSprite);
        oldSprite.info = info;
      } else {
        MovingSprite oldSprite = world.sprites[info.spriteId];
        // TODO: Handle case of connection being gone here.
        KeyState remoteKeyState = world.peer.connections[info.connectionId].remoteKeyState;
        RemotePlayerServerSprite remotePlayerSprite = new RemotePlayerServerSprite.copyFromMovingSprite(
            world, remoteKeyState, info, oldSprite);
        remotePlayerSprite.setImage(oldSprite.imageIndex);
        world.replaceSprite(info.spriteId, remotePlayerSprite);
      }
    }
  }
  
  PlayerInfo playerInfoByConnectionId(var id) {
    for (int i = playerInfo.length -1; i >= 0; i--) {
      PlayerInfo info = playerInfo[i];
      if (info.connectionId == id) {
        return info;
      }
    }
    throw new ArgumentError("${id} doesn't have a matching player?");
  }
  
  bool gameIsFull() {
    return playerInfo.length >= USEABLE_SPRITES.length;
  }
  int getNextUsablePlayerSpriteId() {
    return ID_OFFSET_FOR_NEW_CLIENT + 
        world.spriteNetworkId + playerInfo.length * ID_OFFSET_FOR_NEW_CLIENT;
  }
  int getNextUsableSpriteImage() {
    return imageByName["duck.png"];
//    return imageByName[USEABLE_SPRITES[playerInfo.length]];
  }
  
  String toString() {
    return "${playerInfo}";
  }
}