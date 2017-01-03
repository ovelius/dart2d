library imageindex;

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
    "cock.png",
    "donkey.png",
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
  static const int WORLD_IMAGE_INDEX = 1;
  var _EMPTY_IMAGE;
  var _WORLD_IMAGE;
  DynamicFactory _canvasFactory;
  DynamicFactory _imageFactory;
  // Map ImageName -> ImageIndex.
  Map imageByName = new Map<String, int>();
  // Map ImageName -> Loaded bool.
  Map loadedImages = new Map<int, bool>();
  List images = new List();

  ImageIndex(@CanvasFactory() DynamicFactory canvasFactory,
      @ImageFactory() DynamicFactory imageFactory) {
    this._imageFactory = imageFactory;
    this._canvasFactory = canvasFactory;
    // Image 0 is always empty image.
    // Image 1 is always world image.
    _createBaseImages();
    assert(images[WORLD_IMAGE_INDEX] == _WORLD_IMAGE);
  }

  void _createBaseImages() {
    _EMPTY_IMAGE = _imageFactory.create([100, 100]);
    _EMPTY_IMAGE.src = _EMPTY_IMAGE_DATA_STRING;
    _WORLD_IMAGE = _imageFactory.create([1, 1]);
    images.add(_EMPTY_IMAGE);
    images.add(_WORLD_IMAGE);
  }

  /**
   * Factory constructor to be used in testing.
   */
  useEmptyImagesForTest() {
    for (var img in imageSources) {
      images.add(_EMPTY_IMAGE);
      int index = images.length - 1;
      imageByName[img] = index;
      loadedImages[index] = true;
    }
  }

  getImageByName(String name) {
    return images[imageByName[name]];
  }

  int getImageIdByName(String name) {
    assert(imageByName[name] != null);
    return imageByName[name];
  }

  getImageById(int id) {
    assert(id != null);
    assert(images[id] != null);
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

  void addFromImageData(int index, String data) {
    images[index] = _imageFactory.create([data]);
    loadedImages[index] = true;
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
  String getImageDataUrl(int index) {
    var image = images[index];
    var canvas = _canvasFactory.create([image.width, image.height]);
    canvas.context2D.drawImage(image, 0, 0);
    String data = canvas.toDataUrl("image/png");
    return data;
  }

  loadImagesFromServer([String path = "./img/"]) {
    List<Future> imageFutures = [];
    for (var imgName in imageSources) {
      // Already loaded, skip.
      if (loadedImages[imgName] == true) {
        continue;
      }
      var element = this._imageFactory.create([path + imgName]);
      int index = imageByName[imgName];
      // Already indexed. Update existing item.
      if (index != null) {
        images[index] = element;
      } else {
        // Not indexed add it.
        images.add(element);
        index = images.length - 1;
      }
      imageFutures.add(_imageLoadedFuture(element, index));
      imageByName[imgName] = index;
    }
    return Future.wait(imageFutures);
  }

  Future _imageLoadedFuture(var img, int index) {
    img.onLoad.first.then((e) {
      loadedImages[index] = true;
    });
    return img.onLoad.first;
  }

  loadImagesFromNetwork() {
    for (var img in imageSources) {
      var element = this._imageFactory.create([]);
      images.add(element);
      imageByName[img] = images.length - 1;
    }
  }

  Map<String, int> allImagesByName() {
    return imageByName;
  }

  bool imageIsLoaded(int index) {
    return loadedImages[index] == true;
  }
}
