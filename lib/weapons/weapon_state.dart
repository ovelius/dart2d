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
  WormWorld world;
  LocalPlayerSprite owner;
  Sprite gun;
  MobileControls? mobileControls;
  
  double changeTime = 0.0;
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
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 8, positionBase:weaponState.owner.gun);
      sprite.mod = Mod.DARTGUN;
      sprite.owner = weaponState.owner;
      double sum = sprite.velocity.sum();
      sprite.velocity.x = sprite.velocity.x + random.nextDouble() * sum / 8;
      sprite.velocity.y = sprite.velocity.y + random.nextDouble() * sum / 8;
      sprite.gravityAffect = 0.3;
      sprite.size = new Vec2(20.0, 6.0);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("dart.png"), 1);
      sprite.radius = 2.0;
      sprite.spawn_sound = Sound.DARTGUN;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Jellybean Jet", 8, 40, 9.0, .11, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 8, positionBase:weaponState.owner.gun);
      sprite.mod = Mod.TV;
      sprite.spriteType = SpriteType.CIRCLE;
      double a = random.nextDouble() + 0.2;
      sprite.color = "rgba(${random.nextInt(255)}, ${random.nextInt(255)}, ${random.nextInt(255)}, $a)";
      sprite.owner = weaponState.owner;
      sprite.explodeAfter = 15.0;
      sprite.health = 5;
      sprite.spawn_sound = Sound.BLUBB;
      sprite.velocity = sprite.velocity.multiply(0.8);
      double sum = sprite.velocity.sum();
      sprite.velocity.x = sprite.velocity.x + random.nextDouble() * sum / 8;
      sprite.velocity.y = sprite.velocity.y + random.nextDouble() * sum / 8;
      sprite.gravityAffect = 0.1;
      sprite.bounche = 0.99;
      sprite.size = new Vec2(4.0, 4.0);
      sprite.radius = -1.0;
      sprite.showCounter = false;
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
          radius: 10.0, count: 5, lifeTime: 65, shrinkPerStep:-0.3, particleType: ParticleEffects_ParticleType.FIRE);
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
    }),
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
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 40, positionBase:weaponState.owner.gun);
      sprite.mod = Mod.ZOOKA;
      sprite.spawn_sound = Sound.ZOOKA;
      sprite.radius = 40.0;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.05;
      // sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("zooka.png"), 1);
      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2));
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }),
    new Weapon("Neon Blaster",7, 5, 2.5, 1.20, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new Hyper.createWithOwner(weaponState.world, weaponState.owner, 30, weaponState.owner.gun);
      sprite.radius = 25.0;
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
    weapons[selectedWeaponIndex].think(duration);
  }

  weaponStateSelector(Point<int> delta) {
    changeTime = SHOW_WEAPON_NAME_TIME;


    double wheelRadius = 145;
    double currentAngle = 0.0;
    int weaponCount = weapons.length;
    int closestWeapon = 0;
    double closest = 9999999.0;

    for (int i = 0; i < weaponCount; i++) {
      double deltaX = ((sin(currentAngle) * wheelRadius) - ICON_SIZE_HALF) + delta.x;
      double deltaY = ((cos(currentAngle) * wheelRadius) - ICON_SIZE_HALF) + delta.y;
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

    double wheelRadius = 145;
    double currentAngle = 0.0;

    for (int i = 0; i < weaponCount; i++) {
      double x = sin(currentAngle) * wheelRadius;
      double y = cos(currentAngle) * wheelRadius;
      if (selectedWeaponIndex == i) {
        context.globalAlpha = 1.0;
      } else {
        context.globalAlpha = 0.5;
      }
      _drawIconImageAt(context, iconImages,
          weapons[i].iconIndex,  baseX + x,  baseY + y);
      currentAngle += _anglePerWeapon;
    }
    // Draw the weapon name.
    context.font = '16pt Calibri';
    context.fillStyle = "rgb(255,255,255)".toJS;
    String selectedWeaponName = weapons[selectedWeaponIndex].name;
    TextMetrics metrics = context.measureText(selectedWeaponName);
    context.globalAlpha = 1.0;
    num textY = center.y - WeaponState.ICON_SIZE_HALF;
    if (textY < 0) {
      textY = center.y + WeaponState.ICON_SIZE_HALF;
    }
    context.fillText(selectedWeaponName, center.x - metrics.width /2, textY);
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

  draw(CanvasRenderingContext2D context) {
    if (owner.drawWeaponHelpers()) {
      double radius = owner.getRadius();
      context.fillStyle = "#ffffff".toJS;
      Vec2 center = owner.centerPoint();
      if (reloading()) {
        double percentInverse = (100 - reloadPercent()) / 100.0;
        double circle = pi * 2 * percentInverse - pi/2;

        context.save();
        if (changeTime <= 0) {
          context.fillText("Reloading",
              center.x, center.y - owner.size.y);
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
  }

  bool reloading() => weapons[selectedWeaponIndex].reloading();
  int reloadPercent() => weapons[selectedWeaponIndex].reloadPercent();
}