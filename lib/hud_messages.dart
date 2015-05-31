library hud;

import 'dart:html';
import 'dart:math';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/gamestate.dart';

class _HudMessage {
  final String message;
  double remainingTime;
  _HudMessage(this.message, this.remainingTime);
  double getAlpha() {
    return min(remainingTime, 1.0);
  }
}

class HudMessages {
  static const DEFAULT_DURATION = 4.0;
  World world;
  List<_HudMessage> messages = [];

  HudMessages(this.world);
  
  void displayAndSendToNetwork(String message, [double period]) {
    display(message, period);
    world.network.sendMessage(message);
  }

  void display(String message, [double period]) {
    messages.add(new _HudMessage(
        message, period == null ? DEFAULT_DURATION : period));   
  }

  bool shouldDrawTable() {
    return world.localKeyState.keyIsDown(KeyCode.SHIFT) ||
        world.localKeyState.keyIsDown(KeyCode.CTRL) ||
        world.localKeyState.keyIsDown(KeyCode.H) ||
        world.localKeyState.keyIsDown(KeyCode.HOME) ||
        world.localKeyState.keyIsDown(KeyCode.ALT);
  }

  void showGameTable(CanvasRenderingContext2D context) {
    if (shouldDrawTable()) {
      GameState gameState = world.network.gameState;
      context.setFillColorRgb(200, 0, 0);
      context.setStrokeColorRgb(200, 0, 0);
      for (int i = gameState.playerInfo.length - 1; i >= 0; i--) {
        PlayerInfo info = gameState.playerInfo[i];
        MovingSprite sprite = world.sprites[info.spriteId];
        if (sprite == null) {
          continue;
        }
        Vec2 middle = sprite.centerPoint();
        int x = WIDTH ~/ 3;
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

  void render(CanvasRenderingContext2D context, double timeSpent) {
    context.font = '16pt Calibri';
    context.resetTransform();
    showGameTable(context);
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