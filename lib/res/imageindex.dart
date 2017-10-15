library imageindex;

import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

const MAX_LOCAL_STORAGE_SIZE = 4 * 1024 * 1024;

List<String> PLAYER_SOURCES = [
  "lion88.png",
  "sheep98.png",
  "sheep_black58.png",
  "ele96.png",
  "donkey98.png",
  "goat93.png",
  "cock77.png",
  "dra98.png",
  "turtle96.png"
];

List<String> WORLD_SOURCES = [
  "world_map_mini.png",
  "world_house_mini.png",
  "world_cloud_mini.png",
  "world_maze_mini.png",
  "world_town_mini.png",
];

List<String> GAME_SOURCES = [
  "cake.png",
  "banana.png",
  "shield.png",
  "soda.png",
  "shieldi02.png",
  "health02.png",
  "zooka.png",
  "box.png",
  "gun.png",
];

List<String> IMAGE_SOURCES = new List.from(PLAYER_SOURCES)..addAll(WORLD_SOURCES)..addAll(GAME_SOURCES);

const String _EMPTY_IMAGE_DATA_STRING = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAADElEQVQImWNgoBMAAABpAAFEI8ARAAAAAElFTkSuQmCC";

@Injectable()
class ImageIndex {
  static const int WORLD_IMAGE_INDEX = 1;
  var _EMPTY_IMAGE;
  var _WORLD_IMAGE;
  DynamicFactory _canvasFactory;
  DynamicFactory _imageFactory;
  // Map ImageName -> ImageIndex.
  Map<String, int> imageByName = new Map<String, int>();
  // Map ImageName -> Loaded bool.
  Map<int, bool> loadedImages = new Map<int, bool>();
  List images = new List();
  Map _localStorage;

  ImageIndex(
      @LocalStorage() Map localStorage,
      @CanvasFactory() DynamicFactory canvasFactory,
      @ImageFactory() DynamicFactory imageFactory) {
    this._localStorage = localStorage;
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
    for (var img in IMAGE_SOURCES) {
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
    return loadedImages.length >= IMAGE_SOURCES.length;
  }
  String imagesLoadedString() {
    return "${loadedImages.length}/${IMAGE_SOURCES.length}";
  }

  addImagesFromServer([String path = "./img/"]) {
    loadImagesFromServer();
  }

  void addFromImageData(int index, String data) {
    images[index] = _imageFactory.create([data]);
    loadedImages[index] = true;
    if (finishedLoadingImages()) {
      _cacheInLocalStorage();
    }
  }

  void addImagesFromNetwork() {
    loadImagesFromNetwork();
  }

  bool imagesIndexed() {
    return imageByName.length >= IMAGE_SOURCES.length;
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
    _indexImages();
    _loadFromCacheInLocalStorage();
    for (var imgName in IMAGE_SOURCES) {
      // Already loaded, skip.
      int index = imageByName[imgName];
      if (loadedImages[index] == true) {
        continue;
      }
      imageFutures.add(addSingleImage(imgName));
    }
    return Future.wait(imageFutures);
  }

  Future addSingleImage(String imgName, [String path = "./img/"]) {
    assert(imagesIndexed());
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
      if (finishedLoadingImages()) {
        _cacheInLocalStorage();
      }
    });
    return img.onLoad.first;
  }

  loadImagesFromNetwork() {
    _indexImages();
    _loadFromCacheInLocalStorage();
  }

  void _indexImages() {
    for (var img in IMAGE_SOURCES) {
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

  void clearImageLoader(int index) {
    loadedImages[index] = false;
  }

  bool imageNameIsLoaded(String name) {
    int id = imageByName[name];
    if (id != null) {
      return imageIsLoaded(id);
    }
    return false;
  }

  static final Duration CACHE_TIME = new Duration(days: 7);

  void _loadFromCacheInLocalStorage() {
    assert(imagesIndexed());
    DateTime now = new DateTime.now();
    for (String image in imageByName.keys) {
      String key = "img$image";
      if (_localStorage.containsKey(key) && _localStorage.containsKey("t$key")) {
        String millis = _localStorage["t$key"];
        DateTime cacheTime = new DateTime.fromMillisecondsSinceEpoch(int.parse(millis));
        if (cacheTime.add(CACHE_TIME).isAfter(now)) {
          String data = _localStorage[key];
          int imageIndex = imageByName[image];
          addFromImageData(imageIndex, data);
        }
      }
    }
  }

  void _cacheInLocalStorage() {
    int size = 0;
    for (String image in imageByName.keys) {
      int imageId = imageByName[image];
      // Never cache the world.
      if (imageId <= WORLD_IMAGE_INDEX) {
        continue;
      }
      if (size > MAX_LOCAL_STORAGE_SIZE) {
        continue;
      }
      String imageData = getImageDataUrl(imageId);
      size += imageData.length;
      String key = "img$image";
      if (!_localStorage.containsKey(key)) {
        _localStorage[key] = imageData;
        _localStorage["t$key"] = (new DateTime.now().millisecondsSinceEpoch).toString();
      }
    }
  }
}
