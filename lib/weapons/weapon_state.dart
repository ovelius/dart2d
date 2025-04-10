library weapon_state;

import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'dart:math';
import 'package:dart2d/phys/vec2.dart';

import '../net/state_updates.pb.dart';

class WeaponState {
  static Random random = new Random();
  static const double SHOW_WEAPON_NAME_TIME = .9;
  WormWorld world;
  //KeyState keyState;
  LocalPlayerSprite owner;
  Sprite gun;
  
  double changeTime = 0.0;
  bool _forwardChange = true;
  String _longestWeaponName = "";
  int selectedWeaponIndex = 2;

  String get selectedWeaponName => weapons[selectedWeaponIndex].name;


  WeaponState(this.world, this.owner, this.gun) {
    for (Weapon w in weapons) {
      if (w.name.length > _longestWeaponName.length) {
        _longestWeaponName = w.name;
      }
    }
  }

  Weapon getSelectedWeapon() => weapons[selectedWeaponIndex];

  List<Weapon> weapons = [
    new Weapon("Banana pancake", 2, 5.0, 1.0, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BananaCake.createWithOwner(weaponState.world,  weaponState.owner, 50, weaponState.owner.gun);
      sprite.explodeAfter = 4.0;
      sprite.owner = weaponState.owner;
      sprite.radius = 50.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Brick builder", 20, 5.0, 0.3, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BrickBuilder.createWithOwner(weaponState.world, weaponState.owner, 2, weaponState.owner.gun);
      sprite.mod = Mod.BRICK;
      sprite.owner = weaponState.owner;
      sprite.radius = 50.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Shotgun", 4, 2.0, .8, (WeaponState weaponState) {
      for (int i = 0; i < 8; i++) {
        WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 7, weaponState.owner.gun);
        sprite.mod = Mod.SHOTGUN;
        sprite.spriteType = SpriteType.RECT;
        sprite.owner = weaponState.owner;
        double sum = sprite.velocity.sum();
        sprite.velocity.x = sprite.velocity.x + random.nextDouble() * sum / 8;
        sprite.velocity.y = sprite.velocity.y + random.nextDouble() * sum / 8;
        // Add recoil in y axis only.
        weaponState.owner.velocity.y -= sprite.velocity.y * 0.1;

        sprite.gravityAffect = 0.5;
        
        sprite.size = new Vec2(8.0, 8.0);
        sprite.radius = 8.0;
        weaponState.world.addSprite(sprite);
      }
    }),
    new Weapon("Dart gun", 120, 6.0, .07, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 8, weaponState.owner.gun);
      sprite.mod = Mod.DARTGUN;
      sprite.spriteType = SpriteType.RECT;
      sprite.owner = weaponState.owner;
      double sum = sprite.velocity.sum();
      sprite.velocity.x = sprite.velocity.x + random.nextDouble() * sum / 8;
      sprite.velocity.y = sprite.velocity.y + random.nextDouble() * sum / 8;
      sprite.gravityAffect = 0.3;
      sprite.size = new Vec2(5.0, 5.0);
      sprite.radius = 2.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("TV Commercial", 40, 9.0, .11, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 8, weaponState.owner.gun);
      sprite.mod = Mod.TV;
      sprite.spriteType = SpriteType.CIRCLE;
      double a = random.nextDouble() + 0.2;
      sprite.color = "rgba(${random.nextInt(255)}, ${random.nextInt(255)}, ${random.nextInt(255)}, $a)";
      sprite.owner = weaponState.owner;
      sprite.explodeAfter = 15.0;
      sprite.velocity = sprite.velocity.multiply(0.2);
      double sum = sprite.velocity.sum();
      sprite.velocity.x = sprite.velocity.x + random.nextDouble() * sum / 8;
      sprite.velocity.y = sprite.velocity.y + random.nextDouble() * sum / 8;
      sprite.gravityAffect = 1.5;
      sprite.bounche = 0.99;
      sprite.size = new Vec2(4.0, 4.0);
      sprite.radius = -1.0;
      sprite.showCounter = false;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Coffee Burn", 150, 2.0, .05, (WeaponState weaponState) {
      Vec2 vel = new Vec2(cos(weaponState.gun.angle), sin(weaponState.gun.angle));
      Vec2 position = weaponState.gun.centerPoint();
      double gunRadius = weaponState.gun.size.sum() / 2;
      position.x += cos(weaponState.gun.angle) * gunRadius;
      position.y += sin(weaponState.gun.angle) * gunRadius;
      Particles p = new Particles(
          weaponState.world,
          null, position, vel.multiply(200.0),
          null, 8.0, 5, 45, -0.3, ParticleEffects_ParticleType.FIRE);
      p.sendToNetwork = true;
      p.world = weaponState.world;
      p.collision = true;
      p.damage = 5;
      p.owner = weaponState.owner;
      weaponState.world.addSprite(p);
    }),
    new Weapon("Cat litter box", 1, 5.0, 0.01, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 100, weaponState.owner.gun);
      sprite.mod = Mod.LITTER;
      sprite.radius = 150.0;
      sprite.owner = weaponState.owner;
      sprite.explodeAfter = 5.0;
      sprite.size = new Vec2(140.0 * 0.3, 129.0 * 0.3);
      sprite.angle = 0.0;
      sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("box.png"), 140);
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
    new Weapon("Zooka", 5, 2.5, 0.8, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 40, weaponState.owner.gun);
      sprite.mod = Mod.ZOOKA;
      sprite.radius = 40.0;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.05;
      // sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("zooka.png"));
      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2));
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }),
    new Weapon("Neon Blaster", 5, 2.5, 1.20, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new Hyper.createWithOwner(weaponState.world, weaponState.owner, 30);
      sprite.radius = 25.0;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.00;
      weaponState.world.addSprite(sprite);
    }),
  ];
  
  nextWeapon() {
    _forwardChange = true;
    selectedWeaponIndex++;
    selectedWeaponIndex = selectedWeaponIndex % weapons.length;
    changeTime = SHOW_WEAPON_NAME_TIME;
  }
  
  prevWeapon() {
    _forwardChange = false;
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

  _drawChangeTime(var context, Vec2 center) {
    double halfTime = SHOW_WEAPON_NAME_TIME / 2;
    double changeTimePercentLeft = changeTime < halfTime ? 0.0 :
    (changeTime - halfTime) / halfTime;
    double changeTimePercenLeftInverse = 1.0 - changeTimePercentLeft;
    context.save();
    context.font = '16pt Calibri';
    var metrics = context.measureText(_longestWeaponName);
    double baseX = center.x - metrics.width / 2;
    double baseY = center.y - owner.size.y;
    int textDistance = 20;
    double nextPrevY = baseY + textDistance;
    int next = ((selectedWeaponIndex + 1) % weapons.length);
    int prev = ((selectedWeaponIndex - 1 + weapons.length) % weapons.length);
    if (_forwardChange) {
      int prevPrev = ((selectedWeaponIndex - 2 + weapons.length) % weapons.length);

      double nextXTravel =  (metrics.width + textDistance) * changeTimePercentLeft;

      context.fillText(weapons[selectedWeaponIndex].name, baseX + nextXTravel, baseY + (textDistance * changeTimePercentLeft));

      context.fillText(
          weapons[prev].name, baseX - (metrics.width - textDistance) * changeTimePercenLeftInverse,  baseY + textDistance * changeTimePercenLeftInverse);
      context.globalAlpha = changeTimePercenLeftInverse;
      context.fillText(
          weapons[next].name, baseX + metrics.width + textDistance,
          nextPrevY + (textDistance + textDistance) * changeTimePercentLeft);
      context.globalAlpha = changeTimePercentLeft;
      context.fillText(
          weapons[prevPrev].name, baseX - metrics.width - textDistance,
          nextPrevY + (textDistance + textDistance) * changeTimePercenLeftInverse);
    } else {
      int nextNext = ((selectedWeaponIndex + 2) % weapons.length);

      double nextXTravel =  (metrics.width + textDistance) * changeTimePercentLeft;

      context.fillText(weapons[selectedWeaponIndex].name, baseX - nextXTravel, baseY + (textDistance * changeTimePercentLeft));

      context.fillText(
          weapons[next].name, baseX + (metrics.width - textDistance) * changeTimePercenLeftInverse,  baseY + textDistance * changeTimePercenLeftInverse);

      context.globalAlpha = changeTimePercenLeftInverse;
      context.fillText(
          weapons[prev].name, baseX - metrics.width - textDistance,
          nextPrevY + (textDistance + textDistance) * changeTimePercentLeft);
      context.globalAlpha = changeTimePercentLeft;
      context.fillText(
          weapons[nextNext].name, baseX + metrics.width + textDistance,
          nextPrevY + (textDistance + textDistance) * changeTimePercenLeftInverse);
    }

    context.restore();
  }

  draw(var /*CanvasRenderingContext2D*/ context) {
    if (owner.drawWeaponHelpers()) {
      double radius = owner.getRadius();
      context.fillStyle = "#ffffff";
      Vec2 center = owner.centerPoint();
      if (changeTime > 0) {
        // TODO make nicer animation!
        _drawChangeTime(context, center);
      }
      if (reloading()) {
        double percentInverse = (100 - reloadPercent()) / 100.0;
        double circle = pi * 2 * percentInverse - pi/2;

        context.save();
        if (changeTime <= 0) {
          context.fillText("Reloading",
              center.x, center.y - owner.size.y);
          context.beginPath();
        }

        context.fillStyle = "#009900";
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