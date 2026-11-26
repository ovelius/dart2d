library weapon_state;

import 'dart:js_interop';

import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'dart:math';
import 'package:dart2d/phys/vec2.dart';
import 'package:web/web.dart';

import '../net/state_updates.pb.dart';
import '../res/sounds.dart';
import '../util/mobile_controls.dart';

class WeaponState {
  static Random random = new Random();
  static const double SHOW_WEAPON_NAME_TIME = 1.3;
  static const int ICON_TILE_SIZE = 80;
  static const int ICON_SIZE_HALF = ICON_TILE_SIZE ~/ 2;
  static const int WHEEL_SIZE = 145;
  WormWorld world;
  LocalPlayerSprite owner;
  Sprite gun;
  MobileControls? mobileControls;
  
  double changeTime = 0.0;
  double _laserTime = 0.0;
  String _longestWeaponName = "";
  int selectedWeaponIndex = 2;
  double _anglePerWeapon = 0.0;

  String get selectedWeaponName => weapons[selectedWeaponIndex].name;

  WeaponState(this.world, this.owner, this.gun,  this.mobileControls) {
    for (Weapon w in weapons) {
      if (w.name.length > _longestWeaponName.length) {
        _longestWeaponName = w.name;
      }
    }
    mobileControls?.listenForTouch((int x, int y) {
      if (changeTime > 0) {
        Point<int> location = mobileControls!.buttonLocation(MobileControls.WEAPON_SELECT_BUTTON);
        Point<int> deltaLocation = Point(location.x - x, location.y - y);
        weaponStateSelector(deltaLocation);
      }
    });
    _anglePerWeapon =  (pi * 2)/weapons.length;
  }

  Weapon getSelectedWeapon() => weapons[selectedWeaponIndex];

