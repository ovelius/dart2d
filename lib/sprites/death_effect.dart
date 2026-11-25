import 'dart:js_interop';
import 'dart:math';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:web/web.dart';

class _DeathConfetti {
  final double vx;
  final double vy;
  final double drag;
  final double gravity;
  final double swayAmp;
  final double swayFreq;
  final double swayPhase;
  final double spinSpeed;
  final double spinPhase;
  final double flipSpeed;
  final double flipPhase;
  final double width;
  final double height;
  final String color;
  final String glintColor;
  final double maxLife;

  _DeathConfetti({
    required this.vx,
    required this.vy,
    required this.drag,
    required this.gravity,
    required this.swayAmp,
    required this.swayFreq,
    required this.swayPhase,
    required this.spinSpeed,
    required this.spinPhase,
    required this.flipSpeed,
    required this.flipPhase,
    required this.width,
    required this.height,
    required this.color,
    required this.glintColor,
    required this.maxLife,
  });
}

class _DeathStar {
  final double vx;
  final double vy;
  final double drag;
  final double gravity;
  final double size;
  final double spinSpeed;
  final double spinPhase;
  final double twinkleFreq;
  final String color;
  final double maxLife;

  _DeathStar({
    required this.vx,
    required this.vy,
    required this.drag,
    required this.gravity,
    required this.size,
    required this.spinSpeed,
    required this.spinPhase,
    required this.twinkleFreq,
    required this.color,
    required this.maxLife,
  });
}

class _DeathStreamer {
  final double vx;
  final double vy;
  final double drag;
  final double gravity;
  final double length;
  final double waveFreq;
  final double wavePhase;
  final String color;
  final double maxLife;

  _DeathStreamer({
    required this.vx,
    required this.vy,
    required this.drag,
    required this.gravity,
    required this.length,
    required this.waveFreq,
    required this.wavePhase,
    required this.color,
    required this.maxLife,
  });
}

class _DeathPuff {
  final double vx;
  final double vy;
  final double maxRadius;
  final double delay;

  _DeathPuff(this.vx, this.vy, this.maxRadius, this.delay);
}

class _DeathBloodDrop {
  final double vx;
  final double vy;
  final double drag;
  final double gravity;
  final double radius;
  final String color;
  final double maxLife;

  _DeathBloodDrop({
    required this.vx,
    required this.vy,
    required this.drag,
    required this.gravity,
    required this.radius,
    required this.color,
    required this.maxLife,
  });
}

/**
 * Multi-stage, network-transferable cartoon player death spectacle:
 * 1. Impact flash + comic starburst + hit-shake anticipation with orbiting KO stars.
 * 2. Dramatic tumbling KO launch of the killed player's sprite toward an apex.
 * 3. Celebratory piñata POP with shockwave rings, comic action rays, puff clouds,
 *    3D-fluttering confetti ribbons, twinkling foil stars, curling streamers,
 *    and an ascending translucent cartoon soul with a floating golden halo.
 *
 * Completely blood-free by default; only renders stylized crimson droplets when
 * the `blood` config parameter is explicitly turned on (`blood > 0`).
 */
class PlayerDeathEffect extends MovingSprite {
  static const double HIT_STOP_TIME = 0.16;
  static const double POP_TIME = 0.58;
  static const double DURATION = 2.65;
  static const double LAUNCH_GRAVITY = 520.0;

  static const List<List<String>> _CONFETTI_PALETTE = [
    ["#ff2e7e", "#ff9ec4"], // Hot pink
    ["#ffdc2e", "#fff7a8"], // Sunny gold
    ["#24e0ff", "#b8f6ff"], // Electric cyan
    ["#42eb4e", "#baffbe"], // Neon lime
    ["#ff7b24", "#ffc899"], // Tangerine
    ["#a84dff", "#e1bdff"], // Vivid violet
    ["#ff4242", "#ffa8a8"], // Coral pop
    ["#ffffff", "#fff6d6"], // Crisp shimmer white
  ];

  static const List<String> _STAR_PALETTE = [
    "#ffe44d",
    "#ffffff",
    "#5ceeff",
    "#ff73c6",
    "#9dff6b",
  ];

  static const List<String> _BLOOD_PALETTE = [
    "#c40c18",
    "#9e0812",
    "#e01b24",
    "#78050d",
    "#b3101a",
  ];

  late WormWorld world;
  double _age = 0.0;
  bool _playedPopSound = false;
  bool _playedKillSound = false;

  double launchVx = 45.0;
  double launchVy = -245.0;
  Vec2 playerSize = Vec2(42.0, 42.0);
  double facingAngle = 0.0;
  int playerImageId = -1;
  int playerFrames = 1;
  int seed = 1;
  bool bloodEnabled = false;
  int bloodCount = 0;
  String killerConnectionId = "";

  bool get playedKillSound => _playedKillSound;

  bool _burstInitialized = false;
  final List<_DeathPuff> _puffs = [];
  final List<_DeathConfetti> _confetti = [];
  final List<_DeathStar> _stars = [];
  final List<_DeathStreamer> _streamers = [];
  final List<_DeathBloodDrop> _bloodDrops = [];

