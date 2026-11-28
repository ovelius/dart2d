library imageindex;

import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/crc32.dart';
// NOTE: Whenever you add, remove, or modify images in `web/img/`, run:
//   dart run tool/generate_image_hashes.dart
// to update `lib/res/image_hashes.dart`.
import 'package:dart2d/res/image_hashes.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/worlds/world_data.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:web/web.dart';

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
  "dart.png",
  "shield.png",
  "powerup.png",
  "powerup_swiwel.png",
  "soda.png",
  "snails.png",
  "shieldi02.png",
  "health02.png",
  "weapon_icons.png",
  "zooka.png",
  "box.png",
  "gun.png",
  "shark.png",
];

const LOADER_SPRITE = "shark.png";

// Required for selecting world.
Set<String> WORLD_SOURCES = new Set<String>.from(
  WORLDS.keys
);

// The resources with the highest priority are first in the list here.
List<String> IMAGE_SOURCES = new List.from(PLAYER_SOURCES)..addAll(GAME_SOURCES)..addAll(WORLD_SOURCES);

const String EMPTY_IMAGE_DATA_STRING = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAADElEQVQImWNgoBMAAABpAAFEI8ARAAAAAElFTkSuQmCC";

@Singleton(scope: 'world')
class ImageIndex {
  final Logger log = new Logger('ImageIndex');
  static const int WORLD_IMAGE_INDEX = 1;
  static const String WORLD_NAME = "world";
  static const String EMPTY = "empty";
  late HTMLImageElement _EMPTY_IMAGE;
  late HTMLImageElement _WORLD_IMAGE;
  ConfigParams _configParams;
  late CanvasFactory _canvasFactory;
  late ImageFactory _imageFactory;
  ImageFactory get imageFactory => _imageFactory;
  // Map ImageName -> index of image.
  Map<String, int> imageByName = new Map<String, int>();
  // Map ImageIndex -> Loaded bool.
  Map<int, bool> loadedImages = new Map<int, bool>();
  // Map ImageIndex
  Map<int, Future> _imagesLoading = new Map<int, Future>();
  // Original raw PNG data URLs (from fetch, cache, or P2P) so P2P serving
  // transmits exact bit-for-bit bytes without canvas re-encoding.
  Map<int, String> _rawImageDataUrls = new Map<int, String>();
  // Expected CRC32 hashes for static PNG assets.
  Map<String, int> expectedImageHashes = IMAGE_CRC32_HASHES;
  bool verifyImageHashes = true;
  List<HTMLImageElement> images = [];

  // Keep track of these types in a Set.
  Set<String> _playerImages = new Set.from(PLAYER_SOURCES);
  Set<String> _worldImages = new Set.from(WORLD_SOURCES);
  Set<String> _gameImages = new Set.from(GAME_SOURCES);
  List<int> _orderedImageIds = [];

  late LocalStorage _localStorage;

  ImageIndex(
      this._configParams,
      LocalStorage localStorage,
      CanvasFactory canvasFactory,
      ImageFactory imageFactory) {
    this._localStorage = localStorage;
    this._imageFactory = imageFactory;
    this._canvasFactory = canvasFactory;
    // Image 0 is always empty image.
    // Image 1 is always world image.
    _createBaseImages();
    assert(images[WORLD_IMAGE_INDEX] == _WORLD_IMAGE);
  }

  void _createBaseImages() {
    _EMPTY_IMAGE = _imageFactory.createWithSize(100, 100);
    _EMPTY_IMAGE.src = EMPTY_IMAGE_DATA_STRING;
    _WORLD_IMAGE = _imageFactory.createWithSize(1, 1);
    images.add(_EMPTY_IMAGE);
    images.add(_WORLD_IMAGE);
    imageByName[EMPTY] = 1;
    imageByName[WORLD_NAME] = 1;
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
    _rawImageDataUrls[index] = EMPTY_IMAGE_DATA_STRING;
    loadedImages[index] = true;
    _imageComplete(index, false);
  }

  dynamic getImageByName(String name) {
    assert(imageByName.containsKey(name), "No image called $name");
    assert(imagesIndexed(), "ImageIndex not yet indexed...");
    return images[imageByName[name]!];
  }

  int getImageIdByName(String name) {
    assert(imageByName[name] != null);
    return imageByName[name]!;
  }

