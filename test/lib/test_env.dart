import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'package:injectable/injectable.dart';
import 'test_injector.config.dart';
import 'fake_canvas.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';
import 'test_injector.dart';
import 'test_mocks.mocks.dart';
import 'test_peer.dart';
import 'test_connection.dart';



// Map of connections from id.
Map<String, List<TestConnection>> testConnections = {};
bool logConnectionData = true;

Map<String, List<String>> configParameters = {};

@module
abstract class EnvModule {
  @Named(URI_PARAMS_MAP)
  Map<String, List<String>> get params => configParameters;
  @Named(WORLD_WIDTH)
  int get width => 1024;
  @Named(WORLD_HEIGHT)
  int get height => 768;
  @Named(TOUCH_SUPPORTED)
  bool get touch => false;
  @Named(RELOAD_FUNCTION)
  Function get reload => () { };
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
}

Future<WormWorld> createTestWorld(String id,  {
  bool signalPeerOpen = true,
  bool setPlayer = true,
  bool setPlayerImage = true,
  bool selectMap = true,
  bool completeLoader = true,
  bool loadImages = true,
  bool initByteWorld = true}) async {
  return getIt.popScopesTill('world').then((_) {
    serverChannelPeerId = id;
    getIt.initWorldScope();

    WormWorld world = getIt<WormWorld>();

    if (signalPeerOpen) {
      signalOpen(world);
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
      world.initByteWorld("lion88.png");
    }
    ConnectionFrameHandler.DISABLE_AUTO_ADJUST_FOR_TEST = true;
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

signalOpen(WormWorld w, [List<String> existingPeers = const[]]) {
  TestServerChannel channel = w.network().peer.serverChannel as TestServerChannel;
  channel.sendOpenMessage(existingPeers);
}

dynamic createWorldInjector(String id, [bool loadImages = true]) {
  /*
  TestServerChannel channel = new TestServerChannel(id);
  FakeCanvas fakeCanvas = new FakeCanvas();
  FakeImageFactory fakeImageFactory = new FakeImageFactory();
  if (!loadImages) {
    fakeImageFactory.completeImagesAsap = true;
  }
  TestConnectionFactory connectionFactory = new TestConnectionFactory();
  FpsCounter frameCounter = new FpsCounter();
  frameCounter.setFpsForTest(45.0);

  ModuleInjector injector = new ModuleInjector([
    new Module()
      // Test only.
      ..bind(TestConnectionFactory, toValue: connectionFactory)
      ..bind(TestServerChannel, toValue: channel)
      ..bind(FakeImageFactory, toValue: fakeImageFactory)
      ..bind(ConnectionFactory, toValue: connectionFactory)
      ..bind(FakeImageDataFactory, toValue: new FakeImageDataFactory())
      // World bindings.
      ..bind(ServerChannel, toValue: channel)
      ..bind(int, withAnnotation: const WorldWidth(), toValue: fakeCanvas.width)
      ..bind(int,
          withAnnotation: const WorldHeight(), toValue: fakeCanvas.height)
      ..bind(DynamicFactory,
          withAnnotation: const CanvasFactory(),
          toValue: new DynamicFactory((args) => new FakeCanvas()))
      ..bind(DynamicFactory,
          withAnnotation: const ImageFactory(), toInstanceOf: FakeImageFactory)
      ..bind(DynamicFactory,
          withAnnotation: const ImageDataFactory(),
          toInstanceOf: FakeImageDataFactory)
      ..bind(Object,
          withAnnotation: const WorldCanvas(), toValue: new FakeCanvas())
      ..bind(bool, withAnnotation: const TouchControls(), toValue: false)
      ..bind(Map, withAnnotation: const LocalStorage(), toValue: {})
      ..bind(Map, withAnnotation: const UriParameters(), toValue: {})
      ..bind(KeyState,
          withAnnotation: const LocalKeyState(), toValue: new KeyState())
      ..install(new UtilModule())
      ..install(new NetModule())
      ..install(new WorldModule())
      ..bind(Object,
          withAnnotation: const HtmlScreen(), toValue: new FakeScreen())
      ..bind(DynamicFactory,
          withAnnotation: const ReloadFactory(),
          toValue: new DynamicFactory((args) {
            print("Want to reload the world! Not available in tests...");
          }))
      ..bind(FpsCounter,
          withAnnotation: const ServerFrameCounter(), toValue: frameCounter)
      ..bind(ImageIndex)
      ..bind(SpriteIndex)
  ]);
  if (loadImages) {
    injector.get(ImageIndex).useEmptyImagesForTest();
  }
  injector.get(PowerupManager).setNextPowerForTest(1000.0);
  return injector;
  */
}

@Injectable(as: GaReporter)
class FakeGaReporter extends GaReporter {
  reportEvent(String action, [String? category, int count = 1, String? label]) {
    print("Reported event $action $category $label");
  }
}

@Injectable(as: CanvasFactory)
class FakeCanvasFactory implements CanvasFactory {
  FakeCanvas  fakeCanvas = FakeCanvas();
  @override
  createCanvas(int width, height) {
    return fakeCanvas;
  }
}