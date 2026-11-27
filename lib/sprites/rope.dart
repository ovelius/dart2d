import 'dart:js_interop';
import 'dart:math';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:web/web.dart';

import 'movingsprite.dart';
import 'sprite.dart';

class Rope extends MovingSprite {
  late WormWorld world;
  bool locked = false;
  bool invisibleOutsideCanvas = false;
  MovingSprite? lockedOnOther = null;

  double _age = 0.0;
  double _lockFlash = 0.0;
  double? _hookAngle;

  Rope.createEmpty(WormWorld world)
      : super.empty(world.imageIndex()) {
    this.world = world;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(5.0, 5.0);
    this.invisibleOutsideCanvas = false;
    owner = null;
  }

  Rope.createWithOwner(WormWorld world, LocalPlayerSprite owner, double angle, double velocity)
      : super(new Vec2(), new Vec2(5.0, 5.0), SpriteType.CUSTOM) {
    this.world = world;
    this.owner = owner;
    Vec2 ownerCenter = owner.centerPoint();
    this.position.x = ownerCenter.x - size.x / 2;
    this.position.y = ownerCenter.y - size.y / 2;
    this.angle = owner.angle;
    this._hookAngle = angle;
    this.velocity.x = cos(angle);
    this.velocity.y = sin(angle);
    this.invisibleOutsideCanvas = false;
    this.velocity = this.velocity.multiply(velocity);
    this.velocity = owner.velocity + this.velocity;
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (other != null) {
      if (isOwnedBySamePlayer(other) || other is Rope) {
        return;
      }
      if (networkType != NetworkType.LOCAL) {
        return;
      }
    }
    if (!locked) {
      _lockFlash = 1.0;
      if (this.velocity.sum() > 1.0) {
        _hookAngle = atan2(this.velocity.y, this.velocity.x);
      }
    }
    locked = true;
    this.velocity = new Vec2();
    if (other != null) {
      lockedOnOther = other;
    }
  }

  dragOwner(double duration) {
    Vec2 delta = position - owner!.position;
    delta = delta.multiply(duration * 5.0);
    owner!.velocity += delta;
  }

  frame(double duration, int frames, [Vec2? gravity]) {
    _age += duration;
    if (_lockFlash > 0.0) {
      _lockFlash = max(0.0, _lockFlash - duration * 3.8);
    }
    if (!locked && (velocity.x * velocity.x + velocity.y * velocity.y) > 25.0) {
      _hookAngle = atan2(velocity.y, velocity.x);
    }
    if (owner != null && !owner!.inGame()) {
      this.remove = true;
    }
    if (locked && owner != null) {
      // When locked we have no gravity.
      if (lockedOnOther != null) {
        this.setCenter(lockedOnOther!.centerPoint());
        if (lockedOnOther!.remove) {
          locked = false;
          lockedOnOther = null;
        }
      }
      dragOwner(duration);
      super.frame(duration, frames);
      if (this.velocity.sum() > 0.01) {
        locked = false;
        lockedOnOther = null;
      }
    } else {
      super.frame(duration, frames, gravity);
    }
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    if (owner == null) {
      return;
    }
    final Vec2 start = owner!.centerPoint();
    final Vec2 hookCenter = centerPoint();
    final double dx = hookCenter.x - start.x;
    final double dy = hookCenter.y - start.y;
    final double dist = sqrt(dx * dx + dy * dy);

    final double resolvedAngle = _hookAngle ??
        (dist > 1.0 ? atan2(dy, dx) : owner!.gun.angle);

    // Attach the rope neatly to the hook's rear eyelet ring.
    final double eyeletOffset = 6.0;
    final double endX = hookCenter.x - cos(resolvedAngle) * eyeletOffset;
    final double endY = hookCenter.y - sin(resolvedAngle) * eyeletOffset;

    context.save();
    _drawBraidedRope(context, start.x, start.y, endX, endY, dist);
    _drawGrapplingHook(context, hookCenter.x, hookCenter.y, resolvedAngle);
    context.restore();

    if (debug) {
      super.draw(context, debug);
    }
  }

