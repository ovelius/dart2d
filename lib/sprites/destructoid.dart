library destructoid;

import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/phys/vec2.dart';

class Destructoid extends MovingSprite {
  double bounche = 0.1;
  var canvas;
  Vec2 centerView;

  Destructoid(ByteWorld world, Vec2 centerView, int x, int y, int x2, int y2) :
        super(new Vec2(x.toDouble(), y.toDouble()),  new Vec2((x2 - x).toDouble(), (y2 - y).toDouble()), SpriteType.CUSTOM) {
    this.centerView = centerView;
//    canvas = new CanvasElement(width: size.x.toInt(), height: size.y.toInt());
  //  ImageData data = world.canvas.context2D.getImageData(x, y, x2 - x, y2 - y);
    //canvas.context2D.putImageData(data, 0, 0);
    print("created data of ${position} ${size}");
  }
  
  @override
  draw(var /*CanvasRenderingContext2D*/ context, bool debug) {
    context.translate(position.x + size.x / 2, position.y + size.y / 2);
    
   // context.translate(position.x + size.x / 2, position.y + size.y / 2);
   //  context.fillStyle = "#ff0000";
     //this.drawRect(context);
     
    //context.translate(position.x + size.x / 2, position.y + size.y / 2);
     //context.fiffllRect(-size.x / 2, -size.y / 2, size.x / 2, size.y / 2);
    // print("drawing at ${this.position}");
    // context.resetTransform();
     context.drawImageScaledFromSource(
              canvas,
              0, 0,
              canvas.width, canvas.height,
              -size.x / 2,  -size.y / 2,
              size.x, size.y);
 //    context.drawImage(,  position.x + centerView.x, position.y + centerView.y);
  }
  
  collide(MovingSprite other, ByteWorld world, int direction) {       
      if (world != null && other == null) {
        handleWorldCollide(world, direction);
      }
  }
 
  handleWorldCollide(ByteWorld world, int direction) {
    if (direction == MovingSprite.DIR_BELOW) {
      if (velocity.y > 0) {
        velocity.y = -velocity.y * bounche;
      }
    } else if(direction == MovingSprite.DIR_ABOVE) {
      if (velocity.y < 0) {
        velocity.y = -velocity.y * bounche;
      }
    } else  if(direction == MovingSprite.DIR_LEFT) {
      if (velocity.x < 0) {
        velocity.x = -velocity.x * bounche;
      }
    } else  if(direction == MovingSprite.DIR_RIGHT) {
      if (velocity.x > 0) {
        velocity.x = -velocity.x * bounche;
      }
    }
  }
}