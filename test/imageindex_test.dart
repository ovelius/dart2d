import 'dart:convert';
import 'package:test/test.dart';
import 'package:web/web.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/res/crc32.dart';
import 'package:dart2d/res/image_hashes.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/worlds/world_data.dart';

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
    // Legacy tests in this file pass synthetic data strings rather than real PNG bytes;
    // dedicated CRC32 tests below re-enable hash verification explicitly.
    index.verifyImageHashes = false;
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

  group('CRC32 and raw fetch verification', () {
    test('crc32Bytes matches IEEE 802.3 standard vector', () {
      expect(crc32Bytes(utf8.encode('123456789')), equals(0xCBF43926));
      expect(crc32FromPngDataUrl(EMPTY_IMAGE_DATA_STRING), isNotNull);
      expect(crc32FromPngDataUrl('not-a-png'), isNull);
      expect(crc32FromPngDataUrl('data:image/png;base64,!!!invalid!!!'), isNull);
    });

    test('IMAGE_CRC32_HASHES covers all IMAGE_SOURCES and WORLDS maps', () {
      for (String name in IMAGE_SOURCES) {
        expect(IMAGE_CRC32_HASHES.containsKey(name), isTrue,
            reason: 'Missing precomputed CRC32 hash for $name');
      }
      for (String worldMap in WORLDS.values) {
        expect(IMAGE_CRC32_HASHES.containsKey(worldMap), isTrue,
            reason: 'Missing precomputed CRC32 hash for $worldMap');
      }
    });

    test('CRC32 mismatch rejects image data, skips cache, and falls back to server', () async {
      expectWarningContaining('CRC32 mismatch');
      index.verifyImageHashes = true;
      index.loadImagesFromNetwork();

      int imageId = index.getImageIdByName('lion88.png');
      index.expectedImageHashes = {
        'lion88.png': crc32FromPngDataUrl(EMPTY_IMAGE_DATA_STRING)!,
      };

      // Corrupt data URL with a different base64 payload (different CRC32).
      String corruptData = 'data:image/png;base64,${base64Encode([1, 2, 3, 4])}';
      await index.addFromImageData(imageId, corruptData, true);

      // Should not be marked loaded or cached, and should have triggered server fallback.
      expect(index.loadedImages[imageId], isNull);
      expect(localStorage['imglion88.png'], isNull);

      await fakeImageFactory.completeAllImages();
      expect(index.loadedImages[imageId], isTrue);
    });

    test('Stale localStorage entry with mismatched CRC32 is evicted on load', () {
      index.verifyImageHashes = true;
      index.expectedImageHashes = {
        'lion88.png': crc32FromPngDataUrl(EMPTY_IMAGE_DATA_STRING)!,
      };
      localStorage['imglion88.png'] =
          'data:image/png;base64,${base64Encode([9, 9, 9, 9])}';
      localStorage['timglion88.png'] =
          DateTime.now().millisecondsSinceEpoch.toString();

      index.loadImagesFromNetwork();

      expect(localStorage['imglion88.png'], isNull);
      expect(localStorage['timglion88.png'], isNull);
      expect(index.imageIsLoading(index.getImageIdByName('lion88.png')), isFalse);
    });

    test('Raw fetch preserves exact PNG data URL without canvas re-encoding', () async {
      index.verifyImageHashes = true;
      index.expectedImageHashes = {
        'lion88.png': crc32FromPngDataUrl(EMPTY_IMAGE_DATA_STRING)!,
      };
      fakeImageFactory.mockFetchedDataUrls = {
        './img/lion88.png': EMPTY_IMAGE_DATA_STRING,
      };
      index.loadImagesFromNetwork();

      int imageId = index.getImageIdByName('lion88.png');
      await index.addSingleImage('lion88.png');

      expect(index.imageIsLoaded(imageId), isTrue);
      expect(index.getImageDataUrl(imageId), equals(EMPTY_IMAGE_DATA_STRING));
      expect(localStorage['imglion88.png'], equals(EMPTY_IMAGE_DATA_STRING));
    });

    test('Corrupt image decode triggers onError fallback instead of hanging', () async {
      expectWarningContaining('decode error');
      index.verifyImageHashes = false;
      index.loadImagesFromNetwork();
      int imageId = index.getImageIdByName('lion88.png');

      // Valid base64 prefix, but invalid PNG bytes -> browser fires img.onError.
      String undecodablePng =
          'data:image/png;base64,${base64Encode([0, 1, 2, 3, 4, 5])}';
      await index.addFromImageData(imageId, undecodablePng, true);

      // onError fired and triggered addSingleImage('lion88.png') fallback.
      expect(index.loadedImages[imageId], isNull);
      expect(localStorage['imglion88.png'], isNull);

      await fakeImageFactory.completeAllImages();
      expect(index.loadedImages[imageId], isTrue);
    });
  });
}
