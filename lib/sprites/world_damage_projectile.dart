library world_damage_projectile; 

import 'movingsprite.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';

class WorldDamageProjectile extends MovingSprite {

  MovingSprite owner;
  int damage = 1;

  double homingFactor = null;
  MovingSprite target;

  WorldDamageProjectile(double x, double y, int imageIndex, [int width, int height])
      : super(x, y, imageIndex, width, height);

  collide(MovingSprite other, ByteWorld world) {
    assert(owner != null);
    if (other == null) {
      // World collide.
      
    }
    if (other != null && other != owner && other.takesDamage()) {
      other.takeDamage(this.owner, damage);
    }
    if (world != null && other == null) {
      world.clearAt(centerPoint(), 15);
    }
    // Do animation stuff.
    this.remove = true;
  }

  double piOffsetDelta(double angle) {
    if (angle > PI) {
      return -2*PI + angle; 
    } if (angle < PI) {
      return 2*PI + angle;
    }
  }

  
  frame(double duration, int frameStep, [Vec2 gravity]) {
    if (homingFactor != null) {
   //   home(duration);
    }
    super.frame(duration, frames, gravity);
  }

  WorldDamageProjectile.createWithOwner(MovingSprite owner, int damage, [double homingFactor])
     : super(0.0, 0.0, imageByName["fire.png"]) {
    this.owner = owner;
    this.damage = damage;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(28.0, 7.0);
    this.position.x = ownerCenter.x - size.x / 2;
    this.position.y = ownerCenter.y - size.y / 2;
    this.spriteType = SpriteType.IMAGE;
    this.velocity.x = cos(owner.angle);
    this.angle = owner.angle;
    this.velocity.y = sin(owner.angle);
    this.outOfBoundsMovesRemaining = 2;
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = owner.velocity + this.velocity;
    this.homingFactor = homingFactor;
  }
}