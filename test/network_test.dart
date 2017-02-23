import 'package:dart2d/net/net.dart';
import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/phys/vec2.dart';

class MockRemotePlayerClientSprite extends Mock implements LocalPlayerSprite {
  Vec2 size = new Vec2(1, 1);
  PlayerInfo info = new PlayerInfo('a', 'a', 123);
}

void main() {
  final FAKE_ENABLED_KEYS = {'1': true};
  PacketListenerBindings packetListenerBindings;
  MockHudMessages mockHudMessages;
  MockSpriteIndex mockSpriteIndex;
  MockImageIndex mockImageIndex;
  MockFpsCounter mockFpsCounter;
  MockKeyState mockKeyState;
  TestPeer peer;
  GameState gameState;
  Network network;
  MockWormWorld mockWormWorld;
  TestConnection connectionB;
  TestConnection connectionC;

  setUp(() {
    logOutputForTest();
    clearEnvironment();
    remapKeyNamesForTest();
    mockHudMessages = new MockHudMessages();
    mockImageIndex = new MockImageIndex();
    mockSpriteIndex = new MockSpriteIndex();
    mockFpsCounter = new MockFpsCounter();
    mockWormWorld = new MockWormWorld();
    mockKeyState = new MockKeyState();
    packetListenerBindings = new PacketListenerBindings();
    gameState = new GameState(packetListenerBindings, mockSpriteIndex);
    peer = new TestPeer('a');
    network = new Network(
        new FakeGaReporter(),
        mockHudMessages,
        gameState,
        packetListenerBindings,
        mockFpsCounter,
        peer,
        new FakeJsCallbacksWrapper(),
        mockSpriteIndex,
        mockKeyState);
    network.world = mockWormWorld;
    when(mockFpsCounter.fps()).thenReturn(15.0);
    when(mockWormWorld.network()).thenReturn(network);
    when(mockWormWorld.imageIndex()).thenReturn(mockImageIndex);
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

  tearDown(() {
    assertNoLoggedWarnings();
  });

  frame([double duration = 0.01]) {
    network.frame(duration, new List());
  }

  test('Test basic client network update single connection', () {
    frame();

    network.peer.connectPeer(null, connectionB);

    frame();
    expect(connectionC.decodedRecentDataRecevied(),
        equals({KEY_STATE_KEY: FAKE_ENABLED_KEYS, KEY_FRAME_KEY: 0}));

    _TestSprite sprite = new _TestSprite.withVecPosition(1000, new Vec2(9, 9));
    sprite.color = "rgba(1, 2, 3, 1.0)";
    when(mockSpriteIndex.spriteIds()).thenReturn(new List.filled(1, 1000));
    when(mockSpriteIndex[1000]).thenReturn(sprite);

    frame();

    // Full state sent over network.
    expect(
        connectionC.decodedRecentDataRecevied()['1000'],
        equals([
          sprite.extraSendFlags(),
          9,
          9,
          0,
          180000,
          180000,
          SpriteConstructor.DAMAGE_PROJECTILE.index,
          1,
          "rgba(1, 2, 3, 1.0)",
          2,
          2,
          1,
          0
        ]));

    // Sprites only send full state of a while.
    while (sprite.fullFramesOverNetwork > 0) {
      frame();
    }

    // Now only delta updates.
    network.frame(0.01, new List());
    expect(
        connectionC.decodedRecentDataRecevied()['1000'],
        equals([
          sprite.extraSendFlags(),
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

    frame();

    expectWarningContaining("CLIENT_TO_SERVER connection without being server");

    int connectionNr = 0;
    for (TestConnection connection in connections.values) {
      connection.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        KEY_FRAME_KEY: 0
      });
      connectionNr++;
    }

    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS));

    // We got a gamestate with commanderId set.
    // TODO set more!
    network.gameState.actingCommanderId = '0';
    // And we now have a server connection.
    expect(network.getServerConnection(), isNotNull);

    // Close down every connection.
    for (TestConnection connection in connections.values) {
      connection.getOtherEnd().signalClose();
    }
    expect(network.safeActiveConnections().length, equals(0));
  });

  TestConnection fakeConnection(String from, String to) {
    TestConnection connectionD = new TestConnection(from);
    TestConnection connectionOtherEndD = new TestConnection(to);
    connectionOtherEndD.setOtherEnd(connectionD);
    connectionOtherEndD.bindOnHandler('data', (unused, data) {
      print("Got data ${data}");
    });
    connectionD.setOtherEnd(connectionOtherEndD);
    return connectionD;
  }

  test('Test set as acting commander but we suck too much to be commander :(',
      () {
    TestConnection connectionD = fakeConnection('d', 'e');
    TestConnection connectionF = fakeConnection('f', 'g');

    network.peer.connectPeer(null, connectionB);
    network.peer.connectPeer(null, connectionD);
    network.peer.connectPeer(null, connectionF);

    // Only mark two connections as having active game.
    for (ConnectionWrapper connection
        in network.safeActiveConnections().values) {
      if (connection.id == 'd' || connection.id == 'f') {
        connection.setHandshakeReceived();
      }
    }

    network.gameState.addPlayerInfo(new PlayerInfo('Name a', 'a', -1));
    network.setAsActingCommander();
    expect(network.isCommander(), isTrue);

    // We have two connections.
    expect(new Set.from(network.safeActiveConnections().keys),
        equals(['b', 'd', 'f']));

    frame();

    expect(network.slowCommandingFrames(), 0);

    // We're running out of CPU or running in the background or something.
    when(mockFpsCounter.fps()).thenReturn(0.01);

    frame();
    expect(network.slowCommandingFrames(), 1);

    // PlayerD is no a suitable candidate.
    PlayerInfo playerDInfo = new PlayerInfo('Name d', 'd', -1);
    PlayerInfo playerFInfo = new PlayerInfo('Name f', 'f', -1);
    playerDInfo.fps = 2;
    playerFInfo.fps = 10;
    network.gameState..addPlayerInfo(playerDInfo)..addPlayerInfo(playerFInfo);

    int max = 10;
    while (network.slowCommandingFrames() > 0 && max-- > 0) {
      print("waiting for command transfer");
      frame();
    }

    // We signaled a transfer to another active game connection.
    // We picked F since that has the highest current FPS.
    expect(connectionF.getOtherEnd().decodedRecentDataRecevied().keys,
        contains(TRANSFER_COMMAND));
  });

  test('Test no game no active commander', () {
    network.peer.connectPeer(null, connectionB);
    expect(network.isCommander(), isFalse);
    expect(network.safeActiveConnections(), hasLength(1));

    connectionB.getOtherEnd().sendAndReceivByOtherPeerNativeObject({
      PING: (new DateTime.now().millisecondsSinceEpoch - 1000),
      KEY_FRAME_KEY: 0
    });

    // Now close it.
    connectionB.signalClose();
    frame();
    // We didn't do anything. No game underway!
    expect(network.isCommander(), isFalse);
  });

  test('Test transfer commander to self', () {
    TestConnection connectionD = new TestConnection('d');
    TestConnection connectionOtherEndD = new TestConnection('e');
    connectionOtherEndD.setOtherEnd(connectionD);
    connectionOtherEndD.bindOnHandler('data', (unused, data) {
      print("Got data ${data}");
    });
    connectionD.setOtherEnd(connectionOtherEndD);

    // Connect to two peers.
    network.peer.connectPeer(null, connectionB);
    network.peer.connectPeer(null, connectionD);

    for (ConnectionWrapper connection
        in network.safeActiveConnections().values) {
      connection.setHandshakeReceived();
    }

    frame();

    connectionB.getOtherEnd().sendAndReceivByOtherPeerNativeObject({
      PING: (new DateTime.now().millisecondsSinceEpoch - 1000),
      KEY_FRAME_KEY: 0
    });
    connectionOtherEndD.sendAndReceivByOtherPeerNativeObject({
      PING: (new DateTime.now().millisecondsSinceEpoch - 1000),
      KEY_FRAME_KEY: 0
    });

    MockRemotePlayerClientSprite sprite = new MockRemotePlayerClientSprite();
    when(mockSpriteIndex[1]).thenReturn(sprite);
    when(mockSpriteIndex[2]).thenReturn(sprite);
    when(mockSpriteIndex[3]).thenReturn(sprite);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    network.gameState.actingCommanderId = 'b';
    network.gameState.addPlayerInfo(new PlayerInfo("testC", "c", 1));
    network.gameState.addPlayerInfo(new PlayerInfo("testB", "d", 2));
    network.gameState.addPlayerInfo(new PlayerInfo("testB", "a", 3));

    expect(network.getServerConnection(), isNotNull);
    network.getServerConnection().setHandshakeReceived();
    expect(network.getServerConnection().isValidGameConnection(), isTrue);
    expect(network.gameState.isInGame('a'), isTrue);

    frame();

    connectionB.signalClose();

    frame();

    // We are now the commander.
    expect(network.isCommander(), isTrue);

    // Assert state of connections.
    expect(network.safeActiveConnections(), hasLength(1));
    expect(network.getServerConnection(), isNull);
  });

  test('Test explicit command transfer', () {
    network.peer.connectPeer(null, connectionB);

    for (ConnectionWrapper connection in network.safeActiveConnections().values) {
      connection.setHandshakeReceived();
    }

    MockRemotePlayerClientSprite sprite = new MockRemotePlayerClientSprite();
    when(mockSpriteIndex[1]).thenReturn(sprite);
    when(mockSpriteIndex[2]).thenReturn(sprite);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    network.gameState.actingCommanderId = 'b';
    network.gameState.addPlayerInfo(new PlayerInfo("testC", "a", 1));
    network.gameState.addPlayerInfo(new PlayerInfo("testB", "b", 2));

    network.getServerConnection().setHandshakeReceived();
    expect(network.getServerConnection().isValidGameConnection(), isTrue);

    // We haven't finished loading yet...
    when(mockWormWorld.loaderCompleted()).thenReturn(false);

    expectWarningContaining("Can not transfer command to us before loading has completed");
    connectionB.getOtherEnd().sendAndReceivByOtherPeerNativeObject({
      TRANSFER_COMMAND: 'y',
      KEY_FRAME_KEY: 0
    });

    // We did not accept the command transfer!
    expect(network.isCommander(), isFalse);

    // Now we finished loading.
    when(mockWormWorld.loaderCompleted()).thenReturn(true);

    connectionB.getOtherEnd().sendAndReceivByOtherPeerNativeObject({
      TRANSFER_COMMAND: 'y',
      KEY_FRAME_KEY: 0
    });

    // We accepted the command transfer.
    expect(network.isCommander(), isTrue);
  });

  test('Test find server basic', () {
    List<TestPeer> peers = [];
    List<String> ids = [];
    Map<String, TestConnection> connections = {};
    for (int i = 0; i < 4; i++) {
      TestPeer peer = new TestPeer(i.toString());
      ids.add(i.toString());
      peers.add(peer);
      peer.bindOnHandler('connection', (peer, TestConnection connection) {
        connections[i.toString()] = connection;
        connection.bindOnHandler(
            'data', (TestConnection connection, String data) {});
      });
    }
    // Receive 3 peers.
    network.peer.receivePeers(null, ids);

    expect(network.findServer(), isFalse);

    // All connections got pinged.
    for (TestConnection connection in connections.values) {
      Map data = connection.decodedRecentDataRecevied();
      data[PING] = 123;
      data.remove(CONTAINED_DATA_RECEIPTS);
      expect(data, equals({PING: 123, KEY_FRAME_KEY: 0, IS_KEY_FRAME_KEY: 0}));
      expect(connection.dataReceivedCount, equals(1));
    }

    // Returns pongs for all connection.
    for (TestConnection connection in connections.values) {
      connection.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        KEY_FRAME_KEY: 0
      });
    }

    // Search complete, we didn't find a server :(
    for (int i = 0; i < 4; i++) {
      expect(network.findServer(), isTrue);
    }
    expect(network.getServerConnection(), isNull);
    // No connetions closed.
    expect(network.safeActiveConnections().length, equals(4));
  });

  test('Test find server close/open connections', () {
    List<TestPeer> peers = [];
    List<String> ids = [];
    Map<String, TestConnection> connections = {};
    for (int i = 0; i < 7; i++) {
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

    // Respond with a Pong - this is the server.
    GameState g = new GameState(packetListenerBindings, null);
    g.actingCommanderId = '0';
    connections['0'].sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      GAME_STATE: g.toMap(),
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
    print("Connetions ${network.safeActiveConnections().keys}");
    g.actingCommanderId = '5';
    connections['5'].sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      GAME_STATE: g.toMap(),
      KEY_FRAME_KEY: 0
    });

    // Number 5 came through as our server :)
    expect(network.findServer(), isTrue);
    expect(network.getServerConnection(), isNotNull);

    // aaaand it's gone.
    connections['5'].getOtherEnd().signalClose();

    // No server again.
    expect(network.findServer(), isFalse);

    // Returns pongs for all connections again - no server connection.
    for (TestConnection connection in connections.values) {
      connection.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        KEY_FRAME_KEY: 0
      });
    }

    // We gave up finding a server.
    expectWarningContaining(
        "didn't find any servers, and not able to connect to any more peers. Giving up");
    expect(network.findServer(), isTrue);
    expect(network.getServerConnection(), isNull);
  });

  test('Test find server no peers', () {
    network.peer.receivePeers(null, []);
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

  int extraSendFlags() {
    return 101;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.DAMAGE_PROJECTILE;
  }
}