  dynamic getImageById(int id) {
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

  /// Returns the expected compiled CRC32 hash for the image at [index], or
  /// `null` if no static hash applies (e.g. dynamic [WORLD_IMAGE_INDEX]).
  int? expectedImageHash(int index) {
    if (index <= WORLD_IMAGE_INDEX) {
      return null;
    }
    String? name = _imageNameFromIndexOrNull(index);
    if (name == null) {
      return null;
    }
    return expectedImageHashes[name];
  }

  /// Verifies [data] against the expected CRC32 hash for [index] when one is
  /// configured. Returns `true` if valid or if no static hash applies.
  bool verifyImageDataHash(int index, String data) {
    if (!verifyImageHashes) {
      return true;
    }
    int? expected = expectedImageHash(index);
    if (expected == null) {
      return true;
    }
    int? actual = crc32FromPngDataUrl(data);
    return actual != null && actual == expected;
  }

  Future addFromImageData(int index, String data, bool allowCaching) {
    if (!data.startsWith(PNG_DATA_URL_PREFIX)) {
      String? imageName = _imageNameFromIndexOrNull(index);
      log.warning("Dropping corrupted image data for ${imageName ?? index}, fallback to server.");
      if (index > WORLD_IMAGE_INDEX && imageName != null) {
        addSingleImage(imageName);
      }
      return new Future.value();
    }
    if (!verifyImageDataHash(index, data)) {
      String? imageName = _imageNameFromIndexOrNull(index);
      log.warning(
          "Dropping corrupted image data (CRC32 mismatch) for ${imageName ?? index}, fallback to server.");
      if (imageName != null) {
        _removeFromLocalStorage(imageName);
      }
      if (index > WORLD_IMAGE_INDEX && imageName != null) {
        addSingleImage(imageName);
      }
      return new Future.value();
    }
    _rawImageDataUrls[index] = data;
    images[index] = _imageFactory.createWithSrc(data);
    _imagesLoading[index] = _imageLoadedFuture(
        images[index], index, allowCaching);
    return _imagesLoading[index]!;
  }

  void addImagesFromNetwork() {
    loadImagesFromNetwork();
  }

  bool imagesIndexed() {
    return imageByName.length >= IMAGE_SOURCES.length;
  }

  /**
   * Return an img.src representation of this image.
   */
  String getImageDataUrl(int index) {
    String? raw = _rawImageDataUrls[index];
    if (raw != null) {
      return raw;
    }
    HTMLImageElement image = images[index];
    HTMLCanvasElement canvas = _canvasFactory.createCanvas(image.width, image.height);
    canvas.context2D.drawImage(image, 0, 0);
    // TODO: Use toBlob here instead! c.toBlob(function (b) {
    //     console.log("b" + b.size);
    // });
    String data = canvas.toDataUrl("image/png");
    return data;
  }

  loadImagesFromServer() {
    log.info("Loading images from Server.");
    _indexImages();
    _loadFromCacheInLocalStorage();
    for (var imgName in IMAGE_SOURCES) {
      // Already loaded, skip.
      int index = imageByName[imgName]!;
      if (loadedImages[index] == true) {
        continue;
      }
      Future? existingLoading = _imagesLoading[index];
      if (existingLoading != null) {
        continue;
      }
      addSingleImage(imgName);
    }
    return Future.wait(_imagesLoading.values);
  }

  Future addSingleImage(String imgName, [String path = "./img/"]) {
    assert(imagesIndexed());
    int? index = imageByName[imgName];
    HTMLImageElement element = _imageFactory.supportsRawFetch
        ? this._imageFactory.create()
        : this._imageFactory.createWithSrc(path + imgName);
    // Already indexed. Update existing item.
    if (index != null) {
      images[index] = element;
    } else {
      // Not indexed add it.
      images.add(element);
      index = images.length - 1;
      imageByName[imgName] = index;
    }
    if (_imageFactory.supportsRawFetch) {
      Future loading = _fetchAndLoadImage(element, index, path + imgName);
      _imagesLoading[index] = loading;
      return loading;
    }
    _imagesLoading[index] = _imageLoadedFuture(element, index, true);
    return _imagesLoading[index]!;
  }

  /// Registers and loads a procedurally generated world image from a PNG data URL
  /// without persisting it to localStorage.
  Future addGeneratedImage(String imgName, String dataUrl) {
    assert(imagesIndexed());
    int? index = imageByName[imgName];
    HTMLImageElement element = this._imageFactory.createWithSrc(dataUrl);
    if (index != null) {
      images[index] = element;
      loadedImages.remove(index);
    } else {
      images.add(element);
      index = images.length - 1;
      imageByName[imgName] = index;
    }
    _rawImageDataUrls[index] = dataUrl;
    _imagesLoading[index] = _imageLoadedFuture(element, index, false);
    return _imagesLoading[index]!;
  }

  Future _fetchAndLoadImage(
      HTMLImageElement element, int index, String url) async {
    String? dataUrl = await _imageFactory.fetchImageDataUrl(url);
    Future loaded = _imageLoadedFuture(element, index, true);
    if (dataUrl != null) {
      _rawImageDataUrls[index] = dataUrl;
      element.src = dataUrl;
    } else {
      element.src = url;
    }
    await loaded;
  }

  Future _imageLoadedFuture(dynamic i, int index, bool allowCaching) {
    HTMLImageElement img = i as HTMLImageElement;
    Completer<void> completer = Completer<void>();
    StreamSubscription? loadSub;
    StreamSubscription? errorSub;

    void cleanup() {
      loadSub?.cancel();
      errorSub?.cancel();
    }

    loadSub = img.onLoad.listen((e) {
      cleanup();
      if (images[index].width == 0 || images[index].height == 0) {
        _handleCorruptImageLoad(index, "zero dimensions");
      } else {
        loadedImages[index] = true;
        _imagesLoading.remove(index);
        _imageComplete(index, allowCaching);
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    errorSub = img.onError.listen((e) {
      cleanup();
      _handleCorruptImageLoad(index, "decode error");
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }

  void _handleCorruptImageLoad(int index, String reason) {
    _imagesLoading.remove(index);
    loadedImages.remove(index);
    _rawImageDataUrls.remove(index);
    String? imageName = _imageNameFromIndexOrNull(index);
    if (index > WORLD_IMAGE_INDEX && imageName != null) {
      _removeFromLocalStorage(imageName);
      log.warning(
          "Dropping corrupted image for ${imageName} ($reason), fallback to server.");
      // Only retry from server if the failed source was an inline data URL,
      // to avoid an infinite loop if the server itself returns an error.
      if (images[index].src.startsWith("data:")) {
        addSingleImage(imageName);
      }
    } else {
      log.warning("Dropping corrupted world image ($reason).");
    }
  }

  void _removeFromLocalStorage(String imageName) {
    String key = "img$imageName";
    _localStorage.remove(key);
    _localStorage.remove("t$key");
  }

  String? _imageNameFromIndexOrNull(int index) {
    for (String name in imageByName.keys) {
      if (imageByName[name] == index) {
        return name;
      }
    }
    return null;
  }

  loadImagesFromNetwork() {
    _indexImages();
    _loadFromCacheInLocalStorage();
  }

  void _imageComplete(int index, bool allowCaching) {
    if (allowCaching) {
      _cacheInLocalStorage(index);
    }
    String name = imageNameFromIndex(index);
    _playerImages.remove(name);
    _worldImages.remove(name);
    _gameImages.remove(name);
  }

  String imageNameFromIndex(int index) {
    for (String name in imageByName.keys) {
      if (imageByName[name] == index) {
        return name;
      }
    }
    throw "Missing image with index $index";
  }

  void _indexImages() {
    for (String img in IMAGE_SOURCES) {
      // Don't index again...
      if (!imageByName.containsKey(img)) {
        var element = this._imageFactory.create();
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

  bool imageIsLoaded(int? index) {
    if (index == null) return false;
    return loadedImages[index] == true;
  }

  bool imageIsLoading(int index) {
    return imageIsLoaded(index) ||  _imagesLoading.containsKey(index);
  }

  void clearImageLoader(int index) {
    loadedImages.remove(index);
  }

  bool imageNameIsLoaded(String name) {
    int id = imageByName[name]!;
    return imageIsLoaded(id);
  }

  static final Duration CACHE_TIME = new Duration(days: 7);

  void _loadFromCacheInLocalStorage() {
    if (_configParams.getBool(ConfigParam.DISABLE_CACHE)) {
      return;
    }
    assert(imagesIndexed());
    DateTime now = new DateTime.now();
    for (String image in imageByName.keys) {
      int index = imageByName[image]!;
      // This image is already in the process of being loaded.
      if (imageIsLoading(index)) {
        continue;
      }
      String key = "img$image";
      if (_localStorage.containsKey(key) &&  _localStorage.containsKey("t$key")) {
        String millis = _localStorage["t$key"];
        DateTime cacheTime = new DateTime.fromMillisecondsSinceEpoch(int.parse(millis));
        if (cacheTime.add(CACHE_TIME).isAfter(now)) {
          String data = _localStorage[key];
          int imageIndex = imageByName[image]!;
          if (!verifyImageDataHash(imageIndex, data)) {
            log.info("Evicting cached image ${image} due to CRC32 mismatch.");
            _localStorage.remove(key);
            _localStorage.remove("t$key");
            continue;
          }
          log.info("Added image from cache ${image}.");
          addFromImageData(imageIndex, data, false);
        } else {
          // Clear cache.
          _localStorage.remove(key);
          _localStorage.remove("t$key");
        }
      }
    }
  }

  void _cacheInLocalStorage(int index) {
    Set<String> dontCache = new Set.from(WORLDS.values);
    String image = imageNameFromIndex(index);
    // Never cache the world.
    if (index <= WORLD_IMAGE_INDEX || dontCache.contains(image)) {
      return;
    }
    String imageData = getImageDataUrl(index);
    if (!verifyImageDataHash(index, imageData)) {
      log.info("Skipping localStorage cache for $image due to CRC32 mismatch.");
      return;
    }
    log.info("putting image in cache $image");
    String key = "img$image";
    if (!_localStorage.containsKey(key)) {
      _localStorage[key] = imageData;
      _localStorage["t$key"] = (new DateTime.now().millisecondsSinceEpoch).toString();
    }
  }
}
