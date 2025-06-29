import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:web/web.dart';
import 'package:dart2d/net/state_updates.pb.dart';

/**
 * Represents the destructable world.
 */
@Singleton(scope: 'world')
class ByteWorld {
  final Logger log = new Logger('ByteWorld');
  // Needs to create canvas.
  late CanvasFactory _canvasFactory;
  // Needs to create imageData.
  late ImageDataFactory _imageDataFactory;
  // Needs to create images.
  late ImageFactory _imageFactory;
  late int _width;
  late int _height;
  late Point<int> viewSize;
  // The main canvas object.
  late HTMLCanvasElement? canvas;
  // The part of the world the player can't destroy... if any.
  late HTMLImageElement _bedrockImage;
  // Temporary canvas storage.
  late HTMLCanvasElement _bedrocksCanvas;
  // x line for current bedrock computation.
  int _bedrockLine = -1;

  ByteWorld(
      ImageFactory imageFactory,
      @Named(WORLD_WIDTH) int width, @Named(WORLD_HEIGHT) int height,
      ImageDataFactory imageDataFactory,
      CanvasFactory canvasFactory) {
    this.viewSize = new Point(width, height);
    this._canvasFactory = canvasFactory;
    this._imageDataFactory = imageDataFactory;
    this._imageFactory = imageFactory;
  }

  /**
   * Initialize the world image.
   */
  void setWorldImage(HTMLImageElement image) {
    canvas = _canvasFactory.createCanvas(image.width, image.height);
    _width = canvas!.width;
    _height = canvas!.height;
    canvas!.context2D.drawImage(image, 0, 0, _width, _height);
    _bedrocksCanvas = _canvasFactory.createCanvas(_width, _height);
    _bedrockLine = 0;
  }
  bool worldImageSet() {
    return _bedrockLine >= 0;
  }
  void reset() {
    _bedrockLine = -1;
  }
  bool bedrockComputed() {
    return (_bedrockLine > _width);
  }

  bool byteWorldReady() {
    return worldImageSet() && bedrockComputed();
  }
  /**
   * calculate a single bedrock segment, or finish bedrock computation.
   */
  void bedrockStep() {
    assert(!bedrockComputed());
    int startX = min(_bedrockLine, _width);
    int computeWidth = min(startX + 1, _width) - startX;
    if (computeWidth > 0) {
      _computeBedrockSegment(startX, computeWidth, _bedrocksCanvas);
    }
    _bedrockLine++;
    if (_bedrockLine > _width) {
      _finalizeBedrock();
    }
  }

  /**
   * create the final bedrock image.
   */
  void _finalizeBedrock() {
    _bedrockImage = _imageFactory.createWithSize(_width, _height);
    _bedrockImage.src = _bedrocksCanvas.toDataUrl("png");
  }

  double percentComplete() => _bedrockLine / _width;


  /**
   * Some colors in the level image can't be destroyed, we find them and put them
   * in it's own image.
   */
  void _computeBedrockSegment(int startX, int computeWidth,
      HTMLCanvasElement bedrockCanvas) {
    Uint8ClampedList data = canvas!.context2D.getImageData(startX, 0, computeWidth, _height).data.toDart;
    ImageData newData = _imageDataFactory.createWithSize(computeWidth, _height);
    Uint8ClampedList newDataArr = newData.data.toDart;
    for (int i = 0; i < (data.length ~/ 4); i++) {
      int p = i * 4;
      // Brownish color.
      // #3b2e01
      if (data[p] == 59 && data[p + 1] == 46 && data[p + 2] == 1) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 255 && data[p + 1] == 145 && data[p + 2] == 34) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 231 && data[p + 1] == 3 && data[p + 2] == 30) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 254 && data[p + 1] == 201 && data[p + 2] == 89) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 254 && data[p + 1] == 201 && data[p + 2] == 89) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 171 && data[p + 1] == 206 && data[p + 2] == 150) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
    }
    bedrockCanvas.context2D.putImageData(newData, startX, 0);
  }

  Uint8ClampedList getImageData(Vec2 pos, Vec2 size) {
    return canvas!.context2D.getImageData(pos.x.toInt(), pos.y.toInt(), size.x.toInt(), size.y.toInt()).data.toDart;
  }

  Uint8ClampedList getImageDataFor(int x,y, w,h) {
    return canvas!.context2D.getImageData(x, y, w, h).data.toDart;
  }

  void drawAt(CanvasRenderingContext2D canvas, x, y) {
    canvas.drawImage(
       this.canvas!,
       x, y, // Source
       viewSize.x, viewSize.y, // width.
       0, 0, viewSize.x , viewSize.y);
  }
  
  void drawAsMiniMap(var canvas, x, y, [double wScale= 0.1, double hScale = 0.1]) {
    canvas.drawImage(
       this.canvas,
       0, 0, // Source
       _width, _height, // width.
       x, y, _width * wScale, _height * hScale);
  }

  /**
   * Check if any pixel inside area is solid.
   */
  bool isCanvasCollide(int x, int y, [int width = 1, int height = 1]) {
    Uint8ClampedList data = canvas!.context2D.getImageData(x, y, width, height).data.toDart;
    for (int i = 0; i < data.length / 4; i++) {
      // If transparency data is present, we are solid.
      if (data[i*4 + 3] > 0) {
        return true;
      }
    }
    return  false;
  }
  
  clearAtRect(int x, int y, int width, int height) {
    canvas!.context2D.clearRect(x, y, width, height);
  }
  
  String asDataUrl() {
    return canvas!.toDataUrl("image/png");
  }

  drawFromNetworkUpdate(ByteWorldDraw data) {
    Vec2 pos = Vec2.fromProto(data.position);
    Vec2 size = Vec2.fromProto(data.size);
    String colorString = data.color;
    fillRectAt(pos, size, colorString);
  }

  fillRectAt(Vec2 pos, Vec2 size, String colorString) {
    canvas!.context2D
      ..save();
    canvas!.context2D.fillStyle = colorString.toJS;
    canvas!.context2D
      ..fillRect(pos.x, pos.y, size.x, size.y)
      ..restore();
  }

  /**
   * Destroy part of the world. From an explosion perhaps?
   */
  clearAt(Vec2 pos, double radius) {
    Point<int> restoreRect = Vec2.createIntPoint(pos.x - radius - 1, pos.y - radius - 1);
    int restoreSize =  (radius * 2 + 2).toInt();
    canvas!.context2D
        ..save()
        ..beginPath()
        ..arc(pos.x, pos.y, radius, 0, 2 * pi, false)
        ..clip()
        ..clearRect(restoreRect.x, restoreRect.y, restoreSize, restoreSize)
        ..restore();
    // Re-apply any destroyed bedrock. It can't be destroyed :)
    canvas!.context2D.drawImage(_bedrockImage, 0, 0);
  }

  Vec2 randomNotSolidPoint(Vec2 sizeOffset) {
    assert(byteWorldReady());
    Vec2? point = null;
    Random r = Random();
    for (int i = 0; i < 50; i++) {
      point = new Vec2(
          r.nextInt(_width).toDouble(),
          r.nextInt(_height).toDouble());
      if (!isCanvasCollide(point.x.toInt(), point.y.toInt())) {
        return point;
      }
    }
    throw "Unable to find random not solid location!";
  }

  int get width => _width;
  int get height => _height;
}