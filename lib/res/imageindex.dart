library imageindex;

import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/util/util.dart';
import 'package:di/di.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

const MAX_LOCAL_STORAGE_SIZE = 4 * 1024 * 1024;

// Required for selecting player.
Set<String> PLAYER_SOURCES = new Set<String>.from([
  "lion88.png",
  "sheep98.png",
  "sheep_black58.png",
  "ele96.png",
  "donkey98.png",
  "goat93.png",
  "cock77.png",
  "dra98.png",
  "turtle96.png"
]);

// Required for actually running game.
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

// Required for selecting world.
Set<String> WORLD_SOURCES = new Set<String>.from([
  "world_map_mini.png",
  "world_house_mini.png",
  "world_cloud_mini.png",
  "world_maze_mini.png",
  "world_town_mini.png",
]);

// The resources with the highest priority are first in the list here.
List<String> IMAGE_SOURCES = new List.from(PLAYER_SOURCES)..addAll(GAME_SOURCES)..addAll(WORLD_SOURCES);

const String _EMPTY_IMAGE_DATA_STRING = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAADElEQVQImWNgoBMAAABpAAFEI8ARAAAAAElFTkSuQmCC";

@Injectable()
class ImageIndex {
  final Logger log = new Logger('ImageIndex');
  static const int WORLD_IMAGE_INDEX = 1;
  var _EMPTY_IMAGE;
  var _WORLD_IMAGE;
  ConfigParams _configParams;
  DynamicFactory _canvasFactory;
  DynamicFactory _imageFactory;
  // Map ImageName -> ImageIndex.
  Map<String, int> imageByName = new Map<String, int>();
  // Map ImageName -> Loaded bool.
  Map<int, bool> loadedImages = new Map<int, bool>();
  List images = new List();

  // Keep track of these types in a Set.
  Set<String> _playerImages = new Set.from(PLAYER_SOURCES);
  Set<String> _worldImages = new Set.from(WORLD_SOURCES);
  Set<String> _gameImages = new Set.from(GAME_SOURCES);
  List<int> _orderedImageIds = [];

  Map _localStorage;

  ImageIndex(
      this._configParams,
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

  bool playerResourcesLoaded() => _playerImages.isEmpty;
  bool worldResourcesLoaded() => _worldImages.isEmpty;
  bool gameResourcesLoaded() => _gameImages.isEmpty;
  List<int> orderedImageIds() => _orderedImageIds;

  String imagesLoadedString() {
    return "${loadedImages.length}/${IMAGE_SOURCES.length}";
  }

  addImagesFromServer([String path = "./img/"]) {
    loadImagesFromServer();
  }

  Future addFromImageData(int index, String data) {
    String imageName = imageNameFromIndex(index);
    if (!data.startsWith("data:image/png;base64,")) {
      log.warning("Dropping corrupted image data for ${imageName}, fallback to server.");
      addSingleImage(imageName);
      return new Future.value();
    }
    images[index] = _imageFactory.create([data]);
    // Mark image as complete here.
    loadedImages[index] = true;
    return _imageLoadedFuture(images[index], index);
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
    log.info("Loading images from Server.");
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
      imageByName[imgName] = index;
    }
    return _imageLoadedFuture(element, index);
  }

  Future _imageLoadedFuture(var img, int index) {
    img.onLoad.first.then((e) {
      String imageName = imageNameFromIndex(index);
      if (images[index].width == 0 || images[index].height == 0) {
        log.warning("Dropping corrupted image for ${imageName}, fallback to server.");
        loadedImages.remove(index);
        addSingleImage(imageName);
      } else {
        loadedImages[index] = true;
        _imageComplete(index);
      }
    });
    return img.onLoad.first;
  }

  loadImagesFromNetwork() {
    _indexImages();
    _loadFromCacheInLocalStorage();
  }

  void _imageComplete(int index) {
    if (finishedLoadingImages()) {
      _cacheInLocalStorage();
    }
    String name = imageNameFromIndex(index);
    if (name != null) {
      _playerImages.remove(name);
      _worldImages.remove(name);
      _gameImages.remove(name);
    }
  }

  String imageNameFromIndex(int index) {
    assert(imagesIndexed());
    for (String name in IMAGE_SOURCES) {
      if (imageByName[name] == index) {
        return name;
      }
    }
    return null;
  }

  void _indexImages() {
    for (String img in IMAGE_SOURCES) {
      // Don't index again...
      if (!imageByName.containsKey(img)) {
        var element = this._imageFactory.create([]);
        images.add(element);
        int index = images.length - 1;
        imageByName[img] = index;
        _orderedImageIds.add(index);
      }
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
    if (_configParams.getBool(ConfigParam.DISABLE_CACHE)) {
      return;
    }
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
          log.info("Added image from cache ${image}.");
          addFromImageData(imageIndex, data);
        } else {
          // Clear cache.
          _localStorage.remove(key);
          _localStorage.remove("t$key");
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
