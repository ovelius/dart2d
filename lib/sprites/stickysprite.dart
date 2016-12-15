library stickysprite;

import 'movingsprite.dart';
import 'sprite.dart';
import 'package:dart2d/phys/vec2.dart';

/*
 * A sprite that follows the position of another sprite. 
 */
class StickySprite extends MovingSprite {
 
  Sprite stickTo;

  StickySprite(Sprite stickTo, int imageIndex, int lifeTime, int width, [int height]) :
      super(stickTo.position,imageIndex, new Vec2(width, height == null ? width : height)) {
    this.stickTo = stickTo;
    this.collision = false;
    this.lifeTime = lifeTime;
  }

  frame(double duration, int frames, [Vec2 gravity]) {
    setCenter(stickTo.centerPoint());
    super.frame(duration, frames);
  }
}