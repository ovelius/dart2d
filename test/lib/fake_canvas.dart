import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/net.dart';
import 'dart:async';

class FakeCanvas {
  static const DATA_URL = "data:image/png;base64,THIS_IS_FAKE";

  FakeContext2D context2D;
  num height = 800;
  num width = 800;

  FakeCanvas() {
    context2D = new FakeContext2D(this);
  }

  toDataUrl([String type]) => DATA_URL;
}

class FakeContext2D {

  FakeContext2D(this.canvas);

  FakeCanvas canvas;
  var font;
  var fillStyle;
  num globalAlpha = 1.0;
  String globalCompositeOperation;

  void clearRect(num one, two, three, four) {}
  void setFillColorRgb(num one, two, three, [four]) {}
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

class FakeScreen {

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

class FakeImageFactory extends DynamicFactory {
  FakeImageFactory() : super(null);
  List<FakeImage> createdImages = [];
  create(var args) {
    FakeImage image;
    if (args.length == 2) {
      image = new FakeImage.withHW(args[0], args[1]);
    } else if (args.length == 1) {
      image = new FakeImage.withSrc(args[0]);
    } else if (args.length == 0) {
      image = new FakeImage();
    } else {
      throw new ArgumentError("Can't handle arguments ${args}");
    }
    createdImages.add(image);
    return image;
  }

  void completeAllImages() {
    createdImages.forEach((image) {
      if (!image.onLoad._completer.isCompleted) {
        image.onLoad._completer.complete(0);
        print("Completed fake image ${image.src}");
      }
    });
  }
}

class FakeImage {

  FakeImage() {}
  FakeImage.withSrc(this.src);
  FakeImage.withHW(this.width, this.height);

  String src;
  int width = 100;
  int height = 100;

  _FakeEvenStream onLoad = new _FakeEvenStream();
}

class _FakeEvenStream {
  Completer _completer = new Completer.sync();
  Future first;
  _FakeEvenStream() {
    first = _completer.future;
  }
}

class FakeImageDataFactory extends DynamicFactory {
  FakeImageDataFactory() : super(null);
  create(var args) {
    return null;
  }
}
