import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
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

void drawKilledView(var /*CanvasRenderingContext2D*/ context,
    int width, int height,
    LocalPlayerSprite player, SpriteIndex spriteIndex, ImageIndex imageIndex) {
  int textSize = 40;
  if (player == null || player.inGame()) {
    return;
  }
  PlayerInfo killer = player.killer;
  if (killer == null || killer == player.info) {
    return;
  }
  LocalPlayerSprite killerSprite = spriteIndex[killer.spriteId];
  if (killerSprite == null) {
    return;
  }
  var img = imageIndex.getImageById(killerSprite.imageId);
  context.setFillColorRgb(0, 0, 0, 0.5);
  context.fillRect(0, 0, width, height);
  context.font = "${textSize}px Arial";
  String text = "You were killed by ${killer.name}";
  var metrics = context.measureText(text);

  context.setFillColorRgb(255, 255, 255, 0.5);
  double messageLength =  metrics.width + killerSprite.size.x;
  double x = width / 2 - messageLength / 2;
  double y = height /2;
  context.fillText(text, x, y);

  double frameWidth = (img.width / killerSprite.frames);
  context.drawImageScaledFromSource(
      img,
      0, 0,
      frameWidth, img.height,
      x + metrics.width,  y - killerSprite.size.y - textSize / 2,
      killerSprite.size.x * 2, killerSprite.size.y * 2);
}

