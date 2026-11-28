import 'dart:js_interop';
import 'dart:math';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:web/web.dart';

// ============================================================================
// 1. SPIKY HEDGEHOG MINE + QUILL BURST
// ============================================================================

/// Lobbed cartoon hedgehog proximity mine that settles on terrain, arms after
/// [ARM_TIME], snoozes with a blinking beacon, and puffs up to detonate with a
/// radial burst of [HedgehogQuillProjectile] needles when an enemy approaches.
class HedgehogMine extends WorldDamageProjectile {
  static const double ARM_TIME = 1.0;
  static const double TRIGGER_FUSE = 0.55;
  static const double PROXIMITY_RADIUS = 92.0;
  static const double BLAST_RADIUS = 54.0;
  static const int QUILL_COUNT = 8;
  static const int QUILL_DAMAGE = 8;
  static const double MAX_LIFETIME_SECONDS = 36.0;

  double _age = 0.0;
  bool armed = false;
  bool triggered = false;
  double _triggerCountdown = TRIGGER_FUSE;
  double _clientTriggerElapsed = 0.0;
  bool _exploded = false;

  HedgehogMine(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(24.0, 20.0);
    this.mod = Mod.HEDGEHOG;
    this.bounche = 0.25;
    this.health = 15;
    this.radius = BLAST_RADIUS;
    this.showCounter = false;
    this.explodeAfter = MAX_LIFETIME_SECONDS;
  }

  HedgehogMine.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.mod = Mod.HEDGEHOG;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(24.0, 20.0);
    this.bounche = 0.25;
    this.health = 15;
    this.radius = BLAST_RADIUS;
    this.showCounter = false;
    this.explodeAfter = MAX_LIFETIME_SECONDS;

