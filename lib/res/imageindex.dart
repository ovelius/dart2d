library imageindex;

import 'dart:math';
import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

List<String> imageSources = [
    "lion88.png", // Put here as first item for easier testing.
    "fire.png",
    "duck.png",
    "dragon.png",
    "cock.png",
    "sheep98.png",
    "ele96.png",
    "donkey98.png",
    "goat93.png",
    "cock77.png",
    "dra98.png",
    "turtle96.png",
    "donkey.png",
    "world_map_mini.png",
    "world_house_mini.png",
    "world_cloud_mini.png",
    "world_maze_mini.png",
    "world_town_mini.png",
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
      addEmptyImageForTest(img);
    }
  }

  addEmptyImageForTest(String name) {
    images.add(_EMPTY_IMAGE);
    int index = images.length - 1;
    imageByName[name] = index;
    loadedImages[index] = true;
  }

  getImageByName(String name) {
    return images[imageByName[name]];
  }

  int getImageIdByName(String name) {
    assert (name != null);
    assert(imageByName[name] != null);
    return imageByName[name];
  }

  getImageById(int id) {
    assert(id != null);
    assert(images[id] != null);
    return images[id];
  }
  bool finishedLoadingImages() {
    return loadedImages.length >= imageSources.length;
  }
  String imagesLoadedString() {
    return "${loadedImages.length}/${imageSources.length}";
  }

  addImagesFromServer([String path = "./img/"]) {
    loadImagesFromServer();
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

  loadImagesFromServer() {
    List<Future> imageFutures = [];
    for (var imgName in imageSources) {
      // Already loaded, skip.
      if (loadedImages[imgName] == true) {
        continue;
      }
      imageFutures.add(addSingleImage(imgName));
    }
    return Future.wait(imageFutures);
  }

  Future addSingleImage(String imgName, [String path = "./img/"]) {
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
    imageByName[imgName] = index;
    return _imageLoadedFuture(element, index);
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

  bool imageNameIsLoaded(String name) {
    int id = imageByName[name];
    if (id != null) {
      return imageIsLoaded(id);
    }
    return false;
  }
}
