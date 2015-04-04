import 'movingsprite.dart';
import 'sprite.dart';
import 'dart:math';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';

/*
 * A sprite that follows the position of another sprite. 
 */
class Rope extends MovingSprite {
 
  Sprite owner;

  Rope.createWithOwner(MovingSprite owner, double velocity)
       : super(0.0, 0.0, imageByName["fire.png"]) {
      this.owner = owner;
      Vec2 ownerCenter = owner.centerPoint();
      this.size = new Vec2(5.0, 5.0);
      this.position.x = ownerCenter.x - size.x / 2;
      this.position.y = ownerCenter.y - size.y / 2;
      this.spriteType = SpriteType.RECT;
      
      this.angle = owner.angle;
      this.velocity.x = cos(owner.angle);
      this.velocity.y = sin(owner.angle);
      
      this.velocity = this.velocity.multiply(velocity);
      this.velocity = owner.velocity + this.velocity;
    }
}