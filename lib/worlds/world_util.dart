import 'dart:js_interop';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/net/connection.dart';
import 'package:web/web.dart';
import 'worm_world.dart';
import 'dart:math';
import 'package:dart2d/res/imageindex.dart';

final Logger log = new Logger('WormWorld');

Map<int, String> _KEY_TO_NAME = {
  KeyCodeDart.LEFT: "Left",
  KeyCodeDart.RIGHT: "Right",
  KeyCodeDart.DOWN: "Down",
  KeyCodeDart.UP: "Up",
};

String toKey(int code) {
  if (_KEY_TO_NAME.containsKey(code)) {
    return _KEY_TO_NAME[code]!;
  }
  return new String.fromCharCode(code);
}

/**
 * Draws text to help the player with controls.
 */
void drawControlHelper(CanvasRenderingContext2D context, num controlHelperTime,
    LocalPlayerSprite playerSprite, int width, height) {
  if (controlHelperTime > 0) {
    context.fillStyle = "rgb(0,0,0)".toJS;
    context.strokeStyle = "rgb(0,0,0)".toJS;
    context.fillText("Controls are:", width ~/ 3, 40);
    int i = playerSprite.getControls().length;
    for (String key in playerSprite.getControls().keys) {
      int x = height ~/ 3;
      int y = 70 + i * 30;
      String current = toKey(playerSprite.getControls()[key]!);
      context.fillText("${key}: ${current}", x, y);
      i--;
    }
  }
}

void drawPlayerStats(
    CanvasRenderingContext2D context,
    WormWorld world,
    int width, int height,
    SpriteIndex spriteIndex,
    ImageIndex imageIndex,
    bool netIssue,
    bool blackText) {
  GameState gameState = world.network().gameState;
  List<PlayerInfoProto> infoList = world.network().gameState.playerInfoList();
  Map<String, ConnectionWrapper> connections = world.network().safeActiveConnections();
  infoList.sort((PlayerInfoProto info1, PlayerInfoProto info2) {
    // TODO compare death numbers?
    return info2.score.compareTo(info1.score);
  });

  double spriteScale = 1.5;
  double y = height / 2;

  int fontSize = 20;
  if (blackText) {
    context.fillStyle = "rgb(0, 0, 0, 0.7)".toJS;
  } else {
    context.fillStyle = "rgb(255, 255, 255, 0.7)".toJS;
  }
  context.font = "${fontSize}px Arial";

  for (int i = 0; i < infoList.length; i++) {
    PlayerInfoProto info = infoList[i];
    Sprite? sprite = spriteIndex[info.spriteId];
    // Can happen when starting a game...
    if (sprite == null) {
      log.warning("Not drawing ${info}, sprite is missing");
      continue;
    }
    HTMLImageElement img = imageIndex.getImageById(sprite.imageId);
    int latency = connections.containsKey(info.connectionId) ? connections[info.connectionId]!.expectedLatency().inMilliseconds : 0;
    String text;
    if (netIssue && gameState.gameStateProto.actingCommanderId == info.connectionId) {
      Random r = new Random();
      text = "${info.score} ${info.name} ${r.nextBool() ? "?" : "!"}${r.nextBool() ? "?" : "!"}${r.nextBool() ? "?" : "!"} ms *";
    } else {
      text = "${info.score} ${info.name} ${latency} ms ${gameState.gameStateProto.actingCommanderId == info.connectionId ? "*" : ""}";
    }
    var metrics = context.measureText(text);
    double totalWidth = sprite.size.x * spriteScale + metrics.width;
    double x = width / 2 - totalWidth / 2;
    double frameWidth = (img.width / sprite.frames);
    context.drawImage(
        img,
        0, 0,
        frameWidth, img.height,
        x,  y - (sprite.size.y * spriteScale) / 2 - fontSize /2,
        sprite.size.x * spriteScale, sprite.size.y * spriteScale);
    context.fillText(text, x + sprite.size.x * spriteScale, y);
    y += sprite.size.y * spriteScale;
  }
}

int _textSize = 40;

void drawWinView(CanvasRenderingContext2D context,
    WormWorld world,
    int width, int height,
    LocalPlayerSprite player, SpriteIndex spriteIndex, ImageIndex imageIndex) {

  if (player.inGame()) {
    return;
  }
  context.fillStyle = "rgb(0, 0, 0, 0.7)".toJS;
  context.fillRect(0, 0, width, height);
  drawPlayerStats(context, world, width, height, spriteIndex, imageIndex, false, false);
  GameState gameState = world.network().getGameState();
  PlayerInfoProto? winner = gameState.playerInfoByConnectionId(gameState.gameStateProto.winnerPlayerId);
  if (winner == null) {
    log.warning("Winner no longer in game, can't render scorescreen");
    return;
  }
  LocalPlayerSprite killerSprite = spriteIndex[winner.spriteId] as LocalPlayerSprite;
  HTMLImageElement img = imageIndex.getImageById(killerSprite.imageId);
  context.font = "${_textSize}px Arial";
  String text = "${winner.name} you're winner!";
  var metrics = context.measureText(text);

  context.fillStyle = "rgb(255, 255, 255, 0.5)".toJS;
  double messageLength =  metrics.width + killerSprite.size.x;
  if (messageLength > width) {
    // OOps we are larger than screen. Reduce text size for next frame.
    _textSize -= 2;
  }
  double x = width / 2 - messageLength / 2;
  double y = height / 3;
  context.fillText(text, x, y);

  double frameWidth = (img.width / killerSprite.frames);
  context.drawImage(
      img,
      0, 0,
      frameWidth, img.height,
      x + metrics.width,  y - killerSprite.size.y - _textSize / 2,
      killerSprite.size.x * 2, killerSprite.size.y * 2);

}

void drawKilledView(CanvasRenderingContext2D context,
    WormWorld world,
    int width, int height,
    LocalPlayerSprite player, SpriteIndex spriteIndex, ImageIndex imageIndex) {

  if (player.inGame()) {
    return;
  }
  context.fillStyle = "rgb(0, 0, 0, 0.7)".toJS;
  context.fillRect(0, 0, width, height);
  drawPlayerStats(context, world, width, height, spriteIndex, imageIndex, false, false);
  PlayerInfoProto? killer = player.killer;
  if (killer == null || killer == player.info) {
    return;
  }
  // This can be null.
  LocalPlayerSprite? killerSprite = spriteIndex[killer.spriteId] as LocalPlayerSprite?;
  HTMLImageElement? img = killerSprite == null ? null : imageIndex.getImageById(killerSprite.imageId);
  context.font = "${_textSize}px Arial";
  String text = "You were killed by ${killer.name}";
  var metrics = context.measureText(text);

  context.fillStyle = "rgb(255, 255, 255, 0.7)".toJS;
  double messageLength =  metrics.width + (killerSprite == null ? 0 : killerSprite.size.x);
  if (messageLength > width) {
    // OOps we are larger than screen. Reduce text size for next frame.
    _textSize -= 2;
  }
  double x = width / 2 - messageLength / 2;
  double y = height / 3;
  context.fillText(text, x, y);

  if (img != null && killerSprite != null) {
    double frameWidth = (img.width / killerSprite.frames);
    context.drawImage(
        img,
        0,
        0,
        frameWidth,
        img.height,
        x + metrics.width,
        y - killerSprite.size.y - _textSize / 2,
        killerSprite.size.x * 2,
        killerSprite.size.y * 2);
  }

}

