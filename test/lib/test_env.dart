import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'fake_canvas.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';
import 'package:dart2d/res/imageindex.dart';
import 'test_peer.dart';
import 'test_connection.dart';

clearEnvironment() {
  testConnections.clear();
  testPeers.clear();
}

setPlayerName(Injector i) {
  Map storage = i.get(Map, LocalStorage);
  PlayerWorldSelector selector = i.get(PlayerWorldSelector);
  WormWorld world = i.get(WormWorld);
  storage['playerName'] =
  "name${world.network().peer.getId().toString().toUpperCase()}";
  storage['playerSprite'] = "lion88.png";
  selector.setMapForTest("lion88.png");
}

setPlayerNameAndSignalOpen(Injector i) {
  Map storage = i.get(Map, LocalStorage);
  PlayerWorldSelector selector = i.get(PlayerWorldSelector);
  WormWorld world = i.get(WormWorld);
  storage['playerName'] =
      "name${world.network().peer.getId().toString().toUpperCase()}";
  storage['playerSprite'] = "lion88.png";
  selector.setMapForTest("lion88.png");
  TestServerChannel channel = i.get(TestServerChannel);
  channel.sendOpenMessage();
}

Injector createWorldInjector(String id, [bool loadImages = true]) {
  TestServerChannel channel = new TestServerChannel(id);
  FakeCanvas fakeCanvas = new FakeCanvas();
  FakeImageFactory fakeImageFactory = new FakeImageFactory();
  TestConnectionFactory connectionFactory = new TestConnectionFactory();
  FpsCounter frameCounter = new FpsCounter();
  frameCounter.setFpsForTest(45.0);
  ModuleInjector injector = new ModuleInjector([
    new Module()
      // Test only.
      ..bind(TestConnectionFactory, toValue: connectionFactory)
      ..bind(GaReporter, toValue: new FakeGaReporter())
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
}

class FakeGaReporter extends GaReporter {
  reportEvent(String action, [String category, int count, String label]) {
    print("Reported event $action");
  }
}
