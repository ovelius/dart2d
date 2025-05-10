
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/worlds/byteworld.dart';

class MovingSprite extends Sprite {
  static const int DIR_ABOVE = 1;
  static const int DIR_BELOW = 2;
  static const int DIR_LEFT = 4;
  static const int DIR_RIGHT = 8;

  Vec2 velocity = new Vec2();
  double rotationVelocity = 0.0;
  Vec2 acceleration = new Vec2();

  double gravityAffect = 1.0;
  bool collision = true;
  bool removeOutOfBounds = false;
  
  // Set from network. See static FLAG_ fields above.
  int flags = 0;

  // If owned by a player.
  LocalPlayerSprite? owner;

  MovingSprite.empty(ImageIndex imageIndex): super.empty(imageIndex);

  MovingSprite(Vec2 position, Vec2 size, SpriteType spriteType)
      : super(position, size, spriteType);

  MovingSprite.imageBasedSprite(Vec2 position, int imageId, ImageIndex imageIndex)
      : super.imageBasedSprite(position, imageId, imageIndex);

  frame(double duration, int frames, [Vec2? gravity]) {
    assert(duration >= .0);

    // Protect against low framerates.
    if (duration > 0.2) {
      duration = 0.2;
    }
        
    if (flags & Sprite.FLAG_NO_MOVEMENTS == 0) {
      velocity = velocity.add(
          acceleration.multiply(duration));

      position = position.add(
          velocity.multiply(duration));

      // Don't execute tiny movements. stop them.
      if (velocity.x.abs() < 0.05) {
        velocity.x = 0.0;
      }
      // Don't execute tiny movements. stop them.
      if (velocity.y.abs() < 0.05) {
        velocity.y = 0.0;
      }
    }
    
    if (gravity != null && (flags & Sprite.FLAG_NO_GRAVITY) == 0) {
      _checkIsStill(duration);
      velocity = velocity.add(gravity.multiply(duration * gravityAffect));
    }

    angle += rotationVelocity * duration;

    super.frame(duration, frames, gravity);
  }

  Vec2 _lastPosition = Vec2();
  double _stillDuration = 0.0;
  double? baseGravity = 0.0;

  /**
   * check if sprite is very very still.. in which case we can disable gravity
   * for it temporary...
   */
  void _checkIsStill(double duration) {
    if (baseGravity == null || baseGravity == 0.0) {
      baseGravity = gravityAffect;
      return;
    }
    double positionDelta = (position.x - _lastPosition.x).abs() + (position.y - _lastPosition.y).abs();
    if (positionDelta < 1.5) {
      _stillDuration += duration;
      gravityAffect = 0.0;
    } else {
      _stillDuration = 0.0;
      _lastPosition = position;
    }
    if (_stillDuration > 0.3) {
      gravityAffect = 0.0;
      velocity.y = 0.0;
    } else {
      gravityAffect = baseGravity!;
    }
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.MOVING_SPRITE;
  }
}