  PlayerDeathEffect(this.world, double x, double y)
      : super(Vec2(x, y), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.collision = false;
    this.invisibleOutsideCanvas = false;
    this.fullFramesOverNetwork = 3;
  }

  PlayerDeathEffect.create(
    this.world,
    LocalPlayerSprite victim, {
    required this.bloodEnabled,
    this.bloodCount = 0,
    this.killerConnectionId = "",
  }) : super(Vec2.copy(victim.centerPoint()), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    Random rng = WorldDamageProjectile.random;
    this.collision = false;
    this.invisibleOutsideCanvas = false;
    this.fullFramesOverNetwork = 3;
    this.spawn_sound = Sound.OW;

    this.playerSize = Vec2.copy(victim.size);
    this.playerImageId = victim.imageId;
    this.playerFrames = max(1, victim.frames);
    this.facingAngle = victim.angle;
    this.seed = rng.nextInt(1 << 20) + 1;

    // Launch upward with a lively horizontal kick biased by the player's motion.
    double kickSign = victim.velocity.x.abs() > 15.0
        ? (victim.velocity.x >= 0 ? 1.0 : -1.0)
        : (rng.nextBool() ? 1.0 : -1.0);
    this.launchVx =
        victim.velocity.x.clamp(-110.0, 110.0) * 0.55 + kickSign * (45.0 + rng.nextDouble() * 45.0);
    this.launchVy = -235.0 - rng.nextDouble() * 45.0;

    _initBurst();
    _maybePlayKillSound();
  }

  void _maybePlayKillSound() {
    if (_playedKillSound || killerConnectionId.isEmpty) {
      return;
    }
    if (killerConnectionId == world.network().peer.getId()) {
      _playedKillSound = true;
      world.playSound(Sound.KILL, multiPlay: true);
      if (world.playerSprite != null) {
        world.addSprite(KillScorePopup(world, world.playerSprite!));
      }
    }
  }

  double get age => _age;

  void _initBurst() {
    _burstInitialized = true;
    _puffs.clear();
    _confetti.clear();
    _stars.clear();
    _streamers.clear();
    _bloodDrops.clear();

    Random rng = Random(seed);

    // Classic cartoon "POOF!" puff cloud ring around the pop apex.
    const int puffCount = 8;
    for (int i = 0; i < puffCount; i++) {
      double a = (2.0 * pi * i / puffCount) + (rng.nextDouble() - 0.5) * 0.4;
      double speed = 55.0 + rng.nextDouble() * 70.0;
      _puffs.add(_DeathPuff(
        cos(a) * speed,
        sin(a) * speed - 18.0,
        14.0 + rng.nextDouble() * 14.0,
        rng.nextDouble() * 0.05,
      ));
    }

    if (bloodEnabled) {
      // Stylized crimson droplet burst — only when blood parameter is enabled.
      int dropTotal = bloodCount > 0 ? bloodCount.clamp(45, 130) : 85;
      for (int i = 0; i < dropTotal; i++) {
        double a = rng.nextDouble() * 2.0 * pi;
        double speed = 90.0 + rng.nextDouble() * 340.0;
        _bloodDrops.add(_DeathBloodDrop(
          vx: cos(a) * speed,
          vy: sin(a) * speed - 85.0,
          drag: 0.9 + rng.nextDouble() * 0.6,
          gravity: 340.0 + rng.nextDouble() * 140.0,
          radius: 2.2 + rng.nextDouble() * 4.4,
          color: _BLOOD_PALETTE[rng.nextInt(_BLOOD_PALETTE.length)],
          maxLife: 1.45 + rng.nextDouble() * 0.6,
        ));
      }
      return;
    }

    // Default (blood-free): 70 vibrant 3D-fluttering party confetti ribbons.
    for (int i = 0; i < 70; i++) {
      double a = rng.nextDouble() * 2.0 * pi;
      double speed = 130.0 + rng.nextDouble() * 370.0;
      List<String> pair = _CONFETTI_PALETTE[rng.nextInt(_CONFETTI_PALETTE.length)];
      _confetti.add(_DeathConfetti(
        vx: cos(a) * speed,
        vy: sin(a) * speed - 75.0,
        drag: 2.3 + rng.nextDouble() * 1.1,
        gravity: 210.0 + rng.nextDouble() * 90.0,
        swayAmp: 8.0 + rng.nextDouble() * 16.0,
        swayFreq: 4.0 + rng.nextDouble() * 4.5,
        swayPhase: rng.nextDouble() * 2.0 * pi,
        spinSpeed: (rng.nextBool() ? 1.0 : -1.0) * (4.0 + rng.nextDouble() * 8.0),
        spinPhase: rng.nextDouble() * 2.0 * pi,
        flipSpeed: 7.0 + rng.nextDouble() * 9.0,
        flipPhase: rng.nextDouble() * 2.0 * pi,
        width: 5.5 + rng.nextDouble() * 5.0,
        height: 3.0 + rng.nextDouble() * 2.8,
        color: pair[0],
        glintColor: pair[1],
        maxLife: 1.65 + rng.nextDouble() * 0.42,
      ));
    }

    // 24 twinkling 5-pointed foil stars.
    for (int i = 0; i < 24; i++) {
      double a = (2.0 * pi * i / 24.0) + (rng.nextDouble() - 0.5) * 0.35;
      double speed = 160.0 + rng.nextDouble() * 280.0;
      _stars.add(_DeathStar(
        vx: cos(a) * speed,
        vy: sin(a) * speed - 60.0,
        drag: 1.85 + rng.nextDouble() * 0.8,
        gravity: 130.0 + rng.nextDouble() * 70.0,
        size: 5.0 + rng.nextDouble() * 5.5,
        spinSpeed: (rng.nextBool() ? 1.0 : -1.0) * (3.5 + rng.nextDouble() * 6.0),
        spinPhase: rng.nextDouble() * 2.0 * pi,
        twinkleFreq: 8.0 + rng.nextDouble() * 8.0,
        color: _STAR_PALETTE[rng.nextInt(_STAR_PALETTE.length)],
        maxLife: 1.55 + rng.nextDouble() * 0.48,
      ));
    }

    // 10 curling party streamers.
    for (int i = 0; i < 10; i++) {
      double a = (2.0 * pi * i / 10.0) + (rng.nextDouble() - 0.5) * 0.4;
      double speed = 190.0 + rng.nextDouble() * 190.0;
      List<String> pair = _CONFETTI_PALETTE[rng.nextInt(_CONFETTI_PALETTE.length)];
      _streamers.add(_DeathStreamer(
        vx: cos(a) * speed,
        vy: sin(a) * speed - 70.0,
        drag: 2.2 + rng.nextDouble() * 0.7,
        gravity: 165.0 + rng.nextDouble() * 65.0,
        length: 14.0 + rng.nextDouble() * 10.0,
        waveFreq: 5.5 + rng.nextDouble() * 3.5,
        wavePhase: rng.nextDouble() * 2.0 * pi,
        color: pair[0],
        maxLife: 1.5 + rng.nextDouble() * 0.45,
      ));
    }
  }

