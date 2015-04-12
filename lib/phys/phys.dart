library phys;

import 'dart:math';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/phys/vec2.dart';

const double MIN =  0.000001;

bool collision(MovingSprite sprite1, MovingSprite sprite2, double duration) {
  Vec2 center1 = sprite1.centerPoint();
  Vec2 center2 = sprite2.centerPoint();

  Vec2 deltaPosition = new Vec2(
      center1.x - center2.x,
      center1.y - center2.y);

  Vec2 vel1 = sprite1.velocity.multiply(duration);
  Vec2 vel2 = sprite2.velocity.multiply(duration);


  Vec2 deltaVelocity = new Vec2(
      vel1.x - vel2.x,
      vel1.y - vel2.y);
  
  double deltaVSum = deltaVelocity.sum();
  deltaVSum *= deltaVSum; 
  if(deltaVSum < MIN)
    return false;

  double timeCheck = 
      Vec2.dotProduct(deltaPosition, deltaVelocity)
      / Vec2.dotProduct(deltaVelocity, deltaVelocity);

  Vec2 deltaRmin = deltaPosition - deltaVelocity.multiply(timeCheck);
  Vec2 deltaRend = deltaPosition - deltaVelocity;

  double criticalDistance = sprite1.getRadius() + sprite2.getRadius();
  
  if (timeCheck < 1.0 && timeCheck > 0.0 && deltaRmin.sum() < criticalDistance) {
    return true;
  }
  if (deltaRend.sum() < criticalDistance) {
    return true;
  }
  return false;
}

double velocityForSingleSprite(
  MovingSprite sprite, Vec2 location, double radius, int radiusDamage) {
  Vec2 angle = sprite.centerPoint() - location;
  double distance = angle.sum() - sprite.size.sum() / 2;
  if (distance < radius && distance > 0.0) {
    double damage = radiusDamage / (distance / 10.0);
    sprite.velocity += angle.multiply(damage);
    return damage;
  }
  return 0.0;
}

