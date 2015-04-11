library world_damage_projectile; 

import 'movingsprite.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/sprites/animation.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';

class BananaCake extends WorldDamageProjectile {
  BananaCake(double x, double y, int imageIndex, [int width, int height])
       : super(x, y, imageIndex, width, height);
 
  BananaCake.createWithOwner(WormWorld world, MovingSprite owner, int damage, [double homingFactor])
       : super(0.0, 0.0, imageByName["cake.png"]) {
      this.world = world;
      this.owner = owner;
      this.damage = damage;
      Vec2 ownerCenter = owner.centerPoint();
      this.size = new Vec2(15.0, 17.0);
      this.position.x = ownerCenter.x - size.x / 2;
      this.position.y = ownerCenter.y - size.y / 2;
      this.spriteType = SpriteType.IMAGE;
      this.velocity.x = cos(owner.angle);
     // this.angle = owner.angle;
      this.velocity.y = sin(owner.angle);
      this.outOfBoundsMovesRemaining = 2;
      this.velocity = this.velocity.multiply(200.0);
      this.velocity = owner.velocity + this.velocity;
    }
  
  explode() {
    world.explosionAtSprite(this, this.velocity.multiply(0.2), damage, radius);
    Random r = new Random();
    for (int i = 0; i < 5; i++) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(world, this, 30);
      sprite.setImage(imageByName["banana.png"]);
      sprite.velocity.x = -PI * 2; 
      sprite.velocity.y = -PI * 2; 
      sprite.velocity.x += r.nextDouble() * PI * 4;
      sprite.velocity.y += r.nextDouble() * PI * 4;
      sprite.velocity = sprite.velocity.normalize().multiply(500.0);
      sprite.velocity = velocity + sprite.velocity;
      sprite.rotationVelocity = r.nextDouble() * 200.1;
      sprite.radius = 30.0;
      world.addSprite(sprite);
    }
    this.remove = true;
  }
}

class WorldDamageProjectile extends MovingSprite {

  WormWorld world;
  MovingSprite owner;
  int damage = 1;

  double bounche = 0.5;
  
  double radius = 15.0;

  double explodeAfter = null;
  
  WorldDamageProjectile(double x, double y, int imageIndex, [int width, int height])
      : super(x, y, imageIndex, width, height);

  collide(MovingSprite other, ByteWorld world, int direction) {
    assert(owner != null);
    if (other == null) {
      // World collide.
      
    }
    if (other != null && other != owner && other.takesDamage()) {
      other.takeDamage(this.owner, damage);
      this.remove = true;
    }
     
    if (world != null && other == null) {
      handleWorldCollide(world, direction);
    }
    // Do animation stuff.

  }
  
  handleWorldCollide(ByteWorld world, int direction) {
    if (explodeAfter == null) {
      explode();
    } else {
      if (direction == MovingSprite.DIR_BELOW) {
        if (velocity.y > 0) {
          velocity.y = -velocity.y * bounche;
        }
      } else if(direction == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * bounche;
        }
      } else  if(direction == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          velocity.x = -velocity.x * bounche;
        }
      } else  if(direction == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          velocity.x = -velocity.x * bounche;
        }
      }
    }
  }

  explode() {
    world.explosionAtSprite(this, this.velocity.multiply(0.2), damage, radius);    
    this.remove = true;
  }
  
  frame(double duration, int frameStep, [Vec2 gravity]) {
    if (explodeAfter != null) {
      explodeAfter -= duration;
      if (explodeAfter < 0) {
        explode();
      }
    }
    super.frame(duration, frames, gravity);
  }

  WorldDamageProjectile.createWithOwner(WormWorld world, MovingSprite owner, int damage)
     : super(0.0, 0.0, imageByName["fire.png"]) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(15.0, 7.0);
    this.position.x = ownerCenter.x - size.x / 2;
    this.position.y = ownerCenter.y - size.y / 2;
    this.spriteType = SpriteType.IMAGE;
    this.velocity.x = cos(owner.angle);
    this.angle = owner.angle;
    this.velocity.y = sin(owner.angle);
    this.outOfBoundsMovesRemaining = 2;
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = owner.velocity + this.velocity;
  }
}