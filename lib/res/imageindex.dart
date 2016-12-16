library imageindex;

import 'dart:html';
import 'dart:math';
import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

List<String> imageSources = [
    "shipg01.png",
    "shield.png",
    "shipr01.png",
    "shipb01.png",
    "shipy01.png",
    "fire.png",
    "astroid.png",
    "astroid2.png",
    "astroid3.png",
    "duck.png",
    "dragon.png",
    "world.png",
    "cake.png",
    "banana.png",
    "zooka.png",
    "box.png",
    "gun.png",
];

const String _EMPTY_IMAGE_DATA_STRING = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAADElEQVQImWNgoBMAAABpAAFEI8ARAAAAAElFTkSuQmCC";

@Injectable()
class ImageIndex {
  var _EMPTY_IMAGE;
  DynamicFactory _canvasFactory;
  DynamicFactory _imageFactory;
  Map<String, String> dataUrlCache_ = new Map();
  // Map ImageName -> ImageId.
  Map imageByName = new Map<String, int>();
  Map loadedImages = new Map<String, bool>();
  List images = new List();
  // Item 0 is always empty image.
  List<Future> imageFutures = [];

  ImageIndex(@CanvasFactory() DynamicFactory canvasFactory,
      @ImageFactory() DynamicFactory imageFactory) {
    this._imageFactory = imageFactory;
    this._canvasFactory = canvasFactory;
    // Image 0 is always empty image.
    images.add(_EMPTY_IMAGE);
  }

  void _createEmptyImage() {
    _EMPTY_IMAGE = _imageFactory.create([100, 100]);
    _EMPTY_IMAGE.src = _EMPTY_IMAGE_DATA_STRING;
  }

  /**
   * Factory constructor to be used in testing.
   */
  ImageIndex.useEmptyImagesForTest(DynamicFactory imageFactory) {
    this._imageFactory = imageFactory;
    _createEmptyImage();
    for (var img in imageSources) {
      images.add(_EMPTY_IMAGE());
      imageByName[img] = images.length - 1;
      loadedImages[img] = true;
    }
  }

  getImageByName(String name) {
    return images[imageByName[name]];
  }

  int getImageIdByName(String name) {
    return imageByName[name];
  }

  getImageById(int id) {
    return images[id];
  }
  bool finishedLoadingImages() {
    return loadedImages.length == imageSources.length;
  }
  String imagesLoadedString() {
    return "${loadedImages.length}/${imageSources.length}";
  }

  addImagesFromServer([String path = "./img/"]) {
    loadImagesFromServer(path);
  }

  void addFromImageData(String name, String data) {
    images[imageByName[name]].src = data;
    loadedImages[name] = true;
  }

  void addImagesFromNetwork() {
    loadImagesFromNetwork();
  }

  bool imagesIndexed() {
    return imageByName.length >= imageSources.length;
  }

  /**
   * Return and an img.src represenation of this image.
   */
  String getImageDataUrl(String name) {
    if (dataUrlCache_.containsKey(name)) {
      return dataUrlCache_[name];
    }
    int index = imageByName[name];
    ImageElement image = images[index];
    CanvasElement canvas = new CanvasElement(width:image.width, height:image.height);
    canvas.context2D.drawImage(image, 0, 0);
    String data = canvas.toDataUrl("image/png");
    dataUrlCache_[name] = data;
    return data;
  }

  loadImagesFromServer([String path = "./img/"]) {
    // TODO: What if partially loaded from client?
    // loadedImages[name] will be true then.
    for (var img in imageSources) {
      ImageElement element = new ImageElement(src: path + img);
      images.add(element);
      imageFutures.add(element.onLoad.first);
      element.onLoad.first.then((e) {
        loadedImages[img] = true;
      });
      imageByName[img] = images.length - 1;
    }
    return Future.wait(imageFutures);
  }


  loadImagesFromNetwork() {
    for (var img in imageSources) {
      ImageElement element = new ImageElement();
      images.add(element);
      imageByName[img] = images.length - 1;
    }
  }

  Map<String, int> allImagesByName() {
    return imageByName;
  }

  bool imageIsLoaded(String name) {
    return loadedImages[name] == true;
  }
}
