library movingsprite;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/worlds/sprite_index.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/byteworld.dart';

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

  MovingSprite.empty(ImageIndex imageIndex): super.empty(imageIndex);

  MovingSprite(Vec2 position, Vec2 size, SpriteType spriteType)
      : super(position, size, spriteType);

  MovingSprite.imageBasedSprite(Vec2 position, int imageId, ImageIndex imageIndex)
      : super.imageBasedSprite(position, imageId, imageIndex);

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