library hud;

import 'dart:math';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:di/di.dart';
import 'package:dart2d/gamestate.dart';

class _HudMessage {
  final String message;
  double remainingTime;
  _HudMessage(this.message, this.remainingTime);
  double getAlpha() {
    return min(remainingTime, 1.0);
  }
}

@Injectable()
class HudMessages {
  static const DEFAULT_DURATION = 4.0;
  KeyState _localKeyState;
  List<_HudMessage> messages = [];

  HudMessages(@LocalKeyState() KeyState localKeyState) {
   this._localKeyState = localKeyState;
  }

  void display(String message, [double period]) {
    messages.add(new _HudMessage(
        message, period == null ? DEFAULT_DURATION : period));   
  }

  bool shouldDrawTable() {
    return _localKeyState.keyIsDown(KeyCode.SHIFT) ||
        _localKeyState.keyIsDown(KeyCode.CTRL) ||
        _localKeyState.keyIsDown(KeyCode.H) ||
        _localKeyState.keyIsDown(KeyCode.HOME) ||
        _localKeyState.keyIsDown(KeyCode.ALT);
  }

  void showGameTable(WormWorld world, var /*CanvasRenderingContext2D*/ context) {
    if (shouldDrawTable()) {
      GameState gameState = world.network.gameState;
      context.setFillColorRgb(200, 0, 0);
      context.setStrokeColorRgb(200, 0, 0);
      for (int i = gameState.playerInfo.length - 1; i >= 0; i--) {
        PlayerInfo info = gameState.playerInfo[i];
        MovingSprite sprite = world.spriteIndex[info.spriteId];
        if (sprite == null) {
          continue;
        }
        Vec2 middle = sprite.centerPoint();
        int x = world.width() ~/ 3;
        int y = 40 + i*40;
        context.fillText("${info.name} ${info.score} ${info.deaths}", x, y);
        // TODO: Check that sprite is alive.
        if (sprite != null) {
          context.lineWidth = 2;
          context.beginPath();
          context.moveTo(x, y);
          context.lineTo(middle.x, middle.y);
          context.stroke();
        }
      }
    }    
  }

  void render(WormWorld world, var /*CanvasRenderingContext2D*/ context, double timeSpent) {
    context.font = '16pt Calibri';
    context.resetTransform();
    showGameTable(world, context);
    for (int i = 0; i < messages.length; i++) {
      _HudMessage m = messages[i];
      m.remainingTime -= timeSpent;
      if (m.remainingTime < 0) {
        messages.removeAt(i);
        continue;
      }
      context.setFillColorRgb(255, 255, 255, m.getAlpha());
      context.fillText(m.message, 40, 40 + i * 20);
    }
  }
}