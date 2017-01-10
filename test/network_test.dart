import 'package:dart2d/net/net.dart';
import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

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
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
    clearEnvironment();
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

  test('Test basic client network update single connection', () {
    network.frame(0.01, new List());

    network.peer.connectPeer(null, connectionB);

    network.frame(0.01, new List());
    expect(connectionC.decodedRecentDataRecevied(),
        equals({KEY_STATE_KEY: FAKE_ENABLED_KEYS, KEY_FRAME_KEY: 0}));

    _TestSprite sprite = new _TestSprite.withVecPosition(1000, new Vec2(9, 9));
    when(mockSpriteIndex.spriteIds()).thenReturn(new List.filled(1, 1000));
    when(mockSpriteIndex[1000]).thenReturn(sprite);

    network.frame(0.01, new List());

    // Full state sent over network.
    expect(
        connectionC.decodedRecentDataRecevied()['1000'],
        equals([
          SpriteConstructor.DAMAGE_PROJECTILE.index,
          sprite.sendFlags(),
          9,
          9,
          0,
          180000,
          180000,
          1,
          null,
          2,
          2,
          1,
          0
        ]));

    // Sprites only send full state of a while.
    while (sprite.fullFramesOverNetwork > 0) {
      network.frame(0.01, new List());
    }

    // Now only delta updates.
    // TODO: Reduce this to only send position/velocity?
    network.frame(0.01, new List());
    expect(
        connectionC.decodedRecentDataRecevied()['1000'],
        equals([
          SpriteConstructor.DAMAGE_PROJECTILE.index,
          sprite.sendFlags(),
          9,
          9,
          0,
          180000,
          180000
        ]));
  });

  test('Test many connections differnt types', () {
    List<TestPeer> peers = [];
    List<String> ids = [];
    Map<String, TestConnection> connections = {};
    for (int i = 0; i < 10; i++) {
      TestPeer peer = new TestPeer(i.toString());
      ids.add(i.toString());
      peers.add(peer);
      peer.bindOnHandler('connection', (peer, TestConnection connection) {
        connections[i.toString()] = connection;
        connection.bindOnHandler('data',
            (TestConnection connection, String data) {
          // Unused.
        });
      });
    }
    network.peer.receivePeers(null, ids);
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS));

    network.frame(0.01, new List());

    int connectionNr = 0;
    for (TestConnection connection in connections.values) {
      connection.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        // Signal all types of connection
        CONNECTION_TYPE: connectionNr % ConnectionType.values.length,
        KEY_FRAME_KEY: 0
      });
      connectionNr++;
    }
    // This causes a connection to drop - the one that thinks we are server.
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS - 1));
    // And we now have a server connection.
    expect(network.getServerConnection(), isNotNull);

    for (TestConnection connection in connections.values) {
      connection.getOtherEnd().signalClose();
    }
    expect(network.safeActiveConnections().length, equals(0));
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
