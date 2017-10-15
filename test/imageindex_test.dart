import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/bindings/annotations.dart';

void main() {
  Map<String, String> localStorage;
  ImageIndex index;
  FakeImageFactory fakeImageFactory;
  _FakeCanvas _fakeCanvas;

  setUp(() {
    localStorage = new Map<String, String>();
    fakeImageFactory = new FakeImageFactory();
    _fakeCanvas = new _FakeCanvas();
    index = new ImageIndex(localStorage,  new DynamicFactory((args) => _fakeCanvas), fakeImageFactory);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  test('TestLoadServer', () {
    index.loadImagesFromServer();
    expect(index.finishedLoadingImages(), isFalse);
    expect(index.imagesIndexed(), isTrue);

    fakeImageFactory.completeAllImages();

    expect(index.finishedLoadingImages(), isTrue);

    // Check caching.
    for (String name in index.allImagesByName().keys) {
      FakeImage img = index.getImageByName(name);
      expect(img.src, localStorage["img$name"]);
    }
  });

  test("TestLoadClient", () {
    index.loadImagesFromNetwork();

    expect(index.finishedLoadingImages(), isFalse);
    expect(index.imagesIndexed(), isTrue);

    // Now add data for each image.
    for (int imageId in index.allImagesByName().values) {
      index.addFromImageData(imageId, "testData$imageId");
    }

    expect(index.finishedLoadingImages(), isTrue);

    for (int imageId in index.allImagesByName().values) {
      FakeImage image = index.getImageById(imageId);
      expect(image.src, equals("testData$imageId"));
    }

    // Check caching.
    for (String name in index.allImagesByName().keys) {
      FakeImage img = index.getImageByName(name);
      expect(img.src, localStorage["img$name"]);
      expect(localStorage.containsKey("timg$name"), isTrue);
    }
  });

  test("TestLoadClientAndServer", () {
    index.loadImagesFromNetwork();

    List<int> ids = new List.from(index.allImagesByName().values);
    ids.sort();
    for (int imageId in ids) {
      index.addFromImageData(imageId, "testData$imageId");
      expect(index.imageIsLoaded(imageId), isTrue);
      if (imageId > 5) {
        break;
      }
    }
    // Did not complete from client.
    expect(index.finishedLoadingImages(), isFalse);

    index.loadImagesFromServer();

    fakeImageFactory.completeAllImages();

    expect(index.finishedLoadingImages(), isTrue);

    // Some images got loaded from client.
    for (int id in ids) {
      FakeImage image = index.getImageById(id);
      expect(image.src, equals("testData$id"));
      if (id > 5) {
        break;
      }
     }

    // Check caching.
    for (String name in index.allImagesByName().keys) {
      FakeImage img = index.getImageByName(name);
      expect(img.src, localStorage["img$name"]);
      expect(localStorage.containsKey("timg$name"), isTrue);
    }
  });

  test("TestLoadFromCache", () {
    for (String name in IMAGE_SOURCES) {
      localStorage["img$name"] = "data$name";
      localStorage["timg$name"] = new DateTime.now().millisecondsSinceEpoch.toString();
    }

    index.loadImagesFromNetwork();

    expect(index.finishedLoadingImages(), isTrue);
  });

  test("TestLoadFromCacheServer", () {
    for (String name in IMAGE_SOURCES) {
      localStorage["img$name"] = "data$name";
      localStorage["timg$name"] = new DateTime.now().millisecondsSinceEpoch.toString();
    }

    index.loadImagesFromServer();

    expect(index.finishedLoadingImages(), isTrue);
  });

  test("TestLoadFromCacheTooOld", () {
    for (String name in IMAGE_SOURCES) {
      localStorage["img$name"] = "data$name";
      // Too old...
      localStorage["timg$name"] = (new DateTime.now().millisecondsSinceEpoch - new Duration(days: 14).inMilliseconds).toString();
    }

    index.loadImagesFromNetwork();

    expect(index.finishedLoadingImages(), isFalse);
  });
}

class _FakeCanvas {
  FakeImage image;

  _FakeCanvas context2D;

  _FakeCanvas() {
    this.context2D = this;
  }

  void drawImage(image, int a, int b) {
    this.image = image;
  }

  String toDataUrl([String format = ""]) {
    if (image == null) {
      throw new StateError("No image drawn!");
    }
    return image.src;
  }
}
