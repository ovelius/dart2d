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
  if (killer == null) {
    context.restore();
    return;
  }
  final bool isSelfKill = killer == player.info;
  final Mod? killMod = player.killedByMod;
  final bool isKittenKill = killMod == Mod.KITTEN;

  // Build the playful Mod kill message instead of generic "You were killed by ...".
  String text = (player.killedByMessage != null &&
          player.killedByMessage!.isNotEmpty)
      ? player.killedByMessage!
      : (isSelfKill
          ? selfKillMessage(player.info.name, killMod ?? Mod.UNKNOWN)
          : killedMessage(player.info.name, killer.name, killMod ?? Mod.UNKNOWN));

  LocalPlayerSprite? killerSprite =
      spriteIndex[killer.spriteId] as LocalPlayerSprite?;
  HTMLImageElement? img = killerSprite == null
      ? null
      : imageIndex.getImageById(killerSprite.imageId);

  final double avatarW = killerSprite == null ? 0.0 : killerSprite.size.x * 1.75;
  final double avatarH = killerSprite == null ? 0.0 : killerSprite.size.y * 1.75;
  final double kittenW = isKittenKill ? 66.0 : 0.0;
  final double maxBannerW = max(240.0, width - 48.0);

  // Dynamically fit font size so longer mod messages never clip off-screen.
  int fontSize = 30;
  double textW = 0.0;
  while (fontSize >= 16) {
    context.font = 'bold ${fontSize}px "Trebuchet MS", Arial, sans-serif';
    textW = context.measureText(text).width.toDouble();
    final double totalW =
        textW + (avatarW > 0 ? avatarW + 14.0 : 0.0) + (kittenW > 0 ? kittenW + 12.0 : 0.0);
    if (totalW <= maxBannerW) {
      break;
    }
    fontSize -= 2;
  }

  final double totalW = textW +
      (avatarW > 0 ? avatarW + 14.0 : 0.0) +
      (kittenW > 0 ? kittenW + 12.0 : 0.0);
  final double startX = width / 2.0 - totalW / 2.0;
  final double y = height / 4.0;
  final double animTime =
      max(0.0, LocalPlayerSprite.RESPAWN_TIME - player.spawnIn);

  double cursorX = startX;

  // Kitten Easter Egg: draw a cute animated cartoon kitten right beside the mod message!
  if (isKittenKill) {
    _drawKittenEasterEgg(context, cursorX + kittenW * 0.5, y - 4.0, animTime);
    cursorX += kittenW + 12.0;
  }

  _drawCartoonText(
    context,
    text,
    cursorX,
    y,
    fill: isKittenKill ? "#ffe680" : "#fff7e0",
    stroke: "#181d26",
    strokeWidth: max(4.0, fontSize * 0.20),
  );
  cursorX += textW + 14.0;

  if (img != null && killerSprite != null) {
    double frameWidth = (img.width / killerSprite.frames);
    context.drawImage(
        img,
        0,
        0,
        frameWidth,
        img.height,
        cursorX,
        y - avatarH * 0.72,
        avatarW,
        avatarH);
  }
  context.restore();
}