  void _drawBraidedRope(CanvasRenderingContext2D ctx, double x0, double y0,
      double x1, double y1, double dist) {
    if (dist < 2.0) {
      return;
    }
    final double dx = x1 - x0;
    final double dy = y1 - y0;
    final double segDist = sqrt(dx * dx + dy * dy);
    if (segDist < 1.0) {
      return;
    }
    // Unit normal perpendicular to the rope for slight natural sag / launch whip.
    final double nx = -dy / segDist;
    final double ny = dx / segDist;
    final double midX = (x0 + x1) * 0.5;
    final double midY = (y0 + y1) * 0.5;

    double sag;
    if (locked) {
      // Pulls nearly taut when latched, with a subtle downward catenary drape.
      sag = min(4.5, segDist * 0.018);
    } else {
      // Dynamic whip wave while flying through the air.
      sag = sin(_age * 24.0) * min(8.0, segDist * 0.06);
    }
    final double ctrlX = midX + (locked ? 0.0 : nx * sag);
    final double ctrlY = midY + (locked ? sag : ny * sag);

    void traceRopePath() {
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.quadraticCurveTo(ctrlX, ctrlY, x1, y1);
    }

    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // 1. Dark shadow outline so the braided rope stays crisp on bright or dark worlds.
    ctx.setLineDash(<JSNumber>[].toJS);
    ctx.lineWidth = 4.8;
    ctx.strokeStyle = '#332110'.toJS;
    traceRopePath();
    ctx.stroke();

    // 2. Warm twisted hemp/manila rope core.
    ctx.lineWidth = 3.0;
    ctx.strokeStyle = '#c49658'.toJS;
    traceRopePath();
    ctx.stroke();

    // 3. Sunlit diagonal hemp fiber twist highlights.
    ctx.lineWidth = 1.6;
    ctx.strokeStyle = '#efd5a3'.toJS;
    ctx.setLineDash([4.5.toJS, 4.5.toJS].toJS);
    ctx.lineDashOffset = locked ? 0.0 : -_age * 22.0;
    traceRopePath();
    ctx.stroke();

    // 4. Deep recessed braid groove shadows offset along the strand.
    ctx.lineWidth = 1.3;
    ctx.strokeStyle = '#734d22'.toJS;
    ctx.setLineDash([3.0.toJS, 6.0.toJS].toJS);
    ctx.lineDashOffset = (locked ? 0.0 : -_age * 22.0) + 4.5;
    traceRopePath();
    ctx.stroke();

    ctx.setLineDash(<JSNumber>[].toJS);

    // 5. Little lashing knot where the rope ties onto the hook's eyelet.
    ctx.fillStyle = '#9e7037'.toJS;
    ctx.strokeStyle = '#332110'.toJS;
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.arc(x1, y1, 2.5, 0, pi * 2);
    ctx.fill();
    ctx.stroke();
  }

