library movingsprite;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'dart:math';
import 'dart:html';

class MovingSprite extends Sprite {
  static const int DIR_ABOVE = 0;
  static const int DIR_BELOW = 1;
  static const int DIR_LEFT = 2;
  static const int DIR_RIGHT = 3;

  Vec2 velocity = new Vec2();
  double rotationVelocity = 0.0;
  Vec2 acceleration = new Vec2();

  double gravityAffect = 1.0;
  bool collision = true;
  int outOfBoundsMovesRemaining = -1;

  MovingSprite(double x, double y, int imageIndex, [int width, int height])
      : super(x, y, imageIndex, width, height);
  
  MovingSprite.withVecPosition(Vec2 position, int imageIndex, [Vec2 size])
       : super.withVec2(position, imageIndex, size);

  frame(double duration, int frames, [Vec2 gravity]) {
    assert(duration != null);
    assert(duration >= .0);

    velocity = velocity.add(
        acceleration.multiply(duration));
    
    position = position.add(
        velocity.multiply(duration));
    
    if (gravity != null) {
      velocity = velocity.add(gravity.multiply(duration * gravityAffect));
    }

    angle += rotationVelocity * duration;

    super.frame(duration, frames, gravity);
  }
 
  collide(MovingSprite other, ByteWorld world, int direction) {
 
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    super.draw(context, debug);
    if (debug) {
      context.resetTransform();
      context.translate(position.x, position.y);
      context.fillStyle = "#ffffff";
      context.fillText("vel: ${velocity}", 0, 0);
      context.beginPath();
      context.arc(size.x / 2, size.y /2, getRadius(), 0, 2 * PI, false);
      context.rect(0, 0, size.x, size.y);
      context.lineWidth = 1;
      context.strokeStyle = '#ffffff';
      context.stroke();
    }
  }
}