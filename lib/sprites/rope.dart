import 'movingsprite.dart';
import 'sprite.dart';
import 'dart:math';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'dart:html';

class Rope extends MovingSprite {
 
  ByteWorld world;
  bool locked = false;
  MovingSprite owner;

  Rope.createWithOwner(ByteWorld world, MovingSprite owner, double angle, double velocity)
       : super(0.0, 0.0, imageByName["fire.png"]) {
      this.world = world;
      this.owner = owner;
      Vec2 ownerCenter = owner.centerPoint();
      this.size = new Vec2(5.0, 5.0);
      this.position.x = ownerCenter.x - size.x / 2;
      this.position.y = ownerCenter.y - size.y / 2;
      this.spriteType = SpriteType.RECT;
      
      this.angle = owner.angle;
      this.velocity.x = cos(angle);
      this.velocity.y = sin(angle);
      
      this.velocity = this.velocity.multiply(velocity);
      this.velocity = owner.velocity + this.velocity;
  }
  
  
  collide(MovingSprite other, ByteWorld world, int direction) {
    if (other == null) {
      locked = true;
      this.velocity = new Vec2();
    }
  }
  
  dragOwner(double duration) {
    Vec2 delta = position - owner.position;
    delta = delta.multiply(duration * 5.0);
    owner.velocity += delta;
  }
  
  frame(double duration, int frames, [Vec2 gravity]) {
    if (locked) {
      // When locked we have no gravity.
      dragOwner(duration);
      super.frame(duration, frames);
      if (this.velocity.sum() > 0.01) {
        locked = false;
      }
    } else {
      super.frame(duration, frames, gravity);
    }
  }
  
  draw(CanvasRenderingContext2D context, bool debug) {
    super.draw(context, debug);
  //  context.setFillColorRgb(200, 0, 0);
  //  context.setStrokeColorRgb(200, 0, 0);
    Vec2 ownerCenter = owner.centerPoint();
    context.lineWidth = 2;
    var grad= context.createLinearGradient(ownerCenter.x, ownerCenter.y, position.x, position.y);
    grad.addColorStop(0, "red");
    grad.addColorStop(1, "green");

    context.strokeStyle = grad;

    context.beginPath();
    context.moveTo(ownerCenter.x, ownerCenter.y);
    context.lineTo(position.x, position.y);
    context.stroke();
  }
}