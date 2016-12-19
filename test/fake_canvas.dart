import 'package:dart2d/bindings/annotations.dart';

class FakeCanvas {

  _FakeContext2D context2D;
  num height = 800;
  num width = 800;

  FakeCanvas() {
    context2D = new _FakeContext2D(this);
  }
}

class _FakeContext2D {

  _FakeContext2D(this.canvas);

  FakeCanvas canvas;
  var font;
  var fillStyle;
  num globalAlpha = 1.0;

  void clearRect(num one, two, three, four) {}
  void setFillColorRgb(num one, two, three, [four]) {}
  void fillRect(num one, two, three, four) {}

  void save() {}
  void restore() {}
  void resetTransform() {}

  void translate(num x, y) {}
  void rotate(num rad) {}

  void fillText(var str, num one, [two, three]) {
    print("${this.runtimeType}: fillText $str");
  }
  void drawImageScaled(var image, num one, two, three, four) {}
  void drawImageScaledFromSource(var obj, num one, two, three, four, five, size, seven, eight) {}

  _FakeData getImageData(num x, y, w, h) {
    return new _FakeData(new List.filled((w*h).toInt() * 4 ,0));
  }

  dynamic measureText(String text) {
    return new _FakeTextMetrics(text.length);
  }

   _FakeGradient createLinearGradient(num one, two, three, four) {
    return new _FakeGradient();
  }
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

class FakeImage {
  String src;
  int width = 100;
  int height = 100;
}