  Vec2 _flightPositionAt(double age) {
    if (age <= HIT_STOP_TIME) {
      return Vec2.copy(position);
    }
    double t = min(age, POP_TIME) - HIT_STOP_TIME;
    return Vec2(
      position.x + launchVx * t,
      position.y + launchVy * t + 0.5 * LAUNCH_GRAVITY * t * t,
    );
  }

  @override
  int extraSendFlags() {
    return Sprite.FLAG_NO_GRAVITY | Sprite.FLAG_NO_MOVEMENTS;
  }

  @override
  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = ExtraSpriteData()
      ..extraFloat.add(_age)
      ..extraFloat.add(launchVx)
      ..extraFloat.add(launchVy)
      ..extraFloat.add(playerSize.x)
      ..extraFloat.add(playerSize.y)
      ..extraFloat.add(facingAngle)
      ..extraInt.add(playerImageId)
      ..extraInt.add(playerFrames)
      ..extraInt.add(seed)
      ..extraInt.add(bloodCount)
      ..extraBool.add(bloodEnabled);
    if (killerConnectionId.isNotEmpty) {
      data.extraString.add(killerConnectionId);
    }
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    if (data.extraFloat.isNotEmpty) {
      double remoteAge = data.extraFloat[0];
      if (remoteAge > _age) {
        _age = remoteAge;
      }
    }
    if (data.extraFloat.length >= 6) {
      launchVx = data.extraFloat[1];
      launchVy = data.extraFloat[2];
      playerSize = Vec2(data.extraFloat[3], data.extraFloat[4]);
      facingAngle = data.extraFloat[5];
    }
    bool needInit = !_burstInitialized;
    if (data.extraInt.length >= 4) {
      playerImageId = data.extraInt[0];
      playerFrames = max(1, data.extraInt[1]);
      if (seed != data.extraInt[2]) {
        seed = data.extraInt[2];
        needInit = true;
      }
      if (bloodCount != data.extraInt[3]) {
        bloodCount = data.extraInt[3];
        needInit = true;
      }
    }
    if (data.extraBool.isNotEmpty && bloodEnabled != data.extraBool[0]) {
      bloodEnabled = data.extraBool[0];
      needInit = true;
    }
    if (data.extraString.isNotEmpty) {
      killerConnectionId = data.extraString[0];
      _maybePlayKillSound();
    }
    if (needInit) {
      _initBurst();
    }
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    if (!_playedPopSound && _age >= POP_TIME) {
      _playedPopSound = true;
      world.playSound(Sound.DEATH);
    }
    if (networkType != NetworkType.REMOTE && _age >= DURATION) {
      this.remove = true;
    } else if (networkType == NetworkType.REMOTE && _age >= DURATION * 1.25) {
      this.remove = true;
    }
  }

  void _drawStarPath(
      CanvasRenderingContext2D context, double outerR, double innerR, int points) {
    context.beginPath();
    for (int i = 0; i < points * 2; i++) {
      double r = i.isEven ? outerR : innerR;
      double a = (i * pi / points) - pi / 2.0;
      double x = cos(a) * r;
      double y = sin(a) * r;
      if (i == 0) {
        context.moveTo(x, y);
      } else {
        context.lineTo(x, y);
      }
    }
    context.closePath();
  }

  void _drawImpactBurst(CanvasRenderingContext2D context) {
    if (_age > 0.36) return;
    double t = (_age / 0.36).clamp(0.0, 1.0);
    double ease = 1.0 - pow(1.0 - t, 3).toDouble();
    double alpha = (1.0 - t);

    context.save();
    context.translate(position.x, position.y);
    context.globalCompositeOperation = "lighter";

    // Crisp comic impact starburst.
    if (_age < 0.24) {
      double starT = (_age / 0.24).clamp(0.0, 1.0);
      double starR = 16.0 + 36.0 * (1.0 - pow(1.0 - starT, 3).toDouble());
      context.rotate(starT * 0.45);
      _drawStarPath(context, starR, starR * 0.42, 10);
      context.fillStyle = "rgba(255, 245, 175, ${((1.0 - starT) * 0.85).toStringAsFixed(2)})".toJS;
      context.fill();
    }

    // Impact ring.
    double ringR = 10.0 + 52.0 * ease;
    context.strokeStyle = "rgba(255, 255, 255, ${(alpha * 0.85).toStringAsFixed(2)})".toJS;
    context.lineWidth = 3.5 * alpha + 0.8;
    context.beginPath();
    context.arc(0, 0, ringR, 0, pi * 2.0);
    context.stroke();

    context.restore();
  }

  void _drawLaunchingCharacter(CanvasRenderingContext2D context) {
    if (_age >= POP_TIME) return;

    Vec2 pos = _flightPositionAt(_age);

    // Sparkle trail behind the launching character.
    if (_age > HIT_STOP_TIME) {
      context.save();
      context.globalCompositeOperation = "lighter";
      const int trailDots = 5;
      for (int i = 1; i <= trailDots; i++) {
        double sampleAge = _age - i * 0.045;
        if (sampleAge < HIT_STOP_TIME) continue;
        Vec2 tp = _flightPositionAt(sampleAge);
        double frac = 1.0 - (i / (trailDots + 1));
        context.save();
        context.translate(tp.x, tp.y);
        context.rotate(_age * 6.0 + i);
        _drawStarPath(context, 4.5 + 4.5 * frac, 2.0 + 2.0 * frac, 4);
        context.fillStyle = "rgba(255, 232, 110, ${(frac * 0.85).toStringAsFixed(2)})".toJS;
        context.fill();
        context.restore();
      }
      context.restore();
    }

    // Compute comic shake, spin, and pre-pop balloon inflation!
    double shakeX = 0.0;
    double shakeY = 0.0;
    double rot = 0.0;
    double scaleX = 1.0;
    double scaleY = 1.0;
    double glowAlpha = 0.0;

    if (_age < HIT_STOP_TIME) {
      double ht = _age / HIT_STOP_TIME;
      shakeX = sin(_age * 95.0) * 5.5 * (1.0 - ht * 0.3);
      shakeY = cos(_age * 115.0) * 4.0 * (1.0 - ht * 0.3);
      double squash = sin(ht * pi);
      scaleX = 1.0 + 0.28 * squash;
      scaleY = 1.0 - 0.18 * squash;
      glowAlpha = 0.75 * (1.0 - ht * 0.5);
    } else {
      double ft = (_age - HIT_STOP_TIME) / (POP_TIME - HIT_STOP_TIME);
      double spinDir = launchVx >= 0 ? 1.0 : -1.0;
      rot = spinDir * (ft * ft * 22.0 + ft * 6.0);
      // Balloon swell right before popping!
      double swell = 1.0 + 0.45 * pow(ft, 2.4).toDouble();
      double wobble = sin(ft * 26.0) * 0.1 * ft;
      scaleX = swell + wobble;
      scaleY = swell - wobble;
      glowAlpha = pow(ft, 2.0).toDouble() * 0.85;
    }

    context.save();
    context.translate(pos.x + shakeX, pos.y + shakeY);

    // Warm golden charge-up aura building behind the character right before pop.
    if (glowAlpha > 0.05) {
      context.save();
      context.globalCompositeOperation = "lighter";
      double auraR = max(playerSize.x, playerSize.y) * (0.75 + 0.55 * glowAlpha);
      CanvasGradient grad = context.createRadialGradient(0, 0, 0, 0, 0, auraR);
      grad.addColorStop(0.0, "rgba(255, 255, 225, ${(glowAlpha * 0.9).toStringAsFixed(2)})");
      grad.addColorStop(0.55, "rgba(255, 200, 60, ${(glowAlpha * 0.55).toStringAsFixed(2)})");
      grad.addColorStop(1.0, "rgba(255, 160, 20, 0)");
      context.fillStyle = grad;
      context.beginPath();
      context.arc(0, 0, auraR, 0, pi * 2.0);
      context.fill();
      context.restore();
    }

    // Draw the killed player's actual sprite!
    context.save();
    context.rotate(rot);
    if (facingAngle > pi * 2) {
      context.scale(-scaleX, scaleY);
    } else {
      context.scale(scaleX, scaleY);
    }
    bool drewImage = false;
    if (playerImageId >= 0) {
      try {
        HTMLImageElement img = world.imageIndex().getImageById(playerImageId);
        if (img.width > 0 && img.height > 0) {
          double fw = img.width / max(1, playerFrames);
          context.drawImage(
            img,
            0,
            0,
            fw,
            img.height,
            -playerSize.x / 2.0,
            -playerSize.y / 2.0,
            playerSize.x,
            playerSize.y,
          );
          drewImage = true;
        }
      } catch (_) {}
    }
    if (!drewImage) {
      context.fillStyle = "#ffe066".toJS;
      context.beginPath();
      context.arc(0, 0, playerSize.x * 0.42, 0, pi * 2.0);
      context.fill();
    }
    context.restore();

    // Orbiting dizzy comic KO stars around the character!
    for (int i = 0; i < 3; i++) {
      double orbitA = _age * 11.0 + (2.0 * pi * i / 3.0);
      double ox = cos(orbitA) * (playerSize.x * 0.55);
      double oy = -playerSize.y * 0.42 + sin(orbitA) * 7.0;
      context.save();
      context.translate(ox, oy);
      context.rotate(_age * 8.0 + i);
      _drawStarPath(context, 6.2, 2.7, 5);
      context.fillStyle = "#ffe64d".toJS;
      context.fill();
      context.strokeStyle = "#b37400".toJS;
      context.lineWidth = 1.0;
      context.stroke();
      context.restore();
    }

    context.restore();
  }

  void _drawPopFinale(CanvasRenderingContext2D context, double tPop) {
    Vec2 pop = _flightPositionAt(POP_TIME);

    // 1. Cartoon "POOF!" cloud puffs behind the burst.
    if (tPop < 0.85) {
      context.save();
      for (_DeathPuff puff in _puffs) {
        double lt = ((tPop - puff.delay) / (0.85 - puff.delay)).clamp(0.0, 1.0);
        if (lt <= 0.0) continue;
        double ease = 1.0 - pow(1.0 - lt, 2.5).toDouble();
        double px = pop.x + puff.vx * ease * 0.52;
        double py = pop.y + puff.vy * ease * 0.52 - 12.0 * lt;
        double r = puff.maxRadius * (0.45 + 0.7 * ease) * (1.0 - lt * 0.25);
        double alpha = (lt < 0.15 ? lt / 0.15 : (1.0 - lt) / 0.85) * 0.65;
        context.fillStyle = bloodEnabled
            ? "rgba(215, 175, 175, ${alpha.toStringAsFixed(2)})".toJS
            : "rgba(255, 252, 245, ${alpha.toStringAsFixed(2)})".toJS;
        context.beginPath();
        context.arc(px, py, max(1.0, r), 0, pi * 2.0);
        context.fill();
      }
      context.restore();
    }

    // 2. Pop flash, dual celebratory shockwave rings, and comic action rays.
    if (tPop < 0.52) {
      double pt = (tPop / 0.52).clamp(0.0, 1.0);
      double ease = 1.0 - pow(1.0 - pt, 3).toDouble();
      double alpha = 1.0 - pt;

      context.save();
      context.globalCompositeOperation = "lighter";

      // Warm central pop flash.
      if (tPop < 0.28) {
        double ft = (tPop / 0.28).clamp(0.0, 1.0);
        double flashR = 24.0 + 72.0 * (1.0 - pow(1.0 - ft, 3).toDouble());
        double fa = 1.0 - ft;
        CanvasGradient grad = context.createRadialGradient(
            pop.x, pop.y, 0, pop.x, pop.y, flashR);
        grad.addColorStop(0.0, "rgba(255, 255, 255, ${fa.toStringAsFixed(2)})");
        grad.addColorStop(
            0.45,
            bloodEnabled
                ? "rgba(255, 70, 70, ${(fa * 0.75).toStringAsFixed(2)})"
                : "rgba(255, 228, 95, ${(fa * 0.85).toStringAsFixed(2)})");
        grad.addColorStop(1.0, "rgba(255, 200, 50, 0)");
        context.fillStyle = grad;
        context.beginPath();
        context.arc(pop.x, pop.y, flashR, 0, pi * 2.0);
        context.fill();
      }

      // Outer golden/white shockwave ring.
      double outerR = 14.0 + 115.0 * ease;
      context.strokeStyle = bloodEnabled
          ? "rgba(255, 75, 85, ${(alpha * 0.9).toStringAsFixed(2)})".toJS
          : "rgba(255, 235, 120, ${(alpha * 0.95).toStringAsFixed(2)})".toJS;
      context.lineWidth = 6.0 * alpha + 1.0;
      context.beginPath();
      context.arc(pop.x, pop.y, outerR, 0, pi * 2.0);
      context.stroke();

      // Inner vibrant contrast ring.
      double innerR = 8.0 + 78.0 * ease;
      context.strokeStyle = bloodEnabled
          ? "rgba(255, 190, 190, ${(alpha * 0.85).toStringAsFixed(2)})".toJS
          : "rgba(110, 240, 255, ${(alpha * 0.85).toStringAsFixed(2)})".toJS;
      context.lineWidth = 3.0 * alpha + 0.8;
      context.beginPath();
      context.arc(pop.x, pop.y, innerR, 0, pi * 2.0);
      context.stroke();

      // 10 crisp comic action speed rays.
      if (tPop < 0.34) {
        double rt = (tPop / 0.34).clamp(0.0, 1.0);
        double rAlpha = 1.0 - rt;
        double startR = 16.0 + 52.0 * rt;
        double endR = 36.0 + 96.0 * (1.0 - pow(1.0 - rt, 2).toDouble());
        context.lineCap = "round";
        context.lineWidth = 2.8 * rAlpha + 0.6;
        for (int i = 0; i < 10; i++) {
          double a = (2.0 * pi * i / 10.0) + 0.25;
          context.strokeStyle = (i.isEven
                  ? "rgba(255, 255, 240, ${(rAlpha * 0.9).toStringAsFixed(2)})"
                  : (bloodEnabled
                      ? "rgba(255, 70, 80, ${(rAlpha * 0.85).toStringAsFixed(2)})"
                      : "rgba(255, 180, 70, ${(rAlpha * 0.85).toStringAsFixed(2)})"))
              .toJS;
          context.beginPath();
          context.moveTo(pop.x + cos(a) * startR, pop.y + sin(a) * startR);
          context.lineTo(pop.x + cos(a) * endR, pop.y + sin(a) * endR);
          context.stroke();
        }
      }

      context.restore();
    }

    // 3. Burst particles: Blood (ONLY if blood param enabled) OR Confetti + Stars + Streamers.
    if (bloodEnabled) {
      _drawBloodBurst(context, pop, tPop);
    } else {
      _drawConfettiBurst(context, pop, tPop);
    }

    // 4. Cute ascending cartoon soul / angel ghost with floating golden halo!
    _drawAscendingSoul(context, pop, tPop);
  }

  void _drawConfettiBurst(CanvasRenderingContext2D context, Vec2 pop, double tPop) {
    context.save();

    // Curling wavy party streamers.
    context.lineCap = "round";
    for (_DeathStreamer s in _streamers) {
      if (tPop >= s.maxLife) continue;
      double fade = ((s.maxLife - tPop) / 0.45).clamp(0.0, 1.0);
      double dragInt = (1.0 - exp(-s.drag * tPop)) / s.drag;
      double sx = pop.x + s.vx * dragInt;
      double sy = pop.y + s.vy * dragInt + (s.gravity / s.drag) * (tPop - dragInt);

      double expK = exp(-s.drag * tPop);
      double vxNow = s.vx * expK;
      double vyNow = (s.vy - s.gravity / s.drag) * expK + s.gravity / s.drag;
      double heading = atan2(vyNow, vxNow);

      context.save();
      context.translate(sx, sy);
      context.rotate(heading);
      context.globalAlpha = fade * 0.92;
      context.strokeStyle = s.color.toJS;
      context.lineWidth = 2.6;
      context.beginPath();
      context.moveTo(0, 0);
      double wave1 = sin(tPop * s.waveFreq + s.wavePhase) * 4.5;
      double wave2 = cos(tPop * s.waveFreq + s.wavePhase) * 4.5;
      context.bezierCurveTo(
          -s.length * 0.35, wave1, -s.length * 0.7, -wave2, -s.length, wave1 * 0.6);
      context.stroke();
      context.restore();
    }

    // 3D-fluttering tumbling party confetti ribbons.
    for (_DeathConfetti c in _confetti) {
      if (tPop >= c.maxLife) continue;
      double fade = ((c.maxLife - tPop) / 0.5).clamp(0.0, 1.0);
      double dragInt = (1.0 - exp(-c.drag * tPop)) / c.drag;
      double swayBlend = 1.0 - exp(-2.8 * tPop);
      double cx = pop.x +
          c.vx * dragInt +
          c.swayAmp * sin(tPop * c.swayFreq + c.swayPhase) * swayBlend;
      double cy = pop.y + c.vy * dragInt + (c.gravity / c.drag) * (tPop - dragInt);

      double flipCos = cos(tPop * c.flipSpeed + c.flipPhase);
      double scaleY = flipCos.abs().clamp(0.18, 1.0);
      bool showGlint = flipCos > 0.55;

      context.save();
      context.translate(cx, cy);
      context.rotate(c.spinPhase + tPop * c.spinSpeed);
      context.scale(1.0, scaleY);
      context.globalAlpha = fade;
      context.fillStyle = (showGlint ? c.glintColor : c.color).toJS;
      context.fillRect(-c.width / 2.0, -c.height / 2.0, c.width, c.height);
      context.restore();
    }

    // Twinkling 5-pointed foil stars.
    for (_DeathStar st in _stars) {
      if (tPop >= st.maxLife) continue;
      double fade = ((st.maxLife - tPop) / 0.5).clamp(0.0, 1.0);
      double dragInt = (1.0 - exp(-st.drag * tPop)) / st.drag;
      double sx = pop.x + st.vx * dragInt;
      double sy = pop.y + st.vy * dragInt + (st.gravity / st.drag) * (tPop - dragInt);
      double twinkle = 0.72 + 0.35 * sin(tPop * st.twinkleFreq + st.spinPhase);

      context.save();
      context.translate(sx, sy);
      context.rotate(st.spinPhase + tPop * st.spinSpeed);
      context.globalAlpha = fade;
      _drawStarPath(context, st.size * twinkle, st.size * 0.44 * twinkle, 5);
      context.fillStyle = st.color.toJS;
      context.fill();
      context.restore();
    }

    context.restore();
  }

  void _drawBloodBurst(CanvasRenderingContext2D context, Vec2 pop, double tPop) {
    context.save();
    context.lineCap = "round";
    for (_DeathBloodDrop d in _bloodDrops) {
      if (tPop >= d.maxLife) continue;
      double fade = ((d.maxLife - tPop) / 0.4).clamp(0.0, 1.0);
      double dragInt = (1.0 - exp(-d.drag * tPop)) / d.drag;
      double bx = pop.x + d.vx * dragInt;
      double by = pop.y + d.vy * dragInt + (d.gravity / d.drag) * (tPop - dragInt);

      double expK = exp(-d.drag * tPop);
      double vxNow = d.vx * expK;
      double vyNow = (d.vy - d.gravity / d.drag) * expK + d.gravity / d.drag;

      context.globalAlpha = fade * 0.94;
      if (vxNow * vxNow + vyNow * vyNow > 2500.0) {
        context.strokeStyle = d.color.toJS;
        context.lineWidth = d.radius * 1.4;
        context.beginPath();
        context.moveTo(bx, by);
        context.lineTo(bx - vxNow * 0.024, by - vyNow * 0.024);
        context.stroke();
      }
      context.fillStyle = d.color.toJS;
      context.beginPath();
      context.arc(bx, by, d.radius, 0, pi * 2.0);
      context.fill();
    }
    context.restore();
  }

  void _drawAscendingSoul(CanvasRenderingContext2D context, Vec2 pop, double tPop) {
    double soulLife = DURATION - POP_TIME;
    if (tPop < 0.04 || tPop >= soulLife) return;

    double st = ((tPop - 0.04) / (soulLife - 0.04)).clamp(0.0, 1.0);
    double fadeIn = (st / 0.12).clamp(0.0, 1.0);
    double fadeOut = ((1.0 - st) / 0.30).clamp(0.0, 1.0);
    double alpha = fadeIn * fadeOut * 0.86;
    if (alpha <= 0.01) return;

    double gx = pop.x + sin(tPop * 3.8) * 14.0;
    double gy = pop.y - 12.0 - tPop * 52.0;

    context.save();
    context.translate(gx, gy);
    context.globalAlpha = alpha;

    // Soft ethereal outer glow.
    CanvasGradient glow = context.createRadialGradient(0, 0, 2, 0, 0, 24);
    glow.addColorStop(0.0, "rgba(220, 248, 255, 0.55)");
    glow.addColorStop(1.0, "rgba(170, 225, 255, 0)");
    context.fillStyle = glow;
    context.beginPath();
    context.arc(0, 0, 24, 0, pi * 2.0);
    context.fill();

    // Cute translucent cartoon ghost body with gently waving scalloped tail.
    double sway = sin(tPop * 7.5) * 2.0;
    context.fillStyle = "rgba(240, 250, 255, 0.92)".toJS;
    context.strokeStyle = "rgba(155, 210, 240, 0.9)".toJS;
    context.lineWidth = 1.3;
    context.beginPath();
    context.arc(0, -4, 10.5, pi, 0, false);
    context.lineTo(10.5, 9);
    context.quadraticCurveTo(7.0, 13.5 + sway, 3.5, 9.5);
    context.quadraticCurveTo(0.0, 13.5 - sway, -3.5, 9.5);
    context.quadraticCurveTo(-7.0, 13.5 + sway, -10.5, 9);
    context.closePath();
    context.fill();
    context.stroke();

    // Peaceful cartoon closed eyes (^ ^).
    context.strokeStyle = "rgba(70, 115, 145, 0.9)".toJS;
    context.lineWidth = 1.4;
    context.lineCap = "round";
    context.beginPath();
    context.arc(-3.6, -3.5, 2.2, pi * 1.1, pi * 1.9, false);
    context.stroke();
    context.beginPath();
    context.arc(3.6, -3.5, 2.2, pi * 1.1, pi * 1.9, false);
    context.stroke();

    // Floating bobbing golden halo above the soul!
    double haloY = -19.5 + sin(tPop * 6.0) * 1.6;
    context.strokeStyle = "#ffd84d".toJS;
    context.lineWidth = 2.4;
    context.beginPath();
    context.ellipse(0, haloY, 8.5, 3.0, 0, 0, pi * 2.0);
    context.stroke();

    context.strokeStyle = "rgba(255, 255, 215, 0.9)".toJS;
    context.lineWidth = 1.0;
    context.beginPath();
    context.ellipse(0, haloY - 0.5, 7.2, 2.1, 0, 0, pi * 2.0);
    context.stroke();

    context.restore();
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    if (_age >= DURATION) {
      return;
    }
    if (!_burstInitialized) {
      _initBurst();
    }

    _drawImpactBurst(context);

    if (_age < POP_TIME) {
      _drawLaunchingCharacter(context);
    } else {
      _drawPopFinale(context, _age - POP_TIME);
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.PLAYER_DEATH;
  }
}

