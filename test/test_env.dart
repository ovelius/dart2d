import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/worlds/sprite_index.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'fake_canvas.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';
import 'package:dart2d/res/imageindex.dart';
import 'test_peer.dart';

Injector createWorldInjector(String id) {
  TestPeer peer = new TestPeer(id);
  ModuleInjector injector = new ModuleInjector([
    new Module()
      ..bind(int, withAnnotation: const WorldWidth(), toValue: WIDTH)
      ..bind(int, withAnnotation: const WorldHeight(), toValue: HEIGHT)
      ..bind(DynamicFactory,
          withAnnotation: const CanvasFactory(),
          toValue: new DynamicFactory((args) => new FakeCanvas()))
      ..bind(DynamicFactory, withAnnotation: const ImageFactory(),
          toValue: new DynamicFactory((args) {
        if (args.length == 0) {
          return new FakeImage();
        } else {
          return new FakeImage();
        }
      }))
      ..bind(Object,
          withAnnotation: const WorldCanvas(), toValue: new FakeCanvas())
      ..bind(Object, withAnnotation: const PeerMarker(), toValue: peer)
      ..bind(WormWorld)
      ..bind(ChunkHelper)
      ..bind(ImageIndex)
      ..bind(JsCallbacksWrapper, toImplementation: FakeJsCallbacksWrapper)
      ..bind(SpriteIndex)
  ]);
  injector.get(ImageIndex).useEmptyImagesForTest();
  return injector;
}
