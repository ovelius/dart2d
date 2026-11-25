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

void _drawCartoonText(CanvasRenderingContext2D context, String text, num x, num y,
    {String fill = "#fff9e6",
    String stroke = "#161b24",
    double strokeWidth = 4.5}) {
  context.lineJoin = "round";
  context.strokeStyle = stroke.toJS;
  context.lineWidth = strokeWidth;
  context.strokeText(text, x, y);
  context.fillStyle = fill.toJS;
  context.fillText(text, x, y);
}

/**
 * Draws text to help the player with controls.
 */
void drawControlHelper(CanvasRenderingContext2D context, num controlHelperTime,
    LocalPlayerSprite playerSprite, int width, height) {
  if (controlHelperTime > 0) {
    context.save();
    List<String> keys = playerSprite.getControls().keys.toList();
    double cardW = 260.0;
    double cardH = 54.0 + keys.length * 26.0;
    double cardX = max(20.0, width / 2.0 - cardW / 2.0);
    double cardY = 26.0;

    // Cartoon slate card with bold outline & drop shadow.
    context.fillStyle = "rgba(12, 16, 24, 0.5)".toJS;
    context.beginPath();
    context.roundRect(cardX + 4, cardY + 5, cardW, cardH, 16.0.toJS);
    context.fill();

    context.fillStyle = "rgba(42, 50, 62, 0.92)".toJS;
    context.beginPath();
    context.roundRect(cardX, cardY, cardW, cardH, 16.0.toJS);
    context.fill();
    context.strokeStyle = "#161b24".toJS;
    context.lineWidth = 3.0;
    context.stroke();

    context.font = 'bold 18px "Trebuchet MS", Arial, sans-serif';
    _drawCartoonText(context, "Controls", cardX + 20, cardY + 30,
        fill: "#ffd94a", strokeWidth: 4.0);

    context.font = 'bold 15px "Trebuchet MS", Arial, sans-serif';
    for (int i = 0; i < keys.length; i++) {
      String key = keys[i];
      String current = toKey(playerSprite.getControls()[key]!);
      double rowY = cardY + 58.0 + i * 26.0;
      _drawCartoonText(context, "$key: $current", cardX + 22, rowY,
          fill: "#ffffff", strokeWidth: 3.2);
    }
    context.restore();
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
  int fontSize = 20;

  context.save();
  context.font = 'bold ${fontSize}px "Trebuchet MS", Arial, sans-serif';

  // Build rows first so we can draw a clean cartoon scoreboard panel behind them.
  List<String> labels = [];
  List<Sprite> sprites = [];
  double maxRowW = 0.0;
  double totalH = 0.0;

  for (int i = 0; i < infoList.length; i++) {
    PlayerInfoProto info = infoList[i];
    Sprite? sprite = spriteIndex[info.spriteId];
    // Can happen when starting a game...
    if (sprite == null) {
      log.warning("Not drawing ${info}, sprite is missing");
      continue;
    }
    int latency = connections.containsKey(info.connectionId) ? connections[info.connectionId]!.expectedLatency().inMilliseconds : 0;
    String text;
    if (netIssue && gameState.gameStateProto.actingCommanderId == info.connectionId) {
      Random r = new Random();
      text = "${info.score} ${info.name} ${r.nextBool() ? "?" : "!"}${r.nextBool() ? "?" : "!"}${r.nextBool() ? "?" : "!"} ms *";
    } else {
      text = "${info.score}  ${info.name}  ${latency} ms${gameState.gameStateProto.actingCommanderId == info.connectionId ? " *" : ""}";
    }
    double rowW = sprite.size.x * spriteScale + 12.0 + context.measureText(text).width.toDouble();
    if (rowW > maxRowW) maxRowW = rowW;
    totalH += sprite.size.y * spriteScale;
    labels.add(text);
    sprites.add(sprite);
  }

  double startY = height / 2.0 - totalH / 2.0 + (sprites.isNotEmpty ? sprites[0].size.y * spriteScale * 0.5 : 0.0);

  if (sprites.isNotEmpty) {
    double padX = 24.0;
    double padY = 16.0;
    double cardW = maxRowW + padX * 2;
    double cardH = totalH + padY * 2;
    double cardX = width / 2.0 - cardW / 2.0;
    double cardY = height / 2.0 - cardH / 2.0;

    context.fillStyle = "rgba(12, 16, 24, 0.5)".toJS;
    context.beginPath();
    context.roundRect(cardX + 4, cardY + 5, cardW, cardH, 18.0.toJS);
    context.fill();

    context.fillStyle = "rgba(44, 52, 66, 0.88)".toJS;
    context.beginPath();
    context.roundRect(cardX, cardY, cardW, cardH, 18.0.toJS);
    context.fill();
    context.strokeStyle = "#161b24".toJS;
    context.lineWidth = 3.0;
    context.stroke();
  }

  double y = startY;
  for (int i = 0; i < sprites.length; i++) {
    Sprite sprite = sprites[i];
    String text = labels[i];
    HTMLImageElement img = imageIndex.getImageById(sprite.imageId);
    double metricsW = context.measureText(text).width.toDouble();
    double totalWidth = sprite.size.x * spriteScale + 12.0 + metricsW;
    double x = width / 2.0 - totalWidth / 2.0;
    double frameWidth = (img.width / sprite.frames);
    context.drawImage(
        img,
        0, 0,
        frameWidth, img.height,
        x, y - (sprite.size.y * spriteScale) / 2 - fontSize / 2,
        sprite.size.x * spriteScale, sprite.size.y * spriteScale);
    _drawCartoonText(context, text, x + sprite.size.x * spriteScale + 12.0, y,
        fill: i == 0 ? "#ffe36e" : "#ffffff", strokeWidth: 4.0);
    y += sprite.size.y * spriteScale;
  }
  context.restore();
}

int _textSize = 40;

void drawWinView(CanvasRenderingContext2D context,
    WormWorld world,
    int width, int height,
    LocalPlayerSprite player, SpriteIndex spriteIndex, ImageIndex imageIndex) {

  if (player.inGame()) {
    return;
  }
  context.save();
  context.fillStyle = "rgb(0, 0, 0, 0.65)".toJS;
  context.fillRect(0, 0, width, height);
  drawPlayerStats(context, world, width, height, spriteIndex, imageIndex, false, false);
  GameState gameState = world.network().getGameState();
  PlayerInfoProto? winner = gameState.playerInfoByConnectionId(gameState.gameStateProto.winnerPlayerId);
  if (winner == null) {
    log.warning("Winner no longer in game, can't render scorescreen");
    context.restore();
    return;
  }
  LocalPlayerSprite killerSprite = spriteIndex[winner.spriteId] as LocalPlayerSprite;
  HTMLImageElement img = imageIndex.getImageById(killerSprite.imageId);
  context.font = 'bold ${_textSize}px "Trebuchet MS", Arial, sans-serif';
  String text = "${winner.name} you're winner!";
  var metrics = context.measureText(text);

  double messageLength =  metrics.width + killerSprite.size.x;
  if (messageLength > width) {
    // OOps we are larger than screen. Reduce text size for next frame.
    _textSize -= 2;
  }
  double x = width / 2 - messageLength / 2;
  double y = height / 4;
  _drawCartoonText(context, text, x, y, fill: "#ffe04d", stroke: "#2b1600", strokeWidth: 6.5);

  double frameWidth = (img.width / killerSprite.frames);
  context.drawImage(
      img,
      0, 0,
      frameWidth, img.height,
      x + metrics.width + 8,  y - killerSprite.size.y - _textSize / 2,
      killerSprite.size.x * 2, killerSprite.size.y * 2);
  context.restore();
}

void drawKilledView(CanvasRenderingContext2D context,
    WormWorld world,
    int width, int height,
    LocalPlayerSprite player, SpriteIndex spriteIndex, ImageIndex imageIndex) {

  if (player.inGame()) {
    return;
  }
  // Let the killed player watch the KO pop unobstructed, show a light overlay
  // while zoomed out over the battlefield, then fade clear as the camera zooms
  // into the new spawn location.
  double overlayAlpha = 1.0;
  double backdropAlpha = 0.65;
  if (player.spawnIn <= LocalPlayerSprite.RESPAWN_TIME) {
    double deadElapsed = LocalPlayerSprite.RESPAWN_TIME - player.spawnIn;
    if (deadElapsed < 1.0 || deadElapsed > 4.5) {
      return;
    }
    double fadeIn = ((deadElapsed - 1.0) / 0.6).clamp(0.0, 1.0);
    double fadeOut = ((4.5 - deadElapsed) / 0.9).clamp(0.0, 1.0);
    overlayAlpha = min(fadeIn, fadeOut);
    backdropAlpha = 0.30;
  }
  context.save();
  context.globalAlpha = overlayAlpha;
  context.fillStyle = "rgb(0, 0, 0, ${backdropAlpha.toStringAsFixed(2)})".toJS;
  context.fillRect(0, 0, width, height);
  drawPlayerStats(context, world, width, height, spriteIndex, imageIndex, false, false);
  PlayerInfoProto? killer = player.killer;
  if (killer == null || killer == player.info) {
    context.restore();
    return;
  }
  // This can be null.
  LocalPlayerSprite? killerSprite = spriteIndex[killer.spriteId] as LocalPlayerSprite?;
  HTMLImageElement? img = killerSprite == null ? null : imageIndex.getImageById(killerSprite.imageId);
  context.font = 'bold ${_textSize}px "Trebuchet MS", Arial, sans-serif';
  String text = "You were killed by ${killer.name}";
  var metrics = context.measureText(text);

  double messageLength =  metrics.width + (killerSprite == null ? 0 : killerSprite.size.x);
  if (messageLength > width) {
    // OOps we are larger than screen. Reduce text size for next frame.
    _textSize -= 2;
  }
  double x = width / 2 - messageLength / 2;
  double y = height / 4;
  _drawCartoonText(context, text, x, y, fill: "#fff7e0", stroke: "#181d26", strokeWidth: 6.5);

  if (img != null && killerSprite != null) {
    double frameWidth = (img.width / killerSprite.frames);
    context.drawImage(
        img,
        0,
        0,
        frameWidth,
        img.height,
        x + metrics.width + 8,
        y - killerSprite.size.y - _textSize / 2,
        killerSprite.size.x * 2,
        killerSprite.size.y * 2);
  }
  context.restore();

}

