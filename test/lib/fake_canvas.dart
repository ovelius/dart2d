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


@Injectable(as: HtmlScreen)
class FakeScreen implements HtmlScreen {
  @override
  get orientation => throw UnimplementedError();
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
