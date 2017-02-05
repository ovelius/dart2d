import 'package:mockito/mockito.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';

class MockHudMessages extends Mock implements HudMessages {}

class MockSpriteIndex extends Mock implements SpriteIndex {}

class MockImageIndex extends Mock implements ImageIndex {}

class MockWormWorld extends Mock implements WormWorld {}

class MockFpsCounter extends Mock implements FpsCounter {}

class MockNetwork extends Mock implements Network {}

class MockChunkHelper extends Mock implements ChunkHelper {}

class MockGameState extends Mock implements GameState {}

class MockByteWorld extends Mock implements ByteWorld {}

class MockJsCallbacksWrapper extends Mock implements JsCallbacksWrapper{}

class MockPeerWrapper extends Mock implements PeerWrapper {}