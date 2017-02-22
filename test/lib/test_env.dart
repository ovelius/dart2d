import 'package:dart2d/net/net.dart';
import 'package:dart2d/js_interop/callbacks.dart';
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
  droppedPacketsNextConnection.clear();
  droppedPacketsAfterNextConnection.clear();
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

Injector createWorldInjector(String id, [bool loadImages = true]) {
  TestPeer peer = new TestPeer(id);
  FakeCanvas fakeCanvas = new FakeCanvas();
  FakeImageFactory fakeImageFactory = new FakeImageFactory();
  FpsCounter frameCounter = new FpsCounter();
  frameCounter.setFpsForTest(45.0);
  ModuleInjector injector = new ModuleInjector([
    new Module()
      // Test only.
      ..bind(TestPeer, toValue: peer)
      ..bind(FakeImageFactory, toValue: fakeImageFactory)
      ..bind(FakeImageDataFactory, toValue: new FakeImageDataFactory())
      // World bindings.
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
      ..bind(Object, withAnnotation: const PeerMarker(), toValue: peer)
      ..bind(bool, withAnnotation: const TouchControls(), toValue: false)
      ..bind(Map, withAnnotation: const LocalStorage(), toValue: {})
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
      ..bind(JsCallbacksWrapper, toImplementation: FakeJsCallbacksWrapper)
      ..bind(SpriteIndex)
  ]);
  if (loadImages) {
    injector.get(ImageIndex).useEmptyImagesForTest();
  }
  return injector;
}
