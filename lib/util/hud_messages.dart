library hud;

import 'dart:math';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:di/di.dart';
import 'package:dart2d/util/gamestate.dart';

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
    bool netIssue = world.network().hasNetworkProblem();
    if (shouldDrawTable() || netIssue) {
      context.save();
      if (netIssue) {
        context.setFillColorRgb(0, 0, 0, 0.7);
        context.fillRect(0, 0, world.width(), world.height());
      }
      drawPlayerStats(context, world, world.width(), world.height(), world.spriteIndex, world.imageIndex(), netIssue);
      context.restore();
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