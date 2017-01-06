library hud;

import 'dart:math';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/net/net.dart';
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

  HudMessages(
      @LocalKeyState() KeyState localKeyState,
      PacketListenerBindings packetListenerBindings) {
   this._localKeyState = localKeyState;
   packetListenerBindings.bindHandler(MESSAGE_KEY, (c, List data) {
     for (String message in data) {
       display(message);
     }
   });
  }

  void display(String message, [double period]) {
    messages.add(new _HudMessage(
        message, period == null ? DEFAULT_DURATION : period));   
  }

  bool shouldDrawTable() {
    return _localKeyState.keyIsDown(KeyCodeDart.SHIFT) ||
        _localKeyState.keyIsDown(KeyCodeDart.CTRL) ||
        _localKeyState.keyIsDown(KeyCodeDart.H) ||
        _localKeyState.keyIsDown(KeyCodeDart.HOME) ||
        _localKeyState.keyIsDown(KeyCodeDart.ALT);
  }

  void showGameTable(WormWorld world, var /*CanvasRenderingContext2D*/ context) {
    if (shouldDrawTable()) {
      context.save();
      GameState gameState = world.network.gameState;
      context.setFillColorRgb(200, 0, 0);
      context.setStrokeColorRgb(200, 0, 0);
      context.globalAlpha = 0.5;
      for (int i = gameState.playerInfo.length - 1; i >= 0; i--) {
        PlayerInfo info = gameState.playerInfo[i];
        MovingSprite sprite = world.spriteIndex[info.spriteId];
        if (sprite == null) {
          continue;
        }
        Vec2 middle = sprite.centerPoint();
        int x = world.width() ~/ 3;
        int y = 40 + i*40;
        ConnectionWrapper connection = world.network.peer.connections[info.connectionId];
        context.fillText("${info.name} SCORE: ${info.score} DEATHS: ${info.deaths} LATENCY: ${connection == null ? "N/A" : connection.expectedLatency().inMilliseconds} ms", x, y);
        // TODO: Check that sprite is alive.
        if (sprite != null && info.inGame) {
          context.lineWidth = 2;
          context.beginPath();
          context.moveTo(x, y);
          context.lineTo(middle.x - world.viewPoint.x, middle.y - world.viewPoint.y);
          context.stroke();
        }
      }
    }
    context.restore();
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