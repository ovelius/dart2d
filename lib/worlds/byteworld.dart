import 'dart:math';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

@Injectable()
class ByteWorld {
  DynamicFactory _canvasFactory;
  DynamicFactory _imageDataFactory;
  int width;
  int height;
  Vec2 viewSize;
  var canvas;
  var _bedrocksCanvas;

  ByteWorld(
      @WorldWidth() int width, @WorldHeight() int height,
      @ImageDataFactory() DynamicFactory imageDataFactory,
      @CanvasFactory() DynamicFactory canvasFactory) {
    this.viewSize = new Vec2(width * 1.0, height * 1.0);
    this._canvasFactory = canvasFactory;
    this._imageDataFactory = imageDataFactory;
  }

  /**
   * Initialize the world image.
   */
  void setWorldImage(var image) {
    canvas = _canvasFactory.create([image.width, image.height]);
    width = canvas.width;
    height = canvas.height;
    canvas.context2D.drawImageScaled(image, 0, 0, width, height);
    _bedrocksCanvas = _canvasFactory.create([width, height]);
    _computeBedrock();
  }

  void _computeBedrock() {
    int segments = 10;
    // Compute 10 segments to avoid using too much memory.
    int segmentSize = width ~/ segments;
    for (int i = 0; i < segments + 1; i++) {
      int startX = min(i * segmentSize, width);
      int computeWidth = min(startX + segmentSize, width) - startX;
      if (computeWidth > 0) {
        _computeBedrockSegment(startX, computeWidth);
      }
    }
  }

  void _computeBedrockSegment(int startX, int computeWidth) {
    // rgb = 59, 46, 1
    List data = canvas.context2D.getImageData(startX, 0, computeWidth, height).data;
    var newData = _imageDataFactory.create([computeWidth, height]);
    for (int i = 0; i < (data.length ~/ 4); i++) {
      int p = i * 4;
      if (data[p] == 59 && data[p + 1] == 46 && data[p + 2] == 1) {
        newData.data[p] = data[p];
        newData.data[p + 1] = data[p + 1];
        newData.data[p + 2] = data[p + 2];
        newData.data[p + 3] = data[p + 3];
      }
      if (data[p] == 255 && data[p + 1] == 145 && data[p + 2] == 34) {
        newData.data[p] = data[p];
        newData.data[p + 1] = data[p + 1];
        newData.data[p + 2] = data[p + 2];
        newData.data[p + 3] = data[p + 3];
      }
      if (data[p] == 231 && data[p + 1] == 3 && data[p + 2] == 30) {
        newData.data[p] = data[p];
        newData.data[p + 1] = data[p + 1];
        newData.data[p + 2] = data[p + 2];
        newData.data[p + 3] = data[p + 3];
      }
      if (data[p] == 254 && data[p + 1] == 201 && data[p + 2] == 89) {
        newData.data[p] = data[p];
        newData.data[p + 1] = data[p + 1];
        newData.data[p + 2] = data[p + 2];
        newData.data[p + 3] = data[p + 3];
      }
      if (data[p] == 254 && data[p + 1] == 201 && data[p + 2] == 89) {
        newData.data[p] = data[p];
        newData.data[p + 1] = data[p + 1];
        newData.data[p + 2] = data[p + 2];
        newData.data[p + 3] = data[p + 3];
      }
      if (data[p] == 171 && data[p + 1] == 206 && data[p + 2] == 150) {
        newData.data[p] = data[p];
        newData.data[p + 1] = data[p + 1];
        newData.data[p + 2] = data[p + 2];
        newData.data[p + 3] = data[p + 3];
      }
    }
    _bedrocksCanvas.context2D.putImageData(newData, startX, 0);
  }

  bool initialized() {
    return canvas != null;
  }

  List<int> getImageData(Vec2 pos, Vec2 size) {
    return canvas.context2D.getImageData(pos.x.toInt(), pos.y.toInt(), size.x.toInt(), size.y.toInt()).data;
  }

  List<int> getImageDataFor(int x,y, w,h) {
    return canvas.context2D.getImageData(x, y, w, h).data;
  }

  void drawAt(var canvas, x, y) {
    canvas.drawImageScaledFromSource(
       this.canvas,
       x, y, // Source
       viewSize.x, viewSize.y, // width.
       0, 0, viewSize.x , viewSize.y);
  }
  
  void drawAsMiniMap(var canvas, x, y, [double wScale= 0.1, double hScale = 0.1]) {
    canvas.drawImageScaledFromSource(
       this.canvas,
       0, 0, // Source
       width, height, // width.
       x, y, width * wScale, height * hScale);
  }
  
  bool isCanvasCollide(num x, num y, [num width = 1, num height = 1]) {
    List<int> data = canvas.context2D.getImageData(x, y, width, height).data;
    for (int i = 0; i < data.length / 4; i++) {
      if (data[i*4 + 3] > 0) {
        return true;
      }
    }
    return  false;
  }
  
  clearAtRect(int x, int y, int width, int height) {
    canvas.context2D.clearRect(x, y, width, height);
  }
  
  String asDataUrl() {
    return canvas.toDataUrl("image/png");
  }

  fillRectAt(Vec2 pos, Vec2 size, String colorString) {
    canvas.context2D
      ..save();
    canvas.context2D.fillStyle = colorString;
    canvas.context2D
      ..fillRect(pos.x, pos.y, size.x, size.y)
      ..restore();
  }

  clearAt(Vec2 pos, double radius) {
    canvas.context2D
        ..save()
        ..beginPath()
        ..arc(pos.x, pos.y, radius, 0, 2 * PI, false)
        ..clip()
        ..clearRect(pos.x - radius - 1, pos.y - radius - 1,
                        radius * 2 + 2, radius * 2 + 2)
        ..restore();
    canvas.context2D.drawImageScaled(_bedrocksCanvas, 0, 0, width, height);
  }

  Vec2 randomNotSolidPoint(Vec2 sizeOffset) {
    assert(initialized());
    Vec2 point = null;
    for (int i = 0; i < 30; i++) {
      point = new Vec2(
          new Random().nextInt(width - sizeOffset.x.toInt()).toDouble(),
          new Random().nextInt(height - sizeOffset.y.toInt()).toDouble());
      if (!isCanvasCollide(point.x, point.y)) {
        return point;
      }
    }
    return point;
  }
}