/// Adorable animated cartoon kitten easter egg shown on the death banner
/// whenever a player is knocked out by a runaway kitten (`Mod.KITTEN`).
void _drawKittenEasterEgg(
    CanvasRenderingContext2D ctx, double cx, double cy, double time) {
  ctx.save();
  ctx.translate(cx, cy);

  final double hop = sin(time * 9.0).abs() * -5.0;
  final double tailWag = sin(time * 12.0) * 4.5;
  final double earTwitch = sin(time * 7.5) * 0.08;

  // Subtle pastel glow halo behind the kitten!
  final CanvasGradient halo = ctx.createRadialGradient(0, 0, 4, 0, 0, 32);
  halo.addColorStop(0.0, "rgba(255, 224, 118, 0.55)");
  halo.addColorStop(1.0, "rgba(255, 224, 118, 0.0)");
  ctx.fillStyle = halo;
  ctx.beginPath();
  ctx.arc(0, 0, 32, 0, pi * 2.0);
  ctx.fill();

  ctx.translate(0, hop);

  // Cute swishing orange tabby tail!
  ctx.strokeStyle = "#1a1f2b".toJS;
  ctx.lineWidth = 6.5;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(12, 10);
  ctx.quadraticCurveTo(26, 4 + tailWag, 22, -10 + tailWag * 0.7);
  ctx.stroke();
  ctx.strokeStyle = "#ff9e3b".toJS;
  ctx.lineWidth = 3.8;
  ctx.stroke();

  // Plump sitting kitten body + white chest + tiny paws!
  ctx.fillStyle = "#ff9e3b".toJS;
  ctx.strokeStyle = "#1a1f2b".toJS;
  ctx.lineWidth = 2.4;
  ctx.beginPath();
  ctx.ellipse(0, 10, 14, 12, 0, 0, pi * 2.0);
  ctx.fill();
  ctx.stroke();

  ctx.fillStyle = "#fff5e0".toJS;
  ctx.beginPath();
  ctx.ellipse(0, 12, 7.5, 8.0, 0, 0, pi * 2.0);
  ctx.fill();

  for (final double px in const [-6.5, 6.5]) {
    ctx.fillStyle = "#ffffff".toJS;
    ctx.beginPath();
    ctx.ellipse(px, 19.5, 4.2, 2.8, 0, 0, pi * 2.0);
    ctx.fill();
    ctx.stroke();
  }

  // Big adorable cartoon kitten head with twitching pointy ears!
  ctx.save();
  ctx.rotate(earTwitch);
  ctx.fillStyle = "#ff9e3b".toJS;
  ctx.strokeStyle = "#1a1f2b".toJS;
  ctx.lineWidth = 2.4;
  for (final double side in const [-1.0, 1.0]) {
    ctx.beginPath();
    ctx.moveTo(side * 4, -14);
    ctx.lineTo(side * 13.5, -26);
    ctx.lineTo(side * 15.5, -10);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = "#ff9eb8".toJS;
    ctx.beginPath();
    ctx.moveTo(side * 6.5, -14.5);
    ctx.lineTo(side * 12.2, -22.5);
    ctx.lineTo(side * 13.5, -12.0);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = "#ff9e3b".toJS;
  }

  ctx.beginPath();
  ctx.ellipse(0, -6, 15.5, 13.0, 0, 0, pi * 2.0);
  ctx.fill();
  ctx.stroke();

  // Forehead tabby stripes!
  ctx.fillStyle = "#c45a12".toJS;
  ctx.fillRect(-1.5, -18.5, 3.0, 5.5);
  ctx.fillRect(-6.5, -17.0, 2.4, 4.5);
  ctx.fillRect(4.1, -17.0, 2.4, 4.5);

  // Big sparkling innocent kitten eyes!
  for (final double ex in const [-5.8, 5.8]) {
    ctx.fillStyle = "#7cf55c".toJS;
    ctx.beginPath();
    ctx.arc(ex, -7.0, 3.8, 0, pi * 2.0);
    ctx.fill();
    ctx.fillStyle = "#12151f".toJS;
    ctx.beginPath();
    ctx.arc(ex, -7.0, 2.3, 0, pi * 2.0);
    ctx.fill();
    ctx.fillStyle = "#ffffff".toJS;
    ctx.beginPath();
    ctx.arc(ex - 1.1, -8.3, 1.2, 0, pi * 2.0);
    ctx.fill();
  }

  // Pink nose, happy `:3` mouth & whiskers!
  ctx.fillStyle = "#ff789e".toJS;
  ctx.beginPath();
  ctx.moveTo(-2.2, -3.2);
  ctx.lineTo(2.2, -3.2);
  ctx.lineTo(0, -0.8);
  ctx.closePath();
  ctx.fill();

  ctx.strokeStyle = "#1a1f2b".toJS;
  ctx.lineWidth = 1.6;
  ctx.beginPath();
  ctx.arc(-2.5, -0.5, 2.5, 0.15 * pi, 0.9 * pi);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(2.5, -0.5, 2.5, 0.1 * pi, 0.85 * pi);
  ctx.stroke();

  ctx.lineWidth = 1.1;
  ctx.beginPath();
  ctx.moveTo(-10, -3);
  ctx.lineTo(-18, -4.5);
  ctx.moveTo(-10, -1);
  ctx.lineTo(-17.5, 1);
  ctx.moveTo(10, -3);
  ctx.lineTo(18, -4.5);
  ctx.moveTo(10, -1);
  ctx.lineTo(17.5, 1);
  ctx.stroke();
  ctx.restore();

  // Tiny comic speech bubble "meow!" floating above the kitten!
  ctx.fillStyle = "#ffffff".toJS;
  ctx.strokeStyle = "#1a1f2b".toJS;
  ctx.lineWidth = 1.8;
  ctx.beginPath();
  ctx.roundRect(-24, -44, 48, 16, 7.0.toJS);
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = "#ff5c8a".toJS;
  ctx.font = 'bold 10px "Trebuchet MS", Arial, sans-serif';
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("meow! ♥", 0, -35.8);

  ctx.restore();
}

