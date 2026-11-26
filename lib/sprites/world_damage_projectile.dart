
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:web/web.dart';

import '../res/sounds.dart';
import 'movingsprite.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('DamageProjectile');

class BananaCake extends WorldDamageProjectile {
  double _age = 0.0;
  double _bounceSquash = 0.0;
  double _prevVelX = 0.0;
  double _prevVelY = 0.0;
  bool _hasPrevVel = false;

  BananaCake(WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(26.0, 22.0);
    this.mod = Mod.BANANA;
  }

  BananaCake.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.mod = Mod.BANANA;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(26.0, 22.0);
    this.position.x = ownerCenter.x - size.x / 2;
    this.position.y = ownerCenter.y - size.y / 2;
    this.spriteType = SpriteType.CUSTOM;
    this.velocity.x = cos(positionBase.angle);
    this.velocity.y = sin(positionBase.angle);
    this.velocity = this.velocity.multiply(200.0);
    this.velocity = owner.velocity + this.velocity;
  }

  @override
  handleWorldCollide(ByteWorld world, int direction) {
    super.handleWorldCollide(world, direction);
    _bounceSquash = 1.0;
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    super.frame(duration, frameStep, gravity);

    if (_hasPrevVel &&
        ((_prevVelX * velocity.x < -80.0) || (_prevVelY * velocity.y < -80.0))) {
      _bounceSquash = 1.0;
    }
    _prevVelX = velocity.x;
    _prevVelY = velocity.y;
    _hasPrevVel = true;

    if (_bounceSquash > 0.0) {
      _bounceSquash = max(0.0, _bounceSquash - duration * 6.5);
    }
  }

  void _drawMiniBanana(CanvasRenderingContext2D context, double x, double y,
      double scale, double rot) {
    context.save();
    context.translate(x, y);
    context.rotate(rot);
    context.scale(scale, scale);

    context.beginPath();
    context.moveTo(-6.5, -1.0);
    context.bezierCurveTo(-3.0, 4.8, 3.5, 4.8, 6.8, -1.4);
    context.bezierCurveTo(3.5, 1.5, -2.5, 1.6, -6.5, -1.0);
    context.closePath();

    CanvasGradient grad = context.createRadialGradient(-1.0, 0.5, 0.5, 0.0, 1.0, 7.0);
    grad.addColorStop(0.0, "#fff8ad");
    grad.addColorStop(0.45, "#ffe026");
    grad.addColorStop(1.0, "#cf8f00");
    context.fillStyle = grad;
    context.fill();
    context.strokeStyle = "#663f00".toJS;
    context.lineWidth = 0.9;
    context.stroke();

    // Glossy jellybean-style highlight along banana curve.
    context.strokeStyle = "rgba(255, 255, 255, 0.85)".toJS;
    context.lineWidth = 1.0;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(-3.0, 1.2);
    context.quadraticCurveTo(0.2, 2.7, 3.4, 1.0);
    context.stroke();

    // Dark brown stem & tip.
    context.fillStyle = "#593006".toJS;
    context.beginPath();
    context.arc(6.5, -1.3, 1.1, 0, pi * 2.0);
    context.arc(-6.4, -0.9, 0.9, 0, pi * 2.0);
    context.fill();

    context.restore();
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    Vec2 center = centerPoint();

    context.save();

    // Countdown timer above the pancake.
    if (explodeAfter != null && showCounter) {
      context.fillStyle = "#ffffff".toJS;
      context.strokeStyle = "#2b1604".toJS;
      context.lineWidth = 2.5;
      context.font = "bold 11px Arial";
      String txt = max(0, explodeAfter!.ceil()).toString();
      context.strokeText(txt, center.x - 4, position.y - 6);
      context.fillText(txt, center.x - 4, position.y - 6);
    }

    context.translate(center.x, center.y);

    // Subtle rock with horizontal velocity + elastic bounce squash + pre-detonation pulse.
    double tilt = (velocity.x * 0.0012).clamp(-0.28, 0.28);
    context.rotate(tilt);

    double sx = 1.0;
    double sy = 1.0;
    if (_bounceSquash > 0.01) {
      double wave = sin(_bounceSquash * pi);
      sx += 0.22 * wave;
      sy -= 0.18 * wave;
    }
    double urgency = explodeAfter != null ? ((1.2 - explodeAfter!) / 1.2).clamp(0.0, 1.0) : 0.0;
    if (urgency > 0.0) {
      double pulse = sin(_age * (18.0 + 22.0 * urgency)) * 0.08 * urgency;
      sx += pulse;
      sy += pulse;
    }
    context.scale(sx, sy);

    double rx = size.x * 0.56; // ~14.5px wide pancake
    double ry = size.y * 0.30; // ~6.6px ellipse height

    // 1. Bottom pancake in the stack.
    context.fillStyle = "#c97a26".toJS;
    context.strokeStyle = "#5c2c07".toJS;
    context.lineWidth = 1.2;
    context.beginPath();
    context.ellipse(0, 4.8, rx * 0.96, ry, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Fluffy pale-golden batter rim on bottom pancake.
    context.fillStyle = "#f2c87d".toJS;
    context.beginPath();
    context.ellipse(0, 3.2, rx * 0.95, ry * 0.92, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // 2. Top pancake in the stack.
    context.fillStyle = "#f2c87d".toJS;
    context.beginPath();
    context.ellipse(0, 0.8, rx, ry, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Rich griddled golden-brown top surface.
    CanvasGradient topGrad = context.createRadialGradient(-rx * 0.22, -2.5, 1.0, 0, -0.5, rx * 1.1);
    topGrad.addColorStop(0.0, "#f5be5b");
    topGrad.addColorStop(0.55, "#d68224");
    topGrad.addColorStop(1.0, "#9c4e0e");
    context.fillStyle = topGrad;
    context.beginPath();
    context.ellipse(0, -0.6, rx * 0.94, ry * 0.88, 0, 0, pi * 2.0);
    context.fill();

    // Subtle pancake griddle pores.
    context.fillStyle = "rgba(115, 52, 8, 0.45)".toJS;
    for (List<double> pore in [
      [-rx * 0.45, -1.0, 0.9],
      [rx * 0.48, -0.6, 0.85],
      [rx * 0.22, 1.8, 0.75],
      [-rx * 0.18, 2.2, 0.8],
    ]) {
      context.beginPath();
      context.arc(pore[0], pore[1], pore[2], 0, pi * 2.0);
      context.fill();
    }

    // 3. Glossy amber maple syrup pool & drips over the rim.
    context.fillStyle = "rgba(155, 62, 6, 0.88)".toJS;
    context.beginPath();
    context.ellipse(0, -1.0, rx * 0.62, ry * 0.52, 0, 0, pi * 2.0);
    context.fill();
    // Syrup drips cascading down the front edge.
    context.lineCap = "round";
    context.strokeStyle = "rgba(155, 62, 6, 0.9)".toJS;
    context.lineWidth = 2.6;
    context.beginPath();
    context.moveTo(-rx * 0.36, 1.0);
    context.lineTo(-rx * 0.36, 5.2);
    context.moveTo(rx * 0.28, 1.5);
    context.lineTo(rx * 0.28, 6.4);
    context.stroke();
    // Glossy syrup highlight.
    context.strokeStyle = "rgba(255, 200, 120, 0.65)".toJS;
    context.lineWidth = 1.0;
    context.beginPath();
    context.moveTo(-rx * 0.30, -2.4);
    context.quadraticCurveTo(0, -3.5, rx * 0.26, -2.2);
    context.stroke();

    // 4. Melting pat of butter.
    context.fillStyle = "#fff199".toJS;
    context.strokeStyle = "#c99618".toJS;
    context.lineWidth = 0.85;
    context.beginPath();
    context.roundRect(-3.8, -4.4, 7.6, 4.4, 1.4.toJS);
    context.fill();
    context.stroke();

    // 5. Banana coin slices + glossy mini bananas right on top of the pancake!
    for (List<double> slice in [
      [-6.6, -2.0],
      [6.4, -1.8],
    ]) {
      context.fillStyle = "#fff5b8".toJS;
      context.strokeStyle = "#d9a21b".toJS;
      context.lineWidth = 0.9;
      context.beginPath();
      context.ellipse(slice[0], slice[1], 3.4, 2.0, 0, 0, pi * 2.0);
      context.fill();
      context.stroke();
      context.fillStyle = "#c48c2b".toJS;
      context.beginPath();
      context.arc(slice[0], slice[1], 0.7, 0, pi * 2.0);
      context.fill();
    }

    // Two glossy mini bananas perched proudly on top!
    _drawMiniBanana(context, -3.2, -5.6, 0.95, -0.35);
    _drawMiniBanana(context, 3.6, -5.2, 0.92, 0.32);

    // 6. Sizzling bomb fuse & crackling spark on top.
    context.strokeStyle = "#8a6238".toJS;
    context.lineWidth = 1.8;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(0, -6.5);
    context.quadraticCurveTo(2.5, -11.5, 6.2, -11.2);
    context.stroke();

    // Flickering fuse spark.
    double sparkPhase = _age * (24.0 + 30.0 * urgency);
    double sparkR = 2.6 + sin(sparkPhase) * 1.1 + urgency * 1.6;
    context.save();
    context.globalCompositeOperation = "lighter";
    context.fillStyle = "#ff8811".toJS;
    context.beginPath();
    context.arc(6.5, -11.2, sparkR * 1.5, 0, pi * 2.0);
    context.fill();
    context.fillStyle = "#fff6b0".toJS;
    context.beginPath();
    context.arc(6.5, -11.2, sparkR * 0.75, 0, pi * 2.0);
    context.fill();
    context.restore();

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  explode() {
    world.explosionAtSprite(
        sprite: this, velocity: velocity.multiply(0.2),
        addParticles: particlesOnExplode,
        damage: damage, radius: radius, damageDoer: owner!, mod: Mod.BANANA);
    Random rng = WorldDamageProjectile.random;
    const int bananaCount = 9;
    for (int i = 0; i < bananaCount; i++) {
      double angle = (2.0 * pi * i / bananaCount) + (rng.nextDouble() - 0.5) * 0.45;
      double speed = 420.0 + rng.nextDouble() * 140.0;
      Vec2 burstVel = Vec2(
        cos(angle) * speed + velocity.x * 0.35,
        sin(angle) * speed - 70.0 + velocity.y * 0.35,
      );
      BananaClusterProjectile banana = BananaClusterProjectile.createFromPancake(
        world,
        this.owner!,
        centerPoint(),
        burstVel,
      );
      world.addSprite(banana);
    }
    this.remove = true;
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.BANANA_PANCAKE;
  }
}

/**
 * Glossy, tumbling cartoon banana cluster bomblet spawned when BananaCake explodes.
 * Styled to match JellybeanProjectile with crisp outlines, 3D candy-like yellow shading,
 * curved white specular glaze highlight, and a sunny golden motion streak.
 */
class BananaClusterProjectile extends WorldDamageProjectile {
  static const int MAX_TRAIL = 6;
  final List<Vec2> _trail = [];

  BananaClusterProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(14.0, 9.0);
    this.mod = Mod.BANANA;
    this.color = "#ffe026";
  }

  BananaClusterProjectile.createFromPancake(
      WormWorld world, LocalPlayerSprite owner, Vec2 origin, Vec2 burstVelocity)
      : super(world, origin.x, origin.y, world.imageIndex().getImageIdByName("banana.png"),
            world.imageIndex()) {
    Random rng = WorldDamageProjectile.random;
    this.world = world;
    this.owner = owner;
    this.damage = 30;
    this.mod = Mod.BANANA;
    this.spriteType = SpriteType.CUSTOM;
    this.color = "#ffe026";
    this.size = new Vec2(14.0, 9.0);
    this.setCenter(origin);
    this.velocity = Vec2.copy(burstVelocity);
    this.angle = rng.nextDouble() * 2.0 * pi;
    double spinSign = rng.nextBool() ? 1.0 : -1.0;
    this.rotationVelocity = spinSign * (11.0 + rng.nextDouble() * 9.0);
    this.radius = 40.0;
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    super.frame(duration, frameStep, gravity);
    Vec2 center = centerPoint();
    if (_trail.isNotEmpty) {
      Vec2 last = _trail.last;
      double dx = center.x - last.x;
      double dy = center.y - last.y;
      double distSq = dx * dx + dy * dy;
      if (distSq > 14400.0) {
        _trail.clear();
        _trail.add(center);
      } else if (distSq > 4.0) {
        _trail.add(center);
        if (_trail.length > MAX_TRAIL) {
          _trail.removeAt(0);
        }
      } else if (_trail.length > 1) {
        _trail.removeAt(0);
      }
    } else {
      _trail.add(center);
    }
  }

  void _traceBananaPath(CanvasRenderingContext2D context, double rx, double ry) {
    context.beginPath();
    // Outer convex belly of the banana.
    context.moveTo(-rx, -ry * 0.32);
    context.bezierCurveTo(-rx * 0.48, ry * 1.15, rx * 0.52, ry * 1.15, rx, -ry * 0.38);
    // Right stem tip cap.
    context.bezierCurveTo(rx * 1.04, -ry * 0.62, rx * 0.84, -ry * 0.78, rx * 0.66, -ry * 0.62);
    // Inner concave arch of the banana.
    context.bezierCurveTo(rx * 0.28, ry * 0.24, -rx * 0.28, ry * 0.24, -rx * 0.72, -ry * 0.56);
    // Left blossom tip cap.
    context.bezierCurveTo(-rx * 0.90, -ry * 0.68, -rx * 1.04, -ry * 0.50, -rx, -ry * 0.32);
    context.closePath();
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    Vec2 center = centerPoint();

    context.save();

    // 1. Vibrant sunny-yellow motion streak behind flying bananas (matching jellybean jet style).
    double speedSq = velocity.x * velocity.x + velocity.y * velocity.y;
    if (_trail.length >= 2 && speedSq > 1600.0) {
      context.lineCap = "round";
      context.lineJoin = "round";
      for (int i = 1; i < _trail.length; i++) {
        double frac = i / _trail.length;
        Vec2 p0 = _trail[i - 1];
        Vec2 p1 = _trail[i];
        context.strokeStyle = "rgba(255, 224, 42, ${(frac * 0.45).toStringAsFixed(2)})".toJS;
        context.lineWidth = 1.6 + 4.4 * frac;
        context.beginPath();
        context.moveTo(p0.x, p0.y);
        context.lineTo(p1.x, p1.y);
        context.stroke();
      }
      if (speedSq > 25000.0) {
        Vec2 tail = _trail[_trail.length - 2];
        context.strokeStyle = "rgba(255, 255, 235, 0.38)".toJS;
        context.lineWidth = 1.6;
        context.beginPath();
        context.moveTo(tail.x, tail.y);
        context.lineTo(center.x, center.y);
        context.stroke();
      }
    }

    // 2. Plump glossy cartoon banana body (matching JellybeanProjectile shading & sheen).
    context.translate(center.x, center.y);
    context.rotate(angle);

    double rx = max(8.8, size.x * 0.65);
    double ry = max(5.2, size.y * 0.58);

    _traceBananaPath(context, rx, ry);

    // 3D glossy sunny banana gradient.
    CanvasGradient grad = context.createRadialGradient(
        -rx * 0.15, ry * 0.05, ry * 0.15, 0, ry * 0.25, rx * 1.15);
    grad.addColorStop(0.0, "#fff9b0");
    grad.addColorStop(0.42, "#ffe024");
    grad.addColorStop(1.0, "#cf8f00");
    context.fillStyle = grad;
    context.fill();

    // Subtle banana ridge contour.
    context.strokeStyle = "rgba(190, 128, 0, 0.45)".toJS;
    context.lineWidth = 0.9;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(-rx * 0.62, -ry * 0.15);
    context.quadraticCurveTo(0, ry * 0.72, rx * 0.62, -ry * 0.18);
    context.stroke();

    // Crisp cartoon dark-brown rim outline.
    _traceBananaPath(context, rx, ry);
    context.strokeStyle = "#663e00".toJS;
    context.lineWidth = 1.2;
    context.stroke();

    // Dark-brown woody stem & blossom nubs on both tips.
    context.fillStyle = "#593006".toJS;
    context.beginPath();
    context.arc(rx * 0.84, -ry * 0.52, 1.5, 0, pi * 2.0);
    context.fill();
    context.beginPath();
    context.arc(-rx * 0.86, -ry * 0.44, 1.2, 0, pi * 2.0);
    context.fill();

    // Signature jellybean-style curved glossy white specular highlight & sparkle dot.
    context.strokeStyle = "rgba(255, 255, 255, 0.88)".toJS;
    context.lineWidth = 1.6;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(-rx * 0.46, ry * 0.28);
    context.quadraticCurveTo(0.0, ry * 0.68, rx * 0.44, ry * 0.24);
    context.stroke();

    context.fillStyle = "rgba(255, 255, 255, 0.95)".toJS;
    context.beginPath();
    context.arc(-rx * 0.58, ry * 0.08, 1.1, 0, pi * 2.0);
    context.fill();

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.BANANA;
  }
}

/// Upgraded cartoon Cat Litter Box projectile with 3 animated cats peeking and
/// squirming inside a glossy turquoise litter tray. When the fuse expires it
/// detonates AND launches panicked cartoon cats that jump out and sprint across
/// the world until they hit a wall or explode 2 seconds later.
class CatLitterBox extends WorldDamageProjectile {
  static const int CAT_COUNT = 4;
  double _age = 0.0;
  double _bounceSquash = 0.0;
  double _prevVelX = 0.0;
  double _prevVelY = 0.0;
  bool _hasPrevVel = false;

  CatLitterBox(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(46.0, 36.0);
    this.mod = Mod.LITTER;
    this.bounche = 0.4;
    this.angle = 0.0;
  }

  CatLitterBox.createWithOwner(WormWorld world, LocalPlayerSprite owner,
      int damage, MovingSprite positionBase)
      : super(
            world,
            0.0,
            0.0,
            world.imageIndex().getImageIdByName("box.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.mod = Mod.LITTER;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(46.0, 36.0);
    this.radius = 150.0;
    this.explodeAfter = 5.0;
    this.bounche = 0.4;
    this.angle = 0.0;

    double ownerSize = owner.size.sum() / 2;
    Vec2 ownerCenter = owner.centerPoint();
    this.setCenter(Vec2(
      ownerCenter.x + cos(positionBase.angle) * ownerSize * 0.7,
      ownerCenter.y + sin(positionBase.angle) * ownerSize * 0.7,
    ));
    this.velocity.x = cos(positionBase.angle) * 100.0 + positionBase.velocity.x;
    this.velocity.y = sin(positionBase.angle) * 100.0 + positionBase.velocity.y;
  }

  @override
  handleWorldCollide(ByteWorld world, int direction) {
    super.handleWorldCollide(world, direction);
    _bounceSquash = 1.0;
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    super.frame(duration, frameStep, gravity);

    if (_hasPrevVel &&
        ((_prevVelX * velocity.x < -40.0) || (_prevVelY * velocity.y < -40.0))) {
      _bounceSquash = 1.0;
    }
    _prevVelX = velocity.x;
    _prevVelY = velocity.y;
    _hasPrevVel = true;

    if (_bounceSquash > 0.0) {
      _bounceSquash = max(0.0, _bounceSquash - duration * 6.5);
    }
  }

  void _drawPeekingCat(
    CanvasRenderingContext2D ctx, {
    required double x,
    required double y,
    required double scale,
    required String furColor,
    required String stripeColor,
    required String eyeColor,
    required String bellyColor,
    required double bobOffset,
    bool showPaws = false,
    bool wideEyes = false,
  }) {
    ctx.save();
    ctx.translate(x, y + bobOffset);
    ctx.scale(scale, scale);

    // Pointy cartoon ears with pink inner triangles.
    ctx.fillStyle = furColor.toJS;
    ctx.strokeStyle = "#1c1f29".toJS;
    ctx.lineWidth = 1.6;
    for (final double side in const [-1.0, 1.0]) {
      ctx.beginPath();
      ctx.moveTo(side * 2.5, -5.5);
      ctx.lineTo(side * 6.8, -11.5);
      ctx.lineTo(side * 7.8, -3.5);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = "#ff9eb8".toJS;
      ctx.beginPath();
      ctx.moveTo(side * 3.8, -5.8);
      ctx.lineTo(side * 6.3, -9.6);
      ctx.lineTo(side * 6.9, -4.6);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = furColor.toJS;
    }

    // Plump cat head + shoulders peeking out of litter.
    ctx.fillStyle = furColor.toJS;
    ctx.beginPath();
    ctx.ellipse(0, -1.5, 8.2, 6.8, 0, 0, pi * 2.0);
    ctx.fill();
    ctx.stroke();

    // Coat markings (stripes or tuxedo muzzle/chest).
    ctx.fillStyle = stripeColor.toJS;
    ctx.fillRect(-1.0, -7.8, 2.0, 3.2);
    ctx.fillRect(-4.2, -7.0, 1.6, 2.6);
    ctx.fillRect(2.6, -7.0, 1.6, 2.6);

    // Light muzzle patch.
    ctx.fillStyle = bellyColor.toJS;
    ctx.beginPath();
    ctx.ellipse(0, 1.4, 4.4, 2.7, 0, 0, pi * 2.0);
    ctx.fill();

    // Big expressive cartoon eyes!
    final double eyeR = wideEyes ? 2.4 : 2.0;
    for (final double ex in const [-3.1, 3.1]) {
      ctx.fillStyle = eyeColor.toJS;
      ctx.beginPath();
      ctx.arc(ex, -2.0, eyeR, 0, pi * 2.0);
      ctx.fill();
      ctx.fillStyle = "#12151f".toJS;
      ctx.beginPath();
      ctx.arc(ex, -2.0, eyeR * 0.56, 0, pi * 2.0);
      ctx.fill();
      ctx.fillStyle = "#ffffff".toJS;
      ctx.beginPath();
      ctx.arc(ex - 0.6, -2.6, 0.7, 0, pi * 2.0);
      ctx.fill();
    }

    // Cute pink triangle nose + whiskers!
    ctx.fillStyle = "#ff789e".toJS;
    ctx.beginPath();
    ctx.moveTo(-1.3, 0.0);
    ctx.lineTo(1.3, 0.0);
    ctx.lineTo(0.0, 1.4);
    ctx.closePath();
    ctx.fill();

    ctx.strokeStyle = "#1c1f29".toJS;
    ctx.lineWidth = 0.9;
    ctx.beginPath();
    ctx.moveTo(-4.8, 0.6);
    ctx.lineTo(-9.2, 0.0);
    ctx.moveTo(-4.8, 1.8);
    ctx.lineTo(-9.0, 2.5);
    ctx.moveTo(4.8, 0.6);
    ctx.lineTo(9.2, 0.0);
    ctx.moveTo(4.8, 1.8);
    ctx.lineTo(9.0, 2.5);
    ctx.stroke();

    // Little paws gripping the rim of the litter box!
    if (showPaws) {
      ctx.fillStyle = bellyColor.toJS;
      ctx.strokeStyle = "#1c1f29".toJS;
      ctx.lineWidth = 1.3;
      for (final double px in const [-5.2, 5.2]) {
        ctx.beginPath();
        ctx.ellipse(px, 5.4, 2.8, 2.0, 0, 0, pi * 2.0);
        ctx.fill();
        ctx.stroke();
      }
    }

    ctx.restore();
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 center = centerPoint();
    final double urgency =
        explodeAfter != null ? ((1.8 - explodeAfter!) / 1.8).clamp(0.0, 1.0) : 0.0;

    context.save();

    // Crisp cartoon countdown timer above the box.
    if (explodeAfter != null && showCounter) {
      context.fillStyle = (urgency > 0.5 ? "#ffec66" : "#ffffff").toJS;
      context.strokeStyle = "#19222e".toJS;
      context.lineWidth = 3.0;
      context.font = "bold 12px Arial";
      final String txt = max(0, explodeAfter!.ceil()).toString();
      context.strokeText(txt, center.x - 4, position.y - 12);
      context.fillText(txt, center.x - 4, position.y - 12);
    }

    context.translate(center.x, center.y + 3.0);

    // Excited rumble & squash as the cats prepare to burst out!
    final double wobble =
        sin(_age * (9.0 + 26.0 * urgency)) * (0.04 + 0.14 * urgency);
    context.rotate(wobble);

    double sx = 1.0;
    double sy = 1.0;
    if (_bounceSquash > 0.01) {
      final double wave = sin(_bounceSquash * pi);
      sx += 0.20 * wave;
      sy -= 0.16 * wave;
    }
    if (urgency > 0.0) {
      final double pulse = sin(_age * (16.0 + 24.0 * urgency)) * 0.07 * urgency;
      sx += pulse;
      sy -= pulse * 0.7;
    }
    context.scale(sx, sy);

    final double hw = size.x * 0.50; // ~23px

    // 1. Back rim of the glossy turquoise litter tray.
    context.fillStyle = "#1c8eb8".toJS;
    context.strokeStyle = "#16212e".toJS;
    context.lineWidth = 2.4;
    context.beginPath();
    context.moveTo(-hw + 3, -6);
    context.lineTo(hw - 3, -6);
    context.lineTo(hw + 1, 2);
    context.lineTo(-hw - 1, 2);
    context.closePath();
    context.fill();
    context.stroke();

    // 2. Sandy granular cat litter mound inside the tray!
    final CanvasGradient litterGrad = context.createLinearGradient(0, -10, 0, 4);
    litterGrad.addColorStop(0.0, "#e6dec8");
    litterGrad.addColorStop(1.0, "#b8ae95");
    context.fillStyle = litterGrad;
    context.beginPath();
    context.moveTo(-hw + 4, 1);
    context.quadraticCurveTo(-hw * 0.45, -10, 0, -6);
    context.quadraticCurveTo(hw * 0.45, -11, hw - 4, 1);
    context.closePath();
    context.fill();
    context.stroke();

    // Little pink plastic litter scoop handle sticking out of right corner!
    context.save();
    context.translate(hw - 7, -5);
    context.rotate(0.45);
    context.fillStyle = "#ff7ab3".toJS;
    context.strokeStyle = "#4f1730".toJS;
    context.lineWidth = 1.5;
    context.beginPath();
    context.roundRect(-2.2, -10.5, 4.4, 11.0, 2.0.toJS);
    context.fill();
    context.stroke();
    context.restore();

    // 3. THREE ACTUAL CARTOON CATS SQUIRMING INSIDE THE BOX!
    final double fast = 6.0 + 14.0 * urgency;
    // Left cat: Orange Tabby!
    _drawPeekingCat(
      context,
      x: -11.5,
      y: -5.5,
      scale: 0.88,
      furColor: "#ff9e3b",
      stripeColor: "#c45a12",
      eyeColor: "#9ef562",
      bellyColor: "#fff0d1",
      bobOffset: sin(_age * fast) * (1.4 + urgency * 2.0),
      wideEyes: urgency > 0.45,
    );
    // Right cat: Calico cream & cocoa!
    _drawPeekingCat(
      context,
      x: 11.2,
      y: -5.2,
      scale: 0.86,
      furColor: "#fff3db",
      stripeColor: "#8c4e24",
      eyeColor: "#6be8ff",
      bellyColor: "#ffffff",
      bobOffset: sin(_age * fast + 2.1) * (1.4 + urgency * 2.0),
      wideEyes: urgency > 0.45,
    );
    // Center hero cat: Tuxedo black & white gripping the front rim!
    _drawPeekingCat(
      context,
      x: 0.0,
      y: -7.5,
      scale: 0.96,
      furColor: "#33394a",
      stripeColor: "#1b1f2b",
      eyeColor: "#ffe44d",
      bellyColor: "#ffffff",
      bobOffset: sin(_age * fast + 4.2) * (1.6 + urgency * 2.2),
      showPaws: true,
      wideEyes: urgency > 0.35,
    );

    // 4. Chunky glossy turquoise front wall of the litter box (drawn in front of cats' bellies!).
    final CanvasGradient trayGrad = context.createLinearGradient(0, -1, 0, 14);
    trayGrad.addColorStop(0.0, "#4ce0ff");
    trayGrad.addColorStop(0.55, "#1db4e6");
    trayGrad.addColorStop(1.0, "#107fa8");
    context.fillStyle = trayGrad;
    context.strokeStyle = "#16212e".toJS;
    context.lineWidth = 2.4;
    context.beginPath();
    context.moveTo(-hw, 0);
    context.lineTo(hw, 0);
    context.lineTo(hw - 3, 13.5);
    context.lineTo(-hw + 3, 13.5);
    context.closePath();
    context.fill();
    context.stroke();

    // Raised rounded top lip along front edge!
    context.fillStyle = "#7ef0ff".toJS;
    context.beginPath();
    context.roundRect(-hw - 1.5, -2.5, (hw + 1.5) * 2.0, 4.4, 2.2.toJS);
    context.fill();
    context.stroke();

    // Cute cartoon paw-print emblem stamped on the front of the box!
    context.fillStyle = "#ffffff".toJS;
    context.beginPath();
    context.arc(0, 8.2, 2.6, 0, pi * 2.0);
    context.arc(-3.2, 5.4, 1.2, 0, pi * 2.0);
    context.arc(0.0, 4.5, 1.2, 0, pi * 2.0);
    context.arc(3.2, 5.4, 1.2, 0, pi * 2.0);
    context.fill();

    // 5. Gentle comic stink/excitement squiggles rising above the box!
    context.strokeStyle =
        "rgba(154, 240, 112, ${(0.55 + 0.35 * urgency).toStringAsFixed(2)})".toJS;
    context.lineWidth = 1.6;
    context.lineCap = "round";
    for (int i = -1; i <= 1; i++) {
      final double wx = i * 9.5;
      final double phase = _age * 4.2 + i * 1.4;
      final double rise = (phase % 1.0) * 7.0;
      context.beginPath();
      context.moveTo(wx, -16 - rise);
      context.quadraticCurveTo(
          wx + sin(phase * 3.0) * 3.0, -20 - rise, wx, -24 - rise);
      context.stroke();
    }

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  explode() {
    if (remove) return;
    world.explosionAtSprite(
        sprite: this,
        velocity: velocity.multiply(0.2),
        addParticles: particlesOnExplode,
        damage: damage,
        radius: radius,
        damageDoer: owner!,
        mod: Mod.LITTER);

    final Random rng = WorldDamageProjectile.random;
    final Vec2 origin = centerPoint();
    for (int i = 0; i < CAT_COUNT; i++) {
      final double dir = i.isEven ? -1.0 : 1.0;
      final double jumpSpeedX = dir * (155.0 + rng.nextDouble() * 85.0);
      final double jumpSpeedY = -(200.0 + rng.nextDouble() * 115.0);
      final Vec2 launchOrigin = Vec2(
        origin.x + dir * (6.0 + (i ~/ 2) * 8.0),
        origin.y - 8.0,
      );
      final RunningCatProjectile cat = RunningCatProjectile.createFromBox(
        world,
        this.owner!,
        launchOrigin,
        Vec2(jumpSpeedX + velocity.x * 0.25, jumpSpeedY),
        runDirection: dir,
        catVariant: i % 4,
      );
      world.addSprite(cat);
    }
    this.remove = true;
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.CAT_LITTER_BOX;
  }
}

/// Panicked cartoon cat launched when a [CatLitterBox] explodes.
/// Jumps out of the box, lands on terrain, and sprints horizontally across
/// slopes until it smashes into a wall (or an enemy) or detonates 2 seconds later!
class RunningCatProjectile extends WorldDamageProjectile {
  static const double FUSE_SECONDS = 2.0;
  static const double RUN_SPEED = 220.0;
  static const int WALKABLE_STEP_HEIGHT = 8;

  int catVariant = 0;
  double runDirection = 1.0;
  double _age = 0.0;
  bool _onGround = false;

  RunningCatProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(26.0, 20.0);
    this.mod = Mod.LITTER;
    this.explodeAfter = FUSE_SECONDS;
    this.showCounter = false;
    this.radius = 44.0;
    this.damage = 32;
    this.bounche = 0.0;
    this.angle = 0.0;
  }

  RunningCatProjectile.createFromBox(
    WormWorld world,
    LocalPlayerSprite owner,
    Vec2 origin,
    Vec2 jumpVelocity, {
    required double runDirection,
    required int catVariant,
  }) : super(
            world,
            origin.x,
            origin.y,
            world.imageIndex().getImageIdByName("box.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = 32;
    this.radius = 44.0;
    this.mod = Mod.LITTER;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(26.0, 20.0);
    this.explodeAfter = FUSE_SECONDS;
    this.showCounter = false;
    this.bounche = 0.0;
    this.angle = 0.0;
    this.runDirection = runDirection >= 0 ? 1.0 : -1.0;
    this.catVariant = catVariant % 4;
    this.setCenter(origin);
    this.velocity = Vec2.copy(jumpVelocity);
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    // Keep sprinting in our chosen run direction!
    if (networkType != NetworkType.REMOTE) {
      if (_onGround) {
        velocity.x = runDirection * RUN_SPEED;
      } else if (_age > 0.12) {
        // Maintain forward horizontal momentum mid-leap as well.
        final double targetVx = runDirection * RUN_SPEED;
        velocity.x += (targetVx - velocity.x) * min(1.0, duration * 6.0);
      }
      // Never allow MovingSprite._checkIsStill to disable gravity for a running cat.
      gravityAffect = 1.0;
    } else if (velocity.x.abs() > 10.0) {
      runDirection = velocity.x >= 0 ? 1.0 : -1.0;
    }
    _onGround = false;
    super.frame(duration, frameStep, gravity);
  }

  @override
  handleWorldCollide(ByteWorld byteWorld, int direction) {
    if (remove) return;

    final bool hitBelow =
        (direction & MovingSprite.DIR_BELOW) == MovingSprite.DIR_BELOW;
    final bool hitAbove =
        (direction & MovingSprite.DIR_ABOVE) == MovingSprite.DIR_ABOVE;
    final bool hitLeft =
        (direction & MovingSprite.DIR_LEFT) == MovingSprite.DIR_LEFT;
    final bool hitRight =
        (direction & MovingSprite.DIR_RIGHT) == MovingSprite.DIR_RIGHT;

    // 1. Land & glide over gentle slopes.
    if (hitBelow) {
      _onGround = true;
      if (velocity.y > 0) {
        velocity.y = 0.0;
      }
      int stepped = 0;
      while (stepped < WALKABLE_STEP_HEIGHT &&
          byteWorld.isCanvasCollide(
            (position.x + 2).toInt(),
            (position.y + size.y - 1).toInt(),
            max(1, (size.x - 4).toInt()),
            1,
          )) {
        position.y -= 1.0;
        stepped++;
      }
    }

    // 2. Check for a genuine wall impact in the direction the cat is running!
    final bool movingRight = runDirection >= 0;
    final bool leadingEdgeHit = movingRight ? hitRight : hitLeft;
    if (leadingEdgeHit) {
      final bool atWorldEdge = movingRight
          ? (position.x + size.x >= byteWorld.width - 1.0)
          : (position.x <= 1.0);
      final int probeX = movingRight
          ? (position.x + size.x - 1).toInt()
          : position.x.toInt();
      final int upperWallHeight = max(2, size.y.toInt() - WALKABLE_STEP_HEIGHT);
      final bool solidUpperWall = byteWorld.isCanvasCollide(
        probeX,
        position.y.toInt(),
        1,
        upperWallHeight,
      );

      if (atWorldEdge || solidUpperWall || !hitBelow) {
        explode();
        return;
      }

      // Only the cat's feet brushed a gentle incline -> step up and keep running!
      position.y -= 2.0;
    }

    // 3. Softly deflect off ceilings when leaping out of the box.
    if (hitAbove && velocity.y < 0) {
      velocity.y = -velocity.y * 0.25;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 center = centerPoint();
    final double facing = runDirection >= 0 ? 1.0 : -1.0;
    final double urgency =
        explodeAfter != null ? ((0.55 - explodeAfter!) / 0.55).clamp(0.0, 1.0) : 0.0;

    // 4 distinct cartoon cat coat palettes!
    const List<List<String>> coats = [
      ['#ff9e3b', '#c45a12', '#fff0d1', '#9ef562'], // Orange Tabby
      ['#33394a', '#1b1f2b', '#ffffff', '#ffe44d'], // Tuxedo
      ['#fff3db', '#9e5624', '#ffffff', '#6be8ff'], // Calico
      ['#8b9bb5', '#586882', '#e4ecf7', '#ffd24d'], // Russian Blue
    ];
    final List<String> pal = coats[catVariant.abs() % coats.length];
    final String fur = pal[0];
    final String stripe = pal[1];
    final String belly = pal[2];
    final String eyeCol = pal[3];

    context.save();
    context.translate(center.x, center.y);
    context.scale(facing, 1.0);

    // Subtle puff-up & frantic gallop bob!
    final double stride = _age * 24.0;
    final double hop = _onGround ? sin(stride).abs() * -2.2 : 0.0;
    final double puff = 1.0 + sin(_age * 36.0) * 0.08 * urgency;
    context.translate(0, hop);
    context.scale(puff, puff);

    // Little dust puff behind feet when sprinting on ground.
    if (_onGround) {
      context.fillStyle = "rgba(255, 248, 224, 0.55)".toJS;
      context.beginPath();
      context.arc(-13.5, 6.5, 2.8 + sin(stride) * 0.9, 0, pi * 2.0);
      context.arc(-17.0, 5.2, 1.9, 0, pi * 2.0);
      context.fill();
    }

    // 1. Curved swishing tail + tiny danger spark near detonation!
    final double tailWag = sin(_age * 20.0) * 3.0;
    context.strokeStyle = "#1c1f29".toJS;
    context.lineWidth = 4.6;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(-8.5, -1.0);
    context.quadraticCurveTo(-15.5, -6.5 + tailWag, -12.0, -11.5 + tailWag * 0.6);
    context.stroke();
    context.strokeStyle = fur.toJS;
    context.lineWidth = 2.6;
    context.stroke();

    if (urgency > 0.05) {
      context.save();
      context.globalCompositeOperation = "lighter";
      context.fillStyle = "#ff8822".toJS;
      context.beginPath();
      context.arc(-12.0, -11.5 + tailWag * 0.6, 3.2 + urgency * 2.2, 0, pi * 2.0);
      context.fill();
      context.fillStyle = "#fff5a8".toJS;
      context.beginPath();
      context.arc(-12.0, -11.5 + tailWag * 0.6, 1.6 + urgency, 0, pi * 2.0);
      context.fill();
      context.restore();
    }

    // 2. Animated scampering legs (front & back pairs alternating!).
    final double legSwing = sin(stride) * 4.5;
    context.strokeStyle = "#1c1f29".toJS;
    context.lineWidth = 3.6;
    for (final List<double> leg in [
      [-6.0, 3.0, -7.0 - legSwing, 9.2],
      [-3.5, 3.0, -3.5 + legSwing, 9.2],
      [4.0, 3.0, 5.0 + legSwing, 9.2],
      [6.5, 3.0, 7.0 - legSwing, 9.2],
    ]) {
      context.beginPath();
      context.moveTo(leg[0], leg[1]);
      context.lineTo(leg[2], leg[3]);
      context.stroke();
      context.strokeStyle = belly.toJS;
      context.lineWidth = 1.8;
      context.stroke();
      context.strokeStyle = "#1c1f29".toJS;
      context.lineWidth = 3.6;
    }

    // 3. Plump running cartoon cat body!
    context.fillStyle = fur.toJS;
    context.strokeStyle = "#1c1f29".toJS;
    context.lineWidth = 1.9;
    context.beginPath();
    context.ellipse(-1.0, 0.5, 9.2, 5.4, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Coat stripes/patches on back + light belly.
    context.fillStyle = stripe.toJS;
    context.fillRect(-5.0, -4.4, 2.2, 4.2);
    context.fillRect(-1.2, -4.6, 2.2, 4.5);
    context.fillRect(2.4, -4.0, 2.0, 3.8);
    context.fillStyle = belly.toJS;
    context.beginPath();
    context.ellipse(0.0, 3.2, 5.6, 2.1, 0, 0, pi * 2.0);
    context.fill();

    // 4. Cat head facing forward with pointy ears, wide eye & whiskers!
    context.fillStyle = fur.toJS;
    context.strokeStyle = "#1c1f29".toJS;
    context.lineWidth = 1.8;
    // Pointy ears.
    context.beginPath();
    context.moveTo(4.5, -5.5);
    context.lineTo(6.2, -11.5);
    context.lineTo(9.2, -5.5);
    context.closePath();
    context.fill();
    context.stroke();
    context.beginPath();
    context.moveTo(8.0, -5.5);
    context.lineTo(10.8, -11.2);
    context.lineTo(12.2, -4.8);
    context.closePath();
    context.fill();
    context.stroke();

    // Round head.
    context.beginPath();
    context.arc(8.8, -2.2, 5.4, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Big bright eye + tiny pink nose!
    context.fillStyle = eyeCol.toJS;
    context.beginPath();
    context.arc(10.6, -3.2, 2.0, 0, pi * 2.0);
    context.fill();
    context.fillStyle = "#12151f".toJS;
    context.beginPath();
    context.arc(11.0, -3.2, 1.0, 0, pi * 2.0);
    context.fill();
    context.fillStyle = "#ffffff".toJS;
    context.beginPath();
    context.arc(10.4, -3.8, 0.55, 0, pi * 2.0);
    context.fill();

    context.fillStyle = "#ff789e".toJS;
    context.beginPath();
    context.arc(13.6, -1.6, 1.2, 0, pi * 2.0);
    context.fill();

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  ExtraSpriteData addExtraNetworkData() {
    final ExtraSpriteData data = super.addExtraNetworkData();
    data.extraInt.add(catVariant);
    data.extraInt.add(runDirection >= 0 ? 1 : -1);
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraInt.length > 3) {
      catVariant = data.extraInt[3];
    }
    if (data.extraInt.length > 4) {
      runDirection = data.extraInt[4] >= 0 ? 1.0 : -1.0;
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.RUNNING_CAT;
  }
}

class Hyper extends WorldDamageProjectile {
  static const String COLOR = "#ff1e3c";
  static const int EFFECTIVE_DISTANCE = 300;
  static const int DPS_BEAM = 30;
  static const int EXPLOSION_BEAM_DAMAGE = 15;
  static const double DEFAULT_BLAST_RADIUS = 75.0;
  static const double SOUND_LOOP = 1.0;
  int _quality = 40;

  List<LocalPlayerSprite> _spritesInDamageArea = [];
  double _time = 0.0;
  bool _exploded = false;

  double _nextSound = 0.0;

  Hyper(WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex);

  Hyper.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.color = COLOR;
    double ownerSize = positionBase.size.sum() / 2;
    Vec2 positionCenter = positionBase.centerPoint();
    this.size = new Vec2(25.0, 25.0);
    this.position.x = positionCenter.x + cos(positionBase.angle) * ownerSize;
    this.position.y = positionCenter.y + sin(positionBase.angle) * ownerSize;
    this.velocity.x = cos(positionBase.angle);
    this.angle = positionBase.angle;
    this.velocity.y = sin(positionBase.angle);
    this.velocity = this.velocity.multiply(150.0);
    this.velocity = owner.velocity + this.velocity;
    this.spriteType = SpriteType.CUSTOM;
  }

  void _collectDamageSprites() {
    List<LocalPlayerSprite> spritesInDamageArea = [];
    for (PlayerInfoProto inf in world.network().gameState.playerInfoList()) {
      if (inf.spriteId != owner?.networkId) {
        Sprite? s = world.spriteIndex[inf.spriteId];
        if (s is LocalPlayerSprite && s.inGame() && s.takesDamage(Mod.HYPER)) {
          double dst = distanceTo(s);
          if (dst < EFFECTIVE_DISTANCE) {
            spritesInDamageArea.add(s);
          }
        }
      }
    }
    _spritesInDamageArea = spritesInDamageArea;
  }

  frame(double duration, int frameStep, [Vec2? gravity]) {
    _time += duration;
    _nextSound -= duration;
    int damage = (_time * DPS_BEAM).toInt();
    _time -= (damage / DPS_BEAM);
    _collectDamageSprites();
    if (_nextSound < 0) {
      _nextSound += SOUND_LOOP;
      world.playSoundAtSprite(this, Sound.BUZZ, playSpriteId: true);
    }
    if (owner != null) {
      for (LocalPlayerSprite damageSprite in _spritesInDamageArea) {
        if (damageSprite.takesDamage(Mod.HYPER)) {
          damageSprite.takeDamage(damage, owner!, Mod.HYPER);
        }
      }
    }
    super.frame(duration, frameStep, gravity);
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    context.save();
    Vec2 center = centerPoint();
    for (LocalPlayerSprite sprite in _spritesInDamageArea) {
      if (sprite.inGame() && sprite.takesDamage(Mod.HYPER)) {
        Vec2 targetCenter = sprite.centerPoint();
        context.lineWidth = 4;
        context.strokeStyle = color.toJS;
        context.globalCompositeOperation = "lighter";
        context.beginPath();
        context.moveTo(center.x, center.y);
        context.lineTo(targetCenter.x, targetCenter.y);
        context.stroke();
      }
    }

    super.draw(context, debug);
    double r = getRadius() * 6;
    context.translate(center.x - r, center.y - r);
    context.strokeStyle = this.color.toJS;
    context.globalCompositeOperation = "lighter";
    context.lineWidth = 2;
    for (var i = 0; i < _quality; i++) {
      var theta = 2 * pi * WorldDamageProjectile.random.nextDouble();
      var x = r + (r * cos(theta) / 2);
      var y = r + (r * sin(theta) / 2);
      drawSeed(context, x, y, r);
    }
    context.restore();
  }

  drawSeed(CanvasRenderingContext2D ctx, num x,y,r) {
    num fractions = 3;
    num xM = r;
    num yM = r;
    num xStep = (xM - x) / fractions;
    num yStep = (yM - y) / fractions;
    for (int i = 0; i < fractions; i++) {
      num nextX = xStep * WorldDamageProjectile.random.nextDouble();
      num nextY = yStep * WorldDamageProjectile.random.nextDouble();
      ctx.globalAlpha = 1.0 - (i / fractions);
      drawPath(ctx, xM, yM, xM + nextX, yM + nextY);
      xM += nextX;
      yM += nextY;
    }
  }

  drawPath(CanvasRenderingContext2D ctx, num startX, startY, num destX, destY) {
    ctx.beginPath();
    ctx.moveTo(startX, startY);
    ctx.lineTo(destX, destY);
    ctx.stroke();
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (networkType == NetworkType.REMOTE) {
      return;
    }
    if (owner != null && other != null && other.networkId != owner!.networkId && other.takesDamage(Mod.HYPER)) {
      other.takeDamage(damage, owner!, Mod.HYPER);
      explode();
      return;
    }
    if (world != null && other == null) {
      explode();
    }
  }

  @override
  explode() {
    if (_exploded) {
      return;
    }
    _exploded = true;

    double blastRadius = max(radius, DEFAULT_BLAST_RADIUS);
    Vec2 blastCenter = centerPoint();

    if (owner != null) {
      world.explosionAtSprite(
        sprite: this,
        velocity: velocity.multiply(0.2),
        addParticles: false,
        damage: damage,
        radius: blastRadius,
        damageDoer: owner!,
        mod: Mod.HYPER,
      );
      // BFG-style tracer damage burst to enemies in range on detonation.
      _collectDamageSprites();
      for (LocalPlayerSprite target in _spritesInDamageArea) {
        if (target.takesDamage(Mod.HYPER)) {
          target.takeDamage(EXPLOSION_BEAM_DAMAGE, owner!, Mod.HYPER);
        }
      }
    }

    // Spawn the network-transferable BFG red energy explosion visual.
    HyperExplosion explosion = HyperExplosion.create(world, blastCenter, blastRadius * 2.2);
    explosion.spawn_sound = Sound.EXPLOSION;
    world.addSprite(explosion);

    this.remove = true;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.HYPER;
  }
}

/**
 * Network-transferable BFG-style neon red energy explosion spawned when a
 * Neon Blaster (Hyper) projectile detonates.
 */
class HyperExplosion extends MovingSprite {
  static const double DURATION = 0.65;
  static const int BOLT_COUNT = 14;

  late WormWorld world;
  double _age = 0.0;
  double maxRadius = 165.0;
  final List<_ExplosionSpark> _plasmaSparks = [];

  HyperExplosion(this.world, double x, double y)
      : super(Vec2(x, y), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.color = Hyper.COLOR;
    this.collision = false;
    this.invisibleOutsideCanvas = false;
    this.fullFramesOverNetwork = 3;
    _initPlasmaSparks();
  }

  HyperExplosion.create(this.world, Vec2 center, this.maxRadius)
      : super(Vec2.copy(center), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.color = Hyper.COLOR;
    this.collision = false;
    this.invisibleOutsideCanvas = false;
    this.fullFramesOverNetwork = 3;
    _initPlasmaSparks();
  }

  void _initPlasmaSparks() {
    Random rng = WorldDamageProjectile.random;
    _plasmaSparks.clear();
    for (int i = 0; i < 20; i++) {
      double angle = rng.nextDouble() * 2.0 * pi;
      double speed = 120.0 + rng.nextDouble() * 260.0;
      _plasmaSparks.add(_ExplosionSpark(
        0.0,
        0.0,
        cos(angle) * speed,
        sin(angle) * speed,
        DURATION * (0.5 + 0.5 * rng.nextDouble()),
      ));
    }
  }

  double get age => _age;

  @override
  int extraSendFlags() {
    return Sprite.FLAG_NO_GRAVITY | Sprite.FLAG_NO_MOVEMENTS;
  }

  @override
  ExtraSpriteData addExtraNetworkData() {
    return ExtraSpriteData()
      ..extraFloat.add(_age)
      ..extraFloat.add(maxRadius);
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    if (data.extraFloat.isNotEmpty) {
      double remoteAge = data.extraFloat[0];
      if (remoteAge > _age) {
        _age = remoteAge;
      }
    }
    if (data.extraFloat.length > 1 && data.extraFloat[1] > 0) {
      maxRadius = data.extraFloat[1];
    }
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    double drag = max(0.0, 1.0 - duration * 2.2);
    for (_ExplosionSpark s in _plasmaSparks) {
      if (s.life <= 0) continue;
      s.life -= duration;
      s.x += s.vx * duration;
      s.y += s.vy * duration;
      s.vx *= drag;
      s.vy *= drag;
    }
    if (networkType != NetworkType.REMOTE && _age >= DURATION) {
      this.remove = true;
    } else if (networkType == NetworkType.REMOTE && _age >= DURATION * 1.25) {
      // Fallback cleanup in case a spriteRemoval packet is dropped.
      this.remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    double progress = (_age / DURATION).clamp(0.0, 1.0);
    if (progress >= 1.0) {
      return;
    }
    double alpha = 1.0 - progress;
    double easeOut = 1.0 - pow(1.0 - progress, 3).toDouble();
    double currentRadius = max(8.0, maxRadius * easeOut);
    Vec2 center = centerPoint();

    context.save();
    context.globalCompositeOperation = "lighter";

    // 1. Expanding neon-red plasma core fireball.
    double coreRadius = currentRadius * 0.85;
    CanvasGradient grad = context.createRadialGradient(
        center.x, center.y, 0, center.x, center.y, coreRadius);
    grad.addColorStop(0.0, "rgba(255, 235, 240, ${(alpha).toStringAsFixed(2)})");
    grad.addColorStop(0.25, "rgba(255, 35, 65, ${(alpha * 0.95).toStringAsFixed(2)})");
    grad.addColorStop(0.6, "rgba(190, 0, 30, ${(alpha * 0.6).toStringAsFixed(2)})");
    grad.addColorStop(1.0, "rgba(140, 0, 15, 0)");
    context.fillStyle = grad;
    context.beginPath();
    context.arc(center.x, center.y, coreRadius, 0, pi * 2.0);
    context.fill();

    // 2. Outer + inner expanding BFG shockwave rings.
    context.strokeStyle = "rgba(255, 40, 70, ${(alpha * 0.95).toStringAsFixed(2)})".toJS;
    context.lineWidth = 6.0 * alpha + 1.0;
    context.beginPath();
    context.arc(center.x, center.y, currentRadius, 0, pi * 2.0);
    context.stroke();

    context.strokeStyle = "rgba(255, 210, 220, ${(alpha * 0.85).toStringAsFixed(2)})".toJS;
    context.lineWidth = 2.5 * alpha + 0.5;
    context.beginPath();
    context.arc(center.x, center.y, currentRadius * 0.72, 0, pi * 2.0);
    context.stroke();

    // 3. Crackling jagged neon-red BFG lightning tendrils radiating outward.
    Random rng = WorldDamageProjectile.random;
    double boltReach = currentRadius * 1.18;
    for (int i = 0; i < BOLT_COUNT; i++) {
      double baseAngle = (2.0 * pi * i / BOLT_COUNT) + (rng.nextDouble() - 0.5) * 0.35;
      double reach = boltReach * (0.65 + 0.45 * rng.nextDouble());
      double px = center.x;
      double py = center.y;
      context.beginPath();
      context.moveTo(px, py);
      const int segments = 4;
      for (int s = 1; s <= segments; s++) {
        double frac = s / segments;
        double jitterAngle = baseAngle + (rng.nextDouble() - 0.5) * 0.45 * (1.0 - frac * 0.3);
        px = center.x + cos(jitterAngle) * reach * frac;
        py = center.y + sin(jitterAngle) * reach * frac;
        context.lineTo(px, py);
      }
      context.strokeStyle = (i % 3 == 0)
          ? "rgba(255, 220, 225, ${(alpha * 0.9).toStringAsFixed(2)})".toJS
          : "rgba(255, 25, 55, ${(alpha * 0.95).toStringAsFixed(2)})".toJS;
      context.lineWidth = (i % 3 == 0) ? (2.5 * alpha + 0.5) : (4.0 * alpha + 1.0);
      context.stroke();
    }

    // 4. Brief BFG tracer arcs to nearby players during initial detonation flash.
    if (_age < 0.25) {
      double tracerAlpha = (1.0 - _age / 0.25).clamp(0.0, 1.0);
      context.strokeStyle = "rgba(255, 50, 80, ${tracerAlpha.toStringAsFixed(2)})".toJS;
      context.lineWidth = 4.0 * tracerAlpha + 1.0;
      for (PlayerInfoProto inf in world.network().gameState.playerInfoList()) {
        Sprite? s = world.spriteIndex[inf.spriteId];
        if (s is LocalPlayerSprite && s.inGame()) {
          Vec2 target = s.centerPoint();
          if ((target - center).sum() < Hyper.EFFECTIVE_DISTANCE) {
            context.beginPath();
            context.moveTo(center.x, center.y);
            context.lineTo(target.x, target.y);
            context.stroke();
          }
        }
      }
    }

    // 5. Glowing neon-red plasma embers shooting outward.
    context.lineCap = "round";
    for (_ExplosionSpark s in _plasmaSparks) {
      if (s.life <= 0) continue;
      double sAlpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      double sx = center.x + s.x;
      double sy = center.y + s.y;
      context.strokeStyle = "rgba(255, ${(40 + 180 * sAlpha).toInt()}, ${(60 + 140 * sAlpha).toInt()}, ${sAlpha.toStringAsFixed(2)})".toJS;
      context.lineWidth = 2.0 + 2.0 * sAlpha;
      context.beginPath();
      context.moveTo(sx, sy);
      context.lineTo(sx - s.vx * 0.03, sy - s.vy * 0.03);
      context.stroke();
    }

    context.restore();
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.HYPER_EXPLOSION;
  }
}

class _ExplosionPuff {
  double x;
  double y;
  double vx;
  double vy;
  double maxRadius;
  double delay;
  bool isFire;

  _ExplosionPuff(this.x, this.y, this.vx, this.vy, this.maxRadius, this.delay, this.isFire);
}

class _ExplosionSpark {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  double maxLife;

  _ExplosionSpark(this.x, this.y, this.vx, this.vy, this.maxLife) : life = maxLife;
}

/**
 * Multi-layered fiery cartoon explosion effect (smoke billows, glowing fireball
 * puffs, expanding shockwave ring, and streaked sparks). Spawned locally on
 * every peer via ByteWorldDestruction so default explosions stay in sync
 * across the network without extra sprite traffic.
 */
class ExplosionEffect extends MovingSprite {
  final double blastRadius;
  late final double duration;
  double _age = 0.0;
  final List<_ExplosionPuff> _smokePuffs = [];
  final List<_ExplosionPuff> _firePuffs = [];
  final List<_ExplosionSpark> _sparks = [];

  ExplosionEffect(Vec2 center, Vec2 baseVelocity, this.blastRadius)
      : super(Vec2.copy(center), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.networkType = NetworkType.LOCAL_ONLY;
    this.collision = false;
    this.invisibleOutsideCanvas = false;
    this.duration = (0.38 + blastRadius / 240.0).clamp(0.38, 0.85);

    Random rng = WorldDamageProjectile.random;
    int smokeCount = (5 + (blastRadius / 20).round()).clamp(5, 11);
    int fireCount = (4 + (blastRadius / 22).round()).clamp(4, 9);
    int sparkCount = (8 + (blastRadius / 10).round()).clamp(8, 20);

    for (int i = 0; i < smokeCount; i++) {
      double angle = (2.0 * pi * i / smokeCount) + (rng.nextDouble() - 0.5) * 0.5;
      double speed = blastRadius * (0.45 + rng.nextDouble() * 0.75);
      double offset = blastRadius * rng.nextDouble() * 0.25;
      _smokePuffs.add(_ExplosionPuff(
        center.x + cos(angle) * offset,
        center.y + sin(angle) * offset,
        cos(angle) * speed + baseVelocity.x * 0.25,
        sin(angle) * speed - 25.0 + baseVelocity.y * 0.25,
        blastRadius * (0.35 + rng.nextDouble() * 0.35),
        rng.nextDouble() * 0.08,
        false,
      ));
    }

    for (int i = 0; i < fireCount; i++) {
      double angle = (2.0 * pi * i / fireCount) + (rng.nextDouble() - 0.5) * 0.6;
      double speed = blastRadius * (0.35 + rng.nextDouble() * 0.75);
      double offset = blastRadius * rng.nextDouble() * 0.2;
      _firePuffs.add(_ExplosionPuff(
        center.x + cos(angle) * offset,
        center.y + sin(angle) * offset,
        cos(angle) * speed + baseVelocity.x * 0.3,
        sin(angle) * speed + baseVelocity.y * 0.3,
        blastRadius * (0.32 + rng.nextDouble() * 0.32),
        rng.nextDouble() * 0.05,
        true,
      ));
    }

    for (int i = 0; i < sparkCount; i++) {
      double angle = rng.nextDouble() * 2.0 * pi;
      double speed = blastRadius * (1.8 + rng.nextDouble() * 3.0) + 60.0;
      _sparks.add(_ExplosionSpark(
        center.x,
        center.y,
        cos(angle) * speed + baseVelocity.x * 0.4,
        sin(angle) * speed + baseVelocity.y * 0.4,
        duration * (0.45 + rng.nextDouble() * 0.5),
      ));
    }
  }

  @override
  frame(double dt, int frameStep, [Vec2? gravity]) {
    _age += dt;
    double drag = max(0.0, 1.0 - dt * 2.8);
    for (_ExplosionPuff p in _smokePuffs) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= drag;
      p.vy = p.vy * drag - 18.0 * dt;
    }
    for (_ExplosionPuff p in _firePuffs) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= drag;
      p.vy *= drag;
    }
    double gravY = gravity != null ? gravity.y * 0.65 : 200.0;
    double sparkDrag = max(0.0, 1.0 - dt * 1.4);
    for (_ExplosionSpark s in _sparks) {
      if (s.life <= 0) continue;
      s.life -= dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vx *= sparkDrag;
      s.vy = s.vy * sparkDrag + gravY * dt;
    }
    if (_age >= duration) {
      this.remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    double progress = (_age / duration).clamp(0.0, 1.0);
    if (progress >= 1.0) {
      return;
    }
    Vec2 center = centerPoint();

    context.save();

    // 1. Billowing dark-to-grey smoke puffs behind the fire.
    for (_ExplosionPuff p in _smokePuffs) {
      double localT = ((_age - p.delay) / (duration - p.delay)).clamp(0.0, 1.0);
      if (localT <= 0.0) continue;
      double ease = 1.0 - pow(1.0 - localT, 2).toDouble();
      double r = p.maxRadius * (0.35 + 0.75 * ease);
      double alpha = (localT < 0.2 ? localT / 0.2 : (1.0 - localT) / 0.8) * 0.55;
      int shade = (50 + 45 * localT).toInt();
      context.fillStyle = "rgba($shade, ${shade - 4}, ${shade - 6}, ${alpha.toStringAsFixed(2)})".toJS;
      context.beginPath();
      context.arc(p.x, p.y, r, 0, pi * 2.0);
      context.fill();
    }

    // Switch to additive glow for shockwave, fireball, and sparks.
    context.globalCompositeOperation = "lighter";

    // 2. Fast expanding blast shockwave ring.
    if (progress < 0.45) {
      double ringT = progress / 0.45;
      double ringEase = 1.0 - pow(1.0 - ringT, 3).toDouble();
      double ringAlpha = (1.0 - ringT) * 0.9;
      double ringR = max(4.0, blastRadius * (0.3 + 1.15 * ringEase));
      context.strokeStyle = "rgba(255, 225, 140, ${ringAlpha.toStringAsFixed(2)})".toJS;
      context.lineWidth = (4.5 * (1.0 - ringT)) + 0.8;
      context.beginPath();
      context.arc(center.x, center.y, ringR, 0, pi * 2.0);
      context.stroke();
    }

    // 3. Secondary billowing fiery core puffs.
    if (progress < 0.75) {
      double firePhase = progress / 0.75;
      for (_ExplosionPuff p in _firePuffs) {
        double localT = ((firePhase - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
        if (localT <= 0.0) continue;
        double ease = 1.0 - pow(1.0 - localT, 2).toDouble();
        double r = p.maxRadius * (0.4 + 0.65 * ease) * (1.0 - localT * 0.35);
        double alpha = (1.0 - localT) * 0.85;
        int gVal = (210 * (1.0 - localT * 0.75)).toInt();
        int bVal = (60 * (1.0 - localT)).toInt();
        context.fillStyle = "rgba(255, $gVal, $bVal, ${alpha.toStringAsFixed(2)})".toJS;
        context.beginPath();
        context.arc(p.x, p.y, max(1.0, r), 0, pi * 2.0);
        context.fill();
      }

      // 4. Blazing central radial gradient flash/fireball.
      double coreAlpha = (1.0 - firePhase);
      double coreEase = 1.0 - pow(1.0 - firePhase, 3).toDouble();
      double coreR = max(6.0, blastRadius * (0.55 + 0.6 * coreEase));
      CanvasGradient grad = context.createRadialGradient(
          center.x, center.y, 0, center.x, center.y, coreR);
      grad.addColorStop(0.0, "rgba(255, 255, 230, ${coreAlpha.toStringAsFixed(2)})");
      grad.addColorStop(0.3, "rgba(255, 185, 35, ${(coreAlpha * 0.92).toStringAsFixed(2)})");
      grad.addColorStop(0.68, "rgba(235, 55, 10, ${(coreAlpha * 0.55).toStringAsFixed(2)})");
      grad.addColorStop(1.0, "rgba(180, 20, 0, 0)");
      context.fillStyle = grad;
      context.beginPath();
      context.arc(center.x, center.y, coreR, 0, pi * 2.0);
      context.fill();
    }

    // 5. Flying streaked sparks / embers.
    context.lineCap = "round";
    for (_ExplosionSpark s in _sparks) {
      if (s.life <= 0) continue;
      double sparkAlpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      int gVal = (160 + 95 * sparkAlpha).toInt();
      context.strokeStyle = "rgba(255, $gVal, 80, ${sparkAlpha.toStringAsFixed(2)})".toJS;
      context.lineWidth = 1.5 + 1.5 * sparkAlpha;
      context.beginPath();
      context.moveTo(s.x, s.y);
      context.lineTo(s.x - s.vx * 0.025, s.y - s.vy * 0.025);
      context.stroke();
    }

    context.restore();
  }
}

class _DebrisChunk {
  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double spin;
  double life;
  double maxLife;
  int bounces;
  String fillColor;
  final List<double> vxOffsets;
  final List<double> vyOffsets;

  _DebrisChunk({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.maxLife,
    required this.fillColor,
    required this.vxOffsets,
    required this.vyOffsets,
  })  : life = maxLife,
        bounces = 0;
}

class _DebrisDust {
  double x;
  double y;
  double vx;
  double vy;
  double maxRadius;
  String colorRgb;
  double life;
  double maxLife;

  _DebrisDust(this.x, this.y, this.vx, this.vy, this.maxRadius, this.colorRgb, this.maxLife)
      : life = maxLife;
}

/**
 * Local color-sampled flying terrain debris & dust puffs spawned whenever an
 * explosion carves solid terrain. Chunks fly outward under gravity and bounce
 * off surviving ByteWorld terrain before settling and fading out.
 */
class TerrainDebrisEffect extends MovingSprite {
  final WormWorld world;
  double _age = 0.0;
  double _maxDuration = 0.9;
  final List<_DebrisChunk> _chunks = [];
  final List<_DebrisDust> _dust = [];

  TerrainDebrisEffect(
    this.world,
    Vec2 center,
    Vec2 baseVelocity,
    double blastRadius,
    List<String> terrainColors, {
    bool fullExplosion = true,
    double budgetScale = 1.0,
  }) : super(Vec2.copy(center), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.networkType = NetworkType.LOCAL_ONLY;
    this.collision = false;
    this.invisibleOutsideCanvas = false;

    double clampedScale = budgetScale.clamp(0.0, 1.0);
    if (terrainColors.isEmpty || clampedScale <= 0.0) {
      this.remove = true;
      return;
    }

    Random rng = WorldDamageProjectile.random;
    int chunkCount;
    int dustCount;
    if (fullExplosion) {
      int baseChunks = (7 + (blastRadius / 6.0).round()).clamp(7, 20);
      int baseDust = (4 + (blastRadius / 18.0).round()).clamp(4, 9);
      chunkCount = max(1, (baseChunks * clampedScale).round());
      dustCount = (baseDust * clampedScale).round();
    } else {
      // Carving weapons (Snailgun, Coffee Burn, Shotgun): keep debris very light.
      int baseChunks = (1 + (blastRadius / 14.0).round()).clamp(1, 3);
      chunkCount = (baseChunks * clampedScale).round();
      dustCount = (blastRadius >= 16.0 && clampedScale >= 0.9) ? 1 : 0;
    }

    if (chunkCount <= 0 && dustCount <= 0) {
      this.remove = true;
      return;
    }

    for (int i = 0; i < chunkCount; i++) {
      double angle = (2.0 * pi * i / chunkCount) + (rng.nextDouble() - 0.5) * 0.55;
      double speed = fullExplosion
          ? (95.0 + blastRadius * 2.4) * (0.55 + rng.nextDouble() * 0.85)
          : (60.0 + blastRadius * 1.4) * (0.55 + rng.nextDouble() * 0.75);
      double offsetR = blastRadius * rng.nextDouble() * 0.45;
      double chunkSize = fullExplosion
          ? (2.4 + (blastRadius / 28.0) + rng.nextDouble() * 2.8).clamp(2.4, 6.8)
          : (1.8 + rng.nextDouble() * 1.8).clamp(1.8, 3.8);

      // Build an irregular 5-vertex angular rock polygon.
      const int verts = 5;
      List<double> vxOff = [];
      List<double> vyOff = [];
      for (int v = 0; v < verts; v++) {
        double va = (2.0 * pi * v / verts) + (rng.nextDouble() - 0.5) * 0.45;
        double vr = chunkSize * (0.62 + rng.nextDouble() * 0.48);
        vxOff.add(cos(va) * vr);
        vyOff.add(sin(va) * vr);
      }

      double maxLife = fullExplosion
          ? 0.72 + rng.nextDouble() * 0.58
          : 0.38 + rng.nextDouble() * 0.28;
      if (maxLife > _maxDuration) _maxDuration = maxLife;

      _chunks.add(_DebrisChunk(
        x: center.x + cos(angle) * offsetR,
        y: center.y + sin(angle) * offsetR,
        vx: cos(angle) * speed + baseVelocity.x * 0.25,
        vy: sin(angle) * speed - (fullExplosion ? 65.0 + rng.nextDouble() * 75.0 : 35.0 + rng.nextDouble() * 35.0) + baseVelocity.y * 0.25,
        angle: rng.nextDouble() * 2.0 * pi,
        spin: (rng.nextBool() ? 1.0 : -1.0) * (5.0 + rng.nextDouble() * 12.0),
        maxLife: maxLife,
        fillColor: terrainColors[rng.nextInt(terrainColors.length)],
        vxOffsets: vxOff,
        vyOffsets: vyOff,
      ));
    }

    for (int i = 0; i < dustCount; i++) {
      double angle = (2.0 * pi * i / dustCount) + (rng.nextDouble() - 0.5) * 0.5;
      double speed = blastRadius * (0.5 + rng.nextDouble() * 0.75) + 18.0;
      double offsetR = blastRadius * (0.25 + rng.nextDouble() * 0.45);
      String raw = terrainColors[rng.nextInt(terrainColors.length)];
      String dustRgb = _extractDustRgb(raw);
      double maxLife = fullExplosion
          ? 0.48 + rng.nextDouble() * 0.32
          : 0.32 + rng.nextDouble() * 0.18;
      _dust.add(_DebrisDust(
        center.x + cos(angle) * offsetR,
        center.y + sin(angle) * offsetR,
        cos(angle) * speed,
        sin(angle) * speed - 22.0,
        (blastRadius * 0.28 + rng.nextDouble() * 6.0).clamp(5.0, 22.0),
        dustRgb,
        maxLife,
      ));
    }
  }

  int get chunkCount => _chunks.length;
  int get dustCount => _dust.length;

  static String _extractDustRgb(String rgbStr) {
    // Parse "rgb(r, g, b)" and blend 55% toward warm earthy dust.
    final RegExp re = RegExp(r'(\d+)\s*,\s*(\d+)\s*,\s*(\d+)');
    final RegExpMatch? m = re.firstMatch(rgbStr);
    if (m == null) return "150, 138, 122";
    int r = ((int.parse(m.group(1)!) * 0.45) + (165 * 0.55)).round().clamp(0, 255);
    int g = ((int.parse(m.group(2)!) * 0.45) + (152 * 0.55)).round().clamp(0, 255);
    int b = ((int.parse(m.group(3)!) * 0.45) + (135 * 0.55)).round().clamp(0, 255);
    return "$r, $g, $b";
  }

  @override
  frame(double dt, int frameStep, [Vec2? gravity]) {
    _age += dt;
    double gravY = gravity != null ? gravity.y * 1.35 : 405.0;
    double airDrag = max(0.0, 1.0 - dt * 0.9);
    double dustDrag = max(0.0, 1.0 - dt * 3.0);
    ByteWorld bw = world.byteWorld;
    bool canBounce = bw.worldImageSet();

    for (_DebrisChunk c in _chunks) {
      if (c.life <= 0) continue;
      c.life -= dt;
      c.vx *= airDrag;
      c.vy = c.vy * airDrag + gravY * dt;

      double nextX = c.x + c.vx * dt;
      double nextY = c.y + c.vy * dt;

      if (canBounce && c.bounces < 2 && bw.isSolid(nextX.round(), nextY.round())) {
        bool hitY = bw.isSolid(c.x.round(), nextY.round());
        bool hitX = bw.isSolid(nextX.round(), c.y.round());
        if (hitY) {
          c.vy = -c.vy * 0.42;
          c.vx *= 0.68;
          nextY = c.y;
        }
        if (hitX) {
          c.vx = -c.vx * 0.45;
          nextX = c.x;
        }
        if (!hitX && !hitY) {
          c.vx = -c.vx * 0.42;
          c.vy = -c.vy * 0.42;
          nextX = c.x;
          nextY = c.y;
        }
        c.spin *= -0.65;
        c.bounces++;
      }

      c.x = nextX;
      c.y = nextY;
      c.angle += c.spin * dt;
    }

    for (_DebrisDust d in _dust) {
      if (d.life <= 0) continue;
      d.life -= dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.vx *= dustDrag;
      d.vy = d.vy * dustDrag - 12.0 * dt;
    }

    if (_age >= _maxDuration) {
      this.remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    if (_age >= _maxDuration) return;
    context.save();

    // 1. Terrain-tinted dust puffs billowing off the crater rim.
    for (_DebrisDust d in _dust) {
      if (d.life <= 0) continue;
      double frac = (d.life / d.maxLife).clamp(0.0, 1.0);
      double ageFrac = 1.0 - frac;
      double r = d.maxRadius * (0.45 + 0.75 * ageFrac);
      double alpha = (ageFrac < 0.2 ? ageFrac / 0.2 : frac / 0.8) * 0.36;
      if (alpha <= 0.01) continue;
      CanvasGradient grad = context.createRadialGradient(d.x, d.y, 0, d.x, d.y, r);
      grad.addColorStop(0.0, "rgba(${d.colorRgb}, ${alpha.toStringAsFixed(2)})");
      grad.addColorStop(1.0, "rgba(${d.colorRgb}, 0)");
      context.fillStyle = grad;
      context.beginPath();
      context.arc(d.x, d.y, r, 0, pi * 2.0);
      context.fill();
    }

    // 2. Tumbling angular rocky terrain chunks sampled from the blasted ground.
    for (_DebrisChunk c in _chunks) {
      if (c.life <= 0) continue;
      double frac = (c.life / c.maxLife).clamp(0.0, 1.0);
      double alpha = frac < 0.3 ? (frac / 0.3) : 1.0;
      context.save();
      context.translate(c.x, c.y);
      context.rotate(c.angle);
      context.globalAlpha = alpha;

      context.beginPath();
      for (int i = 0; i < c.vxOffsets.length; i++) {
        if (i == 0) {
          context.moveTo(c.vxOffsets[i], c.vyOffsets[i]);
        } else {
          context.lineTo(c.vxOffsets[i], c.vyOffsets[i]);
        }
      }
      context.closePath();

      context.fillStyle = c.fillColor.toJS;
      context.fill();
      context.strokeStyle = "rgba(20, 14, 10, 0.75)".toJS;
      context.lineWidth = 0.9;
      context.stroke();
      context.restore();
    }

    context.restore();
  }
}

class BrickBuilder extends WorldDamageProjectile {
  static const String COLOR = "#aa3311";
  static const int COLOR_R = 170;
  static const int COLOR_G = 51;
  static const int COLOR_B = 17;
  static const int BRICK_WIDTH = 54;
  static const int BRICK_HEIGHT = 18;
  static const int MORTAR_WIDTH = 1;
  // Adjacent bricks share the 1px white mortar seam so interiors stay intact.
  static const int STEP_X = BRICK_WIDTH + MORTAR_WIDTH;
  static const int STEP_Y = BRICK_HEIGHT + MORTAR_WIDTH;
  static const int COLOR_TOLERANCE = 3;
  static const int SNAP_SEARCH_X = 34;
  static const int SNAP_SEARCH_Y = 18;

  BrickBuilder.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(5.0, 5.0);
    this.position.x = ownerCenter.x - size.x / 2;
    this.position.y = ownerCenter.y - size.y / 2;
    this.spriteType = SpriteType.CIRCLE;
    this.color = COLOR;
    this.velocity.x = cos(positionBase.angle);
    this.velocity.y = sin(positionBase.angle);
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = owner.velocity + this.velocity;
  }

  static bool _matchesBrickRgb(int r, int g, int b, int a) {
    return a > 200 &&
        (r - COLOR_R).abs() <= COLOR_TOLERANCE &&
        (g - COLOR_G).abs() <= COLOR_TOLERANCE &&
        (b - COLOR_B).abs() <= COLOR_TOLERANCE;
  }

  static bool _matchesMortarRgb(int r, int g, int b, int a) {
    return a > 200 && r >= 250 && g >= 250 && b >= 250;
  }

  bool _isBrickInBuffer(Uint8ClampedList data, int bufW, int bufH, int lx, int ly) {
    if (lx < 0 || ly < 0 || lx >= bufW || ly >= bufH) {
      return false;
    }
    int idx = (ly * bufW + lx) * 4;
    return _matchesBrickRgb(data[idx], data[idx + 1], data[idx + 2], data[idx + 3]);
  }

  bool _isMortarInBuffer(Uint8ClampedList data, int bufW, int bufH, int lx, int ly) {
    if (lx < 0 || ly < 0 || lx >= bufW || ly >= bufH) {
      return false;
    }
    int idx = (ly * bufW + lx) * 4;
    return _matchesMortarRgb(data[idx], data[idx + 1], data[idx + 2], data[idx + 3]);
  }

  bool _isBrickAtWorld(int wx, int wy, Uint8ClampedList data, int minX, int minY, int bufW, int bufH) {
    int lx = wx - minX;
    int ly = wy - minY;
    if (lx >= 0 && ly >= 0 && lx < bufW && ly < bufH) {
      return _isBrickInBuffer(data, bufW, bufH, lx, ly);
    }
    if (wx < 0 || wy < 0 || wx >= world.byteWorld.width || wy >= world.byteWorld.height) {
      return false;
    }
    Uint8ClampedList px = world.byteWorld.getImageDataFor(wx, wy, 1, 1);
    return _matchesBrickRgb(px[0], px[1], px[2], px[3]);
  }

  bool _isSlotOccupied(Point<int> slot, Uint8ClampedList data, int minX, int minY, int bufW, int bufH) {
    final List<Point<int>> samples = [
      Point(slot.x + BRICK_WIDTH ~/ 2, slot.y + BRICK_HEIGHT ~/ 2),
      Point(slot.x + BRICK_WIDTH ~/ 4, slot.y + BRICK_HEIGHT ~/ 4),
      Point(slot.x + (BRICK_WIDTH * 3) ~/ 4, slot.y + BRICK_HEIGHT ~/ 4),
      Point(slot.x + BRICK_WIDTH ~/ 4, slot.y + (BRICK_HEIGHT * 3) ~/ 4),
      Point(slot.x + (BRICK_WIDTH * 3) ~/ 4, slot.y + (BRICK_HEIGHT * 3) ~/ 4),
    ];
    int hits = 0;
    for (Point<int> s in samples) {
      if (_isBrickAtWorld(s.x, s.y, data, minX, minY, bufW, bufH)) {
        hits++;
        if (hits >= 2) {
          return true;
        }
      }
    }
    return false;
  }

  Point<int> _computeAlignedOrigin(Vec2 impact) {
    int impactX = impact.x.round();
    int impactY = impact.y.round();
    Point<int> defaultOrigin = Point(
      (impact.x - BRICK_WIDTH / 2).round(),
      (impact.y - BRICK_HEIGHT / 2).round(),
    );

    int bwWidth = world.byteWorld.width;
    int bwHeight = world.byteWorld.height;
    int padX = SNAP_SEARCH_X + BRICK_WIDTH + 2;
    int padY = SNAP_SEARCH_Y + BRICK_HEIGHT + 2;
    int minX = max(0, impactX - padX);
    int minY = max(0, impactY - padY);
    int maxX = min(bwWidth, impactX + padX);
    int maxY = min(bwHeight, impactY + padY);
    int bufW = maxX - minX;
    int bufH = maxY - minY;
    if (bufW <= 0 || bufH <= 0) {
      return defaultOrigin;
    }

    Uint8ClampedList data = world.byteWorld.getImageDataFor(minX, minY, bufW, bufH);

    // Find the closest brick-colored pixel to the impact point within snap range.
    int searchMinX = max(minX, impactX - SNAP_SEARCH_X);
    int searchMaxX = min(maxX - 1, impactX + SNAP_SEARCH_X);
    int searchMinY = max(minY, impactY - SNAP_SEARCH_Y);
    int searchMaxY = min(maxY - 1, impactY + SNAP_SEARCH_Y);

    int? seedX;
    int? seedY;
    int bestDistSq = 1 << 30;
    for (int wy = searchMinY; wy <= searchMaxY; wy++) {
      int ly = wy - minY;
      int dy = wy - impactY;
      int dySq = dy * dy;
      for (int wx = searchMinX; wx <= searchMaxX; wx++) {
        int dx = wx - impactX;
        int distSq = dx * dx + dySq;
        if (distSq >= bestDistSq) {
          continue;
        }
        if (_isBrickInBuffer(data, bufW, bufH, wx - minX, ly)) {
          bestDistSq = distSq;
          seedX = wx;
          seedY = wy;
          if (bestDistSq == 0) {
            break;
          }
        }
      }
      if (bestDistSq == 0) {
        break;
      }
    }

    if (seedX == null || seedY == null) {
      return defaultOrigin;
    }

    // Trace the detected brick's horizontal and vertical brick-colored spans.
    int lx = seedX - minX;
    int ly = seedY - minY;
    int leftX = seedX;
    while (leftX - seedX > -BRICK_WIDTH &&
        _isBrickInBuffer(data, bufW, bufH, leftX - 1 - minX, ly)) {
      leftX--;
    }
    int rightX = seedX;
    while (rightX - leftX + 1 < BRICK_WIDTH &&
        _isBrickInBuffer(data, bufW, bufH, rightX + 1 - minX, ly)) {
      rightX++;
    }
    int topY = seedY;
    while (topY - seedY > -BRICK_HEIGHT &&
        _isBrickInBuffer(data, bufW, bufH, lx, topY - 1 - minY)) {
      topY--;
    }
    int bottomY = seedY;
    while (bottomY - topY + 1 < BRICK_HEIGHT &&
        _isBrickInBuffer(data, bufW, bufH, lx, bottomY + 1 - minY)) {
      bottomY++;
    }

    // Recover the reference brick's top-left origin (even if one edge was cratered).
    int refX;
    if (rightX - leftX + 1 == BRICK_WIDTH ||
        _isMortarInBuffer(data, bufW, bufH, leftX - 1 - minX, ly)) {
      refX = leftX;
    } else if (_isMortarInBuffer(data, bufW, bufH, rightX + 1 - minX, ly)) {
      refX = rightX - BRICK_WIDTH + 1;
    } else {
      refX = leftX;
    }

    int refY;
    if (bottomY - topY + 1 == BRICK_HEIGHT ||
        _isMortarInBuffer(data, bufW, bufH, lx, topY - 1 - minY)) {
      refY = topY;
    } else if (_isMortarInBuffer(data, bufW, bufH, lx, bottomY + 1 - minY)) {
      refY = bottomY - BRICK_HEIGHT + 1;
    } else {
      refY = topY;
    }

    Point<int> above = Point(refX, refY - STEP_Y);
    Point<int> below = Point(refX, refY + STEP_Y);
    Point<int> left = Point(refX - STEP_X, refY);
    Point<int> right = Point(refX + STEP_X, refY);

    // Determine which face of the reference brick was hit.
    Point<int> primary;
    bool insideRef = impact.x >= refX &&
        impact.x < refX + BRICK_WIDTH &&
        impact.y >= refY &&
        impact.y < refY + BRICK_HEIGHT;
    if (insideRef && (velocity.x != 0.0 || velocity.y != 0.0)) {
      // Trace backwards along -velocity to find the exact entry face.
      double tX = double.infinity;
      Point<int> xSlot = left;
      if (velocity.x > 0) {
        tX = (impact.x - refX) / velocity.x;
        xSlot = left;
      } else if (velocity.x < 0) {
        tX = (refX + BRICK_WIDTH - impact.x) / (-velocity.x);
        xSlot = right;
      }
      double tY = double.infinity;
      Point<int> ySlot = above;
      if (velocity.y > 0) {
        tY = (impact.y - refY) / velocity.y;
        ySlot = above;
      } else if (velocity.y < 0) {
        tY = (refY + BRICK_HEIGHT - impact.y) / (-velocity.y);
        ySlot = below;
      }
      primary = tX < tY ? xSlot : ySlot;
    } else {
      double dx = impact.x - (refX + BRICK_WIDTH / 2.0);
      double dy = impact.y - (refY + BRICK_HEIGHT / 2.0);
      double normX = dx.abs() / (BRICK_WIDTH / 2.0);
      double normY = dy.abs() / (BRICK_HEIGHT / 2.0);
      if (normX > normY) {
        primary = dx < 0 ? left : right;
      } else {
        primary = dy <= 0 ? above : below;
      }
    }

    List<Point<int>> candidates = [above, below, left, right];
    candidates.remove(primary);
    candidates.sort((a, b) {
      double adx = (a.x + BRICK_WIDTH / 2.0) - impact.x;
      double ady = (a.y + BRICK_HEIGHT / 2.0) - impact.y;
      double bdx = (b.x + BRICK_WIDTH / 2.0) - impact.x;
      double bdy = (b.y + BRICK_HEIGHT / 2.0) - impact.y;
      return (adx * adx + ady * ady).compareTo(bdx * bdx + bdy * bdy);
    });
    candidates.insert(0, primary);

    for (Point<int> slot in candidates) {
      if (!_isSlotOccupied(slot, data, minX, minY, bufW, bufH)) {
        return slot;
      }
    }
    return primary;
  }

  explode() {
    Vec2 brickSize = new Vec2(BRICK_WIDTH.toDouble(), BRICK_HEIGHT.toDouble());
    Point<int> origin = _computeAlignedOrigin(centerPoint());
    Vec2 brickPosition = new Vec2(origin.x.toDouble(), origin.y.toDouble());
    Vec2 outerPosition = new Vec2(
        (origin.x - MORTAR_WIDTH).toDouble(),
        (origin.y - MORTAR_WIDTH).toDouble());

    world.fillRectAt(
        outerPosition,
        new Vec2(
            (BRICK_WIDTH + MORTAR_WIDTH * 2).toDouble(),
            (BRICK_HEIGHT + MORTAR_WIDTH * 2).toDouble()),
        "#ffffff");
    world.fillRectAt(brickPosition, brickSize, COLOR);
    this.remove = true;
  }
}

class _JellybeanFlavor {
  final String base;
  final String light;
  final String dark;
  final String rim;
  final String trailRgb;
  final String? speckle;

  const _JellybeanFlavor(
      this.base, this.light, this.dark, this.rim, this.trailRgb,
      [this.speckle]);
}

/**
 * Glossy, tumbling, bouncing candy jellybean fired by the Jellybean Jet.
 * Draws a curved kidney-bean silhouette with 3D candy shading, sugar glaze
 * highlight, elastic bounce squash-and-stretch, and a colorful jet streak.
 */
class JellybeanProjectile extends WorldDamageProjectile {
  static const int MAX_TRAIL = 6;
  static const List<_JellybeanFlavor> FLAVORS = [
    // Cherry Red
    _JellybeanFlavor("#ff2846", "#ff99ac", "#b00b24", "#660413", "255, 55, 85"),
    // Tangerine Orange
    _JellybeanFlavor("#ff8414", "#ffd185", "#ba4a00", "#6e2900", "255, 145, 35"),
    // Buttered Lemon Yellow (speckled)
    _JellybeanFlavor("#ffe124", "#fff8b0", "#c79a00", "#785c00", "255, 228, 55", "#d48800"),
    // Juicy Lime Green (speckled)
    _JellybeanFlavor("#38db3d", "#b0ffa8", "#158520", "#094f11", "65, 225, 70", "#13701a"),
    // Blueberry Blue
    _JellybeanFlavor("#268bff", "#a3d6ff", "#0d4cb0", "#062b69", "50, 150, 255"),
    // Grape Purple
    _JellybeanFlavor("#9b3dff", "#ddb5ff", "#5a14a6", "#350866", "165, 80, 255"),
    // Bubblegum Pink (speckled)
    _JellybeanFlavor("#ff4db5", "#ffb8e2", "#b51674", "#6b0943", "255, 95, 190", "#bd1578"),
    // Mint Berry Teal
    _JellybeanFlavor("#1fd9b8", "#a8fff0", "#0c806c", "#054a3e", "45, 220, 190"),
  ];

  int flavorIndex = 0;
  double _bounceSquash = 0.0;
  double _prevVelX = 0.0;
  double _prevVelY = 0.0;
  bool _hasPrevVel = false;
  bool _popSpawned = false;
  final List<Vec2> _trail = [];

  JellybeanProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.showCounter = false;
    this.mod = Mod.TV;
    this.color = FLAVORS[0].base;
  }

  JellybeanProjectile.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super.createWithOwner(world, owner, damage,
            positionBase: positionBase, size: Vec2(8.0, 6.0)) {
    Random rng = WorldDamageProjectile.random;
    this.flavorIndex = rng.nextInt(FLAVORS.length);
    this.color = FLAVORS[flavorIndex].base;
    this.mod = Mod.TV;
    this.spriteType = SpriteType.CUSTOM;
    this.explodeAfter = 15.0;
    this.health = 5;
    this.spawn_sound = Sound.BLUBB;
    this.gravityAffect = 0.1;
    this.bounche = 0.99;
    this.radius = -1.0;
    this.showCounter = false;

    // Pressurized jet stream with centered cone spread and lively speed variance.
    double speedScale = 0.78 + rng.nextDouble() * 0.18;
    this.velocity = this.velocity.multiply(speedScale);
    double sum = this.velocity.sum();
    this.velocity.x += (rng.nextDouble() - 0.5) * sum / 5.5;
    this.velocity.y += (rng.nextDouble() - 0.5) * sum / 5.5;

    // Lively candy tumble spin.
    double spinSign = rng.nextBool() ? 1.0 : -1.0;
    this.rotationVelocity = spinSign * (7.0 + rng.nextDouble() * 8.0);
  }

  @override
  handleWorldCollide(ByteWorld world, int direction) {
    super.handleWorldCollide(world, direction);
    _bounceSquash = 1.0;
    Random rng = WorldDamageProjectile.random;
    double spinSign = rotationVelocity >= 0 ? -1.0 : 1.0;
    rotationVelocity = spinSign * (6.0 + rng.nextDouble() * 10.0);
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    super.frame(duration, frameStep, gravity);

    // Detect sharp velocity reversals so remote clients also play bounce squash.
    if (_hasPrevVel &&
        ((_prevVelX * velocity.x < -100.0) || (_prevVelY * velocity.y < -100.0))) {
      _bounceSquash = 1.0;
    }
    _prevVelX = velocity.x;
    _prevVelY = velocity.y;
    _hasPrevVel = true;

    if (_bounceSquash > 0.0) {
      _bounceSquash = max(0.0, _bounceSquash - duration * 7.5);
    }

    Vec2 center = centerPoint();
    if (_trail.isNotEmpty) {
      Vec2 last = _trail.last;
      double dx = center.x - last.x;
      double dy = center.y - last.y;
      double distSq = dx * dx + dy * dy;
      if (distSq > 14400.0) {
        _trail.clear();
        _trail.add(center);
      } else if (distSq > 4.0) {
        _trail.add(center);
        if (_trail.length > MAX_TRAIL) {
          _trail.removeAt(0);
        }
      } else if (_trail.length > 1) {
        _trail.removeAt(0);
      }
    } else {
      _trail.add(center);
    }
  }

  void _traceBeanPath(CanvasRenderingContext2D context, double rx, double ry) {
    context.beginPath();
    context.moveTo(0, -ry);
    context.bezierCurveTo(rx * 0.62, -ry, rx, -ry * 0.65, rx, 0);
    context.bezierCurveTo(rx, ry * 0.62, rx * 0.84, ry * 0.96, rx * 0.48, ry * 0.92);
    context.bezierCurveTo(rx * 0.22, ry * 0.88, rx * 0.16, ry * 0.44, 0, ry * 0.44);
    context.bezierCurveTo(-rx * 0.16, ry * 0.44, -rx * 0.22, ry * 0.88, -rx * 0.48, ry * 0.92);
    context.bezierCurveTo(-rx * 0.84, ry * 0.96, -rx, ry * 0.62, -rx, 0);
    context.bezierCurveTo(-rx, -ry * 0.65, -rx * 0.62, -ry, 0, -ry);
    context.closePath();
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    _JellybeanFlavor flavor = FLAVORS[flavorIndex % FLAVORS.length];
    Vec2 center = centerPoint();

    double fadeAlpha = 1.0;
    if (explodeAfter != null && explodeAfter! < 0.35) {
      fadeAlpha = (explodeAfter! / 0.35).clamp(0.0, 1.0);
    }

    context.save();
    context.globalAlpha = fadeAlpha;

    // 1. Vibrant candy-jet motion streak behind moving jellybeans.
    double speedSq = velocity.x * velocity.x + velocity.y * velocity.y;
    if (_trail.length >= 2 && speedSq > 1600.0) {
      context.lineCap = "round";
      context.lineJoin = "round";
      for (int i = 1; i < _trail.length; i++) {
        double frac = i / _trail.length;
        Vec2 p0 = _trail[i - 1];
        Vec2 p1 = _trail[i];
        context.strokeStyle =
            "rgba(${flavor.trailRgb}, ${(frac * 0.48 * fadeAlpha).toStringAsFixed(2)})".toJS;
        context.lineWidth = 1.5 + 4.8 * frac;
        context.beginPath();
        context.moveTo(p0.x, p0.y);
        context.lineTo(p1.x, p1.y);
        context.stroke();
      }
      // Subtle glossy white speed-core inside the jet streak at high speed.
      if (speedSq > 25000.0) {
        Vec2 tail = _trail[_trail.length - 2];
        context.strokeStyle =
            "rgba(255, 255, 255, ${(0.35 * fadeAlpha).toStringAsFixed(2)})".toJS;
        context.lineWidth = 1.8;
        context.beginPath();
        context.moveTo(tail.x, tail.y);
        context.lineTo(center.x, center.y);
        context.stroke();
      }
    }

    // 2. Plump curved 3D jellybean body with bounce squash-and-stretch.
    context.translate(center.x, center.y);
    context.rotate(angle);
    if (_bounceSquash > 0.01) {
      double wave = sin(_bounceSquash * pi);
      context.scale(1.0 + 0.24 * wave, 1.0 - 0.20 * wave);
    }

    double rx = max(6.8, size.x * 0.85);
    double ry = max(4.3, size.y * 0.72);

    _traceBeanPath(context, rx, ry);

    // Translucent glossy candy gradient.
    CanvasGradient bodyGrad = context.createRadialGradient(
        -rx * 0.25, -ry * 0.38, ry * 0.12, 0, ry * 0.08, rx * 1.15);
    bodyGrad.addColorStop(0.0, flavor.light);
    bodyGrad.addColorStop(0.42, flavor.base);
    bodyGrad.addColorStop(1.0, flavor.dark);
    context.fillStyle = bodyGrad;
    context.fill();

    // Gourmet candy speckles on speckled flavors (clipped inside the bean).
    if (flavor.speckle != null) {
      context.save();
      context.clip();
      context.fillStyle = flavor.speckle!.toJS;
      context.globalAlpha = fadeAlpha * 0.65;
      for (List<double> dot in [
        [-rx * 0.36, ry * 0.25, 1.1],
        [rx * 0.18, -ry * 0.05, 0.95],
        [rx * 0.48, ry * 0.32, 1.05],
        [-rx * 0.05, ry * 0.16, 0.85],
      ]) {
        context.beginPath();
        context.arc(dot[0], dot[1], dot[2], 0, pi * 2.0);
        context.fill();
      }
      context.restore();
    }

    // Soft translucent underside bounce-light.
    context.strokeStyle =
        "rgba(255, 255, 255, ${(0.22 * fadeAlpha).toStringAsFixed(2)})".toJS;
    context.lineWidth = 1.0;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(-rx * 0.58, ry * 0.58);
    context.quadraticCurveTo(-rx * 0.35, ry * 0.72, -rx * 0.18, ry * 0.55);
    context.moveTo(rx * 0.18, ry * 0.55);
    context.quadraticCurveTo(rx * 0.35, ry * 0.72, rx * 0.58, ry * 0.58);
    context.stroke();

    // Crisp cartoon candy rim outline.
    _traceBeanPath(context, rx, ry);
    context.strokeStyle = flavor.rim.toJS;
    context.lineWidth = 1.15;
    context.stroke();

    // Signature glossy white sugar-glaze highlight along the upper arch.
    context.strokeStyle =
        "rgba(255, 255, 255, ${(0.85 * fadeAlpha).toStringAsFixed(2)})".toJS;
    context.lineWidth = 1.75;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(-rx * 0.44, -ry * 0.36);
    context.quadraticCurveTo(0, -ry * 0.72, rx * 0.42, -ry * 0.36);
    context.stroke();

    // Bright pinpoint specular sparkle on the left shoulder.
    context.fillStyle =
        "rgba(255, 255, 255, ${(0.95 * fadeAlpha).toStringAsFixed(2)})".toJS;
    context.beginPath();
    context.arc(-rx * 0.56, -ry * 0.16, 1.15, 0, pi * 2.0);
    context.fill();

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  void onRemove() {
    if (_popSpawned) return;
    _popSpawned = true;
    world.addSprite(JellybeanPopEffect(
      centerPoint(),
      velocity,
      FLAVORS[flavorIndex % FLAVORS.length],
    ));
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.JELLYBEAN;
  }

  @override
  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = super.addExtraNetworkData();
    data.extraInt.add(flavorIndex);
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraInt.length > 3) {
      flavorIndex = data.extraInt[3].abs() % FLAVORS.length;
      color = FLAVORS[flavorIndex].base;
    }
  }
}

class _CandyShard {
  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double spin;
  double w;
  double h;
  double life;
  double maxLife;
  String fill;

  _CandyShard(this.x, this.y, this.vx, this.vy, this.angle, this.spin, this.w,
      this.h, this.maxLife, this.fill)
      : life = maxLife;
}

/**
 * Local visual candy-pop burst spawned whenever a JellybeanProjectile is hit,
 * destroyed, or expires (triggered on all peers via Sprite.onRemove()).
 */
class JellybeanPopEffect extends MovingSprite {
  static const double DURATION = 0.42;
  final _JellybeanFlavor flavor;
  double _age = 0.0;
  final List<_CandyShard> _shards = [];
  final List<_ExplosionSpark> _sparkles = [];

  JellybeanPopEffect(Vec2 center, Vec2 baseVelocity, this.flavor)
      : super(Vec2.copy(center), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.networkType = NetworkType.LOCAL_ONLY;
    this.collision = false;
    this.invisibleOutsideCanvas = false;

    Random rng = WorldDamageProjectile.random;
    final List<String> shardColors = [flavor.base, flavor.light, flavor.dark];
    for (int i = 0; i < 10; i++) {
      double a = (2.0 * pi * i / 10.0) + (rng.nextDouble() - 0.5) * 0.5;
      double speed = 70.0 + rng.nextDouble() * 145.0;
      _shards.add(_CandyShard(
        center.x,
        center.y,
        cos(a) * speed + baseVelocity.x * 0.2,
        sin(a) * speed - 35.0 + baseVelocity.y * 0.2,
        rng.nextDouble() * 2.0 * pi,
        (rng.nextBool() ? 1.0 : -1.0) * (6.0 + rng.nextDouble() * 10.0),
        3.2 + rng.nextDouble() * 3.0,
        2.0 + rng.nextDouble() * 2.0,
        DURATION * (0.65 + 0.35 * rng.nextDouble()),
        shardColors[i % shardColors.length],
      ));
    }
    for (int i = 0; i < 4; i++) {
      double a = (2.0 * pi * i / 4.0) + rng.nextDouble() * 0.8;
      double speed = 55.0 + rng.nextDouble() * 85.0;
      _sparkles.add(_ExplosionSpark(
        center.x,
        center.y,
        cos(a) * speed,
        sin(a) * speed - 20.0,
        DURATION * (0.55 + 0.4 * rng.nextDouble()),
      ));
    }
  }

  @override
  frame(double dt, int frameStep, [Vec2? gravity]) {
    _age += dt;
    double drag = max(0.0, 1.0 - dt * 2.4);
    double gravY = gravity != null ? gravity.y * 0.8 : 240.0;
    for (_CandyShard s in _shards) {
      if (s.life <= 0) continue;
      s.life -= dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vx *= drag;
      s.vy = s.vy * drag + gravY * dt;
      s.angle += s.spin * dt;
    }
    for (_ExplosionSpark sp in _sparkles) {
      if (sp.life <= 0) continue;
      sp.life -= dt;
      sp.x += sp.vx * dt;
      sp.y += sp.vy * dt;
      sp.vx *= drag;
      sp.vy *= drag;
    }
    if (_age >= DURATION) {
      this.remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    if (_age >= DURATION) return;
    Vec2 center = centerPoint();

    context.save();

    // 1. Snappy candy-colored pop ring & bright center flash.
    if (_age < 0.22) {
      double rt = (_age / 0.22).clamp(0.0, 1.0);
      double ease = 1.0 - pow(1.0 - rt, 3).toDouble();
      double alpha = 1.0 - rt;

      context.strokeStyle =
          "rgba(${flavor.trailRgb}, ${(alpha * 0.9).toStringAsFixed(2)})".toJS;
      context.lineWidth = 2.6 * alpha + 0.7;
      context.beginPath();
      context.arc(center.x, center.y, 4.0 + 18.0 * ease, 0, pi * 2.0);
      context.stroke();

      if (_age < 0.11) {
        double ft = 1.0 - (_age / 0.11);
        context.fillStyle =
            "rgba(255, 255, 255, ${(ft * 0.9).toStringAsFixed(2)})".toJS;
        context.beginPath();
        context.arc(center.x, center.y, 4.5 + 4.5 * (1.0 - ft), 0, pi * 2.0);
        context.fill();
      }
    }

    // 2. Tumbling glossy candy shell shards with crisp outlines.
    for (_CandyShard s in _shards) {
      if (s.life <= 0) continue;
      double alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      context.save();
      context.translate(s.x, s.y);
      context.rotate(s.angle);
      context.globalAlpha = alpha;
      context.fillStyle = s.fill.toJS;
      context.strokeStyle = flavor.rim.toJS;
      context.lineWidth = 0.9;
      context.beginPath();
      context.ellipse(0, 0, s.w * 0.55, s.h * 0.55, 0, 0, pi * 2.0);
      context.fill();
      context.stroke();
      // Tiny sugar glint.
      context.fillStyle = "rgba(255, 255, 255, 0.8)".toJS;
      context.beginPath();
      context.arc(-s.w * 0.18, -s.h * 0.18, 0.75, 0, pi * 2.0);
      context.fill();
      context.restore();
    }

    // 3. Crisp 4-point sugar-glaze sparkles.
    for (_ExplosionSpark sp in _sparkles) {
      if (sp.life <= 0) continue;
      double alpha = (sp.life / sp.maxLife).clamp(0.0, 1.0);
      double r = 3.5 * alpha + 1.0;
      context.save();
      context.translate(sp.x, sp.y);
      context.globalAlpha = alpha;
      context.fillStyle = "#ffffff".toJS;
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

    context.restore();
  }
}

/**
 * Dart gun projectile that noses along its flight arc and plays a crisp
 * stick-twang + metallic spark impact effect on removal across all peers.
 */
class DartProjectile extends WorldDamageProjectile {
  bool _impactSpawned = false;

  DartProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.mod = Mod.DARTGUN;
  }

  DartProjectile.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super.createWithOwner(world, owner, damage,
            positionBase: positionBase, size: new Vec2(20.0, 6.0)) {
    Random rng = WorldDamageProjectile.random;
    this.mod = Mod.DARTGUN;
    double sum = this.velocity.sum();
    this.velocity.x = this.velocity.x + rng.nextDouble() * sum / 8;
    this.velocity.y = this.velocity.y + rng.nextDouble() * sum / 8;
    this.gravityAffect = 0.3;
    this.setImage(world.imageIndex().getImageIdByName("dart.png"), 1);
    this.radius = 2.0;
    this.spawn_sound = Sound.DARTGUN;
    if (velocity.x != 0.0 || velocity.y != 0.0) {
      this.angle = atan2(velocity.y, velocity.x);
    }
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    super.frame(duration, frameStep, gravity);
    if (velocity.x * velocity.x + velocity.y * velocity.y > 25.0) {
      this.angle = atan2(velocity.y, velocity.x);
    }
  }

  @override
  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (networkType == NetworkType.REMOTE || remove) {
      return;
    }
    if (other is WorldDamageProjectile && !other.remove) {
      // Never intercept our own rapidly-fired darts coming out of the barrel.
      if (other is DartProjectile &&
          owner != null &&
          other.owner != null &&
          other.owner!.networkId == owner!.networkId) {
        return;
      }
      if (other is DartProjectile || other is BrickBuilder) {
        other.remove = true;
      } else {
        if (other.owner != null) {
          other.explode();
        }
        other.remove = true;
      }
      this.remove = true;
      return;
    }
    super.collide(other, world, direction);
  }

  @override
  void onRemove() {
    if (_impactSpawned) return;
    _impactSpawned = true;
    world.addSprite(DartImpactEffect(
      world,
      centerPoint(),
      angle,
      velocity,
      size,
      imageId,
    ));
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.DART;
  }
}

/**
 * Local visual impact effect spawned when a DartProjectile hits and is removed:
 * brief stuck-dart twang wobble + metallic tip sparks + dust puff + flight flecks.
 */
class DartImpactEffect extends MovingSprite {
  static const double DURATION = 0.44;
  final WormWorld world;
  final double impactAngle;
  final Vec2 dartSize;
  final int dartImageId;
  double _age = 0.0;
  final List<_ExplosionSpark> _sparks = [];
  final List<_CandyShard> _flecks = [];
  final List<_ExplosionPuff> _dust = [];

  DartImpactEffect(this.world, Vec2 center, this.impactAngle, Vec2 impactVel,
      this.dartSize, this.dartImageId)
      : super(Vec2.copy(center), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.networkType = NetworkType.LOCAL_ONLY;
    this.collision = false;
    this.invisibleOutsideCanvas = false;

    Random rng = WorldDamageProjectile.random;
    // Tip of the dart sits half a dart-length forward along impactAngle.
    double tipX = center.x + cos(impactAngle) * (dartSize.x * 0.45);
    double tipY = center.y + sin(impactAngle) * (dartSize.x * 0.45);
    double backAngle = impactAngle + pi;

    // 6 crisp metallic ricochet sparks spraying back from the steel tip.
    for (int i = 0; i < 6; i++) {
      double a = backAngle + (rng.nextDouble() - 0.5) * 1.65;
      double speed = 85.0 + rng.nextDouble() * 140.0;
      _sparks.add(_ExplosionSpark(
        tipX,
        tipY,
        cos(a) * speed,
        sin(a) * speed - 20.0,
        0.16 + rng.nextDouble() * 0.14,
      ));
    }

    // 3 tiny impact dust puffs at the tip.
    for (int i = 0; i < 3; i++) {
      double a = backAngle + (rng.nextDouble() - 0.5) * 1.4;
      double speed = 22.0 + rng.nextDouble() * 32.0;
      _dust.add(_ExplosionPuff(
        tipX,
        tipY,
        cos(a) * speed,
        sin(a) * speed - 10.0,
        4.5 + rng.nextDouble() * 3.5,
        0.0,
        false,
      ));
    }

    // 3 tiny red/yellow dart-flight flecks kicking off near the tail.
    double tailX = center.x - cos(impactAngle) * (dartSize.x * 0.3);
    double tailY = center.y - sin(impactAngle) * (dartSize.x * 0.3);
    const List<String> fleckColors = ["#e62e2e", "#ffd629", "#c7ccd4"];
    for (int i = 0; i < 3; i++) {
      double a = backAngle + (rng.nextDouble() - 0.5) * 1.8;
      double speed = 45.0 + rng.nextDouble() * 75.0;
      _flecks.add(_CandyShard(
        tailX,
        tailY,
        cos(a) * speed,
        sin(a) * speed - 30.0,
        rng.nextDouble() * 2.0 * pi,
        (rng.nextBool() ? 1.0 : -1.0) * (8.0 + rng.nextDouble() * 10.0),
        3.2,
        1.8,
        0.24 + rng.nextDouble() * 0.16,
        fleckColors[i % fleckColors.length],
      ));
    }
  }

  @override
  frame(double dt, int frameStep, [Vec2? gravity]) {
    _age += dt;
    double drag = max(0.0, 1.0 - dt * 3.2);
    double gravY = gravity != null ? gravity.y * 0.75 : 220.0;
    for (_ExplosionSpark s in _sparks) {
      if (s.life <= 0) continue;
      s.life -= dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vx *= drag;
      s.vy = s.vy * drag + gravY * dt;
    }
    for (_ExplosionPuff d in _dust) {
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.vx *= drag;
      d.vy = d.vy * drag - 10.0 * dt;
    }
    for (_CandyShard f in _flecks) {
      if (f.life <= 0) continue;
      f.life -= dt;
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      f.vx *= drag;
      f.vy = f.vy * drag + gravY * dt;
      f.angle += f.spin * dt;
    }
    if (_age >= DURATION) {
      this.remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    if (_age >= DURATION) return;
    Vec2 center = centerPoint();
    double tipX = center.x + cos(impactAngle) * (dartSize.x * 0.45);
    double tipY = center.y + sin(impactAngle) * (dartSize.x * 0.45);

    context.save();

    // 1. Subtle impact dust puffs at the dart tip.
    if (_age < 0.30) {
      double dt = (_age / 0.30).clamp(0.0, 1.0);
      double alpha = (1.0 - dt) * 0.45;
      context.fillStyle = "rgba(220, 215, 205, ${alpha.toStringAsFixed(2)})".toJS;
      for (_ExplosionPuff d in _dust) {
        double r = d.maxRadius * (0.45 + 0.65 * dt);
        context.beginPath();
        context.arc(d.x, d.y, r, 0, pi * 2.0);
        context.fill();
      }
    }

    // 2. Stuck dart briefly vibrating/twanging around its steel tip before fading out!
    double dartAlpha = _age < 0.24
        ? 1.0
        : (1.0 - ((_age - 0.24) / (DURATION - 0.24))).clamp(0.0, 1.0);
    if (dartAlpha > 0.02) {
      double wobble = sin(_age * 62.0) * exp(-_age * 8.5) * 0.30;
      context.save();
      context.globalAlpha = dartAlpha;
      context.translate(tipX, tipY);
      context.rotate(impactAngle + wobble);
      bool drewImg = false;
      if (dartImageId >= 0) {
        try {
          HTMLImageElement img = world.imageIndex().getImageById(dartImageId);
          if (img.width > 0 && img.height > 0) {
            // Draw dart anchored at its right-hand tip (x = 0).
            context.drawImage(
              img,
              0,
              0,
              img.width,
              img.height,
              -dartSize.x,
              -dartSize.y / 2.0,
              dartSize.x,
              dartSize.y,
            );
            drewImg = true;
          }
        } catch (_) {}
      }
      if (!drewImg) {
        context.strokeStyle = "#d9dee6".toJS;
        context.lineWidth = 2.0;
        context.beginPath();
        context.moveTo(-dartSize.x, 0);
        context.lineTo(0, 0);
        context.stroke();
      }
      context.restore();
    }

    // 3. Tiny flight flecks kicking off.
    for (_CandyShard f in _flecks) {
      if (f.life <= 0) continue;
      double alpha = (f.life / f.maxLife).clamp(0.0, 1.0);
      context.save();
      context.translate(f.x, f.y);
      context.rotate(f.angle);
      context.globalAlpha = alpha;
      context.fillStyle = f.fill.toJS;
      context.fillRect(-f.w / 2.0, -f.h / 2.0, f.w, f.h);
      context.restore();
    }

    // 4. Metallic tip ping ring & ricochet sparks.
    context.globalCompositeOperation = "lighter";
    if (_age < 0.14) {
      double pt = (_age / 0.14).clamp(0.0, 1.0);
      double pa = 1.0 - pt;
      context.strokeStyle =
          "rgba(255, 240, 175, ${(pa * 0.9).toStringAsFixed(2)})".toJS;
      context.lineWidth = 1.8 * pa + 0.5;
      context.beginPath();
      context.arc(tipX, tipY, 2.5 + 10.0 * pt, 0, pi * 2.0);
      context.stroke();
    }

    context.lineCap = "round";
    for (_ExplosionSpark s in _sparks) {
      if (s.life <= 0) continue;
      double alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      context.strokeStyle =
          "rgba(255, ${(190 + 65 * alpha).toInt()}, 110, ${alpha.toStringAsFixed(2)})".toJS;
      context.lineWidth = 1.2 + 1.2 * alpha;
      context.beginPath();
      context.moveTo(s.x, s.y);
      context.lineTo(s.x - s.vx * 0.022, s.y - s.vy * 0.022);
      context.stroke();
    }

    context.restore();
  }
}

class WorldDamageProjectile extends MovingSprite {
  // Visible for testing.
  static Random random = new Random();

  late WormWorld world;
  int damage = 1;

  double bounche = 0.5;
  
  double radius = 15.0;

  // Counter until explode.
  double? explodeAfter = null;

  // Draw the counter?
  bool showCounter = true;

  // Create particles when exploding.
  bool particlesOnExplode = true;

  // Remove when colliding with something.
  bool removeOnCollision = true;

  // Can collide with world ?
  bool worldCollide = true;

  // If this can be take damage/be destroyed.
  int health = -1;

  Vec2? maxSpeed = null;

  Mod mod = Mod.UNKNOWN;
  
  WorldDamageProjectile(WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super.imageBasedSprite(new Vec2(x, y), imageId, imageIndex) {
    this.world = world;
  }

  bool takesDamage(Mod mod) {
    return health > 0 && mod != Mod.TV;
  }

  void takeDamage(int damage, LocalPlayerSprite inflictor, Mod mod) {
    health -= damage;
    if (health < 0) {
      remove = true;
    }
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (networkType == NetworkType.REMOTE) {
      return;
    }
    if (other != null && owner != null && other.networkId != owner!.networkId && other.takesDamage(mod)) {
      other.takeDamage(damage, owner!, mod);
      if (removeOnCollision) {
        explode();
      }
    }
    if (world != null && direction != null) {
      handleWorldCollide(world, direction);
    }
  }

  handleWorldCollide(ByteWorld world, int direction) {
    if (explodeAfter == null) {
      explode();
    } else if (worldCollide) {
      if (direction & MovingSprite.DIR_BELOW == MovingSprite.DIR_BELOW) {
        if (velocity.y > 0) {
          velocity.y = -velocity.y * bounche;
        }
        // Make the "above" check exclusive, as a hacky way of preferring objects to
        // go upwards.
      } else if(direction & MovingSprite.DIR_ABOVE == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * bounche;
        }
      }
      if(direction & MovingSprite.DIR_LEFT == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          velocity.x = -velocity.x * bounche;
        }
      }
      if(direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          velocity.x = -velocity.x * bounche;
        }
      }
    }
  }
  explode() {
    if (radius > 0.0) {
      world.explosionAtSprite(
        sprite: this, velocity: velocity.multiply(0.2),
        addParticles: particlesOnExplode,
        damage: damage, radius: radius, damageDoer: owner!, mod:mod);
    }
    if (removeOnCollision) {
      this.remove = true;
    }
  }
  
  frame(double duration, int frameStep, [Vec2? gravity]) {
    if (networkType != NetworkType.REMOTE) {
      if (explodeAfter != null) {
        explodeAfter = explodeAfter! - duration;
        if (explodeAfter! < 0) {
          explode();
        }
      }
    }
    Vec2? maxSpeed = this.maxSpeed;
    if (maxSpeed != null) {
      if (maxSpeed.x > 0 && velocity.x > maxSpeed.x) {
        this.velocity.x = maxSpeed.x;
        this.acceleration.x = 0;
      }
      if (maxSpeed.x < 0 && velocity.x < maxSpeed.x) {
        this.velocity.x = maxSpeed.x;
        this.acceleration.x = 0;
      }
      if (maxSpeed.y > 0 && velocity.y > maxSpeed.y) {
        this.velocity.y = maxSpeed.y;
        this.acceleration.y = 0;
      }
      if (maxSpeed.y < 0 && velocity.y < maxSpeed.y) {
        this.velocity.y = maxSpeed.y;
        this.acceleration.y = 0;
      }
    }
    super.frame(duration, frameStep, gravity);
  }
  
  draw(var context, bool debug) {
    context.save();
    if (explodeAfter != null && showCounter) {
      context.fillStyle = "#ffffff".toJS;
      context.fillText(
        explodeAfter!.toInt().toString(), position.x, position.y - size.y);
    }
    super.draw(context, debug);
    context.restore();
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.DAMAGE_PROJECTILE;
  }

  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = ExtraSpriteData()
     ..extraFloat.add(radius)
     ..extraInt.add(damage)
     ..extraInt.add(owner == null ? -1 : owner!.networkId!)
     ..extraInt.add(health)
     ..extraBool.add(showCounter)
     ..extraBool.add(removeOnCollision);
    if (explodeAfter != null) {
      data.extraFloat.add(explodeAfter!);
    }
    return data;
  }

  void parseExtraNetworkData(ExtraSpriteData data) {
    radius = data.extraFloat[0];
    damage = data.extraInt[0];
    showCounter = data.extraBool[0];
    removeOnCollision = data.extraBool[1];
    int ownerId = data.extraInt[1];
    health = data.extraInt[2];
    this.owner = world.spriteIndex[ownerId] as LocalPlayerSprite?;
    if (data.extraFloat.length > 1) {
      this.explodeAfter = data.extraFloat[1];
    }
  }

  WorldDamageProjectile.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, {MovingSprite? positionBase = null, Vec2? size = null})
     : super.imageBasedSprite(new Vec2(), world.imageIndex().getImageIdByName("zooka.png"), world.imageIndex()) {
    if (positionBase == null) {
      positionBase = owner;
    }
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.size = size == null? new Vec2(15.0, 7.0) : size;
    double ownerSize = owner.size.sum() / 2;
    Vec2 positionCenter = owner.centerPoint();
    this.setCenter(Vec2(positionCenter.x + cos(positionBase.angle) * ownerSize,
        positionCenter.y + sin(positionBase.angle) * ownerSize));
    this.velocity.x = cos(positionBase.angle);
    this.angle = positionBase.angle;
    this.velocity.y = sin(positionBase.angle);
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = positionBase.velocity + this.velocity;
  }
}