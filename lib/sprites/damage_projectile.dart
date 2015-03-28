library damage_projectile; 

import 'movingsprite.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';

class DamageProjectile extends MovingSprite {

  MovingSprite owner;
  int damage = 1;

  double homingFactor = null;
  MovingSprite target;

  DamageProjectile(double x, double y, int imageIndex, [int width, int height])
      : super(x, y, imageIndex, width, height);

  collide(MovingSprite other) {
    assert(owner != null);
    assert(other != null);
    if (other != owner && other.takesDamage()) {
      this.remove = true;
      other.takeDamage(this.owner, damage);
    }
  }

  double piOffsetDelta(double angle) {
    if (angle > PI) {
      return -2*PI + angle; 
    } if (angle < PI) {
      return 2*PI + angle;
    }
  }

  home(double duration) {
    if (target == null) {
      double minDistance = double.MAX_FINITE;
      for (Sprite sprite in world.getFilteredSprites(
          (Sprite x) => x.takesDamage())) {
        if (sprite != this && sprite != owner) {
          if (distanceTo(sprite) < minDistance) {
            target = sprite;
          }
        }
      }
    }
    if (target != null) {
      Vec2 vector = target.centerPoint() - centerPoint();
      vector.normalize();
      double momentum = velocity.sum();
      double targetAngle = vector.toAngle();
      // TODO: Bork bork when targetAngle close to -+PI
      if (targetAngle > angle) {
        angle += (homingFactor * duration);
      } else {
        angle -= (homingFactor * duration);
      }
      velocity = new Vec2.fromAngle(angle, momentum);
      if (target.remove  /*|| !world.sprites.containsKey(target.networkId)*/) {
        target = null;
      }
    }
  }
  
  frame(double duration, int frameStep) {
    if (homingFactor != null) {
      home(duration);
    }
    super.frame(duration, frames);
  }

  DamageProjectile.createWithOwner(MovingSprite owner, int damage, [double homingFactor])
     : super(0.0, 0.0, imageByName["fire.png"]) {
    this.owner = owner;
    this.damage = damage;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(38.0, 10.0);
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