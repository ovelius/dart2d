library hud;

import 'dart:js_interop';
import 'dart:math';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/net/helpers.dart';
import 'package:injectable/injectable.dart';
import 'package:web/web.dart';

enum _HudTone {
  KILL,
  POSITIVE,
  INFO,
  WARNING,
}

class HudMessage {
  final String message;
  final double totalDuration;
  double remainingTime;
  double age = 0.0;
  double? displayY;
  late final _HudTone tone;

  HudMessage(this.message, this.remainingTime) : totalDuration = remainingTime {
    this.tone = _classifyTone(message);
  }

  static _HudTone _classifyTone(String msg) {
    String lower = msg.toLowerCase();
    if (lower.contains("error") ||
        lower.contains("closed") ||
        lower.contains("closing") ||
        lower.contains("full")) {
      return _HudTone.WARNING;
    }
    if (lower.contains("is back!") ||
        lower.contains("connected") ||
        lower.contains("commander") ||
        lower.contains(":)")) {
      return _HudTone.POSITIVE;
    }
    if (lower.contains("connecting to") ||
        lower.contains("got connection") ||
        lower.contains("got server")) {
      return _HudTone.INFO;
    }
    // Default to celebratory/comic combat feed tone (kill messages, etc.).
    return _HudTone.KILL;
  }

  double getAlpha() {
    if (remainingTime <= 0.0) return 0.0;
    double fadeOut = (remainingTime / 0.55).clamp(0.0, 1.0);
    double fadeIn = (age / 0.14).clamp(0.0, 1.0);
    return min(fadeIn, fadeOut);
  }
}

