library stickysprite;

import 'movingsprite.dart';
import 'sprite.dart';
import 'dart:math';

/*
 * A sprite that follows the position of another sprite. 
 */
class StickySprite extends MovingSprite {
 
  Sprite stickTo;

  StickySprite(Sprite stickTo, int imageIndex, int lifeTime, int width) :
      super(stickTo.position.x, stickTo.position.y, imageIndex, width, width) {
    this.stickTo = stickTo;
    this.collision = false;
    this.lifeTime = lifeTime;
  }

  frame(double duration, int frames) {
    setCenter(stickTo.centerPoint());
    rotationVelocity = new Random().nextDouble() * 10000;
    super.frame(duration, frames);
  }
}