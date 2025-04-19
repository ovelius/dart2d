import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:web/web.dart';

const TEST_DATA_URL = "data:image/png;base64,THIS_IS_TEST_DATA_URL";

@Injectable(as: WorldCanvas)
class FakeCanvas implements WorldCanvas {

  late HTMLCanvasElement canvas;
  late CanvasRenderingContext2D context2D;
  int height = 800;
  int width = 800;

  FakeCanvas() {
    canvas = HTMLCanvasElement();
    canvas.width = width;
    canvas.height = height;
    context2D = canvas.context2D;
  }

  toDataUrl([String type = ""]) => TEST_DATA_URL;
}

class FakeContext2D {

  FakeContext2D(this.canvas);

  FakeCanvas canvas;
  var font;
  var fillStyle;
  num globalAlpha = 1.0;
  late String globalCompositeOperation;

  void clearRect(num one, two, three, four) {}
  void setFillColorRgb(num one, two, three, [four]) {}
  void setStrokeColorRgb(num one, two, three) {}
  void fillRect(num one, two, three, four) {}

  void save() {}
  void restore() {}
  void resetTransform() {}

  void translate(num x, y) {}
  void rotate(num rad) {}

  void fillText(var str, num one, [two, three]) {
  }

  void beginPath() {

  }

  void arc(num x, y, radius, degStart, degEnd, [bool clockWise = false]) {

  }

  void rect(num x,y, num w, h) {

  }

  void clip() { }

  void scale(num one, two) {}

  void fill() { }

  FakeGradient createRadialGradient(num one, two, three, four, five, six) {
    return new FakeGradient();
  }

  void drawImage(var img, num one, two) {}
  void drawImageScaled(var image, num one, two, three, four) {}
  void drawImageScaledFromSource(var obj, num one, two, three, four, five, size, seven, eight) {}

  _FakeData getImageData(num x, y, w, h) {
    return new _FakeData(new List.filled((w*h).toInt() * 4 ,0));
  }

  putImageData(dynamic unused, int w, h) {

  }

  dynamic measureText(String text) {
    return new _FakeTextMetrics(text.length);
  }

   _FakeGradient createLinearGradient(num one, two, three, four) {
    return new _FakeGradient();
  }
}

class FakeGradient {
  void addColorStop(num where, String color) {}
}

@Injectable(as: HtmlScreen)
class FakeScreen implements HtmlScreen {
  @override
  get orientation => throw UnimplementedError();
}

class _FakeTextMetrics {
  int width;
  _FakeTextMetrics(this.width);
}

class _FakeData {
  List<int> data;
  _FakeData(this.data);
}

class _FakeGradient {
  void addColorStop(num arg, var color) {}
}

@Singleton(as: ImageFactory, scope:'world')
class FakeImageFactory extends ImageFactory {
  List<HTMLImageElement> createdImages = [];
  // Required to avoid deadlock in end2end tests.
  bool completeImagesAsap = false;
  bool allowDataImages = true;
  bool allowURLImages = true;


  Future completeAllImages() async {
    List<Future> imagesLoad = [];
    createdImages.forEach((image) async {
      image.src = EMPTY_IMAGE_DATA_STRING;
      imagesLoad.add(image.onLoad.first);
    });
    return Future.wait(imagesLoad);
  }

  @override
  createWithSize(int x, y) {
    HTMLImageElement i = HTMLImageElement();
    i.width = x;
    i.height = y;
    return addImage(i);
  }

  @override
  createWithSrc(String src) {
    if (!allowDataImages && src.startsWith("data:")) {
      throw new ArgumentError("Not allowed to create image from data ${src}");
    }
    if (!allowURLImages && src.startsWith("./")) {
      throw new ArgumentError("Not allowed to create image from URL ${src}");
    }
    HTMLImageElement i = HTMLImageElement();
    i.src = src;
    return addImage(i);
  }

  @override
  create() {
    return addImage(HTMLImageElement());
  }

  HTMLImageElement addImage(HTMLImageElement img) {
    createdImages.add(img);
    if (completeImagesAsap) {
      completeAllImages();
    }
    return img;
  }

}

/*
class FakeImage {

  FakeImage() {}
  FakeImage.withSrc(this.src);
  FakeImage.withHW(this.width, this.height);

  String src = "";
  int width = 100;
  int height = 100;

  _FakeEvenStream onLoad = new _FakeEvenStream();

  String toString() => "src=$src w: $width h: $height";
}

class _FakeEvenStream {
  Completer _completer = new Completer.sync();
  late Future first;
  _FakeEvenStream() {
    first = _completer.future;
  }
} */

@Injectable(as: ImageDataFactory)
class FakeImageDataFactory implements ImageDataFactory {
  @override
  createWithSize(int x, y) {
    HTMLCanvasElement c = HTMLCanvasElement();
    c.height = y;
    c.width = x;
    return c.context2D.getImageData(0, 0, x, y);
  }
}