@Singleton(scope: 'world')
class HudMessages {
  static const DEFAULT_DURATION = 4.5;
  static const int MAX_VISIBLE_MESSAGES = 6;
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
    while (messages.length > MAX_VISIBLE_MESSAGES) {
      messages.removeAt(0);
    }
  }

  bool shouldDrawTable() {
    return _localKeyState.keyIsDown(KeyCodeDart.SHIFT) ||
        _localKeyState.keyIsDown(KeyCodeDart.CTRL) ||
        _localKeyState.keyIsDown(KeyCodeDart.H) ||
        _localKeyState.keyIsDown(KeyCodeDart.HOME) ||
        _localKeyState.keyIsDown(KeyCodeDart.ALT);
  }

  void showGameTable(WormWorld world, CanvasRenderingContext2D context) {
    bool netIssue = world.network().hasNetworkProblem();
    if (shouldDrawTable() || netIssue) {
      context.save();
      if (netIssue) {
        context.fillStyle = "rgb(0, 0, 0, 0.7)".toJS;
        context.fillRect(0, 0, world.width(), world.height());
      }
      drawPlayerStats(context, world, world.width().toInt(), world.height().toInt(), world.spriteIndex, world.imageIndex(), netIssue, true);
      context.restore();
    }
  }

  void _drawBadgeIcon(
      CanvasRenderingContext2D context, double cx, double cy, _HudTone tone) {
    context.save();
    context.translate(cx, cy);
    if (tone == _HudTone.KILL) {
      // Comic 8-point starburst badge for frag/combat messages.
      context.beginPath();
      for (int i = 0; i < 16; i++) {
        double r = i.isEven ? 9.5 : 4.8;
        double a = (i * pi / 8.0) - pi / 2.0;
        double px = cos(a) * r;
        double py = sin(a) * r;
        if (i == 0) {
          context.moveTo(px, py);
        } else {
          context.lineTo(px, py);
        }
      }
      context.closePath();
      context.fillStyle = "#ffcb2e".toJS;
      context.fill();
      context.strokeStyle = "#4d1f00".toJS;
      context.lineWidth = 1.6;
      context.stroke();
      context.fillStyle = "#fff7c2".toJS;
      context.beginPath();
      context.arc(0, 0, 2.8, 0, pi * 2.0);
      context.fill();
    } else if (tone == _HudTone.POSITIVE) {
      // Crisp 5-point star badge for joins / respawns / commander promotion.
      context.beginPath();
      for (int i = 0; i < 10; i++) {
        double r = i.isEven ? 8.5 : 4.0;
        double a = (i * pi / 5.0) - pi / 2.0;
        double px = cos(a) * r;
        double py = sin(a) * r;
        if (i == 0) {
          context.moveTo(px, py);
        } else {
          context.lineTo(px, py);
        }
      }
      context.closePath();
      context.fillStyle = "#5ee85e".toJS;
      context.fill();
      context.strokeStyle = "#104a18".toJS;
      context.lineWidth = 1.5;
      context.stroke();
    } else if (tone == _HudTone.WARNING) {
      // Warning triangle badge.
      context.beginPath();
      context.moveTo(0, -8.0);
      context.lineTo(8.0, 6.5);
      context.lineTo(-8.0, 6.5);
      context.closePath();
      context.fillStyle = "#ff5e4d".toJS;
      context.fill();
      context.strokeStyle = "#4d0b06".toJS;
      context.lineWidth = 1.5;
      context.stroke();
      context.fillStyle = "#ffffff".toJS;
      context.fillRect(-1.1, -3.2, 2.2, 5.0);
      context.fillRect(-1.1, 3.0, 2.2, 2.0);
    } else {
      // Glossy sky-blue info bubble.
      context.beginPath();
      context.arc(0, 0, 7.0, 0, pi * 2.0);
      context.fillStyle = "#4cc3ff".toJS;
      context.fill();
      context.strokeStyle = "#0b3a59".toJS;
      context.lineWidth = 1.5;
      context.stroke();
      context.fillStyle = "#ffffff".toJS;
      context.beginPath();
      context.arc(-2.0, -2.0, 2.0, 0, pi * 2.0);
      context.fill();
    }
    context.restore();
  }

  void _drawCartoonBanner(
      CanvasRenderingContext2D context, HudMessage m, double x, double y, double maxWidth) {
    double alpha = m.getAlpha();
    if (alpha <= 0.01) return;

    // Snappy elastic pop-in + gentle slide from the left.
    double popScale = 1.0;
    double slideX = 0.0;
    if (m.age < 0.24) {
      double t = (m.age / 0.24).clamp(0.0, 1.0);
      double easeOut = 1.0 - pow(1.0 - t, 3).toDouble();
      slideX = -26.0 * (1.0 - easeOut);
      popScale = 1.0 - exp(-9.0 * t) * cos(t * pi * 1.8) * 0.22;
    }
    double exitLift = m.remainingTime < 0.55
        ? -10.0 * (1.0 - (m.remainingTime / 0.55).clamp(0.0, 1.0))
        : 0.0;

    bool isKill = m.tone == _HudTone.KILL;
    String font = isKill
        ? 'bold 17px "Trebuchet MS", "Arial Rounded MT Bold", Arial, sans-serif'
        : 'bold 15px "Trebuchet MS", "Arial Rounded MT Bold", Arial, sans-serif';

    context.save();
    context.font = font;
    double textW = context.measureText(m.message).width.toDouble();
    double padLeft = 34.0;
    double padRight = 16.0;
    double pillH = isKill ? 34.0 : 30.0;
    double pillW = min(maxWidth, textW + padLeft + padRight);
    double radius = pillH * 0.48;

    context.globalAlpha = alpha;
    context.translate(x + slideX, y + exitLift + pillH / 2.0);
    context.scale(popScale, popScale);
    context.translate(0, -pillH / 2.0);

    // Choose comic color theme matching the game's slate-blue icon cards.
    String accentColor;
    String fillTop;
    String fillBottom;
    String textColor;
    switch (m.tone) {
      case _HudTone.KILL:
        accentColor = "#ff9d2e";
        fillTop = "#3d4757";
        fillBottom = "#232a36";
        textColor = "#fff9e6";
        break;
      case _HudTone.POSITIVE:
        accentColor = "#4cd964";
        fillTop = "#374652";
        fillBottom = "#202b33";
        textColor = "#f2fff4";
        break;
      case _HudTone.WARNING:
        accentColor = "#ff5c4d";
        fillTop = "#4a3338";
        fillBottom = "#2e1d22";
        textColor = "#fff0ee";
        break;
      case _HudTone.INFO:
        accentColor = "#4cc3ff";
        fillTop = "#394454";
        fillBottom = "#222a36";
        textColor = "#eef8ff";
        break;
    }

    // 1. Offset comic drop shadow for crisp lift over sky & terrain.
    context.fillStyle = "rgba(12, 16, 24, 0.55)".toJS;
    context.beginPath();
    context.roundRect(3.0, 4.0, pillW, pillH, radius.toJS);
    context.fill();

    // 2. Main cartoon rounded slate banner body.
    CanvasGradient bgGrad = context.createLinearGradient(0, 0, 0, pillH);
    bgGrad.addColorStop(0.0, fillTop);
    bgGrad.addColorStop(1.0, fillBottom);
    context.fillStyle = bgGrad;
    context.beginPath();
    context.roundRect(0, 0, pillW, pillH, radius.toJS);
    context.fill();

    // 3. Subtle glossy cartoon top sheen + colored accent stripe inside the pill.
    context.save();
    context.beginPath();
    context.roundRect(0, 0, pillW, pillH, radius.toJS);
    context.clip();
    context.fillStyle = "rgba(255, 255, 255, 0.13)".toJS;
    context.fillRect(0, 0, pillW, pillH * 0.42);
    context.fillStyle = accentColor.toJS;
    context.fillRect(0, 0, 7.0, pillH);
    context.restore();

    // 4. Bold dark cartoon ink border.
    context.strokeStyle = "#161b24".toJS;
    context.lineWidth = 2.6;
    context.beginPath();
    context.roundRect(0, 0, pillW, pillH, radius.toJS);
    context.stroke();

    // 5. Left comic icon badge.
    _drawBadgeIcon(context, 19.0, pillH / 2.0, m.tone);

    // 6. Bold outlined cartoon text for effortless readability.
    context.textBaseline = "middle";
    context.textAlign = "left";
    context.lineJoin = "round";
    double textMaxW = max(20.0, pillW - padLeft - padRight);
    double textY = pillH / 2.0 + 0.5;
    context.strokeStyle = "#131720".toJS;
    context.lineWidth = 3.6;
    context.strokeText(m.message, padLeft, textY, textMaxW);
    context.fillStyle = textColor.toJS;
    context.fillText(m.message, padLeft, textY, textMaxW);

    context.restore();
  }

  void render(WormWorld world, CanvasRenderingContext2D context, double timeSpent) {
    context.save();
    context.resetTransform();
    showGameTable(world, context);

    // Update lifetimes safely (removing expired entries cleanly without skipping).
    for (int i = messages.length - 1; i >= 0; i--) {
      HudMessage m = messages[i];
      m.age += timeSpent;
      m.remainingTime -= timeSpent;
      if (m.remainingTime <= 0) {
        messages.removeAt(i);
      }
    }

    double maxBannerW = max(180.0, world.width() - 48.0);
    double startX = 20.0;
    double startY = 18.0;
    double rowStride = 40.0;

    for (int i = 0; i < messages.length; i++) {
      HudMessage m = messages[i];
      double targetY = startY + i * rowStride;
      if (m.displayY == null) {
        m.displayY = targetY;
      } else {
        m.displayY = m.displayY! + (targetY - m.displayY!) * min(1.0, timeSpent * 14.0);
      }
      _drawCartoonBanner(context, m, startX, m.displayY!, maxBannerW);
    }

    context.restore();
  }
}