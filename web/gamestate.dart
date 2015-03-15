library gamestate;

import 'imageindex.dart';
import 'world.dart';


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

  bool isAtMaxPlayers() {
    return false;
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
    for (int i = playerInfo.length -1; i >= 0; i--) {
      PlayerInfo info = playerInfo[i];
      if (info.connectionId == id) {
        playerInfo.removeAt(i);
        world.network.sendMessage("${info.name} disconnected :/");
        return;
      }
    }
  }
  
  bool gameIsFull() {
    return playerInfo.length >= USEABLE_SPRITES.length;
  }
  int getNextUsablePlayerSpriteId() {
    return world.spriteNetworkId + playerInfo.length * ID_OFFSET_FOR_NEW_CLIENT;
  }
  int getNextUsableSpriteImage() {
    return imageByName[USEABLE_SPRITES[playerInfo.length]];
  }
  DateTime startedAt;
  List<PlayerInfo> playerInfo = [];
  int level = 0;
  
  String toString() {
    return "${playerInfo}";
  }
}