class _ScoreSparkle {
  final double angle;
  final double speed;
  final double size;
  final double maxLife;

  _ScoreSparkle(this.angle, this.speed, this.size, this.maxLife);
}

/**
 * Satisfying elastic golden "+1" score popup with twinkling sparkles that floats
 * next to the local player when they score a kill (spawned locally only for the killer).
 */
class KillScorePopup extends MovingSprite {
  static const double DURATION = 1.35;
  final WormWorld world;
  final LocalPlayerSprite target;
  double _age = 0.0;
  late final double _offsetX;
  late final double _offsetY;
  final List<_ScoreSparkle> _sparkles = [];

  KillScorePopup(this.world, this.target)
      : super(Vec2.copy(target.centerPoint()), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.networkType = NetworkType.LOCAL_ONLY;
    this.collision = false;
    this.invisibleOutsideCanvas = false;

    Random rng = WorldDamageProjectile.random;
    // Place neatly to the upper-right of the player (slight jitter prevents
    // exact overlap on rapid multi-kills).
    _offsetX = target.size.x * 0.58 + (rng.nextDouble() - 0.5) * 14.0;
    _offsetY = -target.size.y * 0.35 + (rng.nextDouble() - 0.5) * 8.0;

    for (int i = 0; i < 6; i++) {
      double a = (2.0 * pi * i / 6.0) + (rng.nextDouble() - 0.5) * 0.4;
      _sparkles.add(_ScoreSparkle(
        a,
        24.0 + rng.nextDouble() * 26.0,
        3.2 + rng.nextDouble() * 2.4,
        0.45 + rng.nextDouble() * 0.25,
      ));
    }
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    if (target.inGame()) {
      Vec2 c = target.centerPoint();
      position.x = c.x;
      position.y = c.y;
    }
    if (_age >= DURATION) {
      this.remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    if (_age >= DURATION) return;

    double progress = (_age / DURATION).clamp(0.0, 1.0);
    double easeOut = 1.0 - pow(1.0 - progress, 3).toDouble();
    double riseY = -44.0 * easeOut;

    // Elastic spring overshoot pop-in (0.2 -> 1.38 -> 1.0 over first 0.28s).
    double scale;
    if (_age < 0.28) {
      double t = _age / 0.28;
      scale = 1.0 - exp(-9.0 * t) * cos(t * pi * 2.1) * 0.85;
    } else {
      scale = 1.0;
    }

    double alpha = progress > 0.72
        ? (1.0 - (progress - 0.72) / 0.28).clamp(0.0, 1.0)
        : 1.0;
    double wobble = sin(_age * 16.0) * exp(-_age * 5.0) * 0.16;

    double drawX = position.x + _offsetX;
    double drawY = position.y + _offsetY + riseY;

    context.save();
    context.translate(drawX, drawY);
    context.globalAlpha = alpha;

    // 1. Warm golden flash halo on initial pop-in.
    if (_age < 0.35) {
      double ht = (_age / 0.35).clamp(0.0, 1.0);
      double ha = (1.0 - ht) * 0.75;
      double hr = 14.0 + 18.0 * (1.0 - pow(1.0 - ht, 2).toDouble());
      context.save();
      context.globalCompositeOperation = "lighter";
      CanvasGradient glow = context.createRadialGradient(0, 0, 0, 0, 0, hr);
      glow.addColorStop(0.0, "rgba(255, 245, 165, ${ha.toStringAsFixed(2)})");
      glow.addColorStop(1.0, "rgba(255, 190, 40, 0)");
      context.fillStyle = glow;
      context.beginPath();
      context.arc(0, 0, hr, 0, pi * 2.0);
      context.fill();
      context.restore();
    }

    // 2. Twinkling golden 4-point sparkle stars around the "+1".
    for (_ScoreSparkle sp in _sparkles) {
      if (_age >= sp.maxLife) continue;
      double st = (_age / sp.maxLife).clamp(0.0, 1.0);
      double sa = (1.0 - st) * alpha;
      double dist = sp.speed * (1.0 - pow(1.0 - st, 2).toDouble());
      double sx = cos(sp.angle) * dist;
      double sy = sin(sp.angle) * dist;
      double r = sp.size * (0.5 + 0.5 * (1.0 - st));
      context.save();
      context.translate(sx, sy);
      context.globalAlpha = sa;
      context.fillStyle = "#fff6b0".toJS;
      context.beginPath();
      context.moveTo(0, -r);
      context.lineTo(r * 0.32, -r * 0.32);
      context.lineTo(r, 0);
      context.lineTo(r * 0.32, r * 0.32);
      context.lineTo(0, r);
      context.lineTo(-r * 0.32, r * 0.32);
      context.lineTo(-r, 0);
      context.lineTo(-r * 0.32, -r * 0.32);
      context.closePath();
      context.fill();
      context.restore();
    }

    // 3. Bold outlined metallic-gold "+1" text.
    context.rotate(wobble);
    context.scale(scale, scale);
    context.font = 'bold 24px "Trebuchet MS", Arial, sans-serif';
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.lineJoin = "round";

    context.strokeStyle = "#3b1c00".toJS;
    context.lineWidth = 4.5;
    context.strokeText("+1", 0, 0);

    CanvasGradient textGrad = context.createLinearGradient(0, -12, 0, 12);
    textGrad.addColorStop(0.0, "#fffad1");
    textGrad.addColorStop(0.45, "#ffd93b");
    textGrad.addColorStop(1.0, "#ff9100");
    context.fillStyle = textGrad;
    context.fillText("+1", 0, 0);

    context.restore();
  }
}
