
import 'movingsprite.dart';
import 'sprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';

/*
 * A sprite that follows the position of another sprite. 
 */
class StickySprite extends MovingSprite {
 
  late Sprite stickTo;

  StickySprite(Sprite stickTo, int imageId, ImageIndex imageIndex, int lifeTime) :
      super.imageBasedSprite(stickTo.position, imageId, imageIndex) {
    this.stickTo = stickTo;
    this.collision = false;
    this.lifeTime = lifeTime;
  }

  frame(double duration, int frames, [Vec2? gravity]) {
    setCenter(stickTo.centerPoint());
    super.frame(duration, frames);
  }
}