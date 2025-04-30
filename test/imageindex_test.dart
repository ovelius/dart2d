import 'package:test/test.dart';
import 'package:web/web.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/util/util.dart';

void main() {
  late TestLocalStorage localStorage;
  late ImageIndex index;
  late FakeImageFactory fakeImageFactory;
  late FakeCanvasFactory fakeCanvasFactory;

  setUpAll((){
    configureDependencies();
  });

  setUp(() {
    logOutputForTest();
    localStorage =  new TestLocalStorage();
    fakeImageFactory = new FakeImageFactory();
    fakeCanvasFactory = new FakeCanvasFactory();
    index = new ImageIndex(new ConfigParams({}), localStorage,
        fakeCanvasFactory, fakeImageFactory);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  test('TestLoadServer', () async {
    fakeImageFactory.allowDataImages = false;
    index.loadImagesFromServer();
    expect(index.finishedLoadingImages(), isFalse);
    expect(index.imagesIndexed(), isTrue);

    await fakeImageFactory.completeAllImages();

    expect(index.finishedLoadingImages(), isTrue);

    // Check caching.
    for (String name in index.allImagesByName().keys) {
      if (name == ImageIndex.WORLD_NAME || name == ImageIndex.EMPTY) {
        continue;
      }
      expect(localStorage["img$name"], isNotNull);
    }
  });

  test("TestLoadClient", () async {
    fakeImageFactory.allowURLImages = false;
    index.loadImagesFromNetwork();

    expect(index.finishedLoadingImages(), isFalse);
    expect(index.imagesIndexed(), isTrue);

    // Now add data for each image.
    for (String name in PLAYER_SOURCES) {
      int imageId = index.getImageIdByName(name);
      index.addFromImageData(imageId, EMPTY_IMAGE_DATA_STRING, true);
      await fakeImageFactory.completeAllImages();
    }

    expect(index.playerResourcesLoaded(), isTrue);
    expect(index.finishedLoadingImages(), isFalse);

    for (int imageId in index.allImagesByName().values) {
      index.addFromImageData(imageId, EMPTY_IMAGE_DATA_STRING, true);
      await fakeImageFactory.completeAllImages();
      expect(index.imageIsLoaded(imageId), isTrue);
    }

    expect(index.finishedLoadingImages(), isTrue);

    for (int imageId in index.allImagesByName().values) {
      HTMLImageElement image = index.getImageById(imageId);
      expect(image.src, isNotNull);
    }

    // Check caching.
    for (String name in index.allImagesByName().keys) {
      if (name == ImageIndex.WORLD_NAME || name == ImageIndex.EMPTY) {
        continue;
      }
      expect(localStorage["img$name"], isNotNull);
      expect(localStorage.containsKey("timg$name"), isTrue);
    }
  });

  test("TestLoadClientAndServer", () async {
    index.loadImagesFromNetwork();

    List<int> ids = new List.from(index.allImagesByName().values);
    ids.sort();
    for (int imageId in ids) {
      index.addFromImageData(imageId, "data:image/png;base64,testData$imageId", true);
      await fakeImageFactory.completeAllImages();
      expect(index.imageIsLoaded(imageId), isTrue);
      if (imageId > 5) {
        break;
      }
    }
    // Did not complete from client.
    expect(index.finishedLoadingImages(), isFalse);

    // Fallback to server loaded images.
    index.loadImagesFromServer();

    await fakeImageFactory.completeAllImages();

    expect(index.finishedLoadingImages(), isTrue);

    // Some images got loaded from client.
    for (int id in ids) {
      HTMLImageElement image = index.getImageById(id);
      expect(image.src, isNotNull
      , reason: "Image ${image.src} is client loaded and cached");
      if (id > 5) {
        break;
      }
    }

    // Check caching.
    for (String name in index.allImagesByName().keys) {
      if (name == ImageIndex.WORLD_NAME || name == ImageIndex.EMPTY) {
        continue;
      }
      expect(localStorage["img$name"], isNotNull);
      expect(localStorage.containsKey("timg$name"), isTrue);
    }
  });

  test("TestLoadFromCache", () async {
    fakeImageFactory.allowURLImages = false;
    for (String name in IMAGE_SOURCES) {
      localStorage["img$name"] = EMPTY_IMAGE_DATA_STRING;
      localStorage["timg$name"] =
          new DateTime.now().millisecondsSinceEpoch.toString();
    }

    index.loadImagesFromNetwork();

    await fakeImageFactory.completeAllImages();

    expect(index.finishedLoadingImages(), isTrue);
  });

  test("testClientThenServer_loadsCacheOnce", () async {
    fakeImageFactory.allowURLImages = false;
    for (String name in IMAGE_SOURCES) {
      localStorage["img$name"] = "data:image/png;base64,data$name";
      localStorage["timg$name"] =
          new DateTime.now().millisecondsSinceEpoch.toString();
    }

    index.loadImagesFromNetwork();
    await fakeImageFactory.completeAllImages();
    index.loadImagesFromServer();


    expect(index.finishedLoadingImages(), isTrue);
  });

  test("TestLoadFromCacheServer", () async {
    for (String name in IMAGE_SOURCES) {
      localStorage["img$name"] = "data:image/png;base64,data$name";
      localStorage["timg$name"] =
          new DateTime.now().millisecondsSinceEpoch.toString();
    }

    index.loadImagesFromServer();

    await fakeImageFactory.completeAllImages();

    expect(index.finishedLoadingImages(), isTrue);
  });

  test("TestLoadFromCacheTooOld", () {
    for (String name in IMAGE_SOURCES) {
      localStorage["img$name"] = "data$name";
      // Too old...
      localStorage["timg$name"] = (new DateTime.now().millisecondsSinceEpoch -
              new Duration(days: 14).inMilliseconds)
          .toString();
    }

    index.loadImagesFromNetwork();

    expect(index.finishedLoadingImages(), isFalse);
    expect(localStorage.length, 0);
  });

  test("TestAddCorruptImage", () async {
    expectWarningContaining("Dropping corrupted image data");
    index.loadImagesFromNetwork();
    index.addFromImageData(2, "Blergh", false);

    expect(index.loadedImages[2], isNull);
    await fakeImageFactory.completeAllImages();
    expect(index.loadedImages[2], isTrue);

    expect(index.finishedLoadingImages(), isFalse);
  });
}
