library movingsprite;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/world.dart';
import 'dart:math';
import 'dart:html';

class MovingSprite extends Sprite {
 
  Vec2 velocity = new Vec2();
  double rotationVelocity = 0.0;
  Vec2 acceleration = new Vec2();

  bool collision = true;
  int outOfBoundsMovesRemaining = -1;

  MovingSprite(double x, double y, int imageIndex, [int width, int height])
      : super(x, y, imageIndex, width, height);
  
  MovingSprite.withVecPosition(Vec2 position, int imageIndex, [Vec2 size])
       : super.withVec2(position, imageIndex, size);

  frame(double duration, int frames) {
    assert(duration != null);
    assert(duration >= .0);

    velocity = velocity.add(
        acceleration.multiply(duration));
    
    position = position.add(
        velocity.multiply(duration));

    angle += rotationVelocity * duration;

    if (outOfBoundsCheck() && outOfBoundsMovesRemaining > 0) {
      outOfBoundsMovesRemaining--;
      remove = outOfBoundsMovesRemaining == 0;
    }

    super.frame(duration, frames);
  }
 
  collide(MovingSprite other) {
 
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    super.draw(context, debug);
    if (debug) {
      context.resetTransform();
      context.setFillColorRgb(255, 255, 255);
      context.fillText("vel: ${velocity}", position.x, position.y);
      context.beginPath();
      Vec2 center = centerPoint();
      context.arc(center.x, center.y, getRadius(), 0, 2 * PI, false);
      context.rect(position.x, position.y, size.x, size.y);
      context.lineWidth = 1;
      context.strokeStyle = '#ffffff';
      context.stroke();
    }
  }

  bool outOfBoundsCheck() {
    bool outOfBounds = false;
    if (position.x > WIDTH) {
      position.x = -size.x;
      outOfBounds = true;
    }
    if (position.x < -size.x ) {
      position.x = WIDTH.toDouble();
      outOfBounds = true;
    }
    if (position.y > HEIGHT) {
      position.y = -size.y;
      outOfBounds = true;
    }
    if (position.y < -size.y) {
      position.y = HEIGHT.toDouble();
      outOfBounds = true;
    }
    return outOfBounds;
  }
}