    final Vec2 ownerCenter = owner.centerPoint();
    final double offset = max(owner.size.sum() * 0.48, owner.getRadius() + 4.0);
    this.setCenter(Vec2(
      ownerCenter.x + cos(positionBase.angle) * offset,
      ownerCenter.y + sin(positionBase.angle) * offset,
    ));
    clearShallowGroundStep(world.byteWorld, owner, positionBase.angle);
    this.velocity = Vec2(
      cos(positionBase.angle) * 240.0 + owner.velocity.x * 0.65,
      sin(positionBase.angle) * 240.0 + owner.velocity.y * 0.5,
    );
  }

  @override
  handleWorldCollide(ByteWorld world, int direction) {
    super.handleWorldCollide(world, direction);
    if ((direction & MovingSprite.DIR_BELOW) == MovingSprite.DIR_BELOW) {
      velocity.x *= 0.52;
      if (velocity.y.abs() < 18.0) {
        velocity.y = 0.0;
      }
      // Keep bottom sitting cleanly on surface rather than sinking in.
      int guard = 0;
      while (guard++ < 6 &&
          world.isCanvasCollide(
              (position.x + 2).toInt(),
              (position.y + size.y - 1).toInt(),
              max(1, (size.x - 4).toInt()),
              1)) {
        position.y -= 1.0;
      }
    }
  }

  @override
  void takeDamage(int dmg, LocalPlayerSprite inflictor, Mod attackMod) {
    if (_age < 0.35 && inflictor.networkId == owner?.networkId) {
      return;
    }
    health -= dmg;
    if (health <= 0 && !remove) {
      if (networkType != NetworkType.REMOTE && owner != null) {
        explode();
      } else {
        remove = true;
      }
    }
  }

  void _activateTrigger() {
    if (triggered || remove) return;
    triggered = true;
    armed = true;
    _triggerCountdown = TRIGGER_FUSE;
    _clientTriggerElapsed = 0.0;
    // Startled cartoon hop off the ground as it puffs up to detonate!
    if (velocity.y > -60.0) {
      velocity.y = -115.0;
    }
    velocity.x *= 0.25;
    fullFramesOverNetwork = 5;
    world.playSoundAtSprite(this, Sound.JUMP);
  }

  double get activationProgress {
    if (!triggered) return 0.0;
    if (networkType == NetworkType.REMOTE) {
      return (_clientTriggerElapsed / TRIGGER_FUSE).clamp(0.0, 1.0);
    }
    return (1.0 - (_triggerCountdown / TRIGGER_FUSE)).clamp(0.0, 1.0);
  }

  @override
  collide(MovingSprite? other, ByteWorld? byteWorld, int? direction) {
    if (networkType == NetworkType.REMOTE || remove) {
      return;
    }
    if (other is LocalPlayerSprite &&
        owner != null &&
        other.networkId != owner!.networkId &&
        other.inGame()) {
      if (armed) {
        // Always play the ~0.5s startled puff-up warning before detonating!
        _activateTrigger();
      }
      return;
    }
    if (byteWorld != null && direction != null) {
      handleWorldCollide(byteWorld, direction);
    }
  }

  bool _enemyWithinProximity() {
    final Vec2 myCenter = centerPoint();
    for (int id in world.spriteIndex.spriteIds()) {
      final Sprite? s = world.spriteIndex[id];
      if (s is LocalPlayerSprite &&
          s.inGame() &&
          s.networkId != owner?.networkId) {
        final double dist = (s.centerPoint() - myCenter).sum();
        if (dist <= PROXIMITY_RADIUS + s.getRadius() * 0.35) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    if (triggered) {
      _clientTriggerElapsed += duration;
    }
    if (networkType != NetworkType.REMOTE && !remove) {
      if (!armed && _age >= ARM_TIME) {
        armed = true;
      }
      final bool lifetimeEndingSoon =
          explodeAfter != null && explodeAfter! <= TRIGGER_FUSE;
      if (armed && !triggered && (_enemyWithinProximity() || lifetimeEndingSoon)) {
        _activateTrigger();
      } else if (triggered) {
        _triggerCountdown -= duration;
        if (_triggerCountdown <= 0.0) {
          explode();
          return;
        }
      }
    }
    super.frame(duration, frameStep, gravity);
  }

  @override
  explode() {
    if (_exploded) {
      return;
    }
    _exploded = true;
    final Vec2 center = centerPoint();
    if (owner != null) {
      world.explosionAtSprite(
        sprite: this,
        velocity: Vec2(0.0, -40.0),
        addParticles: true,
        damage: damage,
        radius: radius,
        damageDoer: owner!,
        mod: Mod.HEDGEHOG,
      );
      for (int i = 0; i < QUILL_COUNT; i++) {
        final double a = (2.0 * pi * i / QUILL_COUNT) - pi * 0.5;
        final HedgehogQuillProjectile quill =
            HedgehogQuillProjectile.createFromMine(
          world,
          owner!,
          center,
          a,
          QUILL_DAMAGE,
        );
        world.addSprite(quill);
      }
    }
    this.remove = true;
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    final bool facingLeft = velocity.x < -5.0;
    final double trigFrac = activationProgress;
    // Rapid comic jitter + progressive pufferfish-style inflation during the 0.55s activation!
    final double jitterX =
        triggered ? sin(_age * 78.0) * (1.8 + 2.8 * trigFrac) : 0.0;
    final double jitterY =
        triggered ? cos(_age * 92.0) * (1.2 + 1.8 * trigFrac) : 0.0;
    final double puffScale = triggered
        ? (1.12 + 0.38 * trigFrac + sin(_age * 55.0) * 0.06)
        : (1.0 + sin(_age * 4.5) * 0.03);

    context.save();
    context.translate(c.x + jitterX, c.y + jitterY);

    // 1. Subtle proximity ring when armed; urgent filling blast-radius countdown ring when triggered!
    if (triggered) {
      context.save();
      // Pulsing red danger zone fill showing the imminent blast radius.
      final double flash = (sin(_age * 38.0) + 1.0) * 0.5;
      context.fillStyle =
          "rgba(255, 52, 42, ${(0.10 + 0.16 * trigFrac + 0.08 * flash).toStringAsFixed(2)})".toJS;
      context.beginPath();
      context.arc(0, 0, BLAST_RADIUS, 0, pi * 2.0);
      context.fill();

      // Faint full blast ring track + bright clockwise countdown arc (0 -> 100% over 0.55s).
      context.strokeStyle = "rgba(255, 80, 68, 0.38)".toJS;
      context.lineWidth = 1.6;
      context.setLineDash([5.0.toJS, 4.0.toJS].toJS);
      context.beginPath();
      context.arc(0, 0, BLAST_RADIUS, 0, pi * 2.0);
      context.stroke();
      context.setLineDash(<JSNumber>[].toJS);

      context.strokeStyle = (trigFrac > 0.65 ? "#ffe44d" : "#ff3b3b").toJS;
      context.lineWidth = 2.8;
      context.lineCap = "round";
      context.beginPath();
      context.arc(
          0, 0, BLAST_RADIUS, -pi * 0.5, -pi * 0.5 + pi * 2.0 * trigFrac);
      context.stroke();
      context.restore();
    } else if (armed) {
      final double pulse = (sin(_age * 5.5) + 1.0) * 0.5;
      context.save();
      context.strokeStyle =
          "rgba(255, 92, 72, ${(0.14 + 0.14 * pulse).toStringAsFixed(2)})".toJS;
      context.lineWidth = 1.2;
      context.setLineDash([5.0.toJS, 5.0.toJS].toJS);
      context.beginPath();
      context.arc(0, 0, PROXIMITY_RADIUS * 0.85, 0, pi * 2.0);
      context.stroke();
      context.setLineDash(<JSNumber>[].toJS);
      context.restore();
    }

    context.save();
    if (facingLeft) {
      context.scale(-1.0, 1.0);
    }
    context.scale(puffScale, puffScale);

    // 2. Crown of sharp cartoon hedgehog quills (bristle sharply outward during activation)!
    final int spikes = triggered ? 11 : 9;
    context.lineJoin = "round";
    for (int i = 0; i < spikes; i++) {
      final double span = triggered ? pi * 1.28 : pi * 0.92;
      final double startA = triggered ? -pi * 1.18 : -pi * 1.05;
      final double a = startA + span * (i / (spikes - 1));
      final double innerR = 7.5;
      final double outerR =
          (triggered ? (15.0 + 5.5 * trigFrac) : 13.5) + (i.isEven ? 1.8 : 0.0);
      context.fillStyle = (triggered && trigFrac > 0.5 && sin(_age * 48.0) > 0.0
              ? "#d94126"
              : (i.isEven ? "#6b3d22" : "#8c5330"))
          .toJS;
      context.strokeStyle = "#1c1410".toJS;
      context.lineWidth = 1.4;
      context.beginPath();
      context.moveTo(cos(a - 0.22) * innerR - 1.5, sin(a - 0.22) * innerR + 1.0);
      context.lineTo(cos(a) * outerR - 1.5, sin(a) * outerR + 1.0);
      context.lineTo(cos(a + 0.22) * innerR - 1.5, sin(a + 0.22) * innerR + 1.0);
      context.closePath();
      context.fill();
      context.stroke();

      // Cream/white-hot quill tip highlight.
      context.fillStyle = (triggered ? "#fffbe0" : "#f7e6bd").toJS;
      context.beginPath();
      context.arc(
          cos(a) * (outerR - 2.2) - 1.5, sin(a) * (outerR - 2.2) + 1.0, 1.2, 0, pi * 2.0);
      context.fill();
    }

    // 3. Blinking LED mine beacon on back (+ comic siren rays when triggered!).
    final bool blinkOn = triggered || (armed && sin(_age * 9.0) > 0.0);
    if (triggered) {
      context.strokeStyle = "#ffe44d".toJS;
      context.lineWidth = 1.8;
      context.lineCap = "round";
      for (final double rayA in const [-2.35, -1.85, -1.25, -0.75]) {
        context.beginPath();
        context.moveTo(-1.5 + cos(rayA) * 5.5, -10.5 + sin(rayA) * 5.5);
        context.lineTo(
            -1.5 + cos(rayA) * (9.5 + 3.5 * trigFrac),
            -10.5 + sin(rayA) * (9.5 + 3.5 * trigFrac));
        context.stroke();
      }
    }
    context.fillStyle = (blinkOn ? "#ff3848" : "#6e222a").toJS;
    context.strokeStyle = "#1c1410".toJS;
    context.lineWidth = 1.3;
    context.beginPath();
    context.arc(-1.5, -10.5, triggered ? 3.6 : 3.0, 0, pi * 2.0);
    context.fill();
    context.stroke();
    if (blinkOn) {
      context.fillStyle =
          (triggered ? "rgba(255, 65, 65, 0.62)" : "rgba(255, 80, 90, 0.42)").toJS;
      context.beginPath();
      context.arc(-1.5, -10.5, triggered ? 8.5 : 6.5, 0, pi * 2.0);
      context.fill();
    }

    // 4. Chubby curled brown body + warm tan snout (flushes hot red right before pop!).
    final bool hotFlash = triggered && sin(_age * (26.0 + 34.0 * trigFrac)) > 0.0;
    context.fillStyle = (hotFlash ? "#b83b28" : "#7a472a").toJS;
    context.strokeStyle = "#1c1410".toJS;
    context.lineWidth = 1.8;
    context.beginPath();
    context.ellipse(-1.5, 1.8, 9.5, 7.6, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    context.fillStyle = (hotFlash ? "#ffbfa8" : "#ebc394").toJS;
    context.beginPath();
    context.ellipse(4.8, 2.4, 6.8, 5.8, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Cute ear, eye (sleeping closed vs startled wide open!), & berry nose.
    context.fillStyle = "#d4a06a".toJS;
    context.beginPath();
    context.arc(2.2, -3.2, 2.6, 0, pi * 2.0);
    context.fill();
    context.stroke();

    if (triggered) {
      context.fillStyle = "#ffffff".toJS;
      context.beginPath();
      context.arc(6.8, 0.5, 3.0, 0, pi * 2.0);
      context.fill();
      context.stroke();
      context.fillStyle = "#141820".toJS;
      context.beginPath();
      context.arc(7.3, 0.5, 1.1, 0, pi * 2.0);
      context.fill();
    } else {
      context.strokeStyle = "#1c1410".toJS;
      context.lineWidth = 1.5;
      context.beginPath();
      context.arc(6.8, 1.2, 2.0, 0.15, pi - 0.15);
      context.stroke();
    }

    context.fillStyle = "#ee3e5c".toJS;
    context.beginPath();
    context.arc(11.6, 2.0, 2.0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    context.restore();

    // 5. Floating "z" when snoozing vs bold comic "!!" alert when triggered!
    if (triggered) {
      final double alertPop = 1.0 + 0.22 * sin(_age * 35.0);
      context.save();
      context.translate(0.0, -21.0 - trigFrac * 4.0);
      context.scale(alertPop, alertPop);
      context.font = '900 15px "Trebuchet MS", Arial, sans-serif';
      context.textAlign = "center";
      context.strokeStyle = "#1c1410".toJS;
      context.lineWidth = 3.5;
      context.strokeText("!!", 0, 0);
      context.fillStyle = (trigFrac > 0.6 ? "#ff5252" : "#ffe44d").toJS;
      context.fillText("!!", 0, 0);
      context.restore();
    } else if (armed) {
      final double zCycle = (_age * 0.9) % 1.0;
      context.globalAlpha = sin(zCycle * pi) * 0.85;
      context.font = 'bold 10px "Trebuchet MS", Arial, sans-serif';
      context.fillStyle = "#fff4c2".toJS;
      context.fillText("z", 6.0 + zCycle * 5.0, -10.0 - zCycle * 9.0);
    }

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  int extraSendFlags() =>
      (armed && !triggered && velocity.y.abs() < 2.0)
          ? Sprite.FLAG_NO_GRAVITY
          : 0;

  @override
  ExtraSpriteData addExtraNetworkData() {
    final ExtraSpriteData data = super.addExtraNetworkData();
    data.extraBool.add(armed);
    data.extraBool.add(triggered);
    data.extraInt.add((activationProgress * 100.0).round());
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraBool.length > 2) {
      armed = data.extraBool[2];
    }
    if (data.extraBool.length > 3) {
      triggered = data.extraBool[3];
    }
    if (data.extraInt.length > 3 && triggered) {
      _clientTriggerElapsed =
          (data.extraInt[3] / 100.0).clamp(0.0, 1.0) * TRIGGER_FUSE;
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.HEDGEHOG_MINE;
  }
}

/// High-speed sharp quill needle fired in a 360-degree burst when [HedgehogMine] detonates.
class HedgehogQuillProjectile extends WorldDamageProjectile {
  HedgehogQuillProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(14.0, 5.0);
    this.mod = Mod.HEDGEHOG;
    this.gravityAffect = 0.18;
    this.radius = 10.0;
    this.particlesOnExplode = false;
    this.showCounter = false;
  }

  HedgehogQuillProjectile.createFromMine(WormWorld world,
      LocalPlayerSprite owner, Vec2 origin, double launchAngle, int damage)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("dart.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.mod = Mod.HEDGEHOG;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(14.0, 5.0);
    this.gravityAffect = 0.18;
    this.radius = 10.0;
    this.particlesOnExplode = false;
    this.showCounter = false;
    this.explodeAfter = 0.50;
    this.bounche = 0.0;
    this.angle = launchAngle;
    this.setCenter(Vec2(
      origin.x + cos(launchAngle) * 10.0,
      origin.y + sin(launchAngle) * 10.0,
    ));
    this.velocity = Vec2(cos(launchAngle) * 330.0, sin(launchAngle) * 330.0);
  }

  @override
  handleWorldCollide(ByteWorld world, int direction) {
    explode();
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    super.frame(duration, frameStep, gravity);
    if (velocity.x * velocity.x + velocity.y * velocity.y > 16.0) {
      angle = atan2(velocity.y, velocity.x);
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    context.save();
    context.translate(c.x, c.y);
    context.rotate(angle);

    context.strokeStyle = "#1c1410".toJS;
    context.lineWidth = 1.4;
    context.fillStyle = "#6e3e22".toJS;
    context.beginPath();
    context.moveTo(-7.0, 0.0);
    context.lineTo(-1.0, -2.4);
    context.lineTo(7.5, 0.0);
    context.lineTo(-1.0, 2.4);
    context.closePath();
    context.fill();
    context.stroke();

    // Ivory tip.
    context.fillStyle = "#fff1c9".toJS;
    context.beginPath();
    context.moveTo(1.5, -1.4);
    context.lineTo(7.2, 0.0);
    context.lineTo(1.5, 1.4);
    context.closePath();
    context.fill();

    context.restore();
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.HEDGEHOG_QUILL;
  }
}

// ============================================================================
// 2. TURBO MOLE DRILL (BUNKER-BUSTER / TUNNEL CARVER)
// ============================================================================

/// Hard-hatted cartoon mole torpedo that flies through open air, then burrows
/// straight through solid terrain carving a walkable tunnel before detonating
/// upon emerging on the far side of a wall (or after [MAX_DRILL_TIME] underground).
class MoleDrillProjectile extends WorldDamageProjectile {
  static const double LAUNCH_SPEED = 320.0;
  static const double AIR_GRAVITY = 0.85;
  static const double DRILL_SPEED = 150.0;
  static const double MAX_DRILL_TIME = 1.25;
  static const double CARVE_INTERVAL = 0.04;
  static const double TUNNEL_RADIUS = 25.75;
  static const int DRILL_TICK_DAMAGE = 4;
  static const double BLAST_RADIUS = 60.0;

  bool drilling = false;
  double drillAngle = 0.0;
  double _drillElapsed = 0.0;
  double _carveAccum = 0.0;
  bool _emerging = false;
  double _emergeCountdown = 0.14;
  double _age = 0.0;
  bool _exploded = false;

  MoleDrillProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(30.0, 18.0);
    this.mod = Mod.MOLE;
    this.gravityAffect = AIR_GRAVITY;
    this.health = 25;
    this.radius = BLAST_RADIUS;
    this.removeOutOfBounds = false;
    this.showCounter = false;
  }

  MoleDrillProjectile.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super.createWithOwner(world, owner, damage,
            positionBase: positionBase, size: new Vec2(30.0, 18.0)) {
    this.spriteType = SpriteType.CUSTOM;
    this.mod = Mod.MOLE;
    this.gravityAffect = AIR_GRAVITY;
    this.health = 25;
    this.radius = BLAST_RADIUS;
    this.removeOutOfBounds = false;
    this.showCounter = false;
    this.drillAngle = positionBase.angle;
    this.angle = positionBase.angle;
    this.velocity = Vec2(
      cos(positionBase.angle) * LAUNCH_SPEED + owner.velocity.x * 0.35,
      sin(positionBase.angle) * LAUNCH_SPEED + owner.velocity.y * 0.35,
    );
  }

  bool get isFacingLeft => cos(angle) < 0.0;

  Vec2 _drillVelocity() =>
      Vec2(cos(drillAngle) * DRILL_SPEED, sin(drillAngle) * DRILL_SPEED);

  bool _touchesSolidTerrain(ByteWorld byteWorld) {
    final int xStart = position.x.toInt();
    final int xWidth = size.x.toInt();
    final int yStart = position.y.toInt();
    final int yHeight = size.y.toInt();
    for (int x = 0; x < xWidth; x++) {
      if (byteWorld.isSolid(xStart + x, yStart) ||
          byteWorld.isSolid(xStart + x, yStart + yHeight - 1)) {
        return true;
      }
    }
    for (int y = 0; y < yHeight; y++) {
      if (byteWorld.isSolid(xStart, yStart + y) ||
          byteWorld.isSolid(xStart + xWidth - 1, yStart + y)) {
        return true;
      }
    }
    return false;
  }

  @override
  void takeDamage(int dmg, LocalPlayerSprite inflictor, Mod attackMod) {
    // Ignore self-inflicted tunnel-carving ticks from our own nose drill.
    if (attackMod == Mod.MOLE && inflictor.networkId == owner?.networkId) {
      return;
    }
    health -= dmg;
    if (health <= 0 && !remove) {
      if (networkType != NetworkType.REMOTE && owner != null) {
        explode();
      } else {
        remove = true;
      }
    }
  }

  void _startDrilling() {
    if (drilling) return;
    drilling = true;
    if (velocity.x * velocity.x + velocity.y * velocity.y > 4.0) {
      drillAngle = atan2(velocity.y, velocity.x);
    }
    angle = drillAngle;
    gravityAffect = 0.0;
    flags |= Sprite.FLAG_NO_GRAVITY;
    velocity = _drillVelocity();
    _carveAccum = CARVE_INTERVAL; // Carve entry hole immediately on next step.
    world.playSoundAtSprite(this, Sound.THUD);
  }

  void _carveTunnelStep() {
    if (owner == null) return;
    final Vec2 c = centerPoint();
    final Vec2 nose = Vec2(
      c.x + cos(drillAngle) * (size.x * 0.30),
      c.y + sin(drillAngle) * (size.x * 0.30),
    );
    world.explosionAt(
      location: nose,
      velocity: _drillVelocity().multiply(-0.25),
      addParticles: false,
      damage: DRILL_TICK_DAMAGE,
      radius: TUNNEL_RADIUS,
      damagerDoer: owner,
      mod: Mod.MOLE,
    );
    // Restore steady burrowing velocity after explosionAt's radial impulse.
    if (drilling) {
      velocity = _drillVelocity();
    }
  }

  @override
  collide(MovingSprite? other, ByteWorld? byteWorld, int? direction) {
    if (networkType == NetworkType.REMOTE || remove) {
      return;
    }
    if (other != null &&
        owner != null &&
        shouldDamageTarget(other) &&
        other.takesDamage(Mod.MOLE)) {
      other.takeDamage(damage, owner!, Mod.MOLE);
      explode();
      return;
    }
    if (byteWorld != null && direction != null) {
      final bool hitSideOrBottomEdge = position.x < 0 ||
          position.x + size.x > byteWorld.width ||
          position.y + size.y > byteWorld.height;
      if (hitSideOrBottomEdge) {
        explode();
        return;
      }
      final bool hitTopSkyEdge = position.y - size.y < 0;
      if (hitTopSkyEdge) {
        if (drilling) {
          explode();
          return;
        }
        if (!_touchesSolidTerrain(byteWorld)) {
          // Arcing through open sky near top of map — let gravity bring it down.
          return;
        }
      }
      if (!drilling && _touchesSolidTerrain(byteWorld)) {
        _startDrilling();
        _carveTunnelStep();
        _carveAccum = 0.0;
      }
    }
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    if (drilling) {
      gravityAffect = 0.0;
      angle = drillAngle;
      velocity = Vec2(cos(drillAngle) * DRILL_SPEED, sin(drillAngle) * DRILL_SPEED);
      if (networkType != NetworkType.REMOTE && !remove) {
        _drillElapsed += duration;
        _carveAccum += duration;

        // Check ahead of our carve radius to detect bursting out the far side of a wall!
        if (!_emerging && _drillElapsed >= 0.14 && world.byteWorld.byteWorldReady()) {
          final Vec2 c = centerPoint();
          final double probeDist = size.x * 0.30 + TUNNEL_RADIUS + 7.0;
          final int px = (c.x + cos(drillAngle) * probeDist).round();
          final int py = (c.y + sin(drillAngle) * probeDist).round();
          if (px >= 0 &&
              py >= 0 &&
              px < world.byteWorld.width &&
              py < world.byteWorld.height &&
              !world.byteWorld.isSolid(px, py)) {
            _emerging = true;
          }
        }

        if (_carveAccum >= CARVE_INTERVAL) {
          _carveAccum = 0.0;
          _carveTunnelStep();
        }

        if (_emerging) {
          _emergeCountdown -= duration;
          if (_emergeCountdown <= 0.0) {
            explode();
            return;
          }
        }
        if (_drillElapsed >= MAX_DRILL_TIME) {
          explode();
          return;
        }
      }
    } else if (velocity.x * velocity.x + velocity.y * velocity.y > 25.0) {
      angle = atan2(velocity.y, velocity.x);
    }
    super.frame(duration, frameStep, drilling ? null : gravity);
  }

  @override
  explode() {
    if (_exploded) return;
    _exploded = true;
    if (owner != null) {
      world.explosionAtSprite(
        sprite: this,
        velocity: velocity.multiply(0.25),
        addParticles: true,
        damage: damage,
        radius: radius,
        damageDoer: owner!,
        mod: Mod.MOLE,
      );
    }
    this.remove = true;
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    context.save();
    context.translate(c.x, c.y);
    context.rotate(angle);
    if (isFacingLeft) {
      context.scale(1.0, -1.0);
    }

    // 1. Flying dirt clods & spark spray when actively drilling!
    if (drilling) {
      context.fillStyle = "#8c5a32".toJS;
      for (int i = 0; i < 4; i++) {
        final double phase = (_age * 16.0 + i * 0.25) % 1.0;
        final double side = i.isEven ? -1.0 : 1.0;
        final double dx = 6.0 - phase * 22.0;
        final double dy = side * (5.0 + phase * 8.0);
        context.beginPath();
        context.arc(dx, dy, 2.4 * (1.0 - phase * 0.5), 0, pi * 2.0);
        context.fill();
      }
    }

    // 2. Headlamp light cone in front of hard-hat!
    context.save();
    final CanvasGradient beam = context.createLinearGradient(2.0, -9.0, 26.0, -9.0);
    beam.addColorStop(0.0, "rgba(255, 248, 150, 0.55)");
    beam.addColorStop(1.0, "rgba(255, 248, 150, 0.0)");
    context.fillStyle = beam;
    context.beginPath();
    context.moveTo(2.0, -8.5);
    context.lineTo(26.0, -15.0);
    context.lineTo(26.0, -2.0);
    context.closePath();
    context.fill();
    context.restore();

    // 3. Chubby velvet mole body + pink digging paw.
    context.fillStyle = "#5c4a46".toJS;
    context.strokeStyle = "#18161a".toJS;
    context.lineWidth = 1.8;
    context.beginPath();
    context.ellipse(-5.0, 1.0, 9.2, 6.8, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    context.fillStyle = "#f2b0a2".toJS;
    context.beginPath();
    context.ellipse(-2.0, 6.8, 3.6, 2.2, 0.2, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // 4. Yellow miner hard-hat + glowing headlamp + cyan visor!
    context.fillStyle = "#ffd633".toJS;
    context.beginPath();
    context.arc(-3.5, -3.5, 6.5, pi, pi * 2.0);
    context.closePath();
    context.fill();
    context.stroke();
    context.fillRect(-10.5, -4.5, 14.0, 2.2);
    context.strokeRect(-10.5, -4.5, 14.0, 2.2);

    context.fillStyle = "#fff9b3".toJS;
    context.beginPath();
    context.arc(2.5, -6.5, 2.0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    context.fillStyle = "#47e3ff".toJS;
    context.beginPath();
    context.roundRect(-2.5, -1.8, 6.0, 3.4, 1.2.toJS);
    context.fill();
    context.stroke();

    // 5. Brass collar + spinning spiral steel drill cone!
    context.fillStyle = "#e8982a".toJS;
    context.fillRect(3.2, -5.8, 2.6, 11.6);
    context.strokeRect(3.2, -5.8, 2.6, 11.6);

    final CanvasGradient steel = context.createLinearGradient(5.8, -6.0, 5.8, 6.0);
    steel.addColorStop(0.0, "#f2f7ff");
    steel.addColorStop(0.5, "#98a8bc");
    steel.addColorStop(1.0, "#515f70");
    context.fillStyle = steel;
    context.beginPath();
    context.moveTo(5.8, -5.8);
    context.lineTo(17.5, 0.0);
    context.lineTo(5.8, 5.8);
    context.closePath();
    context.fill();
    context.stroke();

    // Animated spinning spiral flutes on the drill bit!
    final double spinOffset = (_age * (drilling ? 38.0 : 18.0)) % 4.0;
    context.save();
    context.beginPath();
    context.moveTo(5.8, -5.5);
    context.lineTo(17.2, 0.0);
    context.lineTo(5.8, 5.5);
    context.closePath();
    context.clip();
    context.strokeStyle = "#1d2430".toJS;
    context.lineWidth = 1.3;
    for (double x = 5.0 + spinOffset; x < 17.0; x += 4.0) {
      context.beginPath();
      context.moveTo(x - 1.5, -6.5);
      context.lineTo(x + 1.5, 6.5);
      context.stroke();
    }
    context.restore();

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  int extraSendFlags() {
    return drilling ? Sprite.FLAG_NO_GRAVITY : 0;
  }

  @override
  ExtraSpriteData addExtraNetworkData() {
    final ExtraSpriteData data = super.addExtraNetworkData();
    data.extraBool.add(drilling);
    data.extraInt.add((drillAngle * 1000.0).round());
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraBool.length > 2) {
      drilling = data.extraBool[2];
    }
    if (data.extraInt.length > 3) {
      drillAngle = data.extraInt[3] / 1000.0;
    }
    if (drilling) {
      gravityAffect = 0.0;
      angle = drillAngle;
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.MOLE_DRILL;
  }
}

// ============================================================================
// 3. ANGRY BEEHIVE + SOFT-HOMING BEES
// ============================================================================

/// Lobbed golden beehive that bounces on terrain like [CatLitterBox] with a
/// visible countdown timer, then shatters into [BEE_COUNT] buzzing
/// [HomingBeeProjectile]s that chase nearby enemy players.
class AngryBeehive extends WorldDamageProjectile {
  static const int BEE_COUNT = 5;
  static const int BEE_DAMAGE = 11;
  static const double FUSE_SECONDS = 4.0;

  double _age = 0.0;
  double _bounceSquash = 0.0;
  double _prevVelX = 0.0;
  double _prevVelY = 0.0;
  bool _hasPrevVel = false;
  bool _exploded = false;

  AngryBeehive(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(26.0, 28.0);
    this.mod = Mod.BEEHIVE;
    this.gravityAffect = 1.0;
    this.bounche = 0.42;
    this.health = 18;
    this.radius = 34.0;
    this.explodeAfter = FUSE_SECONDS;
    this.showCounter = true;
    this.angle = 0.0;
  }

  AngryBeehive.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.mod = Mod.BEEHIVE;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(26.0, 28.0);
    this.gravityAffect = 1.0;
    this.bounche = 0.42;
    this.health = 18;
    this.radius = 34.0;
    this.explodeAfter = FUSE_SECONDS;
    this.showCounter = true;
    this.angle = 0.0;

    final Vec2 ownerCenter = owner.centerPoint();
    final double offset = max(owner.size.sum() * 0.45, owner.getRadius() + 4.0);
    this.setCenter(Vec2(
      ownerCenter.x + cos(positionBase.angle) * offset,
      ownerCenter.y + sin(positionBase.angle) * offset,
    ));
    clearShallowGroundStep(world.byteWorld, owner, positionBase.angle);
    this.velocity = Vec2(
      cos(positionBase.angle) * 200.0 + owner.velocity.x * 0.6,
      sin(positionBase.angle) * 200.0 + owner.velocity.y * 0.5,
    );
  }

  @override
  handleWorldCollide(ByteWorld world, int direction) {
    super.handleWorldCollide(world, direction);
    _bounceSquash = 1.0;
    if ((direction & MovingSprite.DIR_BELOW) == MovingSprite.DIR_BELOW) {
      velocity.x *= 0.82;
    }
  }

  @override
  void takeDamage(int dmg, LocalPlayerSprite inflictor, Mod attackMod) {
    if (_age < 0.35 && inflictor.networkId == owner?.networkId) {
      return;
    }
    health -= dmg;
    if (health <= 0 && !remove) {
      if (networkType != NetworkType.REMOTE && owner != null) {
        explode();
      } else {
        remove = true;
      }
    }
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

  @override
  explode() {
    if (_exploded) return;
    _exploded = true;
    final Vec2 center = centerPoint();
    if (owner != null) {
      world.explosionAtSprite(
        sprite: this,
        velocity: velocity.multiply(0.2),
        addParticles: true,
        damage: damage,
        radius: radius,
        damageDoer: owner!,
        mod: Mod.BEEHIVE,
      );
      world.playSoundAtPosition(center, Sound.BUZZ, multiPlay: true);
      for (int i = 0; i < BEE_COUNT; i++) {
        final double launchAngle =
            -pi * 0.85 + (pi * 0.70) * (i / (BEE_COUNT - 1));
        final HomingBeeProjectile bee = HomingBeeProjectile.createFromHive(
          world,
          owner!,
          center,
          launchAngle,
          BEE_DAMAGE,
          beeSeed: i,
        );
        world.addSprite(bee);
      }
    }
    this.remove = true;
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    final double urgency =
        explodeAfter != null ? ((1.8 - explodeAfter!) / 1.8).clamp(0.0, 1.0) : 0.0;

    context.save();

    // Crisp cartoon countdown timer above the hive (matches CatLitterBox).
    if (explodeAfter != null && showCounter) {
      context.fillStyle = (urgency > 0.5 ? "#ffec66" : "#ffffff").toJS;
      context.strokeStyle = "#2b1808".toJS;
      context.lineWidth = 3.0;
      context.font = "bold 12px Arial";
      final String txt = max(0, explodeAfter!.ceil()).toString();
      context.strokeText(txt, c.x - 4.0, position.y - 8.0);
      context.fillText(txt, c.x - 4.0, position.y - 8.0);
    }

    context.translate(c.x, c.y);

    final double wobble =
        sin(_age * (10.0 + 26.0 * urgency)) * (0.06 + 0.14 * urgency);
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

    context.strokeStyle = "#2b1808".toJS;
    context.lineWidth = 1.7;
    const List<List<double>> tiers = [
      [-6.5, -10.5, 13.0, 5.2],
      [-9.5, -6.2, 19.0, 5.8],
      [-11.0, -1.2, 22.0, 6.2],
      [-9.2, 4.0, 18.4, 5.6],
      [-6.2, 8.6, 12.4, 4.8],
    ];
    for (int i = 0; i < tiers.length; i++) {
      final List<double> t = tiers[i];
      context.fillStyle = (i.isEven ? "#ffcf38" : "#f0a818").toJS;
      context.beginPath();
      context.roundRect(t[0], t[1], t[2], t[3], (t[3] * 0.48).toJS);
      context.fill();
      context.stroke();
    }

    // Dark entrance hole.
    context.fillStyle = "#2b1608".toJS;
    context.beginPath();
    context.ellipse(0.0, 2.0, 3.2, 3.8, 0, 0, pi * 2.0);
    context.fill();

    // Two tiny angry guard bees orbiting the flying hive!
    for (int b = 0; b < 2; b++) {
      final double a = _age * 9.0 + b * pi;
      final double bx = cos(a) * 14.0;
      final double by = sin(a * 1.4) * 8.0 - 4.0;
      context.fillStyle = "#ffe44d".toJS;
      context.beginPath();
      context.arc(bx, by, 2.4, 0, pi * 2.0);
      context.fill();
      context.stroke();
    }

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.ANGRY_BEEHIVE;
  }
}

/// Buzzing cartoon bee spawned by [AngryBeehive] that gently steers toward the
/// nearest active enemy player and can be swatted by [DartProjectile] or roasted
/// by Coffee Burn (`health = 1`).
class HomingBeeProjectile extends WorldDamageProjectile {
  static const double BEE_SPEED = 215.0;
  static const double TURN_RATE = 6.2;
  static const double HOMING_RANGE = 440.0;
  static const double HOMING_DELAY = 0.20;
  static const double FUSE_SECONDS = 3.6;

  int beeSeed = 0;
  double _age = 0.0;
  bool _exploded = false;

  HomingBeeProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(14.0, 12.0);
    this.mod = Mod.BEEHIVE;
    this.gravityAffect = 0.0;
    this.bounche = 0.85;
    this.health = 1;
    this.radius = 16.0;
    this.showCounter = false;
    this.explodeAfter = FUSE_SECONDS;
  }

  HomingBeeProjectile.createFromHive(WormWorld world, LocalPlayerSprite owner,
      Vec2 origin, double launchAngle, int damage,
      {this.beeSeed = 0})
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.mod = Mod.BEEHIVE;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(14.0, 12.0);
    this.gravityAffect = 0.0;
    this.flags |= Sprite.FLAG_NO_GRAVITY;
    this.bounche = 0.85;
    this.health = 1;
    this.radius = 16.0;
    this.showCounter = false;
    this.explodeAfter = FUSE_SECONDS;
    this.angle = launchAngle;
    this.setCenter(Vec2(
      origin.x + cos(launchAngle) * 10.0,
      origin.y + sin(launchAngle) * 10.0 - 4.0,
    ));
    this.velocity = Vec2(
      cos(launchAngle) * (BEE_SPEED * 0.85),
      sin(launchAngle) * (BEE_SPEED * 0.85) - 35.0,
    );
  }

  LocalPlayerSprite? _nearestEnemy() {
    final Vec2 myCenter = centerPoint();
    LocalPlayerSprite? best;
    double bestDist = HOMING_RANGE;
    for (int id in world.spriteIndex.spriteIds()) {
      final Sprite? s = world.spriteIndex[id];
      if (s is LocalPlayerSprite &&
          s.inGame() &&
          s.networkId != owner?.networkId) {
        final double d = (s.centerPoint() - myCenter).sum();
        if (d < bestDist) {
          bestDist = d;
          best = s;
        }
      }
    }
    return best;
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    gravityAffect = 0.0;
    if (networkType != NetworkType.REMOTE && _age >= HOMING_DELAY && !remove) {
      final LocalPlayerSprite? target = _nearestEnemy();
      double curAngle = atan2(velocity.y, velocity.x);
      if (target != null) {
        final Vec2 toTarget = target.centerPoint() - centerPoint();
        final double desired = atan2(toTarget.y, toTarget.x);
        double diff = desired - curAngle;
        while (diff > pi) diff -= 2.0 * pi;
        while (diff < -pi) diff += 2.0 * pi;
        final double maxTurn = TURN_RATE * duration;
        curAngle += diff.clamp(-maxTurn, maxTurn);
      }
      // Subtle figure-8 bee buzz weave.
      final double buzzWeave =
          sin(_age * 18.0 + beeSeed * 1.7) * 1.4 * duration;
      curAngle += buzzWeave;
      velocity = Vec2(cos(curAngle) * BEE_SPEED, sin(curAngle) * BEE_SPEED);
      angle = curAngle;
    } else if (velocity.x * velocity.x + velocity.y * velocity.y > 9.0) {
      angle = atan2(velocity.y, velocity.x);
    }
    super.frame(duration, frameStep, null);
  }

  @override
  void takeDamage(int dmg, LocalPlayerSprite inflictor, Mod attackMod) {
    if (attackMod == Mod.BEEHIVE && inflictor.networkId == owner?.networkId) {
      return;
    }
    super.takeDamage(dmg, inflictor, attackMod);
  }

  @override
  collide(MovingSprite? other, ByteWorld? byteWorld, int? direction) {
    if (networkType == NetworkType.REMOTE || remove) {
      return;
    }
    if (other is HomingBeeProjectile &&
        other.owner?.networkId == owner?.networkId) {
      return;
    }
    super.collide(other, byteWorld, direction);
  }

  @override
  explode() {
    if (_exploded) return;
    _exploded = true;
    if (owner != null) {
      world.explosionAtSprite(
        sprite: this,
        velocity: velocity.multiply(0.2),
        addParticles: false,
        damage: damage,
        radius: radius,
        damageDoer: owner!,
        mod: Mod.BEEHIVE,
      );
    }
    this.remove = true;
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    final bool facingLeft = cos(angle) < 0.0;
    final double wingFlutter = sin(_age * 65.0 + beeSeed) * 2.5;

    context.save();
    context.translate(c.x, c.y);
    if (facingLeft) {
      context.scale(-1.0, 1.0);
    }

    // Fluttering translucent wings.
    context.fillStyle = "rgba(220, 248, 255, 0.85)".toJS;
    context.strokeStyle = "#1c1814".toJS;
    context.lineWidth = 1.1;
    context.beginPath();
    context.ellipse(-1.0, -5.0 + wingFlutter * 0.4, 2.8, 4.0, -0.25, 0, pi * 2.0);
    context.fill();
    context.stroke();
    context.beginPath();
    context.ellipse(1.8, -4.6 - wingFlutter * 0.4, 2.5, 3.6, 0.2, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Sharp rear stinger.
    context.fillStyle = "#1c1814".toJS;
    context.beginPath();
    context.moveTo(-5.5, 0.0);
    context.lineTo(-9.2, 0.5);
    context.lineTo(-5.5, 2.0);
    context.closePath();
    context.fill();

    // Plump yellow & black striped bumblebee body.
    context.fillStyle = "#ffe036".toJS;
    context.lineWidth = 1.5;
    context.beginPath();
    context.ellipse(0.0, 0.5, 6.2, 4.6, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    context.fillStyle = "#1c1814".toJS;
    context.fillRect(-2.8, -3.5, 2.0, 8.0);
    context.fillRect(0.6, -3.5, 1.8, 8.0);

    // Fierce tiny eye.
    context.fillStyle = "#ffffff".toJS;
    context.beginPath();
    context.arc(4.0, -0.4, 1.7, 0, pi * 2.0);
    context.fill();
    context.fillStyle = "#111111".toJS;
    context.beginPath();
    context.arc(4.5, -0.4, 0.8, 0, pi * 2.0);
    context.fill();

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  int extraSendFlags() => Sprite.FLAG_NO_GRAVITY;

  @override
  ExtraSpriteData addExtraNetworkData() {
    final ExtraSpriteData data = super.addExtraNetworkData();
    data.extraInt.add(beeSeed);
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraInt.length > 3) {
      beeSeed = data.extraInt[3];
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.HOMING_BEE;
  }
}

// ============================================================================
// 4. PIGEON AIR STRIKE (SIGNAL FLARE + BOMBER PIGEONS + BIRD DROPPINGS)
// ============================================================================

/// Glowing signal flare that lands on terrain, counts down [LANDED_FUSE] while
/// vulnerable to enemy fire, then locks in (`strikeConfirmed = true`) with an
/// unmistakable incoming-airstrike beacon animation while summoning a squadron
/// of [BomberPigeonProjectile]s across the sky.
class PigeonStrikeFlare extends WorldDamageProjectile {
  static const int PIGEON_COUNT = 5;
  static const int BOMB_DAMAGE = 48;
  static const double LANDED_FUSE = 2.30;
  static const double ACTIVE_STRIKE_DURATION = 2.50;
  static const double STRIKE_SPREAD = 58.0;
  static const double SPAWN_APPROACH_DIST = 340.0;
  static const double SPAWN_STAGGER_DIST = 70.0;

  bool landed = false;
  bool strikeConfirmed = false;
  double _landedCountdown = LANDED_FUSE;
  double _activeStrikeRemaining = ACTIVE_STRIKE_DURATION;
  double _age = 0.0;
  double _confirmedAge = 0.0;
  bool _calledStrike = false;
  bool _fizzleSpawned = false;

  PigeonStrikeFlare(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(14.0, 14.0);
    this.mod = Mod.PIGEON;
    this.gravityAffect = 0.72;
    this.bounche = 0.25;
    this.health = 10;
    this.radius = 0.0;
    this.showCounter = false;
    this.invisibleOutsideCanvas = false;
    this.explodeAfter = 9.0;
  }

  PigeonStrikeFlare.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = 5;
    this.mod = Mod.PIGEON;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(14.0, 14.0);
    this.gravityAffect = 0.72;
    this.bounche = 0.25;
    this.health = 10;
    this.radius = 0.0;
    this.showCounter = false;
    this.invisibleOutsideCanvas = false;
    this.explodeAfter = 9.0;

    final Vec2 ownerCenter = owner.centerPoint();
    final double offset = max(owner.size.sum() * 0.48, owner.getRadius() + 4.0);
    this.setCenter(Vec2(
      ownerCenter.x + cos(positionBase.angle) * offset,
      ownerCenter.y + sin(positionBase.angle) * offset,
    ));
    clearShallowGroundStep(world.byteWorld, owner, positionBase.angle);
    this.velocity = Vec2(
      cos(positionBase.angle) * 360.0 + owner.velocity.x * 0.5,
      sin(positionBase.angle) * 360.0 + owner.velocity.y * 0.35,
    );
  }

  double get armingProgress => strikeConfirmed
      ? 1.0
      : (landed ? (1.0 - _landedCountdown / LANDED_FUSE).clamp(0.0, 1.0) : 0.0);

  @override
  bool takesDamage(Mod attackMod) {
    if (strikeConfirmed) return false;
    return super.takesDamage(attackMod);
  }

  @override
  void takeDamage(int dmg, LocalPlayerSprite inflictor, Mod attackMod) {
    if (strikeConfirmed) return;
    if (_age < 0.35 && inflictor.networkId == owner?.networkId) {
      return;
    }
    health -= dmg;
    if (health <= 0 && !remove) {
      // Destroyed before lock-in — fizzle out WITHOUT summoning the airstrike!
      remove = true;
    }
  }

  @override
  void onRemove() {
    if (!strikeConfirmed && !_fizzleSpawned) {
      _fizzleSpawned = true;
      world.addSprite(FlareDestroyedFizzleEffect(centerPoint()));
    }
  }

  @override
  handleWorldCollide(ByteWorld world, int direction) {
    super.handleWorldCollide(world, direction);
    final bool hitBelow =
        (direction & MovingSprite.DIR_BELOW) == MovingSprite.DIR_BELOW;
    final bool touchesSolid = world.byteWorldReady() &&
        world.isCanvasCollide(
          position.x.toInt(),
          position.y.toInt(),
          max(1, size.x.toInt()),
          max(1, size.y.toInt()),
        );
    if (!hitBelow && !touchesSolid && position.y - size.y < 0) {
      // Brushed top open-sky boundary — let gravity arc it back down.
      return;
    }
    landed = true;
    velocity.x *= 0.35;
    if (hitBelow && velocity.y.abs() < 20.0) {
      velocity.y = 0.0;
    }
  }

  @override
  collide(MovingSprite? other, ByteWorld? byteWorld, int? direction) {
    if (networkType == NetworkType.REMOTE || remove || strikeConfirmed) {
      return;
    }
    if (other is LocalPlayerSprite &&
        owner != null &&
        other.networkId != owner!.networkId &&
        other.inGame()) {
      landed = true;
      _landedCountdown = 0.0;
      explode();
      return;
    }
    if (byteWorld != null && direction != null) {
      handleWorldCollide(byteWorld, direction);
    }
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    if (strikeConfirmed) {
      _confirmedAge += duration;
      velocity = Vec2.ZERO;
      gravityAffect = 0.0;
      _activeStrikeRemaining = max(0.0, _activeStrikeRemaining - duration);
      if (networkType != NetworkType.REMOTE &&
          !remove &&
          _activeStrikeRemaining <= 0.0) {
        remove = true;
        return;
      }
      super.frame(duration, frameStep, null);
      return;
    }
    if (networkType != NetworkType.REMOTE && landed && !remove) {
      _landedCountdown -= duration;
      if (_landedCountdown <= 0.0) {
        explode();
        return;
      }
    }
    final bool settledOnClient =
        networkType == NetworkType.REMOTE && landed && velocity.y.abs() < 4.0;
    super.frame(duration, frameStep, settledOnClient ? null : gravity);
  }

  @override
  explode() {
    if (_calledStrike) return;
    _calledStrike = true;
    strikeConfirmed = true;
    landed = true;
    collision = false;
    gravityAffect = 0.0;
    flags |= Sprite.FLAG_NO_GRAVITY;
    velocity = Vec2.ZERO;
    explodeAfter = null;
    _activeStrikeRemaining = ACTIVE_STRIKE_DURATION;
    fullFramesOverNetwork = 4;

    if (owner != null) {
      final Vec2 target = centerPoint();
      final double worldW =
          world.byteWorld.width > 0 ? world.byteWorld.width.toDouble() : 800.0;
      final double worldH =
          world.byteWorld.height > 0 ? world.byteWorld.height.toDouble() : 600.0;
      // Approach from whichever side of the map gives a longer visible flight run!
      final double dirX = target.x > worldW * 0.5 ? 1.0 : -1.0;

      const double pigeonH = 22.0;
      final double minSafeY = pigeonH + 3.0;
      final double maxSafeY = max(minSafeY, worldH - pigeonH - 4.0);
      final double desiredY = min(target.y - 160.0, worldH * 0.16);
      final double baseFlightY = desiredY.clamp(minSafeY, maxSafeY);

      world.playSoundAtPosition(target, Sound.SWOSH, multiPlay: true);

      for (int i = 0; i < PIGEON_COUNT; i++) {
        final double offsetFromCenter =
            (i - (PIGEON_COUNT - 1) * 0.5) * STRIKE_SPREAD;
        final double dropX =
            (target.x + offsetFromCenter).clamp(12.0, max(12.0, worldW - 12.0));
        final double startX =
            dropX - dirX * (SPAWN_APPROACH_DIST + i * SPAWN_STAGGER_DIST);
        final double yJitter = (i.isEven ? -4.0 : 4.0);
        final double startY =
            (baseFlightY + yJitter).clamp(minSafeY, maxSafeY);

        final BomberPigeonProjectile pigeon =
            BomberPigeonProjectile.createForStrike(
          world,
          owner!,
          Vec2(startX, startY),
          dirX: dirX,
          dropX: dropX,
          bombDamage: BOMB_DAMAGE,
        );
        world.addSprite(pigeon);
      }
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    context.save();
    context.translate(c.x, c.y);

    if (strikeConfirmed) {
      // ======================================================================
      // CONFIRMED AIRSTRIKE INCOMING ANIMATION!
      // Wide emerald-green sky spotlight, expanding radar shockwaves, scrolling
      // downward target chevrons, ground bullseye, and bobbing "INCOMING!" pill!
      // ======================================================================
      final double fadeOut = _activeStrikeRemaining < 0.45
          ? (_activeStrikeRemaining / 0.45).clamp(0.0, 1.0)
          : 1.0;
      context.globalAlpha = fadeOut;

      final double pulse = (sin(_confirmedAge * 18.0) + 1.0) * 0.5;
      final double beamHalfW = 16.0 + 4.0 * pulse;
      final CanvasGradient skyBeam =
          context.createLinearGradient(0.0, 4.0, 0.0, -210.0);
      skyBeam.addColorStop(
          0.0, "rgba(62, 255, 138, ${(0.52 + 0.22 * pulse).toStringAsFixed(2)})");
      skyBeam.addColorStop(0.55, "rgba(62, 255, 168, 0.22)");
      skyBeam.addColorStop(1.0, "rgba(62, 255, 168, 0.0)");
      context.fillStyle = skyBeam;
      context.fillRect(-beamHalfW, -210.0, beamHalfW * 2.0, 214.0);

      // Bright core beam line.
      context.fillStyle = "rgba(220, 255, 236, 0.78)".toJS;
      context.fillRect(-2.2, -195.0, 4.4, 198.0);

      // Scrolling downward target chevrons inside the beam!
      context.strokeStyle = "rgba(235, 255, 242, 0.90)".toJS;
      context.lineWidth = 2.2;
      context.lineCap = "round";
      final double chevScroll = (_confirmedAge * 115.0) % 34.0;
      for (int k = 0; k < 4; k++) {
        final double cy = -145.0 + k * 34.0 + chevScroll;
        if (cy < -155.0 || cy > -12.0) continue;
        context.beginPath();
        context.moveTo(-8.5, cy - 5.5);
        context.lineTo(0.0, cy + 1.5);
        context.lineTo(8.5, cy - 5.5);
        context.stroke();
      }

      // Expanding concentric green radar confirmation rings!
      for (int rIdx = 0; rIdx < 2; rIdx++) {
        final double ringPhase = ((_confirmedAge * 1.65) + rIdx * 0.5) % 1.0;
        final double ringR = 8.0 + ringPhase * 42.0;
        final double ringA = (1.0 - ringPhase) * 0.82;
        context.strokeStyle =
            "rgba(88, 255, 152, ${ringA.toStringAsFixed(2)})".toJS;
        context.lineWidth = 2.4 * (1.0 - ringPhase * 0.5);
        context.beginPath();
        context.ellipse(0.0, 4.0, ringR, ringR * 0.42, 0.0, 0.0, pi * 2.0);
        context.stroke();
      }

      // Bobbing cartoon "INCOMING!" confirmation badge above the beacon.
      final double badgeY = -28.0 + sin(_confirmedAge * 14.0) * 2.5;
      context.font = '900 10px "Trebuchet MS", Arial, sans-serif';
      context.textAlign = "center";
      context.strokeStyle = "#12241a".toJS;
      context.lineWidth = 3.2;
      context.strokeText("INCOMING!", 0.0, badgeY);
      context.fillStyle = "#7dffad".toJS;
      context.fillText("INCOMING!", 0.0, badgeY);
    } else if (landed) {
      // ======================================================================
      // ARMING / CALLING IN PHASE (vulnerable to being destroyed beforehand!):
      // Thin amber-red signal beam + filling circular lock-on progress ring.
      // ======================================================================
      final double prog = armingProgress;
      final double pulse = (sin(_age * 16.0) + 1.0) * 0.5;
      final CanvasGradient skyBeam =
          context.createLinearGradient(0.0, 0.0, 0.0, -95.0);
      skyBeam.addColorStop(
          0.0, "rgba(255, 92, 72, ${(0.32 + 0.22 * pulse).toStringAsFixed(2)})");
      skyBeam.addColorStop(1.0, "rgba(255, 92, 72, 0.0)");
      context.fillStyle = skyBeam;
      context.fillRect(-3.2, -95.0, 6.4, 95.0);

      // Circular arming progress ring filling clockwise around the flare!
      context.strokeStyle = "rgba(20, 24, 32, 0.72)".toJS;
      context.lineWidth = 3.6;
      context.beginPath();
      context.arc(0.0, 0.0, 12.5, 0.0, pi * 2.0);
      context.stroke();

      context.strokeStyle = "#ffcf48".toJS;
      context.lineWidth = 2.2;
      context.lineCap = "round";
      context.beginPath();
      context.arc(
          0.0, 0.0, 12.5, -pi * 0.5, -pi * 0.5 + (pi * 2.0 * prog));
      context.stroke();
    }

    // Glowing flare spark halo (amber-red while arming, bright emerald once confirmed!).
    final double flicker = 8.0 + sin(_age * 36.0) * 2.5;
    context.fillStyle = (strikeConfirmed
            ? "rgba(72, 255, 148, 0.52)"
            : "rgba(255, 90, 70, 0.45)")
        .toJS;
    context.beginPath();
    context.arc(0, -2.0, flicker, 0, pi * 2.0);
    context.fill();

    // Cartoon flare stick + sizzling tip.
    context.save();
    context.rotate((landed || strikeConfirmed) ? -0.35 : _age * 8.0);
    context.fillStyle = (strikeConfirmed ? "#2ecc71" : "#e63244").toJS;
    context.strokeStyle = "#1c1418".toJS;
    context.lineWidth = 1.5;
    context.beginPath();
    context.roundRect(-3.0, -6.0, 6.0, 12.0, 2.0.toJS);
    context.fill();
    context.stroke();

    context.fillStyle = (strikeConfirmed ? "#dcffea" : "#fff8b8").toJS;
    context.beginPath();
    context.arc(0.0, -6.0, 3.0, 0, pi * 2.0);
    context.fill();
    context.restore();

    context.restore();
  }

  @override
  int extraSendFlags() =>
      (strikeConfirmed || (landed && velocity.y.abs() < 2.0))
          ? Sprite.FLAG_NO_GRAVITY
          : 0;

  @override
  ExtraSpriteData addExtraNetworkData() {
    final ExtraSpriteData data = super.addExtraNetworkData();
    data.extraBool.add(landed);
    data.extraBool.add(strikeConfirmed);
    data.extraInt.add((armingProgress * 100.0).round());
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraBool.length > 2) {
      landed = data.extraBool[2];
    }
    if (data.extraBool.length > 3) {
      strikeConfirmed = data.extraBool[3];
    }
    if (data.extraInt.length > 3 && !strikeConfirmed) {
      final double remoteProg = (data.extraInt[3] / 100.0).clamp(0.0, 1.0);
      _landedCountdown = LANDED_FUSE * (1.0 - remoteProg);
    }
    if (strikeConfirmed) {
      collision = false;
      gravityAffect = 0.0;
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.PIGEON_FLARE;
  }
}

/// Local fizzle smoke-and-X pop spawned when an enemy destroys a
/// [PigeonStrikeFlare] BEFORE its airstrike locks in!
class FlareDestroyedFizzleEffect extends MovingSprite {
  static const double DURATION = 0.55;
  double _age = 0.0;

  FlareDestroyedFizzleEffect(Vec2 center)
      : super(Vec2.copy(center), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.networkType = NetworkType.LOCAL_ONLY;
    this.collision = false;
    this.invisibleOutsideCanvas = false;
  }

  @override
  frame(double dt, int frameStep, [Vec2? gravity]) {
    _age += dt;
    if (_age >= DURATION) {
      remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    if (_age >= DURATION) return;
    final Vec2 c = centerPoint();
    final double t = (_age / DURATION).clamp(0.0, 1.0);
    final double alpha = 1.0 - t;

    context.save();
    context.translate(c.x, c.y);
    context.globalAlpha = alpha;

    // Rising dead grey smoke puffs.
    context.fillStyle = "rgba(130, 138, 148, 0.78)".toJS;
    for (int i = 0; i < 4; i++) {
      final double a = -pi * 0.85 + (pi * 0.70) * (i / 3.0);
      final double dist = 4.0 + t * 22.0;
      final double r = (4.5 + i * 0.8) * (1.0 - t * 0.35);
      context.beginPath();
      context.arc(cos(a) * dist, sin(a) * dist - t * 10.0, r, 0, pi * 2.0);
      context.fill();
    }

    // Crisp cancelled red "X" pop!
    final double xSize = 5.5 + t * 2.5;
    context.strokeStyle = "#1a1418".toJS;
    context.lineWidth = 4.0;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(-xSize, -8.0 - xSize - t * 8.0);
    context.lineTo(xSize, -8.0 + xSize - t * 8.0);
    context.moveTo(xSize, -8.0 - xSize - t * 8.0);
    context.lineTo(-xSize, -8.0 + xSize - t * 8.0);
    context.stroke();

    context.strokeStyle = "#ff5252".toJS;
    context.lineWidth = 2.0;
    context.stroke();

    context.restore();
  }
}

/// Chubby aviator bomber pigeon that swoops horizontally across the sky, drops
/// a [PigeonDroppingBomb] at [dropX], and banks upward out of the battlefield.
class BomberPigeonProjectile extends WorldDamageProjectile {
  static const double FLIGHT_SPEED = 260.0;

  double dirX = 1.0;
  double dropX = 0.0;
  bool droppedBomb = false;
  double _age = 0.0;

  BomberPigeonProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(32.0, 22.0);
    this.mod = Mod.PIGEON;
    this.collision = false;
    this.worldCollide = false;
    this.invisibleOutsideCanvas = false;
    this.gravityAffect = 0.0;
    this.removeOnCollision = false;
    this.particlesOnExplode = false;
    this.radius = 0.0;
    this.showCounter = false;
    this.explodeAfter = 5.0;
  }

  BomberPigeonProjectile.createForStrike(
      WormWorld world, LocalPlayerSprite owner, Vec2 position,
      {required this.dirX, required this.dropX, required int bombDamage})
      : super(world, position.x, position.y,
            world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = bombDamage;
    this.mod = Mod.PIGEON;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(32.0, 22.0);
    this.collision = false;
    this.worldCollide = false;
    this.invisibleOutsideCanvas = false;
    this.gravityAffect = 0.0;
    this.flags |= Sprite.FLAG_NO_GRAVITY;
    this.removeOnCollision = false;
    this.particlesOnExplode = false;
    this.radius = 0.0;
    this.showCounter = false;
    this.explodeAfter = 5.0;
    this.velocity = Vec2(dirX * FLIGHT_SPEED, 0.0);
  }

  @override
  collide(MovingSprite? other, ByteWorld? byteWorld, int? direction) {
    // Bomber pigeons fly above the fray ignoring terrain collisions.
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    gravityAffect = 0.0;
    if (networkType != NetworkType.REMOTE && !remove) {
      final Vec2 c = centerPoint();
      final bool reachedDrop = dirX >= 0 ? c.x >= dropX : c.x <= dropX;
      if (!droppedBomb && reachedDrop && owner != null) {
        droppedBomb = true;
        final PigeonDroppingBomb bomb = PigeonDroppingBomb.createFromPigeon(
          world,
          owner!,
          Vec2(c.x, c.y + 8.0),
          Vec2(velocity.x * 0.04, 165.0),
          damage,
        );
        world.addSprite(bomb);
        // Bank gently upward & speed away after bomb release!
        velocity = Vec2(dirX * (FLIGHT_SPEED * 1.25), -38.0);
      }
      // Cleanly exit once past map horizontal bounds after dropping bomb.
      if (droppedBomb &&
          (position.x < -size.x - 40.0 ||
              position.x > world.byteWorld.width + size.x + 40.0 ||
              position.y < -size.y)) {
        remove = true;
        return;
      }
    }
    super.frame(duration, frameStep, null);
  }

  @override
  explode() {
    this.remove = true;
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    final double flap = sin(_age * 24.0) * 6.0;

    context.save();
    context.translate(c.x, c.y);
    if (dirX < 0) {
      context.scale(-1.0, 1.0);
    }

    // Flared pigeon tail feathers.
    context.fillStyle = "#8695a6".toJS;
    context.strokeStyle = "#1c2029".toJS;
    context.lineWidth = 1.6;
    context.beginPath();
    context.moveTo(-9.5, 1.0);
    context.lineTo(-16.5, -2.2);
    context.lineTo(-15.5, 4.8);
    context.closePath();
    context.fill();
    context.stroke();

    // Chubby grey pigeon body + iridescent neck patch.
    context.fillStyle = "#aebbc9".toJS;
    context.strokeStyle = "#1c2029".toJS;
    context.lineWidth = 1.8;
    context.beginPath();
    context.ellipse(-1.5, 1.5, 10.5, 7.2, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    context.fillStyle = "#48d6a8".toJS;
    context.beginPath();
    context.arc(6.0, 1.0, 3.5, 0, pi * 2.0);
    context.fill();

    // Head + leather aviator cap + brass pilot goggles + yellow beak!
    context.fillStyle = "#bcc8d6".toJS;
    context.beginPath();
    context.arc(8.8, -3.2, 5.2, 0, pi * 2.0);
    context.fill();
    context.stroke();

    context.fillStyle = "#8a4c26".toJS;
    context.beginPath();
    context.arc(8.5, -4.0, 5.3, pi, pi * 2.0);
    context.closePath();
    context.fill();
    context.stroke();

    context.fillStyle = "#ffd24c".toJS;
    context.fillRect(8.5, -5.8, 5.2, 2.8);
    context.strokeRect(8.5, -5.8, 5.2, 2.8);

    context.fillStyle = "#ffc42e".toJS;
    context.beginPath();
    context.moveTo(13.5, -3.2);
    context.lineTo(17.8, -1.8);
    context.lineTo(13.5, -0.4);
    context.closePath();
    context.fill();
    context.stroke();

    // Flapping wing with pigeon wing-bars.
    context.fillStyle = "#95a4b5".toJS;
    context.beginPath();
    context.moveTo(-4.0, 0.5);
    context.quadraticCurveTo(-9.0, -9.0 + flap, 1.5, -5.5 + flap * 0.6);
    context.quadraticCurveTo(3.5, 1.0, -4.0, 0.5);
    context.closePath();
    context.fill();
    context.stroke();

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  int extraSendFlags() => Sprite.FLAG_NO_GRAVITY;

  @override
  ExtraSpriteData addExtraNetworkData() {
    final ExtraSpriteData data = super.addExtraNetworkData();
    data.extraInt.add(dirX >= 0 ? 1 : -1);
    data.extraInt.add(dropX.round());
    data.extraBool.add(droppedBomb);
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraInt.length > 3) {
      dirX = data.extraInt[3] >= 0 ? 1.0 : -1.0;
    }
    if (data.extraInt.length > 4) {
      dropX = data.extraInt[4].toDouble();
    }
    if (data.extraBool.length > 2) {
      droppedBomb = data.extraBool[2];
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.BOMBER_PIGEON;
  }
}

/// Explosive cartoon bird dropping ("splat!") released by [BomberPigeonProjectile].
class PigeonDroppingBomb extends WorldDamageProjectile {
  static const double BLAST_RADIUS = 58.0;
  static const int _MAX_TRAIL = 5;

  final List<Vec2> _trail = [];
  double _age = 0.0;
  bool _exploded = false;
  bool _splatSpawned = false;

  PigeonDroppingBomb(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(16.0, 20.0);
    this.mod = Mod.PIGEON;
    this.gravityAffect = 1.15;
    this.health = 8;
    this.radius = BLAST_RADIUS;
    this.removeOutOfBounds = true;
    this.showCounter = false;
  }

  PigeonDroppingBomb.createFromPigeon(WormWorld world, LocalPlayerSprite owner,
      Vec2 origin, Vec2 initialVel, int damage)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.mod = Mod.PIGEON;
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(16.0, 20.0);
    this.gravityAffect = 1.15;
    this.health = 8;
    this.radius = BLAST_RADIUS;
    this.removeOutOfBounds = true;
    this.showCounter = false;
    this.setCenter(origin);
    this.velocity = initialVel;
    this.angle = atan2(initialVel.y, initialVel.x);
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    super.frame(duration, frameStep, gravity);
    if (velocity.x * velocity.x + velocity.y * velocity.y > 16.0) {
      angle = atan2(velocity.y, velocity.x);
    }
    final Vec2 c = centerPoint();
    if (_trail.isEmpty || (c - _trail.last).sum() > 6.0) {
      _trail.add(c);
      if (_trail.length > _MAX_TRAIL) {
        _trail.removeAt(0);
      }
    }
  }

  @override
  void takeDamage(int dmg, LocalPlayerSprite inflictor, Mod attackMod) {
    if (attackMod == Mod.PIGEON && inflictor.networkId == owner?.networkId) {
      return;
    }
    health -= dmg;
    if (health <= 0 && !remove) {
      if (networkType != NetworkType.REMOTE && owner != null) {
        explode();
      } else {
        remove = true;
      }
    }
  }

  @override
  collide(MovingSprite? other, ByteWorld? byteWorld, int? direction) {
    if (networkType == NetworkType.REMOTE || remove) {
      return;
    }
    if (other is BomberPigeonProjectile ||
        (other is PigeonDroppingBomb &&
            other.owner?.networkId == owner?.networkId)) {
      return;
    }
    super.collide(other, byteWorld, direction);
  }

  @override
  void onRemove() {
    if (_splatSpawned) return;
    _splatSpawned = true;
    world.addSprite(PigeonSplatEffect(centerPoint(), velocity));
  }

  @override
  explode() {
    if (_exploded) return;
    _exploded = true;
    if (owner != null) {
      world.explosionAtSprite(
        sprite: this,
        velocity: velocity.multiply(0.2),
        addParticles: true,
        damage: damage,
        radius: radius,
        damageDoer: owner!,
        mod: Mod.PIGEON,
      );
    }
    this.remove = true;
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();

    // 1. Trailing little white bird-dropping droplets in world space!
    if (_trail.length >= 2) {
      context.save();
      for (int i = 0; i < _trail.length - 1; i++) {
        final double frac = (i + 1) / _trail.length;
        final Vec2 pt = _trail[i];
        context.fillStyle =
            "rgba(244, 249, 255, ${(0.55 * frac).toStringAsFixed(2)})".toJS;
        context.strokeStyle =
            "rgba(28, 34, 45, ${(0.45 * frac).toStringAsFixed(2)})".toJS;
        context.lineWidth = 1.0;
        context.beginPath();
        context.arc(pt.x, pt.y, 1.4 + 1.8 * frac, 0, pi * 2.0);
        context.fill();
        context.stroke();
      }
      context.restore();
    }

    // 2. Plump wobbly cartoon teardrop bird dropping!
    final double wobble = sin(_age * 28.0) * 0.08;
    context.save();
    context.translate(c.x, c.y);
    context.rotate(angle - pi * 0.5); // Bulbous bottom points downward along fall
    context.scale(1.0 + wobble, 1.0 - wobble);

    // Creamy-white teardrop body tapering to a dripping tail at top (-y).
    final CanvasGradient splatGrad =
        context.createRadialGradient(-1.8, 2.0, 1.0, 0.0, 2.5, 9.5);
    splatGrad.addColorStop(0.0, "#ffffff");
    splatGrad.addColorStop(0.58, "#eef4fc");
    splatGrad.addColorStop(1.0, "#cad6e6");

    context.fillStyle = splatGrad;
    context.strokeStyle = "#1c222d".toJS;
    context.lineWidth = 1.7;
    context.lineJoin = "round";
    context.beginPath();
    context.moveTo(0.0, -10.5);
    context.bezierCurveTo(2.4, -4.5, 6.8, -0.5, 6.4, 4.2);
    context.bezierCurveTo(6.0, 8.6, 3.0, 10.2, 0.0, 10.2);
    context.bezierCurveTo(-3.0, 10.2, -6.0, 8.6, -6.4, 4.2);
    context.bezierCurveTo(-6.8, -0.5, -2.4, -4.5, 0.0, -10.5);
    context.closePath();
    context.fill();
    context.stroke();

    // Little side-drip bead trailing off the side.
    context.fillStyle = "#f4f8ff".toJS;
    context.lineWidth = 1.2;
    context.beginPath();
    context.arc(5.4, -2.8, 2.0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Classic two-tone olive-charcoal inner dropping core near the bottom bulb!
    context.fillStyle = "#4b5945".toJS;
    context.beginPath();
    context.ellipse(0.6, 4.6, 2.9, 3.4, 0.25, 0, pi * 2.0);
    context.fill();

    // Wet glossy white cartoon highlight!
    context.fillStyle = "#ffffff".toJS;
    context.beginPath();
    context.ellipse(-2.2, 2.6, 1.5, 2.6, -0.2, 0, pi * 2.0);
    context.fill();

    context.restore();
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.PIGEON_BOMB;
  }
}

/// Juicy white & olive cartoon splat burst spawned on all peers when a
/// [PigeonDroppingBomb] impacts!
class PigeonSplatEffect extends MovingSprite {
  static const double DURATION = 0.46;
  double _age = 0.0;
  final List<List<double>> _droplets = [];

  PigeonSplatEffect(Vec2 center, Vec2 impactVel)
      : super(Vec2.copy(center), Vec2(1.0, 1.0), SpriteType.CUSTOM) {
    this.networkType = NetworkType.LOCAL_ONLY;
    this.collision = false;
    this.invisibleOutsideCanvas = false;

    final Random rng = WorldDamageProjectile.random;
    for (int i = 0; i < 11; i++) {
      final double a = -pi + (pi * i / 10.0) + (rng.nextDouble() - 0.5) * 0.35;
      final double spd = 75.0 + rng.nextDouble() * 145.0;
      _droplets.add([
        center.x,
        center.y,
        cos(a) * spd + impactVel.x * 0.1,
        sin(a) * spd - 35.0,
        2.4 + rng.nextDouble() * 3.0,
        i % 3 == 0 ? 1.0 : 0.0, // 1 = olive fleck, 0 = creamy white splat
      ]);
    }
  }

  @override
  frame(double dt, int frameStep, [Vec2? gravity]) {
    _age += dt;
    final double gravY = gravity != null ? gravity.y * 0.85 : 255.0;
    for (final List<double> d in _droplets) {
      d[0] += d[2] * dt;
      d[1] += d[3] * dt;
      d[2] *= max(0.0, 1.0 - dt * 2.5);
      d[3] += gravY * dt;
    }
    if (_age >= DURATION) {
      remove = true;
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    if (_age >= DURATION) return;
    final Vec2 c = centerPoint();
    final double t = (_age / DURATION).clamp(0.0, 1.0);
    final double alpha = 1.0 - t;

    context.save();
    context.globalAlpha = alpha;

    // Expanding creamy-white splat ring at impact site!
    if (t < 0.55) {
      final double rt = t / 0.55;
      context.strokeStyle = "rgba(245, 250, 255, ${(1.0 - rt).toStringAsFixed(2)})".toJS;
      context.lineWidth = 3.6 * (1.0 - rt) + 0.8;
      context.beginPath();
      context.ellipse(c.x, c.y, 8.0 + rt * 28.0, 4.0 + rt * 12.0, 0, 0, pi * 2.0);
      context.stroke();
    }

    // Flying cartoon splat droplets.
    context.strokeStyle = "#1c222d".toJS;
    context.lineWidth = 1.1;
    for (final List<double> d in _droplets) {
      final double r = d[4] * (1.0 - t * 0.35);
      context.fillStyle = (d[5] > 0.5 ? "#4b5945" : "#f5f9ff").toJS;
      context.beginPath();
      context.arc(d[0], d[1], r, 0, pi * 2.0);
      context.fill();
      context.stroke();
    }

    context.restore();
  }
}

/// Tiny flapping cartoon chicken projectile fired by the "Chicken shooter".
class ChickenProjectile extends WorldDamageProjectile {
  double _age = 0.0;

  ChickenProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = new Vec2(12.0, 10.0);
    this.mod = Mod.SHOTGUN;
    this.gravityAffect = 0.5;
    this.radius = 8.0;
    this.particlesOnExplode = false;
    this.showCounter = false;
  }

  ChickenProjectile.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super.createWithOwner(world, owner, damage,
            positionBase: positionBase, size: new Vec2(12.0, 10.0)) {
    this.spriteType = SpriteType.CUSTOM;
    this.mod = Mod.SHOTGUN;
    this.gravityAffect = 0.5;
    this.radius = 8.0;
    this.particlesOnExplode = false;
    this.showCounter = false;
    this.angle = positionBase.angle;
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    _age += duration;
    super.frame(duration, frameStep, gravity);
    if (velocity.x * velocity.x + velocity.y * velocity.y > 16.0) {
      angle = atan2(velocity.y, velocity.x);
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    final bool facingLeft = cos(angle) < 0.0;
    final double flap = sin(_age * 36.0) * 2.2;

    context.save();
    context.translate(c.x, c.y);
    if (facingLeft) {
      context.scale(-1.0, 1.0);
    }

    // Little red comb on top of head.
    context.fillStyle = "#e63232".toJS;
    context.beginPath();
    context.arc(2.2, -4.8, 1.6, 0, pi * 2.0);
    context.arc(0.4, -4.4, 1.3, 0, pi * 2.0);
    context.fill();

    // Plump tiny white-cream chicken body.
    context.fillStyle = "#fff9e6".toJS;
    context.strokeStyle = "#1c1814".toJS;
    context.lineWidth = 1.3;
    context.beginPath();
    context.ellipse(-0.5, 0.5, 4.8, 3.6, 0, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Flapping tiny wing.
    context.fillStyle = "#f2e4c2".toJS;
    context.beginPath();
    context.ellipse(-1.2, 0.2 + flap * 0.4, 2.4, 1.5, -0.3, 0, pi * 2.0);
    context.fill();
    context.stroke();

    // Orange triangle beak.
    context.fillStyle = "#ff9914".toJS;
    context.beginPath();
    context.moveTo(4.0, -1.2);
    context.lineTo(6.8, -0.2);
    context.lineTo(4.0, 0.8);
    context.closePath();
    context.fill();

    // Tiny black eye.
    context.fillStyle = "#141414".toJS;
    context.beginPath();
    context.arc(2.8, -1.2, 0.9, 0, pi * 2.0);
    context.fill();

    context.restore();
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.CHICKEN;
  }
}

// ============================================================================
// 5. MEGA SHARK (ULTIMATE SUNGLASSES LAND-HUNTING SHARK)
// ============================================================================

/// Ultimate powerup weapon projectile: a massive sunglasses shark that first
/// strikes a pose putting on its black wayfarers with a bright sunflare, then
/// hunts down the nearest hostile player at 2/3 player speed, chews straight
/// through terrain at half speed toward locked targets, and stops for 0.5s to
/// deliver an animated 80-damage chomp!
class HunterSharkProjectile extends WorldDamageProjectile {
  static const int SPRITE_FRAMES = 5;
  static const int BARE_EYES_FRAME = 1;
  static const double SHARK_WIDTH = 56.0;
  static const double SHARK_HEIGHT = 42.0;
  static const int BITE_DAMAGE = 80;
  static const double BITE_RANGE = 18.0;
  static const double LIFETIME_SECONDS = 60.0;
  static const double GLASSES_DROP_DURATION = 1.275;
  static const double SUNFLARE_DURATION = 0.75;
  static const double INTRO_DURATION =
      GLASSES_DROP_DURATION + SUNFLARE_DURATION;

  /// 2/3 of LocalPlayerSprite.MAX_WALK_SPEED (150.0 -> 100.0).
  static const double SWIM_SPEED = 100.0;

  /// Half of swim speed while chewing through solid terrain.
  static const double CHEW_SPEED = SWIM_SPEED * 0.5;
  static const double TURN_RATE = 5.4;
  static const double BITE_PAUSE_SECONDS = 1.00;
  static const double BITE_ANIM_SECONDS = 1.00;
  static const double CHEW_CARVE_INTERVAL = 0.14;
  static const double CHEW_CARVE_RADIUS = 22.0;

  static double frameWidthForImage(HTMLImageElement img) {
    if (img.width >= img.height * 4) {
      return img.width / 5.0;
    }
    if (img.width >= img.height * 3) {
      return img.width / 4.0;
    }
    return img.width.toDouble();
  }

  double _age = 0.0;
  double _bitePauseRemaining = 0.0;
  double _biteAnimRemaining = 0.0;
  double _chewCarveCooldown = 0.0;
  bool _chewingTerrain = false;
  bool _facingLeft = true;
  bool _patrolInitialized = false;
  bool _sunflareSoundPlayed = false;
  bool _removedWithPoof = false;

  bool get isInSunglassesIntro => _age < INTRO_DURATION;
  double get sunglassesProgress =>
      (_age / GLASSES_DROP_DURATION).clamp(0.0, 1.0);
  double get sunflareProgress => _age < GLASSES_DROP_DURATION
      ? 0.0
      : ((_age - GLASSES_DROP_DURATION) / SUNFLARE_DURATION).clamp(0.0, 1.0);
  bool get isChewingTerrain => _chewingTerrain;
  bool get isBiting => _biteAnimRemaining > 0.0;
  double get bitePauseRemaining => _bitePauseRemaining;
  double get age => _age;

  HunterSharkProjectile(
      WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, world.imageIndex().getImageIdByName("shark.png"),
            imageIndex) {
    _configureDefaults(world);
  }

  HunterSharkProjectile.createWithOwner(
      WormWorld world, LocalPlayerSprite owner, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("shark.png"),
            world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    _configureDefaults(world);
    this._facingLeft = cos(positionBase.angle) < 0.0;
    this.angle = _facingLeft ? pi : 0.0;
    final Vec2 ownerCenter = owner.centerPoint();
    // Spawn on owner's shoulder where it was mounted.
    this.setCenter(Vec2(ownerCenter.x, owner.position.y + 4.0));
    this.velocity = Vec2(0.0, 0.0);
    this.fullFramesOverNetwork = 4;
  }

  void _configureDefaults(WormWorld world) {
    this.spriteType = SpriteType.CUSTOM;
    this.size = Vec2(SHARK_WIDTH, SHARK_HEIGHT);
    this.mod = Mod.SHARK;
    this.damage = BITE_DAMAGE;
    this.radius = 0.0;
    this.gravityAffect = 0.0;
    this.flags |= Sprite.FLAG_NO_GRAVITY;
    this.bounche = 1.0;
    this.health = LocalPlayerSprite.MAX_HEALTH;
    this.showCounter = false;
    this.removeOnCollision = false;
    this.explodeAfter = LIFETIME_SECONDS;
    this.worldCollide = true;
    this.removeOutOfBounds = false;
    this.collision = true;
    if (world.imageIndex().imagesIndexed()) {
      setImage(world.imageIndex().getImageIdByName("shark.png"), 1);
    }
  }

  LocalPlayerSprite? nearestHostileTarget() {
    final Vec2 myCenter = centerPoint();
    LocalPlayerSprite? best;
    double bestDistSq = double.infinity;
    for (int id in world.spriteIndex.spriteIds()) {
      final Sprite? s = world.spriteIndex[id];
      if (s is LocalPlayerSprite &&
          s.inGame() &&
          s.health > 0 &&
          s.networkId != owner?.networkId) {
        final Vec2 diff = s.centerPoint() - myCenter;
        final double dSq = diff.x * diff.x + diff.y * diff.y;
        if (dSq < bestDistSq) {
          bestDistSq = dSq;
          best = s;
        }
      }
    }
    return best;
  }

  bool _overlapsWorld(ByteWorld byteWorld) {
    return byteWorld.isCanvasCollide(
      (position.x + 4).toInt(),
      (position.y + 4).toInt(),
      max(1, (size.x - 8).toInt()),
      max(1, (size.y - 8).toInt()),
    );
  }

  @override
  bool get friendlyFireCanHit => true;

  @override
  void takeDamage(int dmg, LocalPlayerSprite inflictor, Mod attackMod) {
    // Only ignore self-bite damage; all weapon projectiles (including owner's) destroy it!
    if (attackMod == Mod.SHARK && inflictor.networkId == owner?.networkId) {
      return;
    }
    health -= dmg;
    fullFramesOverNetwork = 2;
    if (health <= 0 && !remove) {
      health = 0;
      explode();
    }
  }

  @override
  explode() {
    if (_removedWithPoof) return;
    _removedWithPoof = true;
    if (!world.network().isCommander() && networkType == NetworkType.REMOTE) {
      remove = true;
      return;
    }
    final Vec2 c = centerPoint();
    final SharkDeathEffect deathEffect =
        SharkDeathEffect(world, c.x, c.y, facingLeft: _facingLeft);
    deathEffect.spawn_sound = Sound.EXPLOSION;
    world.addSprite(deathEffect);
    remove = true;
  }

  @override
  collide(MovingSprite? other, ByteWorld? byteWorld, int? direction) {
    if (remove) {
      return;
    }
    if (isInSunglassesIntro) {
      velocity = Vec2(0.0, 0.0);
      return;
    }
    if (networkType != NetworkType.REMOTE &&
        other is LocalPlayerSprite &&
        other.inGame() &&
        owner != null &&
        !isOwnedBySamePlayer(other) &&
        other.takesDamage(Mod.SHARK) &&
        _bitePauseRemaining <= 0.0) {
      final Vec2 myCenter = centerPoint();
      final Vec2 targetCenter = other.centerPoint();
      final double dx = targetCenter.x - myCenter.x;
      final double dy = targetCenter.y - myCenter.y;
      if (dx * dx + dy * dy > BITE_RANGE * BITE_RANGE) {
        return;
      }
      other.takeDamage(BITE_DAMAGE, owner!, Mod.SHARK);
      _bitePauseRemaining = BITE_PAUSE_SECONDS;
      _biteAnimRemaining = BITE_ANIM_SECONDS;
      velocity = Vec2(0.0, 0.0);
      _chewingTerrain = false;
      fullFramesOverNetwork = 6;
      world.playSoundAtSprite(this, Sound.WHIP);
      final Particles biteSparks = Particles(
        world,
        null,
        other.centerPoint(),
        Vec2(0.0, -30.0),
        radius: 14.0,
        count: 10,
        lifeTime: 18,
        shrinkPerStep: 0.85,
        particleType: ParticleEffects_ParticleType.BLOOD,
      );
      biteSparks.sendToNetwork = true;
      world.addSprite(biteSparks);
      return;
    }
    if (byteWorld != null &&
        direction != null &&
        !_chewingTerrain &&
        nearestHostileTarget() == null) {
      // No target locked: collide with environment and bounce cleanly on both commander and client!
      super.handleWorldCollide(byteWorld, direction);
      if ((direction & MovingSprite.DIR_BELOW) == MovingSprite.DIR_BELOW &&
          velocity.y > 0) {
        velocity.y = -velocity.y * bounche;
      }
      if ((direction & MovingSprite.DIR_ABOVE) == MovingSprite.DIR_ABOVE &&
          velocity.y < 0) {
        velocity.y = -velocity.y * bounche;
      }
      int pushGuard = 0;
      while (pushGuard++ < 6 && _overlapsWorld(byteWorld)) {
        if ((direction & MovingSprite.DIR_BELOW) != 0) position.y -= 1.0;
        if ((direction & MovingSprite.DIR_ABOVE) != 0) position.y += 1.0;
        if ((direction & MovingSprite.DIR_LEFT) != 0) position.x += 1.0;
        if ((direction & MovingSprite.DIR_RIGHT) != 0) position.x -= 1.0;
      }
      if (velocity.x.abs() > 1.0) {
        _facingLeft = velocity.x < 0.0;
      }
    }
  }

  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    final double prevAge = _age;
    _age += duration;
    gravityAffect = 0.0;
    if (!_sunflareSoundPlayed &&
        prevAge < GLASSES_DROP_DURATION &&
        _age >= GLASSES_DROP_DURATION) {
      _sunflareSoundPlayed = true;
      world.playSoundAtSprite(this, Sound.POWERUP);
    }
    if (_biteAnimRemaining > 0.0) {
      _biteAnimRemaining = max(0.0, _biteAnimRemaining - duration);
    }

    if (networkType != NetworkType.REMOTE && !remove) {
      if (_age >= LIFETIME_SECONDS || (explodeAfter != null && explodeAfter! <= 0)) {
        explode();
        return;
      }
      if (_bitePauseRemaining > 0.0) {
        _bitePauseRemaining = max(0.0, _bitePauseRemaining - duration);
      }

      if (isInSunglassesIntro || _bitePauseRemaining > 0.0) {
        velocity = Vec2(0.0, 0.0);
        _chewingTerrain = false;
      } else {
        final LocalPlayerSprite? target = nearestHostileTarget();
        final bool inTerrain = _overlapsWorld(world.byteWorld);
        if (target != null) {
          _patrolInitialized = false;
          _chewingTerrain = inTerrain;
          // Preserve explosion-gained speed until biting a player or chewing terrain.
          final double targetSpeed =
              _chewingTerrain ? CHEW_SPEED : max(SWIM_SPEED, velocity.sum());
          final Vec2 toTarget = target.centerPoint() - centerPoint();
          final double desiredAngle = atan2(toTarget.y, toTarget.x);
          double curAngle = (velocity.x * velocity.x + velocity.y * velocity.y > 4.0)
              ? atan2(velocity.y, velocity.x)
              : desiredAngle;
          double diff = desiredAngle - curAngle;
          while (diff > pi) diff -= 2.0 * pi;
          while (diff < -pi) diff += 2.0 * pi;
          final double maxTurn = TURN_RATE * duration;
          curAngle += diff.clamp(-maxTurn, maxTurn);
          final double wave = _chewingTerrain ? 0.0 : sin(_age * 7.5) * 0.25 * duration;
          curAngle += wave;
          velocity = Vec2(cos(curAngle) * targetSpeed, sin(curAngle) * targetSpeed);
          angle = curAngle;
          if (velocity.x.abs() > 2.0) {
            _facingLeft = velocity.x < 0.0;
          } else if (toTarget.x.abs() > 1.0) {
            _facingLeft = toTarget.x < 0.0;
          }

          if (_chewingTerrain) {
            _chewCarveCooldown -= duration;
            if (_chewCarveCooldown <= 0.0) {
              _chewCarveCooldown = CHEW_CARVE_INTERVAL;
              final Vec2 mouthPos = centerPoint() +
                  Vec2(cos(curAngle) * (SHARK_WIDTH * 0.24),
                      sin(curAngle) * (SHARK_HEIGHT * 0.24));
              world.explosionAt(
                location: mouthPos,
                velocity: velocity.multiply(-0.25),
                addParticles: false,
                damage: 0,
                radius: CHEW_CARVE_RADIUS,
                damagerDoer: owner,
                mod: Mod.SHARK,
              );
            }
          }
        } else {
          // Patrol with real velocity so world bounce collisions hold without slowing explosion boosts!
          _chewingTerrain = false;
          if (!_patrolInitialized ||
              velocity.sum() < 10.0) {
            final double dirX = _facingLeft ? -1.0 : 1.0;
            velocity = Vec2(dirX * (SWIM_SPEED * 0.55), 14.0);
            _patrolInitialized = true;
          }
          _facingLeft = velocity.x < 0.0;
          alignAngleWithVelocity();
        }
      }
    } else {
      if (velocity.x.abs() > 2.0) {
        _facingLeft = velocity.x < 0.0;
      }
      alignAngleWithVelocity();
    }

    super.frame(duration, frameStep, null);
    if (!isInSunglassesIntro && _bitePauseRemaining <= 0.0) {
      alignAngleWithVelocity();
    }
  }

  @override
  int extraSendFlags() => Sprite.FLAG_NO_GRAVITY;

  @override
  ExtraSpriteData addExtraNetworkData() {
    explodeAfter ??= max(0.0, LIFETIME_SECONDS - _age);
    final ExtraSpriteData data = super.addExtraNetworkData();
    final int stateFlags = (isInSunglassesIntro ? 1 : 0) |
        (_chewingTerrain ? 2 : 0) |
        (isBiting ? 4 : 0) |
        (_facingLeft ? 8 : 0);
    // super pushes [damage, ownerId, health] in extraInt and [radius, explodeAfter] in extraFloat.
    data.extraInt.add(stateFlags);
    data.extraFloat.add(_age);
    data.extraFloat.add(_biteAnimRemaining);
    return data;
  }

  @override
  void parseExtraNetworkData(ExtraSpriteData data) {
    super.parseExtraNetworkData(data);
    if (data.extraInt.length >= 4) {
      final int stateFlags = data.extraInt[3];
      _chewingTerrain = (stateFlags & 2) != 0;
      _facingLeft = (stateFlags & 8) != 0;
    }
    if (data.extraFloat.length >= 4) {
      _age = data.extraFloat[2];
      _biteAnimRemaining = data.extraFloat[3];
    }
  }

  int activeSpriteFrameIndex() => _activeSpriteFrameIndex();

  int _activeSpriteFrameIndex() {
    if (isInSunglassesIntro && sunglassesProgress < 1.0) {
      return 1; // Bare fierce eyes before sunglasses land!
    }
    if (_biteAnimRemaining > 0.0) {
      final double u =
          (1.0 - _biteAnimRemaining / BITE_ANIM_SECONDS).clamp(0.0, 1.0);
      if (u < 0.28) return 2; // Jaws wide open
      if (u < 0.52) return 3; // Half-closed bite
      if (u < 0.82) return 4; // Jaws chomped shut
      return 3; // Half-closed release
    }
    if (_chewingTerrain) {
      const List<int> chewCycle = <int>[2, 3, 4, 3];
      return chewCycle[((_age * 12.0).floor()) % chewCycle.length];
    }
    return 0; // Cool swimming with sunglasses!
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    final double t = _age;
    final bool inIntro = isInSunglassesIntro;
    final double dropT = sunglassesProgress;
    final double flareT = sunflareProgress;

    final double bobY = inIntro ? 0.0 : sin(t * 8.0) * 2.0;
    final double tilt = inIntro
        ? sin(dropT * pi) * -0.06
        : (_chewingTerrain ? sin(t * 22.0) * 0.10 : sin(t * 6.5) * 0.05);

    context.save();
    context.translate(c.x, c.y + bobY);
    if (_facingLeft) {
      context.rotate(angle - pi + tilt);
    } else {
      context.rotate(angle - tilt);
      context.scale(-1.0, 1.0);
    }

    // 1. Draw the isolated animation frame from the 5-frame shark.png spritesheet!
    final int frameIdx = _activeSpriteFrameIndex();
    final ImageIndex imgIdx = world.imageIndex();
    if (imageId >= 0 && imageId < imgIdx.images.length) {
      final HTMLImageElement sharkImg = imgIdx.getImageById(imageId);
      if (sharkImg.width > 0 && sharkImg.height > 0) {
        final double frameW = frameWidthForImage(sharkImg);
        final bool isSheet = sharkImg.width >= sharkImg.height * 3;
        final double sx = isSheet ? frameIdx * frameW : 0.0;
        context.drawImage(
          sharkImg,
          sx,
          0,
          frameW,
          sharkImg.height,
          -SHARK_WIDTH * 0.5,
          -SHARK_HEIGHT * 0.5,
          SHARK_WIDTH,
          SHARK_HEIGHT,
        );
      }
    }

    // 2. Slide sunglasses down onto Frame 1 during the put-on intro!
    if (inIntro && dropT < 1.0) {
      context.save();
      final double easeDrop = 1.0 - pow(1.0 - dropT, 2.2).toDouble();
      final double glassesY = -28.0 + easeDrop * 22.5;
      context.translate(-11.0, glassesY);
      context.fillStyle = "#12161f".toJS;
      context.strokeStyle = "#080b10".toJS;
      context.lineWidth = 1.2;
      context.beginPath();
      context.roundRect(-14.5, -4.5, 12.0, 8.8, 2.2.toJS);
      context.roundRect(0.5, -4.5, 13.0, 9.2, 2.2.toJS);
      context.fill();
      context.stroke();
      context.fillRect(-3.0, -3.5, 4.0, 2.6);
      context.fillStyle = "#f2c14e".toJS;
      context.fillRect(-13.8, -3.5, 1.6, 1.1);
      context.fillRect(11.4, -3.5, 1.6, 1.1);
      context.restore();
    }

    // 3. Distinct golden-white sunflare when sunglasses snap onto the face!
    if (flareT > 0.0 && flareT < 1.0) {
      final double fAlpha = sin(flareT * pi).clamp(0.0, 1.0);
      final double fRadius = 10.0 + sin(flareT * pi) * 16.0;
      context.save();
      context.translate(-6.0, -6.5);
      context.globalAlpha = fAlpha;
      final CanvasGradient g =
          context.createRadialGradient(0, 0, 1.0, 0, 0, fRadius * 1.3);
      g.addColorStop(0.0, "rgba(255, 255, 240, 1.0)");
      g.addColorStop(0.45, "rgba(255, 232, 92, 0.85)");
      g.addColorStop(1.0, "rgba(255, 196, 48, 0.0)");
      context.fillStyle = g;
      context.beginPath();
      context.arc(0, 0, fRadius * 1.3, 0, pi * 2.0);
      context.fill();

      context.rotate(flareT * 0.9);
      context.fillStyle = "#ffffff".toJS;
      context.beginPath();
      for (int i = 0; i < 8; i++) {
        final double a = i * pi / 4.0;
        final double r = i.isEven ? fRadius * 1.45 : fRadius * 0.24;
        if (i == 0) {
          context.moveTo(cos(a) * r, sin(a) * r);
        } else {
          context.lineTo(cos(a) * r, sin(a) * r);
        }
      }
      context.closePath();
      context.fill();
      context.restore();
    }

    context.restore();

    if (debug) {
      super.draw(context, true);
    }
  }

  @override
  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.HUNTER_SHARK;
  }
}
