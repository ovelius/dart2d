import 'dart:html' show KeyCode, CanvasRenderingContext2D;
import 'package:dart2d/sprites/worm_player.dart';

Map<int, String> _KEY_TO_NAME = {
  KeyCode.LEFT: "Left",
  KeyCode.RIGHT: "Right",
  KeyCode.DOWN: "Down",
  KeyCode.UP: "Up",
};

String toKey(int code) {
  if (KeyCode.isCharacterKey(code)) {
    return new String.fromCharCode(code);
  } else {
    return _KEY_TO_NAME[code];
  }
}

/**
 * Draws text to help the player with controls.
 */
void drawControlHelper(CanvasRenderingContext2D context,
        num controlHelperTime,
        LocalPlayerSprite playerSprite,
        int width, height) {
  if (controlHelperTime > 0) {
    context.setFillColorRgb(255, 255, 255);
    context.setStrokeColorRgb(255, 255, 255);
    context.fillText("Controls are:", width ~/ 3, 40);
    int i = playerSprite.getControls().length;
    for (String key in playerSprite.getControls().keys) {
      int x = height ~/ 3;
      int y = 70 + i*30;
      String current = toKey(playerSprite.getControls()[key]);
      context.fillText("${key}: ${current}", x, y);
      i--;
    }
  }
}