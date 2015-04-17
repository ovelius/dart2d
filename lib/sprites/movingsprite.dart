library movingsprite;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'dart:math';
import 'dart:html';

class MovingSprite extends Sprite {
  static const int FLAG_NO_GRAVITY = 1;
  static const int FLAG_NO_MOVEMENTS = 2;
  
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
  
  // Set from network. See static FLAG_ fields above.
  int flags = 0;

  MovingSprite.empty(): super.empty() {}
  
  MovingSprite(double x, double y, int imageIndex, [int width, int height])
      : super(x, y, imageIndex, width, height);
  
  MovingSprite.withVecPosition(Vec2 position, int imageIndex, [Vec2 size])
       : super.withVec2(position, imageIndex, size);

  frame(double duration, int frames, [Vec2 gravity]) {
    assert(duration != null);
    assert(duration >= .0);
        
    if (flags & FLAG_NO_MOVEMENTS == 0) {
      velocity = velocity.add(
          acceleration.multiply(duration));
    
      position = position.add(
          velocity.multiply(duration));
    }
    
    if (gravity != null && (flags & FLAG_NO_GRAVITY) == 0) {
      velocity = velocity.add(gravity.multiply(duration * gravityAffect));
    }

    angle += rotationVelocity * duration;

    super.frame(duration, frames, gravity);
  }

  collide(MovingSprite other, ByteWorld world, int direction) {
 
  }
  
  int sendFlags() {
    return 0;
  }
  
  int remoteRepresentation() {
    return SpriteIndex.MOVING_SPRITE;
  }
}