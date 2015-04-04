import 'dart:typed_data';
import 'dart:html';
import 'dart:math';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart'; 

class ByteWorld {
  int width;
  int height;
  
  Vec2 viewSize;
  
  CanvasElement canvas;
  ByteWorld(int imageId, Vec2 viewSize) {
    ImageElement image = images[imageId];
    canvas = new CanvasElement(width: image.width, height: image.height);
    this.width = canvas.width;
    this.height = canvas.height;
    canvas.context2D.drawImageScaled(image, 0, 0, width, height);
    this.viewSize = viewSize;
  }
  
  void drawAt(CanvasRenderingContext2D canvas, x, y) {
    canvas.drawImageScaledFromSource(
       this.canvas,
       x, y, // Source
       viewSize.x, viewSize.y, // width.
       0, 0, viewSize.x , viewSize.y);
  }
  
  bool isCanvasCollide(num x, num y, [num width = 1, num height = 1]) {
    List<int> data = canvas.context2D.getImageData(x, y, 1, 1).data;
    for (int i = 0; i < data.length / 4; i++) {
      if (data[i*4 + 3] > 0) {
        return true;
      }
    }
    return  false;
  }
  
  clearAt(Vec2 pos, radius) {
    canvas.context2D
        ..save()
        ..beginPath()
        ..arc(pos.x, pos.y, radius, 0, 2 * PI, false)
        ..clip()
        ..clearRect(pos.x - radius - 1, pos.y - radius - 1,
                        radius * 2 + 2, radius * 2 + 2)
        ..restore();
  }
}