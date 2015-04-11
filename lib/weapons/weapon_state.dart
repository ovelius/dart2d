import 'package:dart2d/keystate.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/sprites/world_damage_projectile.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';
import 'dart:html';
import 'package:dart2d/phys/vec2.dart';

class WeaponState {
  static const double SHOW_WEAPON_NAME_TIME = 0.5;
  World world;
  KeyState keyState;
  Sprite owner;
  Sprite gun;
  
  double changeTime = 0.0;
  int weaponIndex = 2;
  
  List<Weapon> weapons = [
    new Weapon("Banana pancake", 2, 5.0, 1.0, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BananaCake.createWithOwner(weaponState.world, weaponState.gun, 50);
      sprite.explodeAfter = 4.0;
      sprite.radius = 50.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Shotgun", 4, 2.0, .8, (WeaponState weaponState) {
      Random r = new Random();
      for (int i = 0; i < 10; i++) {
        WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 15);
        sprite.spriteType = SpriteType.RECT;
        double sum = sprite.velocity.sum();
        sprite.velocity.x = sprite.velocity.x + r.nextDouble() * sum / 8;
        sprite.velocity.y = sprite.velocity.y + r.nextDouble() * sum / 8;
           
        sprite.gravityAffect = 0.5;
        
        sprite.size = new Vec2(8.0, 8.0);
        sprite.radius = 8.0;
        weaponState.world.addSprite(sprite);
      }
    }),
    new Weapon("Cofee Burn", 150, 2.0, .05, (WeaponState weaponState) {
      Vec2 vel = new Vec2(cos(weaponState.gun.angle), sin(weaponState.gun.angle));
      Particles p = new Particles(
          null, weaponState.owner.position, vel.multiply(200.0),
          8.0, 5, 45, -0.3, Particles.FIRE);
      p.world = weaponState.world;
      p.damage = 22;
      weaponState.world.addSprite(p);
    }),
    new Weapon("Zooka", 3, 5.0, 1.0, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 40);
      sprite.radius = 30.0;
      sprite.gravityAffect = 0.0;
      // sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(imageByName["zooka.png"]);
      weaponState.world.addSprite(sprite);
      Particles p = new Particles(sprite, sprite.position, sprite.velocity.multiply(0.2));
      weaponState.world.addSprite(p);
    }),
  ];
  
  WeaponState(this.world, this.keyState, this.owner, this.gun);
  
  nextWeapon() {
    weaponIndex++;
    weaponIndex = weaponIndex % weapons.length;
    changeTime = SHOW_WEAPON_NAME_TIME;
  }
  
  prevWeapon() {
    weaponIndex--;
    if (weaponIndex < 0) {
      weaponIndex = weapons.length - 1;
    }
    changeTime = SHOW_WEAPON_NAME_TIME;
  }
  
  fire() {
    weapons[weaponIndex].fireButton(this);
  }
  
  think(double duration) {
    changeTime -= duration;
    weapons[weaponIndex].think(duration);
  }
  
  draw(CanvasRenderingContext2D context) {
    context.fillStyle = "#ffffff";
    Vec2 center = owner.centerPoint();
    if (changeTime > 0) {
      TextMetrics metrics = 
        context.measureText(weapons[weaponIndex].name);
      context.fillText(weapons[weaponIndex].name, center.x - metrics.width/2, center.y - owner.size.y);
    }
    if (weapons[weaponIndex].reloading()) {
      context.fillText(weapons[weaponIndex].reloadPercent().toString(),
          center.x, center.y - owner.size.y);
    }
  }
  
}