  List<Weapon> weapons = [
    new Weapon("Banana pancake", 4, 2, 5.0, 1.0,  (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BananaCake.createWithOwner(weaponState.world,  weaponState.owner, 50, weaponState.owner.gun);
      sprite.explodeAfter = 4.0;
      sprite.owner = weaponState.owner;
      sprite.radius = 50.0;
      sprite.spawn_sound = Sound.SWOSH;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Brick builder", 9, 20, 5.0, 0.3, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BrickBuilder.createWithOwner(weaponState.world, weaponState.owner, 2, weaponState.owner.gun);
      sprite.mod = Mod.BRICK;
      sprite.spawn_sound = Sound.THUD;
      sprite.owner = weaponState.owner;
      sprite.radius = 50.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Shotgun",0, 4, 2.0, .8, (WeaponState weaponState) {
      weaponState.world.playSoundAtSprite(weaponState.owner, Sound.SHOTGUN);
      for (int i = 0; i < 8; i++) {
        WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 7, positionBase:weaponState.owner.gun);
        sprite.mod = Mod.SHOTGUN;
        sprite.particlesOnExplode = false;
        sprite.spriteType = SpriteType.CIRCLE;
        sprite.owner = weaponState.owner;
        double sum = sprite.velocity.sum();
        sprite.velocity.x = sprite.velocity.x + random.nextDouble() * sum / 4;
        sprite.velocity.y = sprite.velocity.y + random.nextDouble() * sum / 4;

        sprite.gravityAffect = 0.5;
        
        sprite.size = new Vec2(2.0, 2.0);
        sprite.radius = 8.0;
        weaponState.world.addSprite(sprite);
      }
    }),
    new Weapon("Dart gun", 1, 120, 6.0, .12, (WeaponState weaponState) {
      DartProjectile sprite = new DartProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 8, weaponState.owner.gun);
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Jellybean Jet", 8, 40, 9.0, .11, (WeaponState weaponState) {
      JellybeanProjectile sprite = new JellybeanProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 8, weaponState.owner.gun);
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Coffee Burn",2, 150, 2.0, .05, (WeaponState weaponState) {
      Vec2 vel = new Vec2(cos(weaponState.gun.angle), sin(weaponState.gun.angle));
      Vec2 position = weaponState.gun.centerPoint();
      double gunRadius = weaponState.gun.size.sum() / 2;
      position.x += cos(weaponState.gun.angle) * gunRadius;
      position.y += sin(weaponState.gun.angle) * gunRadius;
      Particles p = new Particles(
          weaponState.world,
          null, position, vel.multiply(400.0),
          radius: 10.0, count: 5, lifeTime: 65, shrinkPerStep: -0.3, particleType: ParticleEffects_ParticleType.FIRE);
      p.sendToNetwork = true;
      p.world = weaponState.world;
      p.collision = true;
      p.damage = 7;
      p.spawn_sound = Sound.BURN;
      p.owner = weaponState.owner;
      weaponState.world.addSprite(p);
    }),
    new Weapon("Snailgun",3, 4, 1.0, 0.3, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 12,
          positionBase: weaponState.owner.gun, size: new Vec2(180.0/ 4, 130/6));
      sprite.mod = Mod.SNAIL;
      sprite.radius = 19.0;
      sprite.owner = weaponState.owner;
      sprite.worldCollide = false;
      sprite.removeOutOfBounds = true;
      sprite.gravityAffect = 0;
      sprite.particlesOnExplode = false;
      sprite.removeOnCollision = false;
      sprite.maxSpeed = sprite.velocity.multiply(1.0);
      sprite.velocity = sprite.velocity.multiply(0.1);
      sprite.acceleration = sprite.velocity.multiply(10.0);
      int frame = Random().nextInt(3);
      sprite.setImageWithLockedFrame(weaponState.world.imageIndex().getImageIdByName("snails.png"), 3, frame);

      Vec2 offset = Vec2(-sprite.size.x * cos(sprite.angle),
          -sprite.size.y * sin(sprite.angle)).multiply(0.3);

      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2),
          count: 60, lifeTime: 160, shrinkPerStep: 0.2, followOffset: offset);
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }, hasLaserSight: true),
    new Weapon("Cat litter box", 5, 1, 5.0, 0.01, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 100, positionBase:weaponState.owner.gun);
      sprite.mod = Mod.LITTER;
      sprite.radius = 150.0;
      sprite.owner = weaponState.owner;
      sprite.explodeAfter = 5.0;
      sprite.size = new Vec2(140.0 * 0.3, 129.0 * 0.3);
      sprite.angle = 0.0;
      sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("box.png"), 2);
      weaponState.world.addSprite(sprite);
    }),
    /*
    new Weapon("Black sheep down", 1, 5.0, 0.01, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 100);
      sprite.radius = 450.0;
      sprite.owner = weaponState.owner;
      sprite.explodeAfter = 5.0;
      sprite.size = new Vec2(58.0 * 0.7, 58.0 * 0.7);
      sprite.angle = 0.0;
      sprite.bounche = 1.0;
      sprite.velocity = sprite.velocity.multiply(0.4);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("sheep_black58.png"), 58);
      weaponState.world.addSprite(sprite);
    }), */
    new Weapon("Zooka",6, 5, 2.5, 0.8, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 40,
          positionBase: weaponState.owner.gun, size: new Vec2(38.0, 16.0));
      sprite.mod = Mod.ZOOKA;
      sprite.spawn_sound = Sound.ZOOKA;
      sprite.radius = 40.0;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.05;
      // sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("zooka.png"), 1);
      Vec2 offset = Vec2(-cos(sprite.angle), -sin(sprite.angle)).multiply(sprite.size.x * 0.46);
      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2),
          count: 45, lifeTime: 55, radius: 9.0, shrinkPerStep: 0.2, followOffset: offset);
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }),
    new Weapon("Neon Blaster",7, 5, 2.5, 1.20, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new Hyper.createWithOwner(weaponState.world, weaponState.owner, 30, weaponState.owner.gun);
      sprite.radius = Hyper.DEFAULT_BLAST_RADIUS;
      sprite.spawn_sound = Sound.HYPER;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.00;
      weaponState.world.addSprite(sprite);
    }),
  ];
  
  nextWeapon() {
    selectedWeaponIndex++;
    selectedWeaponIndex = selectedWeaponIndex % weapons.length;
    changeTime = SHOW_WEAPON_NAME_TIME;
  }
  
  prevWeapon() {
    selectedWeaponIndex--;
    if (selectedWeaponIndex < 0) {
      selectedWeaponIndex = weapons.length - 1;
    }
    changeTime = SHOW_WEAPON_NAME_TIME;
  }
  
  fire() {
    weapons[selectedWeaponIndex].fireButton(this);
  }
  
  think(double duration) {
    changeTime -= duration;
    _laserTime += duration;
    weapons[selectedWeaponIndex].think(duration);
  }

  weaponStateSelector(Point<int> delta) {
    changeTime = SHOW_WEAPON_NAME_TIME;

    double currentAngle = 0.0;
    int weaponCount = weapons.length;
    int closestWeapon = 0;
    double closest = 9999999.0;

    for (int i = 0; i < weaponCount; i++) {
      double deltaX = ((sin(currentAngle) * WHEEL_SIZE) - ICON_SIZE_HALF) + delta.x;
      double deltaY = ((cos(currentAngle) * WHEEL_SIZE) - ICON_SIZE_HALF) + delta.y;
      double distance = sqrt(deltaX * deltaX + deltaY * deltaY);
      if (distance < closest) {
        closestWeapon = i;
        closest = distance;
      }
      currentAngle += _anglePerWeapon;
    }
    selectedWeaponIndex = closestWeapon;
  }

  _drawIconImageAt(CanvasRenderingContext2D context,
      HTMLImageElement iconImages, int index, num x, num y) {
    context.drawImage(iconImages,
        index * 128, 0, 128, 128,
        x, y
        ,ICON_TILE_SIZE, ICON_TILE_SIZE);
  }

  _drawChangeTime(CanvasRenderingContext2D context,
      HTMLImageElement iconImages, Point<int> center) {
    context.save();
    int baseX = center.x - ICON_SIZE_HALF;
    int baseY = center.y - ICON_SIZE_HALF;

    int weaponCount = weapons.length;

    double currentAngle = 0.0;

    for (int i = 0; i < weaponCount; i++) {
      double x = sin(currentAngle) * WHEEL_SIZE;
      double y = cos(currentAngle) * WHEEL_SIZE;
      if (selectedWeaponIndex == i) {
        context.globalAlpha = 1.0;
      } else {
        context.globalAlpha = 0.5;
      }
      _drawIconImageAt(context, iconImages,
          weapons[i].iconIndex,  baseX + x,  baseY + y);
      currentAngle += _anglePerWeapon;
    }
    // Draw the weapon name in bold cartoon outlined style.
    context.font = 'bold 20px "Trebuchet MS", Arial, sans-serif';
    String selectedWeaponName = weapons[selectedWeaponIndex].name;
    TextMetrics metrics = context.measureText(selectedWeaponName);
    context.globalAlpha = 1.0;
    num textY = center.y - WeaponState.ICON_SIZE_HALF;
    if (textY < 0) {
      textY = center.y + WeaponState.ICON_SIZE_HALF;
    }
    double textX = center.x - metrics.width / 2;
    context.lineJoin = "round";
    context.strokeStyle = "#161b24".toJS;
    context.lineWidth = 4.5;
    context.strokeText(selectedWeaponName, textX, textY);
    context.fillStyle = "#ffe97a".toJS;
    context.fillText(selectedWeaponName, textX, textY);
    context.restore();
  }


  drawWeaponHelper(CanvasRenderingContext2D context, Point<int> center, bool drawCurrentWeapon) {
    HTMLImageElement iconImages = world.imageIndex().getImageByName("weapon_icons.png");
    if (changeTime > 0 && owner.drawWeaponHelpers()) {
      _drawChangeTime(context, iconImages, center);
    }
    if (drawCurrentWeapon) {
      if (changeTime <= 0) {
        context.globalAlpha = 0.3;
      }
      _drawIconImageAt(context, iconImages,
          weapons[selectedWeaponIndex].iconIndex,  center.x  -ICON_SIZE_HALF,  center.y -ICON_SIZE_HALF);
      context.globalAlpha = 1.0;
    }
  }

  LaserSightTrace computeLaserSightTrace() {
    final Vec2 center = owner.centerPoint();
    final double dirX = cos(gun.angle);
    final double dirY = sin(gun.angle);
    final double muzzleOffset = gun.size.x * 0.5;
    final double startX = center.x + dirX * muzzleOffset;
    final double startY = center.y + dirY * muzzleOffset;

    double maxDist = 2500.0;
    final bool worldReady = world.byteWorld.byteWorldReady();
    if (worldReady) {
      final double maxW = world.byteWorld.width.toDouble();
      final double maxH = world.byteWorld.height.toDouble();
      double boundDist = double.infinity;
      if (dirX.abs() > 1e-6) {
        final double tx = dirX > 0 ? (maxW - startX) / dirX : (0.0 - startX) / dirX;
        if (tx >= 0.0) boundDist = min(boundDist, tx);
      }
      if (dirY.abs() > 1e-6) {
        final double ty = dirY > 0 ? (maxH - startY) / dirY : (0.0 - startY) / dirY;
        if (ty >= 0.0) boundDist = min(boundDist, ty);
      }
      if (boundDist.isFinite) {
        maxDist = boundDist.clamp(0.0, 4000.0);
      }
    }

    // Find first terrain contact (the Snailgun pierces straight through terrain,
    // so we show a crisp laser beam up to terrain and a glowing dashed x-ray
    // penetration path beyond it).
    double? terrainHitDist;
    if (worldReady && maxDist > 0.0) {
      const double step = 6.0;
      for (double d = 0.0; d <= maxDist; d += step) {
        final int sx = (startX + dirX * d).round();
        final int sy = (startY + dirY * d).round();
        if (world.byteWorld.isSolid(sx, sy)) {
          // Refine within the last step for a crisp dot right on the surface.
          double refined = max(0.0, d - step);
          while (refined < d &&
              !world.byteWorld.isSolid(
                  (startX + dirX * refined).round(),
                  (startY + dirY * refined).round())) {
            refined += 1.0;
          }
          terrainHitDist = refined;
          break;
        }
      }
    }

    // Find any enemy players along the snail's straight path for target-lock dots.
    final List<Vec2> playerHits = [];
    for (int id in world.spriteIndex.spriteIds()) {
      final Sprite? s = world.spriteIndex[id];
      if (s is LocalPlayerSprite && s != owner && s.inGame()) {
        final Vec2 targetCenter = s.centerPoint();
        final double toX = targetCenter.x - startX;
        final double toY = targetCenter.y - startY;
        final double proj = toX * dirX + toY * dirY;
        if (proj > 0.0 && proj <= maxDist) {
          final double perpSq =
              (toX - dirX * proj) * (toX - dirX * proj) +
              (toY - dirY * proj) * (toY - dirY * proj);
          final double hitRadius = s.getRadius() * 0.95;
          if (perpSq <= hitRadius * hitRadius) {
            playerHits.add(Vec2(startX + dirX * proj, startY + dirY * proj));
          }
        }
      }
    }

    return LaserSightTrace(
      start: Vec2(startX, startY),
      dir: Vec2(dirX, dirY),
      totalDistance: maxDist,
      terrainHitDistance: terrainHitDist,
      playerHits: playerHits,
    );
  }

  void _drawLaserSight(CanvasRenderingContext2D context) {
    final LaserSightTrace trace = computeLaserSightTrace();
    if (trace.totalDistance <= 1.0) return;

    final bool isLocalOwner = owner.drawWeaponHelpers();
    final double reloadDim = (isLocalOwner && reloading()) ? 0.32 : 1.0;
    final double ownerAlpha = (isLocalOwner ? 1.0 : 0.68) * reloadDim;
    final double pulse = 0.88 + 0.12 * sin(_laserTime * 14.0);
    final double alpha = ownerAlpha * pulse;

    final double startX = trace.start.x;
    final double startY = trace.start.y;
    final double dirX = trace.dir.x;
    final double dirY = trace.dir.y;
    final double solidEndDist = trace.terrainHitDistance ?? trace.totalDistance;
    final double solidEndX = startX + dirX * solidEndDist;
    final double solidEndY = startY + dirY * solidEndDist;

    context.save();
    context.lineCap = "round";

    // 1. Primary open-air laser beam (soft outer glow + bright crimson + hot core).
    if (solidEndDist > 0.5) {
      context.strokeStyle = "rgba(255, 32, 48, ${0.26 * alpha})".toJS;
      context.lineWidth = 6.5;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();

      context.strokeStyle = "rgba(255, 48, 62, ${0.84 * alpha})".toJS;
      context.lineWidth = 2.2;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();

      context.strokeStyle = "rgba(255, 232, 234, ${0.92 * alpha})".toJS;
      context.lineWidth = 0.9;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();
    }

    // 2. Piercing path continuation beyond first terrain hit (animated dashed beam
    // showing the snail will burrow straight through the wall!).
    if (trace.terrainHitDistance != null &&
        trace.terrainHitDistance! < trace.totalDistance - 1.0) {
      final double pierceStart = trace.terrainHitDistance!;
      const double dashLen = 11.0;
      const double gapLen = 9.0;
      const double period = dashLen + gapLen;
      final double phase = (_laserTime * 55.0) % period;

      // Soft outer piercing glow.
      context.strokeStyle = "rgba(255, 52, 68, ${0.22 * alpha})".toJS;
      context.lineWidth = 4.2;
      context.beginPath();
      for (double d = pierceStart + phase; d < trace.totalDistance; d += period) {
        final double segEnd = min(d + dashLen, trace.totalDistance);
        context.moveTo(startX + dirX * d, startY + dirY * d);
        context.lineTo(startX + dirX * segEnd, startY + dirY * segEnd);
      }
      context.stroke();

      // Crisp inner piercing laser dashes.
      context.strokeStyle = "rgba(255, 92, 102, ${0.72 * alpha})".toJS;
      context.lineWidth = 1.5;
      context.beginPath();
      for (double d = pierceStart + phase; d < trace.totalDistance; d += period) {
        final double segEnd = min(d + dashLen, trace.totalDistance);
        context.moveTo(startX + dirX * d, startY + dirY * d);
        context.lineTo(startX + dirX * segEnd, startY + dirY * segEnd);
      }
      context.stroke();

      // Glowing laser contact dot right where the beam hits terrain.
      final double dotR = 3.2 + 0.8 * sin(_laserTime * 18.0);
      context.fillStyle = "rgba(255, 42, 58, ${0.38 * alpha})".toJS;
      context.beginPath();
      context.arc(solidEndX, solidEndY, dotR * 2.1, 0, 2 * pi);
      context.fill();

      context.fillStyle = "rgba(255, 225, 228, ${0.95 * alpha})".toJS;
      context.beginPath();
      context.arc(solidEndX, solidEndY, dotR * 0.85, 0, 2 * pi);
      context.fill();
    }

    // 3. Target-lock laser dots on any enemy player along the snail's trajectory!
    for (final Vec2 hit in trace.playerHits) {
      final double lockPulse = 1.0 + 0.25 * sin(_laserTime * 20.0);
      context.strokeStyle = "rgba(255, 48, 64, ${0.9 * alpha})".toJS;
      context.lineWidth = 1.8;
      context.beginPath();
      context.arc(hit.x, hit.y, 7.5 * lockPulse, 0, 2 * pi);
      context.stroke();

      context.fillStyle = "rgba(255, 240, 240, ${0.95 * alpha})".toJS;
      context.beginPath();
      context.arc(hit.x, hit.y, 2.8, 0, 2 * pi);
      context.fill();
    }

    // 4. Tiny glowing emitter dot at the gun barrel tip.
    context.fillStyle = "rgba(255, 58, 72, ${0.5 * alpha})".toJS;
    context.beginPath();
    context.arc(startX, startY, 3.8, 0, 2 * pi);
    context.fill();
    context.fillStyle = "rgba(255, 240, 240, ${0.95 * alpha})".toJS;
    context.beginPath();
    context.arc(startX, startY, 1.6, 0, 2 * pi);
    context.fill();

    context.restore();
  }

  draw(CanvasRenderingContext2D context) {
    context.save();
    if (getSelectedWeapon().hasLaserSight) {
      _drawLaserSight(context);
    }
    if (owner.drawWeaponHelpers()) {
      double radius = owner.getRadius();
      context.fillStyle = "#ffffff".toJS;
      Vec2 center = owner.centerPoint();
      if (reloading()) {
        double percentInverse = (100 - reloadPercent()) / 100.0;
        double circle = pi * 2 * percentInverse - pi/2;

        context.save();
        if (changeTime <= 0) {
          context.font = 'bold 13px "Trebuchet MS", Arial, sans-serif';
          context.lineJoin = "round";
          context.strokeStyle = "#161b24".toJS;
          context.lineWidth = 3.2;
          double reloadX = center.x - 28;
          double reloadY = center.y - owner.size.y * 0.75;
          context.strokeText("Reloading", reloadX, reloadY);
          context.fillStyle = "#fff9e6".toJS;
          context.fillText("Reloading", reloadX, reloadY);
          context.beginPath();
        }

        context.fillStyle = "#009900".toJS;
        context.globalAlpha = 0.5;
        context.arc(center.x, center.y, radius + 5,
            - pi/2, circle, false);
        context.arc(center.x, center.y, radius,
            circle, pi*2 - pi/2, true);
        context.fill();
        context.restore();
      }
    }
    context.restore();
  }

  bool reloading() => weapons[selectedWeaponIndex].reloading();
  int reloadPercent() => weapons[selectedWeaponIndex].reloadPercent();
}

class LaserSightTrace {
  final Vec2 start;
  final Vec2 dir;
  final double totalDistance;
  final double? terrainHitDistance;
  final List<Vec2> playerHits;

  const LaserSightTrace({
    required this.start,
    required this.dir,
    required this.totalDistance,
    required this.terrainHitDistance,
    required this.playerHits,
  });

  Vec2 get end =>
      Vec2(start.x + dir.x * totalDistance, start.y + dir.y * totalDistance);
}