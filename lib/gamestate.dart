library gamestate;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/keystate.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('GameState');

class PlayerInfo {
  String name;
  var connectionId;
  int spriteId;
  int score = 0;
  int deaths = 0;
  bool inGame = false;
  PlayerInfo(this.name, this.connectionId, this.spriteId);

  PlayerInfo.fromMap(Map map) {
    name = map["n"];
    spriteId = map["sid"];
    connectionId = map["cid"];
    score = map["s"];
    deaths = map["d"];
    inGame = map.containsKey("g");
  }

  Map toMap() {
    Map map = new Map();
    map["n"] = name;
    map["sid"] = spriteId;
    map["cid"] = connectionId;
    map["s"] = score;
    map["d"] = deaths;
    if (inGame) {
      map["g"] = inGame;
    }
    return map;
  }

  String toString() => "${spriteId} ${name} ${inGame}";  
}

class GameState {
  static final int ID_OFFSET_FOR_NEW_CLIENT = 1000;
  static final List<String> USEABLE_SPRITES =
      ["duck.png", "cock.png", "donkey.png",  "dragon.png"];

  DateTime startedAt;
  List<PlayerInfo> playerInfo = [];
  int mapId = 0;
  String actingServerId = null;
  // True if we have urgent data for the network.
  bool urgentData = false;
  
  bool retrieveAndResetUrgentData() {
    bool tUrgentData = urgentData;
    urgentData = false;
    return tUrgentData;
  }
  
  bool isAtMaxPlayers() {
    return playerInfo.length >= USEABLE_SPRITES.length;
  }

  GameState() {
    startedAt = new DateTime.now();
  }

  GameState.fromMap(Map map) {
    List<Map> players = map["p"];
    for (Map playerMap in players) {
      playerInfo.add(new PlayerInfo.fromMap(playerMap));
    }
    mapId = map["m"];
    actingServerId = map["e"];
    startedAt = new DateTime.fromMillisecondsSinceEpoch(map["s"]);
  }
  
  Map toMap() {
    Map map = new Map();
    map["m"] = mapId;
    map["e"] = actingServerId;
    map["s"] = startedAt.millisecondsSinceEpoch;
    List<Map> players = [];
    for (PlayerInfo info in playerInfo) {
      players.add(info.toMap());
    }
    map["p"] = players;
    return map;
  }
  
  removeByConnectionId(WormWorld world, var id) {
    for (int i = playerInfo.length -1; i >= 0; i--) {
      PlayerInfo info = playerInfo[i];
      if (info.connectionId == id) {
        playerInfo.removeAt(i);
        world.network.sendMessage("${info.name} disconnected :/");
        // This code runs under the assumption that we are acting server.
        // That means we have to do something about the dead servers sprite.
        Sprite sprite = world.spriteIndex[info.spriteId];
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
    this.actingServerId = selfConnectionId;
    for (PlayerInfo info in playerInfo) {
      if (info.connectionId == selfConnectionId) {
        LocalPlayerSprite oldSprite = world.spriteIndex[info.spriteId];
        LocalPlayerSprite playerSprite =
            new LocalPlayerSprite.copyFromRemotePlayerSprite(oldSprite);
        playerSprite.setImage(oldSprite.imageId, oldSprite.size.x.toInt());
        world.replaceSprite(info.spriteId, playerSprite);
        oldSprite.info = info;
        world.playerSprite = playerSprite;
      } else {
        MovingSprite oldSprite = world.spriteIndex[info.spriteId];
        ConnectionWrapper connection =
            world.network.peer.connections[info.connectionId];
        if (connection != null) {
          RemotePlayerServerSprite remotePlayerSprite =
          new RemotePlayerServerSprite.copyFromMovingSprite(
              world, connection.remoteKeyState, info, oldSprite);
          remotePlayerSprite.setImage(
              oldSprite.imageId, oldSprite.size.x.toInt());
          world.replaceSprite(info.spriteId, remotePlayerSprite);
        } else {
          // Connection isn't there :( Not much we can do but kill the playerinfo.
          removeByConnectionId(world, info.connectionId);
        }
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
    return null;
  }
  
  bool gameIsFull() {
    return playerInfo.length >= USEABLE_SPRITES.length;
  }
  int getNextUsablePlayerSpriteId(WormWorld world) {
    int id = ID_OFFSET_FOR_NEW_CLIENT +
        world.spriteNetworkId + playerInfo.length * ID_OFFSET_FOR_NEW_CLIENT;
    // Make sure we don't pick and ID we already use.
    while (world.spriteIndex.hasSprite(id)) {
      id = id + ID_OFFSET_FOR_NEW_CLIENT;
    }
    return id;
  }
  int getNextUsableSpriteImage(ImageIndex imageIndex) {
    return imageIndex.getImageIdByName(USEABLE_SPRITES[playerInfo.length]);
  }
  
  String toString() {
    return "GameState with map ${mapId} server ${actingServerId} ${playerInfo}";
  }
}