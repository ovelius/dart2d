import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/net/net.dart';
import 'worm_world.dart';
import 'package:dart2d/res/imageindex.dart';

Map<int, String> _KEY_TO_NAME = {
  KeyCodeDart.LEFT: "Left",
  KeyCodeDart.RIGHT: "Right",
  KeyCodeDart.DOWN: "Down",
  KeyCodeDart.UP: "Up",
};

String toKey(int code) {
  if (_KEY_TO_NAME.containsKey(code)) {
    return _KEY_TO_NAME[code];
  }
  return new String.fromCharCode(code);
}

/**
 * Draws text to help the player with controls.
 */
void drawControlHelper(var /*CanvasRenderingContext2D*/ context, num controlHelperTime,
    LocalPlayerSprite playerSprite, int width, height) {
  if (controlHelperTime > 0) {
    context.setFillColorRgb(255, 255, 255);
    context.setStrokeColorRgb(255, 255, 255);
    context.fillText("Controls are:", width ~/ 3, 40);
    int i = playerSprite.getControls().length;
    for (String key in playerSprite.getControls().keys) {
      int x = height ~/ 3;
      int y = 70 + i * 30;
      String current = toKey(playerSprite.getControls()[key]);
      context.fillText("${key}: ${current}", x, y);
      i--;
    }
  }
}

void drawPlayerStats(
    var /*CanvasRenderingContext2D*/ context,
    WormWorld world,
    int width, int height,
    SpriteIndex spriteIndex,
    ImageIndex imageIndex) {
  GameState gameState = world.network().gameState;
  List<PlayerInfo> infoList = world.network().gameState.playerInfoList();
  Map<String, ConnectionWrapper> connections = world.network().safeActiveConnections();
  infoList.sort((PlayerInfo info1, PlayerInfo info2) {
    // TODO compare death numbers?
    return info2.score.compareTo(info1.score);
  });

  double spriteScale = 1.5;
  double y = height / 2;

  int fontSize = 20;
  context.setFillColorRgb(255, 255, 255, 0.5);
  context.font = "${fontSize}px Arial";

  for (int i = 0; i < infoList.length; i++) {
    PlayerInfo info = infoList[i];
    LocalPlayerSprite sprite = spriteIndex[info.spriteId];
    // Can happen when starting a game...
    if (sprite == null) {
      continue;
    }
    var img = imageIndex.getImageById(sprite.imageId);
    int latency = connections.containsKey(info.connectionId) ? connections[info.connectionId].expectedLatency().inMilliseconds : 0;
    String text = "${info.score} ${info.name} ${latency} ms ${gameState.actingCommanderId == info.connectionId ? "*" : ""}";
    var metrics = context.measureText(text);
    double totalWidth = sprite.size.x * spriteScale + metrics.width;
    double x = width / 2 - totalWidth / 2;
    double frameWidth = (img.width / sprite.frames);
    context.drawImageScaledFromSource(
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

void drawKilledView(var /*CanvasRenderingContext2D*/ context,
    WormWorld world,
    int width, int height,
    LocalPlayerSprite player, SpriteIndex spriteIndex, ImageIndex imageIndex) {

  if (player == null || player.inGame()) {
    return;
  }
  context.setFillColorRgb(0, 0, 0, 0.5);
  context.fillRect(0, 0, width, height);
  drawPlayerStats(context, world, width, height, spriteIndex, imageIndex);
  PlayerInfo killer = player.killer;
  if (killer == null || killer == player.info) {
    return;
  }
  LocalPlayerSprite killerSprite = spriteIndex[killer.spriteId];
  if (killerSprite == null) {
    return;
  }
  var img = imageIndex.getImageById(killerSprite.imageId);
  context.font = "${_textSize}px Arial";
  String text = "You were killed by ${killer.name}";
  var metrics = context.measureText(text);

  context.setFillColorRgb(255, 255, 255, 0.5);
  double messageLength =  metrics.width + killerSprite.size.x;
  if (messageLength > width) {
    // OOps we are larger than screen. Reduce text size for next frame.
    _textSize -= 2;
  }
  double x = width / 2 - messageLength / 2;
  double y = height / 3;
  context.fillText(text, x, y);

  double frameWidth = (img.width / killerSprite.frames);
  context.drawImageScaledFromSource(
      img,
      0, 0,
      frameWidth, img.height,
      x + metrics.width,  y - killerSprite.size.y - _textSize / 2,
      killerSprite.size.x * 2, killerSprite.size.y * 2);

}

