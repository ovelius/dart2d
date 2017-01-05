import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/worlds/world_listener.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/hud_messages.dart';
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

Injector createWorldInjector(String id, [bool loadImages = true]) {
  TestPeer peer = new TestPeer(id);
  FakeCanvas fakeCanvas = new FakeCanvas();
  FakeImageFactory fakeImageFactory = new FakeImageFactory();
  ModuleInjector injector = new ModuleInjector([
    new Module()
      // Test only.
      ..bind(TestPeer, toValue: peer)
      ..bind(FakeImageFactory, toValue: fakeImageFactory)
      // World bindings.
      ..bind(int, withAnnotation: const WorldWidth(), toValue: fakeCanvas.width)
      ..bind(int, withAnnotation: const WorldHeight(), toValue: fakeCanvas.height)
      ..bind(DynamicFactory,
          withAnnotation: const CanvasFactory(),
          toValue: new DynamicFactory((args) => new FakeCanvas()))
      ..bind(DynamicFactory, withAnnotation: const ImageFactory(),
          toInstanceOf: FakeImageFactory)
      ..bind(Object,
          withAnnotation: const WorldCanvas(), toValue: new FakeCanvas())
      ..bind(Object, withAnnotation: const PeerMarker(), toValue: peer)
      ..bind(KeyState, withAnnotation: const LocalKeyState(), toValue: new KeyState(null))
      ..bind(WormWorld)
      ..bind(WorldListener)
      ..bind(ChunkHelper)
      ..bind(HudMessages)
      ..bind(ImageIndex)
      ..bind(ByteWorld)
      ..bind(Network)
      ..bind(Loader)
      ..bind(PacketListenerBindings)
      ..bind(JsCallbacksWrapper, toImplementation: FakeJsCallbacksWrapper)
      ..bind(SpriteIndex)
  ]);
  if (loadImages) {
    injector.get(ImageIndex).useEmptyImagesForTest();
  }
  return injector;
}
