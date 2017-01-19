library weapon_state;

import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';
import 'package:dart2d/phys/vec2.dart';

class WeaponState {
  static const double SHOW_WEAPON_NAME_TIME = 0.5;
  WormWorld world;
  KeyState keyState;
  LocalPlayerSprite owner;
  Sprite gun;
  
  double changeTime = 0.0;
  int selectedWeaponIndex = 2;

  int manualReloadPercent = null;

  List<Weapon> weapons = [
    new Weapon("Banana pancake", 2, 5.0, 1.0, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BananaCake.createWithOwner(weaponState.world, weaponState.gun, 50);
      sprite.explodeAfter = 4.0;
      sprite.owner = weaponState.owner;
      sprite.radius = 50.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Shotgun", 4, 2.0, .8, (WeaponState weaponState) {
      Random r = new Random();
      for (int i = 0; i < 8; i++) {
        WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 15);
        sprite.spriteType = SpriteType.RECT;
        sprite.owner = weaponState.owner;
        double sum = sprite.velocity.sum();
        sprite.velocity.x = sprite.velocity.x + r.nextDouble() * sum / 8;
        sprite.velocity.y = sprite.velocity.y + r.nextDouble() * sum / 8;
        // Add recoil in y axis only.
        weaponState.owner.velocity.y -= sprite.velocity.y * 0.1;

        sprite.gravityAffect = 0.5;
        
        sprite.size = new Vec2(8.0, 8.0);
        sprite.radius = 8.0;
        weaponState.world.addSprite(sprite);
      }
    }),
    new Weapon("Dart gun", 120, 6.0, .07, (WeaponState weaponState) {
      Random r = new Random();
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 5);
      sprite.spriteType = SpriteType.RECT;
      sprite.owner = weaponState.owner;
      double sum = sprite.velocity.sum();
      sprite.velocity.x = sprite.velocity.x + r.nextDouble() * sum / 8;
      sprite.velocity.y = sprite.velocity.y + r.nextDouble() * sum / 8;
      sprite.gravityAffect = 0.3;
      sprite.size = new Vec2(5.0, 5.0);
      sprite.radius = 2.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Cofee Burn", 150, 2.0, .05, (WeaponState weaponState) {
      Vec2 vel = new Vec2(cos(weaponState.gun.angle), sin(weaponState.gun.angle));
      Vec2 position = weaponState.gun.centerPoint();
      double gunRadius = weaponState.gun.size.sum() / 2;
      position.x += cos(weaponState.gun.angle) * gunRadius;
      position.y += sin(weaponState.gun.angle) * gunRadius;
      Particles p = new Particles(
          weaponState.world,
          null, position, vel.multiply(200.0),
          8.0, 5, 45, -0.3, Particles.FIRE);
      p.sendToNetwork = true;
      p.world = weaponState.world;
      p.damage = 22;
      weaponState.world.addSprite(p);
    }),
    new Weapon("Cat litter box", 1, 5.0, 0.01, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 100);
      sprite.radius = 150.0;
      sprite.owner = weaponState.owner;
      sprite.explodeAfter = 5.0;
      sprite.size = new Vec2(140.0 * 0.3, 129.0 * 0.3);
      sprite.angle = 0.0;
      sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex.getImageIdByName("box.png"), 140);
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Zooka", 3, 3.0, 1.0, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 40);
      sprite.radius = 40.0;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.0;
      // sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex.getImageIdByName("zooka.png"));
      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2));
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }),
  ];
  
  WeaponState(this.world, this.keyState, this.owner, this.gun);
  
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
  
  draw(var /*CanvasRenderingContext2D*/ context) {
    if (owner.drawWeaponHelpers()) {
      context.fillStyle = "#ffffff";
      Vec2 center = owner.centerPoint();
      if (changeTime > 0) {
        var metrics =
        context.measureText(weapons[selectedWeaponIndex].name);
        context.fillText(
            weapons[selectedWeaponIndex].name, center.x - metrics.width / 2,
            center.y - owner.size.y);
      }
      if (reloading()) {
        context.fillText(reloadPercent().toString(),
            center.x, center.y - owner.size.y);
      }
    }
  }

  bool reloading() => manualReloadPercent != null || weapons[selectedWeaponIndex].reloading();
  int reloadPercent() => manualReloadPercent == null ? weapons[selectedWeaponIndex].reloadPercent() : manualReloadPercent;
}