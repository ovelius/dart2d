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
    logOutputForTest();
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

  tearDown((){
    assertNoLoggedWarnings();
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

  test('Test many connections different types', () {
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

    expectWarningContaining("CLIENT_TO_SERVER connection without being server");

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

    // Close down every connection.
    for (TestConnection connection in connections.values) {
      connection.getOtherEnd().signalClose();
    }
    expect(network.safeActiveConnections().length, equals(0));
  });

  test('Test find server', () {
    List<TestPeer> peers = [];
    List<String> ids = [];
    Map<String, TestConnection> connections = {};
    for (int i = 0; i < 10; i++) {
      TestPeer peer = new TestPeer(i.toString());
      ids.add(i.toString());
      peers.add(peer);
      peer.bindOnHandler('connection', (peer, TestConnection connection) {
        connections[i.toString()] = connection;
        connection.bindOnHandler(
            'data', (TestConnection connection, String data) {});
      });
    }
    network.peer.receivePeers(null, ids);

    expect(network.findServer(), isFalse);

    // All connections got pinged.
    for (TestConnection connection in connections.values) {
      Map data = connection.decodedRecentDataRecevied();
      data[PING] = 123;
      expect(
          data,
          equals({
            PING: 123,
            CONNECTION_TYPE: 0,
            KEY_FRAME_KEY: 0,
            IS_KEY_FRAME_KEY: 0
          }));
      expect(connection.dataReceivedCount, equals(1));
    }

    // Respond with a Pong - this is the server.
    connections['0'].sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      // Signal all types of connection
      CONNECTION_TYPE: ConnectionType.SERVER_TO_CLIENT.index,
      KEY_FRAME_KEY: 0
    });

    // We now have a server.
    expect(network.findServer(), isTrue);
    expect(network.getServerConnection(), isNotNull);

    for (TestConnection connection in connections.values) {
      expect(connection.dataReceivedCount, equals(1));
    }

    // Close it.
    network.getServerConnection().close(null);

    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS - 1));

    // No longer having a server.
    expect(network.findServer(), isFalse);
    expect(network.getServerConnection(), isNull);

    // This did not open more connections - as we don't know the type of the other connections yet.
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS - 1));

    // Returns pongs for all connection.
    for (TestConnection connection in connections.values) {
      connection.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        // Signal all types of connection
        CONNECTION_TYPE: ConnectionType.BOOTSTRAP.index,
        KEY_FRAME_KEY: 0
      });
    }

    // Still false.
    expect(network.findServer(), isFalse);
    expect(network.findServer(), isFalse);
    expect(network.findServer(), isFalse);

    // We're back at max connections again.
    expect(network.safeActiveConnections().length,
         equals(PeerWrapper.MAX_AUTO_CONNECTIONS));

    // Respond with a Pong - this is the server.
    connections['6'].sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      // Signal all types of connection
      CONNECTION_TYPE: ConnectionType.SERVER_TO_CLIENT.index,
      KEY_FRAME_KEY: 0
    });

    // Number 6 came through as our server :)
    expect(network.findServer(), isTrue);
    expect(network.getServerConnection(), isNotNull);

    // aaaand it's gone.
    connections['6'].getOtherEnd().signalClose();

    // No server again.
    expect(network.findServer(), isFalse);

    // Returns pongs for all connections again - no server connection.
    for (TestConnection connection in connections.values) {
      connection.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        // Signal all types of connection
        CONNECTION_TYPE: ConnectionType.BOOTSTRAP.index,
        KEY_FRAME_KEY: 0
      });
    }

    // We gave up finding a server.
    expectWarningContaining("didn't find any servers, and not able to connect to any more peers. Giving up");
    expect(network.findServer(), isTrue);
    expect(network.getServerConnection(), isNull);
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