  void _drawGrapplingHook(CanvasRenderingContext2D ctx, double cx, double cy,
      double hookAngle) {
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(hookAngle);

    // Optional metallic clink spark right when latching onto terrain/sprite.
    if (_lockFlash > 0.02) {
      ctx.save();
      ctx.globalAlpha = _lockFlash.clamp(0.0, 1.0);
      final double r = 6.0 + (1.0 - _lockFlash) * 8.0;
      ctx.strokeStyle = '#fff5b8'.toJS;
      ctx.lineWidth = 1.8;
      for (int i = 0; i < 4; i++) {
        final double a = i * pi / 2.0 + pi / 4.0;
        ctx.beginPath();
        ctx.moveTo(6.0 + cos(a) * 2.5, sin(a) * 2.5);
        ctx.lineTo(6.0 + cos(a) * r, sin(a) * r);
        ctx.stroke();
      }
      ctx.restore();
    }

    // Rear steel eyelet ring (rope attaches at x = -6).
    ctx.lineWidth = 1.8;
    ctx.strokeStyle = '#1b222c'.toJS;
    ctx.beginPath();
    ctx.arc(-6.0, 0.0, 2.8, 0, pi * 2);
    ctx.stroke();
    ctx.lineWidth = 1.0;
    ctx.strokeStyle = '#b9c6d4'.toJS;
    ctx.beginPath();
    ctx.arc(-6.0, 0.0, 2.6, 0, pi * 2);
    ctx.stroke();

    // Swept upper and lower barbed steel grappling flukes (prongs).
    final CanvasGradient steelGrad = ctx.createLinearGradient(-4.0, -7.0, 8.0, 7.0);
    steelGrad.addColorStop(0.0, '#eef4fa');
    steelGrad.addColorStop(0.45, '#95a3b3');
    steelGrad.addColorStop(1.0, '#46515e');

    ctx.fillStyle = steelGrad;
    ctx.strokeStyle = '#192029'.toJS;
    ctx.lineWidth = 1.4;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';

    // Draw both symmetrical curved barbed prongs + central spearhead tip.
    for (final double sign in [-1.0, 1.0]) {
      ctx.beginPath();
      ctx.moveTo(4.8, sign * 1.4);
      // Outer curve sweeping back to sharp barb tip.
      ctx.quadraticCurveTo(3.4, sign * 7.8, -2.6, sign * 7.4);
      // Barbed inward notch.
      ctx.lineTo(-0.4, sign * 4.8);
      // Inner curve back to shank collar.
      ctx.quadraticCurveTo(1.8, sign * 4.4, 2.0, sign * 1.5);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }

    // Forged central steel shank & pointed grapple crown.
    ctx.beginPath();
    ctx.moveTo(-4.0, -1.6);
    ctx.lineTo(4.2, -2.1);
    ctx.lineTo(8.8, 0.0); // Spear tip
    ctx.lineTo(4.2, 2.1);
    ctx.lineTo(-4.0, 1.6);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Subtle 3D center prong ridge & specular metal highlight.
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.72)'.toJS;
    ctx.lineWidth = 0.9;
    ctx.beginPath();
    ctx.moveTo(-2.5, -0.6);
    ctx.lineTo(6.6, -0.2);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(3.6, -2.6);
    ctx.quadraticCurveTo(2.4, -6.2, -1.5, -6.4);
    ctx.stroke();

    // Small brass/iron collar rivet at the crown.
    ctx.fillStyle = '#333d4a'.toJS;
    ctx.beginPath();
    ctx.arc(2.5, 0.0, 1.1, 0, pi * 2);
    ctx.fill();

    ctx.restore();
  }

  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = ExtraSpriteData();
    data.extraInt.add(owner!.networkId!);
    if (lockedOnOther != null) {
      data.extraInt.add(lockedOnOther!.networkId!);
    } else {
      data.extraInt.add(-1);
    }
    return data;
  }

  void parseExtraNetworkData(ExtraSpriteData data) {
    this.owner = world.spriteIndex[data.extraInt[0]] as LocalPlayerSprite?;
    if (this.owner != null && networkType != NetworkType.LOCAL) {
      this.ownerId = this.owner!.info.connectionId;
    }
    this.lockedOnOther = world.spriteIndex[data.extraInt[1]] as MovingSprite?;
    final bool nowLocked =
        lockedOnOther != null || (flags & Sprite.FLAG_NO_GRAVITY) != 0;
    if (nowLocked && !this.locked) {
      _lockFlash = 1.0;
    }
    this.locked = nowLocked;
  }

  int extraSendFlags() {
    if (locked) {
      return Sprite.FLAG_NO_GRAVITY;
    }
    return 0;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.ROPE_SPRITE;
  }
}