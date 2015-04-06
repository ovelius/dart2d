import 'package:dart2d/keystate.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/sprites/world_damage_projectile.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';
import 'dart:html';
import 'package:dart2d/phys/vec2.dart';

class WeaponState {
  World world;
  KeyState keyState;
  Sprite owner;
  
  double fireRate = 0.5;
  double untilNextFire = 0.0;
  
  int weaponIndex = 2;
  
  List<dynamic> weapons = [
    (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BananaCake.createWithOwner(weaponState.world, weaponState.owner, 3);
      sprite.explodeAfter = 4.0;
      sprite.radius = 50.0;
      weaponState.world.addSprite(sprite);
    },
    (WeaponState weaponState) {
      Random r = new Random();
      for (int i = 0; i < 10; i++) {
        WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 3);
        sprite.spriteType = SpriteType.RECT;
        double sum = sprite.velocity.sum();
        sprite.velocity.x = sprite.velocity.x + r.nextDouble() * sum / 8;
        sprite.velocity.y = sprite.velocity.y + r.nextDouble() * sum / 8;
           
        sprite.gravityAffect = 0.5;
        
        sprite.size = new Vec2(2.0, 2.0);
        sprite.radius = 8.0;
        weaponState.world.addSprite(sprite);
      }
    },
    (WeaponState weaponState) {
         WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.owner, 3);
         sprite.radius = 30.0;
         sprite.gravityAffect = 0.0;
        // sprite.velocity = sprite.velocity.multiply(0.2);
         sprite.setImage(imageByName["zooka.png"]);
         weaponState.world.addSprite(sprite);
         Particles p = new Particles(sprite, sprite.velocity.multiply(0.2));
         weaponState.world.addSprite(p);
       },
  ];
  
  WeaponState(this.world, this.keyState, this.owner);
  
  nextWeapon() {
    weaponIndex++;
    weaponIndex = weaponIndex % weapons.length;
  }
  
  prevWeapon() {
    weaponIndex--;
    if (weaponIndex < 0) {
      weaponIndex = weapons.length - 1;
    }
  }
  
  fire(double duration) {
    untilNextFire -= duration;
    if (untilNextFire < 0) {
      untilNextFire = fireRate;
    } else {
      return;
    }
    weapons[weaponIndex](this);
  }
}