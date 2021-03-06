import 'dart:math';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

@Injectable()
/**
 * Represents the destructable world.
 */
class ByteWorld {
  // Needs to create canvas.
  DynamicFactory _canvasFactory;
  // Needs to create imageData.
  DynamicFactory _imageDataFactory;
  // Needs to create images.
  DynamicFactory _imageFactory;
  int _width;
  int _height;
  Point<int> viewSize;
  var canvas;
  var _bedrockImage;

  ByteWorld(
      @ImageFactory() DynamicFactory imageFactory,
      @WorldWidth() int width, @WorldHeight() int height,
      @ImageDataFactory() DynamicFactory imageDataFactory,
      @CanvasFactory() DynamicFactory canvasFactory) {
    this.viewSize = new Point(width, height);
    this._canvasFactory = canvasFactory;
    this._imageDataFactory = imageDataFactory;
    this._imageFactory = imageFactory;
  }

  /**
   * Initialize the world image.
   */
  void setWorldImage(var image) {
    canvas = _canvasFactory.create([image.width, image.height]);
    _width = canvas.width;
    _height = canvas.height;
    canvas.context2D.drawImageScaled(image, 0, 0, _width, _height);
    var bedrocksCanvas = _canvasFactory.create([_width, _height]);
    _computeBedrock(bedrocksCanvas);
    // Store bedrock result in image.
    _bedrockImage = _imageFactory.create([_width, _height]);
    _bedrockImage.src = bedrocksCanvas.toDataUrl();
  }

  /**
   * Bedrock represents the parts of the world that can't be destroyed.
   */
  void _computeBedrock(var bedrockCanvas) {
    int segments = 10;
    // Compute 10 segments to avoid using too much memory.
    int segmentSize = _width ~/ segments;
    for (int i = 0; i < segments + 1; i++) {
      int startX = min(i * segmentSize, _width);
      int computeWidth = min(startX + segmentSize, _width) - startX;
      if (computeWidth > 0) {
        _computeBedrockSegment(startX, computeWidth, bedrockCanvas);
      }
    }
  }

  /**
   * Some colors in the level image can't be, we find them and put them
   * in it's own image.
   */
  void _computeBedrockSegment(int startX, int computeWidth, var bedrockCanvas) {
    List data = canvas.context2D.getImageData(startX, 0, computeWidth, _height).data;
    var newData = _imageDataFactory.create([computeWidth, _height]);
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
    bedrockCanvas.context2D.putImageData(newData, startX, 0);
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
       _width, _height, // width.
       x, y, _width * wScale, _height * hScale);
  }

  /**
   * Check if any pixel inside area is solid.
   */
  bool isCanvasCollide(num x, num y, [num width = 1, num height = 1]) {
    List<int> data = canvas.context2D.getImageData(x, y, width, height).data;
    for (int i = 0; i < data.length / 4; i++) {
      // If transparency data is present, we are solid.
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

  /**
   * Destroy part of the world. From an explosion perhaps?
   */
  clearAt(Vec2 pos, double radius) {
    Point<int> restoreRect = Vec2.createIntPoint(pos.x - radius - 1, pos.y - radius - 1);
    int restoreSize =  (radius * 2 + 2).toInt();
    canvas.context2D
        ..save()
        ..beginPath()
        ..arc(pos.x, pos.y, radius, 0, 2 * PI, false)
        ..clip()
        ..clearRect(restoreRect.x, restoreRect.y, restoreSize, restoreSize)
        ..restore();
    // Re-apply any destroyed bedrock. It can't be destroyed :)
    canvas.context2D.drawImage(_bedrockImage, 0, 0);
  }

  Vec2 randomNotSolidPoint(Vec2 sizeOffset) {
    assert(initialized());
    Vec2 point = null;
    for (int i = 0; i < 30; i++) {
      point = new Vec2(
          new Random().nextInt(_width - sizeOffset.x.toInt()).toDouble(),
          new Random().nextInt(_height - sizeOffset.y.toInt()).toDouble());
      if (!isCanvasCollide(point.x, point.y)) {
        return point;
      }
    }
    return point;
  }

  int get width => _width;
  int get height => _height;
}