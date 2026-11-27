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
  static const int ICON_TILE_SIZE = 68;
  static const int ICON_SIZE_HALF = ICON_TILE_SIZE ~/ 2;
  static const int WHEEL_SIZE = 172;
  WormWorld world;
  LocalPlayerSprite owner;
  Sprite gun;
  MobileControls? mobileControls;
  
  double changeTime = 0.0;
  double _laserTime = 0.0;
  bool _wasReloading = false;
  double _reloadReadyFlash = 0.0;
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
      SnailProjectile sprite = new SnailProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 12, weaponState.owner.gun);

      Vec2 offset = Vec2(-sprite.size.x * cos(sprite.angle),
          -sprite.size.y * sin(sprite.angle)).multiply(0.35);

      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2),
          radius: 6.8, count: 42, lifeTime: 115, shrinkPerStep: 0.25, followOffset: offset);
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }, hasLaserSight: true),
    new Weapon("Cat litter box", 5, 1, 5.0, 0.01, (WeaponState weaponState) {
      CatLitterBox sprite = new CatLitterBox.createWithOwner(
          weaponState.world, weaponState.owner, 100, weaponState.owner.gun);
      sprite.spawn_sound = Sound.SWOSH;
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
    new Weapon("Spiky Hedgehog", 10, 2, 5.5, 0.9, (WeaponState weaponState) {
      HedgehogMine sprite = new HedgehogMine.createWithOwner(
          weaponState.world, weaponState.owner, 38, weaponState.owner.gun);
      sprite.spawn_sound = Sound.SWOSH;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Turbo Mole", 11, 2, 5.0, 1.0, (WeaponState weaponState) {
      MoleDrillProjectile sprite = new MoleDrillProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 45, weaponState.owner.gun);
      sprite.spawn_sound = Sound.ZOOKA;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Angry Beehive", 12, 2, 5.5, 1.0, (WeaponState weaponState) {
      AngryBeehive sprite = new AngryBeehive.createWithOwner(
          weaponState.world, weaponState.owner, 18, weaponState.owner.gun);
      sprite.spawn_sound = Sound.SWOSH;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Pigeon Strike", 13, 1, 6.5, 1.0, (WeaponState weaponState) {
      PigeonStrikeFlare sprite = new PigeonStrikeFlare.createWithOwner(
          weaponState.world, weaponState.owner, weaponState.owner.gun);
      sprite.spawn_sound = Sound.DARTGUN;
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
    if (_reloadReadyFlash > 0.0) {
      _reloadReadyFlash = max(0.0, _reloadReadyFlash - duration * 3.6);
    }
    weapons[selectedWeaponIndex].think(duration);
    final bool nowReloading = reloading();
    if (_wasReloading && !nowReloading) {
      _reloadReadyFlash = 1.0;
    }
    _wasReloading = nowReloading;
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
    if ((index + 1) * 128 <= iconImages.width && iconImages.height >= 128) {
      context.drawImage(iconImages,
          index * 128, 0, 128, 128,
          x, y,
          ICON_TILE_SIZE, ICON_TILE_SIZE);
    } else {
      context.save();
      context.fillStyle = "#424b54".toJS;
      context.beginPath();
      context.roundRect(x, y, ICON_TILE_SIZE, ICON_TILE_SIZE, 12.0.toJS);
      context.fill();
      context.restore();
    }
  }

  _drawChangeTime(CanvasRenderingContext2D context,
      HTMLImageElement iconImages, Point<int> center) {
    context.save();
    int baseX = center.x - ICON_SIZE_HALF;
    int baseY = center.y - ICON_SIZE_HALF;

    int weaponCount = weapons.length;

    double currentAngle = 0.0;

    for (int i = 0; i < weaponCount; i++) {
      final double x = sin(currentAngle) * WHEEL_SIZE;
      final double y = cos(currentAngle) * WHEEL_SIZE;
      final double tileX = baseX + x;
      final double tileY = baseY + y;
      final bool isSelected = selectedWeaponIndex == i;
      context.globalAlpha = isSelected ? 1.0 : 0.55;
      _drawIconImageAt(context, iconImages, weapons[i].iconIndex, tileX, tileY);
      _drawWheelClipBadge(context, weapons[i], tileX, tileY, isSelected);
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

  /// Draws a compact cartoon clip-size pill badge (`shotsLeft/shotsPerClip`
  /// plus a slim ammo/reload bar) at the bottom of each weapon wheel tile.
  void _drawWheelClipBadge(
    CanvasRenderingContext2D context,
    Weapon weapon,
    double tileX,
    double tileY,
    bool isSelected,
  ) {
    final int maxShots = weapon.shotsPerClip;
    if (maxShots <= 0) return;

    final bool isReloading = weapon.reloading();
    final int remaining = isReloading ? 0 : weapon.shotsLeft.clamp(0, maxShots);
    final double frac = isReloading
        ? (weapon.reloadTime > 0
            ? (1.0 - weapon.untilReload / weapon.reloadTime).clamp(0.0, 1.0)
            : 0.0)
        : (remaining / maxShots).clamp(0.0, 1.0);
    final bool isLow = !isReloading && (remaining == 1 || frac <= 0.25);

    final String label = isReloading
        ? "${max(0.0, weapon.untilReload).toStringAsFixed(1)}s"
        : "$remaining/$maxShots";

    context.save();
    context.globalAlpha = isSelected ? 1.0 : 0.86;
    context.font = 'bold 11px "Trebuchet MS", Arial, sans-serif';
    final double textW = context.measureText(label).width;
    final double pillW = max(36.0, min(ICON_TILE_SIZE - 4.0, textW + 14.0));
    const double pillH = 19.0;
    final double pillX = tileX + (ICON_TILE_SIZE - pillW) * 0.5;
    final double pillY = tileY + ICON_TILE_SIZE - pillH - 2.0;
    const double radius = 6.5;

    // Dark cartoon capsule background.
    context.fillStyle = "rgba(18, 25, 38, 0.90)".toJS;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.fill();

    // Slim bottom ammo / reload progress bar clipped inside the pill.
    const double barH = 3.5;
    final double barX = pillX + 3.0;
    final double barY = pillY + pillH - barH - 2.0;
    final double barW = pillW - 6.0;
    context.fillStyle = "rgba(255, 255, 255, 0.14)".toJS;
    context.beginPath();
    context.roundRect(barX, barY, barW, barH, 2.0.toJS);
    context.fill();

    if (frac > 0.0) {
      context.fillStyle = (isReloading
              ? "#5ce8ff"
              : (isLow ? "#ff6e48" : "#ffe252"))
          .toJS;
      context.beginPath();
      context.roundRect(barX, barY, max(2.0, barW * frac), barH, 2.0.toJS);
      context.fill();
    }

    // Crisp comic border (gold highlight on the currently selected weapon).
    context.strokeStyle = (isSelected
            ? "#ffe97a"
            : (isReloading ? "#5ce8ff" : "#3a4a61"))
        .toJS;
    context.lineWidth = isSelected ? 1.8 : 1.3;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.stroke();

    // Centered bold ammo text.
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillStyle = (isReloading
            ? "#9ef4ff"
            : (isLow
                ? "#ff9675"
                : (remaining >= maxShots ? "#fff29e" : "#ffffff")))
        .toJS;
    context.fillText(label, pillX + pillW * 0.5, pillY + 7.2);

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
    final bool lockedOnPlayer = trace.hasLivePlayerInPath;

    final String outerGlowRgb = lockedOnPlayer ? "32, 248, 112" : "255, 32, 48";
    final String coreBeamRgb = lockedOnPlayer ? "56, 255, 128" : "255, 48, 62";
    final String hotFilamentRgb =
        lockedOnPlayer ? "224, 255, 236" : "255, 232, 234";
    final String pierceGlowRgb =
        lockedOnPlayer ? "42, 240, 116" : "255, 52, 68";
    final String pierceDashRgb =
        lockedOnPlayer ? "96, 255, 156" : "255, 92, 102";

    final double startX = trace.start.x;
    final double startY = trace.start.y;
    final double dirX = trace.dir.x;
    final double dirY = trace.dir.y;
    final double solidEndDist = trace.terrainHitDistance ?? trace.totalDistance;
    final double solidEndX = startX + dirX * solidEndDist;
    final double solidEndY = startY + dirY * solidEndDist;

    context.save();
    context.lineCap = "round";

    // 1. Primary open-air laser beam (turns neon lock-on green when a live player is in path!).
    if (solidEndDist > 0.5) {
      context.strokeStyle = "rgba($outerGlowRgb, ${0.28 * alpha})".toJS;
      context.lineWidth = 6.5;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();

      context.strokeStyle = "rgba($coreBeamRgb, ${0.86 * alpha})".toJS;
      context.lineWidth = 2.2;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();

      context.strokeStyle = "rgba($hotFilamentRgb, ${0.94 * alpha})".toJS;
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
      context.strokeStyle = "rgba($pierceGlowRgb, ${0.24 * alpha})".toJS;
      context.lineWidth = 4.2;
      context.beginPath();
      for (double d = pierceStart + phase; d < trace.totalDistance; d += period) {
        final double segEnd = min(d + dashLen, trace.totalDistance);
        context.moveTo(startX + dirX * d, startY + dirY * d);
        context.lineTo(startX + dirX * segEnd, startY + dirY * segEnd);
      }
      context.stroke();

      // Crisp inner piercing laser dashes.
      context.strokeStyle = "rgba($pierceDashRgb, ${0.76 * alpha})".toJS;
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
      context.fillStyle = "rgba($coreBeamRgb, ${0.40 * alpha})".toJS;
      context.beginPath();
      context.arc(solidEndX, solidEndY, dotR * 2.1, 0, 2 * pi);
      context.fill();

      context.fillStyle = "rgba($hotFilamentRgb, ${0.95 * alpha})".toJS;
      context.beginPath();
      context.arc(solidEndX, solidEndY, dotR * 0.85, 0, 2 * pi);
      context.fill();
    }

    // 3. Target-lock laser reticle on any live enemy player along the snail's trajectory!
    for (final Vec2 hit in trace.playerHits) {
      final double lockPulse = 1.0 + 0.22 * sin(_laserTime * 20.0);
      final double ringR = 8.0 * lockPulse;
      context.strokeStyle = "rgba($coreBeamRgb, ${0.92 * alpha})".toJS;
      context.lineWidth = 2.0;
      context.beginPath();
      context.arc(hit.x, hit.y, ringR, 0, 2 * pi);
      context.stroke();

      // Crisp lock-on cardinal ticks around the green target ring.
      context.lineWidth = 1.6;
      context.beginPath();
      context.moveTo(hit.x - ringR - 3.5, hit.y);
      context.lineTo(hit.x - ringR + 1.5, hit.y);
      context.moveTo(hit.x + ringR - 1.5, hit.y);
      context.lineTo(hit.x + ringR + 3.5, hit.y);
      context.moveTo(hit.x, hit.y - ringR - 3.5);
      context.lineTo(hit.x, hit.y - ringR + 1.5);
      context.moveTo(hit.x, hit.y + ringR - 1.5);
      context.lineTo(hit.x, hit.y + ringR + 3.5);
      context.stroke();

      context.fillStyle = "rgba($hotFilamentRgb, ${0.96 * alpha})".toJS;
      context.beginPath();
      context.arc(hit.x, hit.y, 2.8, 0, 2 * pi);
      context.fill();
    }

    // 4. Tiny glowing emitter dot at the gun barrel tip.
    context.fillStyle = "rgba($coreBeamRgb, ${0.52 * alpha})".toJS;
    context.beginPath();
    context.arc(startX, startY, 3.8, 0, 2 * pi);
    context.fill();
    context.fillStyle = "rgba($hotFilamentRgb, ${0.95 * alpha})".toJS;
    context.beginPath();
    context.arc(startX, startY, 1.6, 0, 2 * pi);
    context.fill();

    context.restore();
  }

  static const double AIM_GUIDE_DISTANCE = 170.0;

  static WeaponBallisticsProfile ballisticsForWeapon(String weaponName) {
    switch (weaponName) {
      case "Zooka":
        return const WeaponBallisticsProfile(launchSpeed: 500.0, gravityAffect: 0.05);
      case "Neon Blaster":
        return const WeaponBallisticsProfile(launchSpeed: 150.0, gravityAffect: 0.0);
      case "Snailgun":
        return const WeaponBallisticsProfile(launchSpeed: 500.0, gravityAffect: 0.0);
      case "Jellybean Jet":
        return const WeaponBallisticsProfile(launchSpeed: 435.0, gravityAffect: 0.10);
      case "Dart gun":
        return const WeaponBallisticsProfile(launchSpeed: 530.0, gravityAffect: 0.30);
      case "Shotgun":
        return const WeaponBallisticsProfile(launchSpeed: 540.0, gravityAffect: 0.50);
      case "Brick builder":
        return const WeaponBallisticsProfile(launchSpeed: 500.0, gravityAffect: 1.0);
      case "Coffee Burn":
        return const WeaponBallisticsProfile(launchSpeed: 400.0, gravityAffect: 0.0);
      case "Pigeon Strike":
        return const WeaponBallisticsProfile(launchSpeed: 360.0, gravityAffect: 0.72);
      case "Turbo Mole":
        return const WeaponBallisticsProfile(launchSpeed: 320.0, gravityAffect: 0.85);
      case "Spiky Hedgehog":
        return const WeaponBallisticsProfile(launchSpeed: 240.0, gravityAffect: 1.0);
      case "Banana pancake":
      case "Angry Beehive":
        return const WeaponBallisticsProfile(launchSpeed: 200.0, gravityAffect: 1.0);
      case "Cat litter box":
        return const WeaponBallisticsProfile(launchSpeed: 100.0, gravityAffect: 1.0);
      default:
        return const WeaponBallisticsProfile(launchSpeed: 350.0, gravityAffect: 0.5);
    }
  }

  /// Computes a simple, static, fixed-distance ballistic aim guide from the gun
  /// muzzle based solely on `gun.angle` and the selected weapon's launch speed
  /// and gravity (ignoring player velocity and world terrain collisions).
  TrajectoryGuideTrace computeTrajectoryGuide() {
    final WeaponBallisticsProfile profile =
        ballisticsForWeapon(getSelectedWeapon().name);
    final Vec2 center = owner.centerPoint();
    final double dirX = cos(gun.angle);
    final double dirY = sin(gun.angle);
    final double muzzleOffset = gun.size.x * 0.5;

    final double startX = center.x + dirX * muzzleOffset;
    final double startY = center.y + dirY * muzzleOffset;
    final double vx = dirX * profile.launchSpeed;
    final double vy = dirY * profile.launchSpeed;

    double worldGravityY = 300.0;
    try {
      worldGravityY = world.gravity.y;
    } catch (_) {}
    final double gy = worldGravityY * profile.gravityAffect;

    const double dt = 0.025;
    const int maxSteps = 60;
    final List<Vec2> points = [Vec2(startX, startY)];
    double px = startX;
    double py = startY;
    double traveled = 0.0;

    for (int i = 1; i <= maxSteps; i++) {
      final double t = i * dt;
      final double nx = startX + vx * t;
      final double ny = startY + vy * t + 0.5 * gy * t * t;
      final double segDx = nx - px;
      final double segDy = ny - py;
      final double segLen = sqrt(segDx * segDx + segDy * segDy);

      if (traveled + segLen >= AIM_GUIDE_DISTANCE && segLen > 1e-6) {
        final double frac = (AIM_GUIDE_DISTANCE - traveled) / segLen;
        points.add(Vec2(px + segDx * frac, py + segDy * frac));
        break;
      }
      traveled += segLen;
      px = nx;
      py = ny;
      points.add(Vec2(px, py));
    }

    return TrajectoryGuideTrace(
      points: points,
      crosshair: points.last,
    );
  }

  void _drawTrajectoryGuide(CanvasRenderingContext2D context) {
    final TrajectoryGuideTrace guide = computeTrajectoryGuide();
    if (guide.points.length < 2) return;

    final double alpha = reloading() ? 0.32 : 0.82;
    final List<double> cumDist = [0.0];
    for (int i = 1; i < guide.points.length; i++) {
      final double dx = guide.points[i].x - guide.points[i - 1].x;
      final double dy = guide.points[i].y - guide.points[i - 1].y;
      cumDist.add(cumDist.last + sqrt(dx * dx + dy * dy));
    }
    final double totalArc = cumDist.last;
    if (totalArc < 6.0) return;

    context.save();
    context.globalAlpha = alpha;

    // Static, evenly-spaced guide dots out to the fixed crosshair distance.
    const double dotSpacing = 22.0;
    int segIdx = 0;
    for (double d = 18.0; d < totalArc - 14.0; d += dotSpacing) {
      while (segIdx < cumDist.length - 2 && cumDist[segIdx + 1] < d) {
        segIdx++;
      }
      final double segStart = cumDist[segIdx];
      final double segSpan = max(1e-6, cumDist[segIdx + 1] - segStart);
      final double t = ((d - segStart) / segSpan).clamp(0.0, 1.0);
      final double x = guide.points[segIdx].x +
          (guide.points[segIdx + 1].x - guide.points[segIdx].x) * t;
      final double y = guide.points[segIdx].y +
          (guide.points[segIdx + 1].y - guide.points[segIdx].y) * t;

      context.fillStyle = "rgba(16, 22, 34, 0.80)".toJS;
      context.beginPath();
      context.arc(x, y, 3.0, 0, 2 * pi);
      context.fill();

      context.fillStyle = "#fffdf0".toJS;
      context.beginPath();
      context.arc(x, y, 1.9, 0, 2 * pi);
      context.fill();
    }

    // Simple static crosshair reticle at the fixed endpoint.
    final Vec2 ch = guide.crosshair;
    const double ringR = 6.8;
    const double tickIn = 2.0;
    const double tickOut = 3.2;
    context.lineCap = "round";

    for (int pass = 0; pass < 2; pass++) {
      context.strokeStyle =
          (pass == 0 ? "rgba(16, 22, 34, 0.85)" : "#fffdf0").toJS;
      context.lineWidth = pass == 0 ? 3.0 : 1.5;
      context.beginPath();
      context.arc(ch.x, ch.y, ringR, 0, 2 * pi);
      context.moveTo(ch.x - ringR - tickOut, ch.y);
      context.lineTo(ch.x - ringR + tickIn, ch.y);
      context.moveTo(ch.x + ringR - tickIn, ch.y);
      context.lineTo(ch.x + ringR + tickOut, ch.y);
      context.moveTo(ch.x, ch.y - ringR - tickOut);
      context.lineTo(ch.x, ch.y - ringR + tickIn);
      context.moveTo(ch.x, ch.y + ringR - tickIn);
      context.lineTo(ch.x, ch.y + ringR + tickOut);
      context.stroke();
    }

    context.restore();
  }

  draw(CanvasRenderingContext2D context) {
    context.save();
    if (getSelectedWeapon().hasLaserSight) {
      _drawLaserSight(context);
    } else if (owner.drawWeaponHelpers()) {
      _drawTrajectoryGuide(context);
    }
    if (owner.drawWeaponHelpers()) {
      _drawMagazineIndicator(context);
      if (reloading()) {
        _drawReloadIndicator(context);
      }
    }
    context.restore();
  }

  /// Draws a fresh cartoon reload widget cleanly above the clip size indicator:
  /// a compact glossy rounded pill with a spinning cartoon reload arrow glyph
  /// and a smooth candy-gradient progress bar with gliding shine.
  void _drawReloadIndicator(CanvasRenderingContext2D context) {
    final Weapon weapon = getSelectedWeapon();
    final double progress = weapon.reloadTime > 0.0
        ? (1.0 - (weapon.untilReload / weapon.reloadTime)).clamp(0.0, 1.0)
        : 1.0;

    final Vec2 center = owner.centerPoint();
    final double bobY = sin(_laserTime * 7.5) * 1.2;
    const double pillW = 62.0;
    const double pillH = 15.0;
    const double radius = pillH * 0.5;
    final double pillX = center.x - pillW * 0.5;
    final double pillY = owner.position.y - 31.0 + bobY;

    context.save();
    context.globalAlpha = 0.95;

    // Cartoon drop shadow.
    context.fillStyle = "rgba(10, 16, 28, 0.45)".toJS;
    context.beginPath();
    context.roundRect(pillX + 1.4, pillY + 1.8, pillW, pillH, radius.toJS);
    context.fill();

    // Glossy cartoon slate-navy capsule body.
    final CanvasGradient bodyGrad =
        context.createLinearGradient(0, pillY, 0, pillY + pillH);
    bodyGrad.addColorStop(0.0, "#243b5c");
    bodyGrad.addColorStop(1.0, "#132036");
    context.fillStyle = bodyGrad;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.fill();

    // Glossy top shine strip.
    context.fillStyle = "rgba(255, 255, 255, 0.16)".toJS;
    context.beginPath();
    context.roundRect(
        pillX + 3.0, pillY + 1.2, pillW - 6.0, pillH * 0.36, (radius * 0.5).toJS);
    context.fill();

    // Bold cartoon ink border + subtle golden accent rim.
    context.strokeStyle = "#0e1726".toJS;
    context.lineWidth = 2.0;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.stroke();

    // Spinning circular reload arrow icon on the left side of the pill.
    final double iconCx = pillX + 9.0;
    final double iconCy = pillY + pillH * 0.5;
    const double iconR = 4.2;
    context.save();
    context.translate(iconCx, iconCy);
    context.rotate(_laserTime * 6.5);
    context.strokeStyle = "#ffe454".toJS;
    context.fillStyle = "#ffe454".toJS;
    context.lineWidth = 1.6;
    context.lineCap = "round";
    for (int half = 0; half < 2; half++) {
      final double startA = half * pi + 0.35;
      final double endA = startA + pi * 0.65;
      context.beginPath();
      context.arc(0, 0, iconR, startA, endA);
      context.stroke();

      // Tiny arrowhead at end of arc.
      final double ax = cos(endA) * iconR;
      final double ay = sin(endA) * iconR;
      final double tangent = endA + pi * 0.5;
      context.beginPath();
      context.moveTo(ax + cos(tangent) * 2.2, ay + sin(tangent) * 2.2);
      context.lineTo(ax + cos(endA) * 1.9 - cos(tangent) * 1.2,
          ay + sin(endA) * 1.9 - sin(tangent) * 1.2);
      context.lineTo(ax - cos(endA) * 1.7 - cos(tangent) * 1.2,
          ay - sin(endA) * 1.7 - sin(tangent) * 1.2);
      context.closePath();
      context.fill();
    }
    context.restore();

    // Smooth candy-gradient reload progress track to the right of the icon.
    final double trackX = pillX + 16.5;
    final double trackW = pillW - 21.5;
    const double trackH = 7.0;
    final double trackY = pillY + (pillH - trackH) * 0.5;
    const double trackR = trackH * 0.5;

    context.fillStyle = "rgba(8, 14, 24, 0.82)".toJS;
    context.beginPath();
    context.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
    context.fill();

    if (progress > 0.0) {
      context.save();
      context.beginPath();
      context.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
      context.clip();

      final double fillW = max(trackH * 0.6, trackW * progress);
      final CanvasGradient fillGrad =
          context.createLinearGradient(trackX, 0, trackX + trackW, 0);
      fillGrad.addColorStop(0.0, "#47f0ff");
      fillGrad.addColorStop(0.55, "#6dff8f");
      fillGrad.addColorStop(1.0, "#ffe44d");
      context.fillStyle = fillGrad;
      context.fillRect(trackX, trackY, fillW, trackH);

      // Gliding cartoon shine highlight across the reload bar.
      final double sheenX =
          trackX + ((_laserTime * 75.0) % (trackW + 24.0)) - 12.0;
      final CanvasGradient sheen =
          context.createLinearGradient(sheenX - 7.0, 0, sheenX + 7.0, 0);
      sheen.addColorStop(0.0, "rgba(255, 255, 255, 0.0)");
      sheen.addColorStop(0.5, "rgba(255, 255, 255, 0.62)");
      sheen.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
      context.fillStyle = sheen;
      context.fillRect(trackX, trackY, fillW, trackH);

      // Glossy top highlight.
      context.fillStyle = "rgba(255, 255, 255, 0.34)".toJS;
      context.fillRect(trackX, trackY + 0.6, fillW, trackH * 0.36);
      context.restore();
    }

    context.strokeStyle = "rgba(255, 255, 255, 0.30)".toJS;
    context.lineWidth = 0.9;
    context.beginPath();
    context.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
    context.stroke();

    context.restore();
  }

  /// Draws a discreet cartoon magazine indicator above the local player:
  /// - Small clips (<= 6 shots): individual rounded ammo pips.
  /// - Large clips (> 6 shots): a slim rounded cartoon ammo bar.
  void _drawMagazineIndicator(CanvasRenderingContext2D context) {
    final Weapon weapon = getSelectedWeapon();
    final int maxShots = weapon.shotsPerClip;
    if (maxShots <= 0) return;

    final bool isReloading = reloading();
    final int remaining = isReloading ? 0 : weapon.shotsLeft.clamp(0, maxShots);
    final double frac = remaining / maxShots;
    final Vec2 center = owner.centerPoint();
    final double baseY = owner.position.y - 10.0;
    // Stay subtle when full, become clearly visible as the clip drains or reloads.
    final bool isFull = !isReloading && remaining >= maxShots;
    final bool isLow = !isReloading && (remaining == 1 || frac <= 0.25);
    final double alpha = _reloadReadyFlash > 0.0
        ? 0.96
        : (isFull ? 0.45 : (isReloading ? 0.72 : 0.88));
    final double popScale = 1.0 + _reloadReadyFlash * 0.16;

    context.save();
    context.globalAlpha = alpha;
    if (_reloadReadyFlash > 0.01) {
      context.translate(center.x, baseY);
      context.scale(popScale, popScale);
      context.translate(-center.x, -baseY);
    }

    if (maxShots <= 6) {
      final double pipW = maxShots == 1 ? 12.0 : 7.0;
      final double pipH = 5.0;
      final double gap = 3.0;
      final double totalW = maxShots * pipW + (maxShots - 1) * gap;
      final double startX = center.x - totalW * 0.5;
      final double y = baseY - pipH * 0.5;
      final double r = pipH * 0.5;

      for (int i = 0; i < maxShots; i++) {
        final double x = startX + i * (pipW + gap);
        final bool filled = i < remaining;
        if (filled) {
          context.fillStyle = (isLow ? "#ff7a45" : "#ffe252").toJS;
        } else {
          context.fillStyle = "rgba(18, 24, 36, 0.55)".toJS;
        }
        context.beginPath();
        context.roundRect(x, y, pipW, pipH, r.toJS);
        context.fill();

        if (filled) {
          context.fillStyle = "rgba(255, 255, 255, 0.45)".toJS;
          context.fillRect(x + 1.0, y + 0.7, pipW - 2.0, pipH * 0.35);
        }

        context.strokeStyle = "#121b28".toJS;
        context.lineWidth = 1.3;
        context.beginPath();
        context.roundRect(x, y, pipW, pipH, r.toJS);
        context.stroke();
      }
    } else {
      const double barW = 38.0;
      const double barH = 5.0;
      final double x = center.x - barW * 0.5;
      final double y = baseY - barH * 0.5;
      const double r = barH * 0.5;

      // Dark trough.
      context.fillStyle = "rgba(18, 24, 36, 0.72)".toJS;
      context.beginPath();
      context.roundRect(x, y, barW, barH, r.toJS);
      context.fill();

      // Clipped ammo fill.
      if (frac > 0.0) {
        context.save();
        context.beginPath();
        context.roundRect(x, y, barW, barH, r.toJS);
        context.clip();
        final double fillW = barW * frac;
        context.fillStyle = (isLow ? "#ff684a" : "#ffe054").toJS;
        context.fillRect(x, y, fillW, barH);
        context.fillStyle = "rgba(255, 255, 255, 0.38)".toJS;
        context.fillRect(x, y + 0.6, fillW, barH * 0.38);
        context.restore();
      }

      // Crisp thin comic border.
      context.strokeStyle = "#121b28".toJS;
      context.lineWidth = 1.4;
      context.beginPath();
      context.roundRect(x, y, barW, barH, r.toJS);
      context.stroke();
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

  bool get hasLivePlayerInPath => playerHits.isNotEmpty;

  String get beamColorMode => hasLivePlayerInPath ? "green" : "red";

  Vec2 get end =>
      Vec2(start.x + dir.x * totalDistance, start.y + dir.y * totalDistance);
}

class WeaponBallisticsProfile {
  final double launchSpeed;
  final double gravityAffect;

  const WeaponBallisticsProfile({
    required this.launchSpeed,
    required this.gravityAffect,
  });
}

class TrajectoryGuideTrace {
  final List<Vec2> points;
  final Vec2 crosshair;

  const TrajectoryGuideTrace({
    required this.points,
    required this.crosshair,
  });
}