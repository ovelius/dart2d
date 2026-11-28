import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'package:injectable/injectable.dart';
import 'package:web/web.dart';
import 'test_factories.dart';
import 'test_injector.config.dart';
import 'fake_canvas.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/crc32.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/res/sounds.dart';
import 'test_injector.dart';
import 'test_mocks.mocks.dart';
import 'test_peer.dart';
import 'test_connection.dart';



// Map of connections from id.
Map<String, List<TestConnection>> testConnections = {};
bool logConnectionData = true;

Map<String, List<String>> configParameters = {};
bool testTouchSupported = false;

@module
abstract class EnvModule {
  @Named(URI_PARAMS_MAP)
  Map<String, List<String>> get params => configParameters;
  @Named(WORLD_WIDTH)
  int get width => 1024;
  @Named(WORLD_HEIGHT)
  int get height => 768;
  @Named(TOUCH_SUPPORTED)
  bool get touch => testTouchSupported;
  @Named(RELOAD_FUNCTION)
  Function get reload => () { };
  TestConnectionFactory get getConnectionFactory =>
      getIt<ConnectionFactory>() as TestConnectionFactory;
  FakeImageFactory get getImageFactory =>
      getIt<ImageFactory>() as FakeImageFactory;
}

@Singleton(as: LocalStorage, scope: 'world')
class TestLocalStorage extends LocalStorage {
  Map<String, String> _data = {};
  @override
  String? getItem(String key) => _data[key];

  @override
  void remove(String key) => _data.remove(key);

  @override
  void setItem(String key, String value) => _data[key] = value;

  int get length => _data.length;
}

clearEnvironment() {
  testConnections.clear();
  testPeers.clear();
  testTouchSupported = false;
  FakeScreen.mockOrientationType = null;
  (getIt<ConnectionFactory>() as TestConnectionFactory).reset();
}

Future<WormWorld> createTestWorld(String id,  {
  bool signalPeerOpen = true,
  bool setPlayer = true,
  bool setPlayerImage = true,
  bool selectMap = true,
  bool completeLoader = true,
  bool loadImages = true,
  bool initByteWorld = true}) async {
  return getIt.popScopesTill('world').then((_) async {
    serverChannelPeerId = id;
    getIt.initWorldScope();

    WormWorld world = getIt<WormWorld>();
    ByteWorld byteWorld = getIt<ByteWorld>();
    ImageIndex imageIndex = getIt<ImageIndex>();
    // Test worlds use EMPTY_IMAGE_DATA_STRING rather than real PNG files from disk;
    // keep CRC32 verification active using EMPTY_IMAGE_DATA_STRING's hash.
    final int emptyImageHash = crc32FromPngDataUrl(EMPTY_IMAGE_DATA_STRING)!;
    imageIndex.expectedImageHashes = {
      for (String name in IMAGE_SOURCES) name: emptyImageHash,
    };
    final Sounds sounds = getIt<Sounds>();
    final int testSoundHash = crc32FromDataUrl(TEST_SOUND, 'data:audio/')!;
    sounds.expectedSoundHashes = {
      for (Sound s in Sound.values)
        if (s != Sound.SILENCE) s.url: testSoundHash,
    };

    if (signalPeerOpen) {
      await signalOpen(world);
    }
    if (loadImages) {
      world.imageIndex().useEmptyImagesForTest();
    }
    if (setPlayer) {
      setPlayerName(world.network().peer.getId().toString().toUpperCase());
    }
    if (setPlayerImage) {
      setPlayerImageId();
    }
    if (selectMap) {
      setMap();
    }
    if (completeLoader) {
      world.loader.markCompleted();
    }
    if (initByteWorld) {
      byteWorld.setWorldImage(imageIndex.getImageById(2));
      while (!byteWorld.bedrockComputed()) {
        byteWorld.bedrockStep();
      }
    }
    ConnectionFrameHandler.DISABLE_AUTO_ADJUST_FOR_TEST = true;
    // Prevent random powerups from spawning on top of players during unrelated world tests.
    getIt<PowerupManager>().setNextPowerForTest(999.0);
    return world;
  });
}

// Assumes we're inside the world scope.
setPlayerName(String id) {
  LocalStorage localStorage = getIt<LocalStorage>();
  localStorage['playerName'] = "name${id}";
}

setPlayerImageId() {
  LocalStorage localStorage = getIt<LocalStorage>();
  localStorage['playerSprite'] = "lion88.png";
}

setMap() {
  PlayerWorldSelector selector = getIt<PlayerWorldSelector>();
  selector.setMapForTest("lion88.png");
}

Future signalOpen(WormWorld w, [List<String> existingPeers = const[]]) {
  TestServerChannel channel = w.network().peer.serverChannel as TestServerChannel;
  return channel.sendOpenMessage(existingPeers);
}


@Injectable(as: GaReporter)
class FakeGaReporter extends GaReporter {
  reportEvent(String action, [String? category, int count = 1, String? label]) {
    print("Reported event $action $category $label");
  }
}

@Injectable(as: CanvasFactory)
class FakeCanvasFactory implements CanvasFactory {
  @override
  createCanvas(int width, height) {
    HTMLCanvasElement c = HTMLCanvasElement();
    c.width = width;
    c.height = height;
    return c;
  }
}