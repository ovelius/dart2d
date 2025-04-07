library hud;

import 'dart:math';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/net/helpers.dart';
import 'package:injectable/injectable.dart';
import 'package:dart2d/net/state_updates.dart';

class HudMessage {
  final String message;
  double remainingTime;
  HudMessage(this.message, this.remainingTime);
  double getAlpha() {
    return min(remainingTime, 1.0);
  }
}

@Singleton(scope: 'world')
class HudMessages {
  static const DEFAULT_DURATION = 4.0;
  late KeyState _localKeyState;
  List<HudMessage> messages = [];

  HudMessages(
      KeyState localKeyState,
      PacketListenerBindings packetListenerBindings) {
   this._localKeyState = localKeyState;
   packetListenerBindings.bindHandler(StateUpdate_Update.userMessage, (c, StateUpdate data) {
      display(data.userMessage);
   });
  }

  void display(String message, [double period = DEFAULT_DURATION]) {
    messages.add(new HudMessage(message, period));
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
      drawPlayerStats(context, world, world.width().toInt(), world.height().toInt(), world.spriteIndex, world.imageIndex(), netIssue, true);
      context.restore();
    }
  }

  void render(WormWorld world, var /*CanvasRenderingContext2D*/ context, double timeSpent) {
    context.font = '16pt Calibri';
    context.resetTransform();
    showGameTable(world, context);
    for (int i = 0; i < messages.length; i++) {
      HudMessage m = messages[i];
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