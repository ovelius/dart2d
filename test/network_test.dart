import 'package:dart2d/net/net.dart';
import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/phys/vec2.dart';

class MockHudMessages extends Mock implements HudMessages {}
class MockSpriteIndex extends Mock implements SpriteIndex {}
class MockKeyState extends Mock implements KeyState {}

void main() {
  final FAKE_ENABLED_KEYS = {'1': true};
  PacketListenerBindings packetListenerBindings;
  MockHudMessages mockHudMessages;
  MockSpriteIndex mockSpriteIndex;
  MockKeyState mockKeyState;
  TestPeer peer;
  Network network;
  TestConnection connectionB;
  TestConnection connectionC;
  setUp(() {
    mockHudMessages = new MockHudMessages();
    mockSpriteIndex = new MockSpriteIndex();
    mockKeyState = new MockKeyState();
    packetListenerBindings = new PacketListenerBindings();
    peer = new TestPeer('a');
    network = new Network(mockHudMessages, packetListenerBindings, peer,
        new FakeJsCallbacksWrapper(), mockSpriteIndex, mockKeyState);
    network.peer.openPeer(null, 'a');
    when(mockSpriteIndex.spriteIds()).thenReturn(new List());
    when(mockKeyState.getEnabledState()).thenReturn(FAKE_ENABLED_KEYS);
    remapKeyNamesForTest();
    connectionB = new TestConnection('b');
    connectionC = new TestConnection('c');
    connectionB.setOtherEnd(connectionC);
    connectionC.setOtherEnd(connectionB);
    connectionC.bindOnHandler('data', (unused, data) {
      print("Got data ${data}");
    });
  });

  test('Test basic client network update', () {
    network.frame(0.01, new List());

    network.peer.connectPeer(null, connectionB);

    network.frame(0.01, new List());
    expect(connectionC.decodedRecentDataRecevied(),
        equals({KEY_STATE_KEY:FAKE_ENABLED_KEYS, KEY_FRAME_KEY: 0}));

    _TestSprite sprite = new _TestSprite.withVecPosition(1000, new Vec2(9, 9));
    when(mockSpriteIndex.spriteIds()).thenReturn(new List.filled(1, 1000));
    when(mockSpriteIndex[1000]).thenReturn(sprite);

    network.frame(0.01, new List());

    // Full state sent over network.
    expect(connectionC.decodedRecentDataRecevied()['1000'],
        equals([SpriteConstructor.DAMAGE_PROJECTILE.index,101,9,9,0,180000,180000,1,null,2,2,1,0]));

    // Sprites only send full state of a while.
    while (sprite.fullFramesOverNetwork > 0) {
      network.frame(0.01, new List());
    }

    // Now only delta updates.
    // TODO: Reduce this to only send position/velocity?
    network.frame(0.01, new List());
    expect(connectionC.decodedRecentDataRecevied()['1000'],
        equals([SpriteConstructor.DAMAGE_PROJECTILE.index, 101, 9, 9, 0, 180000, 180000]));

  });
}

class _TestSprite extends MovingSprite {
  int drawCalls = 0;
  int frameCalls = 0;
  _TestSprite.withVecPosition(int networkId, Vec2 position)
      : super(position, new Vec2(2.0, 2.0), SpriteType.RECT) {
    this.networkId = networkId;
    this.velocity = new Vec2(position.x * 2, position.y * 2);
  }

  @override
  frame(double duration, int frameStep, [Vec2 gravity]) {
    frameCalls++;
  }

  @override
  draw(var context, bool debug) {
    drawCalls++;
  }

  int sendFlags() {
    return 101;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.DAMAGE_PROJECTILE;
  }
}
