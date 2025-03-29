import 'package:dart2d/worlds/player_world_selector.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';

@GenerateNiceMocks([MockSpec<ImageIndex>()])
@GenerateNiceMocks([MockSpec<Network>()])
@GenerateNiceMocks([MockSpec<HudMessages>()])
@GenerateNiceMocks([MockSpec<PacketListenerBindings>()])
@GenerateNiceMocks([MockSpec<ConnectionFrameHandler>()])
@GenerateNiceMocks([MockSpec<ByteWorld>()])
@GenerateNiceMocks([MockSpec<PeerWrapper>()])
@GenerateNiceMocks([MockSpec<FpsCounter>()])
@GenerateNiceMocks([MockSpec<WormWorld>()])
@GenerateNiceMocks([MockSpec<ConnectionFactory>()])
@GenerateNiceMocks([MockSpec<ConnectionWrapper>()])
@GenerateNiceMocks([MockSpec<KeyState>()])
@GenerateNiceMocks([MockSpec<GameState>()])
@GenerateNiceMocks([MockSpec<SpriteIndex>()])
@GenerateNiceMocks([MockSpec<ChunkHelper>()])
@GenerateNiceMocks([MockSpec<LocalPlayerSprite>()])
@GenerateNiceMocks([MockSpec<PlayerWorldSelector>()])


// class MockImageIndex extends Mock implements ImageIndex {}

class MockConfigParams extends Mock implements ConfigParams { }


