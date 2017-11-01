import 'package:dart2d/net/net.dart';
import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/phys/vec2.dart';

class MockRemotePlayerClientSprite extends Mock implements LocalPlayerSprite {
  Vec2 size = new Vec2(1, 1);
  PlayerInfo info = new PlayerInfo('a', 'a', 123);
}

class FakeConnectionFactory extends ConnectionFactory {
  Map<String, Map<String, TestConnection>> connections = {};

  connectTo(ConnectionWrapper wrapper, String ourPeerId, String otherPeerId) {
    TestConnection testConnection = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId][otherPeerId] = testConnection;
    wrapper.setRtcConnection(testConnection);
    wrapper.readyDataChannel(testConnection);
    wrapper.open();

    TestConnection otherEnd =
        new TestConnection(ourPeerId, new MockConnectionWrapper());
    testConnection.setOtherEnd(otherEnd);
    otherEnd.setOtherEnd(testConnection);
  }

  createInboundConnection(ConnectionWrapper wrapper, dynamic sdp,
      String otherPeerId, String ourPeerId) {}
  handleCreateAnswer(dynamic connection, String src, String dst) {}
  handleGotAnswer(dynamic connection, dynamic sdp) {}
  handleIceCandidateReceived(dynamic connection, dynamic iceCandidate) {}
}

void main() {
  final FAKE_ENABLED_KEYS = {'1': true};
  PacketListenerBindings packetListenerBindings;
  MockHudMessages mockHudMessages;
  MockSpriteIndex mockSpriteIndex;
  MockImageIndex mockImageIndex;
  MockFpsCounter mockFpsCounter;
  MockKeyState mockKeyState;
  TestServerChannel channel;
  FakeConnectionFactory fakeConnectionFactory;
  GameState gameState;
  Network network;
  MockWormWorld mockWormWorld;

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
    channel = new TestServerChannel('c');

    when(mockFpsCounter.fps()).thenReturn(15.0);
    when(mockWormWorld.imageIndex()).thenReturn(mockImageIndex);
    channel.sendOpenMessage();
    when(mockSpriteIndex.spriteIds()).thenReturn(new List());
    when(mockKeyState.getEnabledState()).thenReturn(FAKE_ENABLED_KEYS);
    remapKeyNamesForTest();

    fakeConnectionFactory = new FakeConnectionFactory();
    network = new Network(
        new FakeGaReporter(),
        fakeConnectionFactory,
        mockHudMessages,
        gameState,
        packetListenerBindings,
        mockFpsCounter,
        channel,
        new ConfigParams({}),
        mockSpriteIndex,
        mockKeyState);
    network.world = mockWormWorld;
    when(mockWormWorld.network()).thenReturn(network);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  frame([double duration = 0.01]) {
    network.frame(duration, new List());
  }

  test('Test basic client network update single connection', () {
    frame();

    network.peer.connectTo('b');
    expect(network.peer.connections.keys, contains('b'));
    network.peer.connections['b'].setHandshakeReceived();
    TestConnection connectionBtoC =
        fakeConnectionFactory.connections['c']['b'].getOtherEnd();

    frame();
    expect(connectionBtoC.decodedRecentDataRecevied(),
        equals({KEY_STATE_KEY: FAKE_ENABLED_KEYS, KEY_FRAME_KEY: 0, FPS: 15, IS_KEY_FRAME_KEY: 0, CONNECTIONS_LIST: [['b', 6000]]}));

    _TestSprite sprite = new _TestSprite.withVecPosition(1000, new Vec2(9, 9));
    sprite.color = "rgba(1, 2, 3, 1.0)";
    when(mockSpriteIndex.spriteIds()).thenReturn(new List.filled(1, 1000));
    when(mockSpriteIndex[1000]).thenReturn(sprite);

    frame(KEY_FRAME_DEFAULT + 0.01);

    // Full state sent over network.
    expect(
        connectionBtoC.decodedRecentDataRecevied()['1000'],
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
    expect(connectionBtoC.decodedRecentDataRecevied()['1000'],
        equals([sprite.extraSendFlags(), 9, 9, 0, 180000, 180000]));
  });

  test('Test many connections different types', () {
    List<TestServerChannel> peers = [];
    List<String> ids = [];
    for (int i = 0; i < 10; i++) {
      TestServerChannel peer = new TestServerChannel(i.toString());
      ids.add(i.toString());
      peers.add(peer);
    }
    channel.sendOpenMessage(ids);
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS));

    frame();

    expectWarningContaining("CLIENT_TO_SERVER connection without being server");

    int connectionNr = 0;
    for (TestConnection connection
        in fakeConnectionFactory.connections['c'].values) {
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
    for (TestConnection connection
        in fakeConnectionFactory.connections['c'].values) {
      connection.signalClose();
    }
    expect(network.safeActiveConnections().length, equals(0));
  });

  test('Test set as acting commander but we suck too much to be commander :(',
      () {
    network.peer.connectTo('1');
    network.peer.connectTo('2');
    network.peer.connectTo('3');

    // Only mark two connections as having active game.
    for (ConnectionWrapper connection
        in network.safeActiveConnections().values) {
      if (connection.id == '1' || connection.id == '3') {
        connection.setHandshakeReceived();
      }
    }

    network.gameState.addPlayerInfo(new PlayerInfo('Name c', 'c', -1));
    network.setAsActingCommander();
    expect(network.isCommander(), isTrue);

    // We have three connections.
    expect(new Set.from(network.safeActiveConnections().keys),
        equals(['1', '2', '3']));

    frame();

    expect(network.slowCommandingFrames(), 0);

    // We're running out of CPU or running in the background or something.
    when(mockFpsCounter.fps()).thenReturn(0.01);

    frame();
    expect(network.slowCommandingFrames(), 1);

    // Player1 is no a suitable candidate.
    PlayerInfo player1Info = new PlayerInfo('Name 1', '1', -1);
    PlayerInfo player3Info = new PlayerInfo('Name 3', '3', -1);
    player1Info.fps = 2;
    player3Info.fps = 10;
    network.gameState..addPlayerInfo(player1Info)..addPlayerInfo(player3Info);

    int max = 10;
    while (network.slowCommandingFrames() > 0 && max-- > 0) {
      print("waiting for command transfer");
      frame();
    }

    // We signaled a transfer to another active game connection.
    // We picked 3 (index 2) since that has the highest current FPS.
    print(fakeConnectionFactory.connections);
    expect(
        fakeConnectionFactory.connections['c']['3']
            .getOtherEnd()
            .decodedRecentDataRecevied()
            .keys,
        contains(TRANSFER_COMMAND));
  });

  test('Test no game no active commander', () {
    network.peer.connectTo('b');
    expect(network.isCommander(), isFalse);
    expect(network.safeActiveConnections(), hasLength(1));

    fakeConnectionFactory.connections['c']['b']
        .sendAndReceivByOtherPeerNativeObject({
      PING: (new DateTime.now().millisecondsSinceEpoch - 1000),
      KEY_FRAME_KEY: 0
    });

    // Now close it.
    fakeConnectionFactory.connections['c']['b'].signalClose();
    frame();
    // We didn't do anything. No game underway!
    expect(network.isCommander(), isFalse);
  });

  test('Test transfer commander to self', () {
    // Connect to two peers.
    network.peer.connectTo('b');
    network.peer.connectTo('d');

    for (ConnectionWrapper connection
        in network.safeActiveConnections().values) {
      connection.setHandshakeReceived();
    }

    frame();

    for (TestConnection connection
        in fakeConnectionFactory.connections['c'].values) {
      connection.sendAndReceivByOtherPeerNativeObject({
        PING: (new DateTime.now().millisecondsSinceEpoch - 1000),
        KEY_FRAME_KEY: 0
      });
    }

    MockRemotePlayerClientSprite sprite = new MockRemotePlayerClientSprite();
    when(mockSpriteIndex[1]).thenReturn(sprite);
    when(mockSpriteIndex[2]).thenReturn(sprite);
    when(mockSpriteIndex[3]).thenReturn(sprite);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    network.gameState.actingCommanderId = 'b';
    network.gameState.addPlayerInfo(new PlayerInfo("testC", "b", 1));
    network.gameState.addPlayerInfo(new PlayerInfo("testB", "d", 2));
    network.gameState.addPlayerInfo(new PlayerInfo("testB", "c", 3));

    expect(network.getServerConnection(), isNotNull);
    network.getServerConnection().setHandshakeReceived();
    expect(network.getServerConnection().isValidGameConnection(), isTrue);
    expect(network.gameState.isInGame('c'), isTrue);

    frame();

    expect(network.isCommander(), isFalse);
    network.getServerConnection().close("Test");

    frame();

    // We are now the commander.
    expect(network.isCommander(), isTrue);

    // Assert state of connections.
    expect(network.safeActiveConnections(), hasLength(1));
    expect(network.getServerConnection(), isNull);
  });

  test('Test network sprite types', () {
    // Connect to two peers.
    network.peer.connectTo('b');
    network.peer.connectTo('d');

    network.gameState.actingCommanderId = 'c';
    gameState.addPlayerInfo(new PlayerInfo("testC", "c", 1));
    expect(network.isCommander(), isTrue);

    for (ConnectionWrapper connection
        in network.safeActiveConnections().values) {
      connection.setHandshakeReceived();
    }

    // Not sent to network.
    _TestSprite sprite = new _TestSprite.withVecPosition(1, Vec2.ONE);
    sprite.networkType = NetworkType.REMOTE_FORWARD;
    sprite.ownerId = 'b';
    when(mockSpriteIndex[1]).thenReturn(sprite);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    // Not sent to network.
    _TestSprite sprite2 = new _TestSprite.withVecPosition(2, Vec2.ONE);
    sprite2.networkType = NetworkType.LOCAL_ONLY;
    when(mockSpriteIndex[2]).thenReturn(sprite2);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    // Sent to network.
    _TestSprite sprite3 = new _TestSprite.withVecPosition(3, Vec2.ONE);
    sprite3.networkType = NetworkType.LOCAL;
    when(mockSpriteIndex[3]).thenReturn(sprite3);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    when(mockSpriteIndex.spriteIds()).thenReturn([1, 2, 3]);

    frame();

    expect(recentSentDataTo("b"),
        new MapKeyMatcher.doesNotContain(sprite.networkId.toString()));
    expect(recentSentDataTo("d"),
        new MapKeyMatcher.doesNotContain(sprite.networkId.toString()));
    expect(recentSentDataTo("b"),
        new MapKeyMatcher.doesNotContain(sprite2.networkId.toString()));
    expect(recentSentDataTo("d"),
        new MapKeyMatcher.doesNotContain(sprite2.networkId.toString()));
    expect(recentSentDataTo("b"),
        new MapKeyMatcher.containsKey(sprite3.networkId.toString()));
    expect(recentSentDataTo("d"),
        new MapKeyMatcher.containsKey(sprite3.networkId.toString()));

    List<int> data = propertiesToIntList(sprite, false);
    TestConnection connectionBtoC =
        fakeConnectionFactory.connections['c']['b'].getOtherEnd();
    connectionBtoC.sendAndReceivByOtherPeerNativeObject(
        {KEY_FRAME_KEY: 1, sprite.networkId.toString(): data});

    // b and d is not connected.
    expect(gameState.isConnected('b', 'd'), isFalse);
    // b should not get this REMOTE_FORWARD, it is the owner of the sprite.
    expect(recentSentDataTo("b"),
        new MapKeyMatcher.doesNotContain(sprite.networkId.toString()));
    // d should get this, since there is no direct connection b -> d yet.
    expect(recentSentDataTo("d"),
        new MapKeyMatcher.containsKey(sprite.networkId.toString()));

    frame(0.1);

    gameState.addPlayerInfo(new PlayerInfo("testB", "b", sprite.networkId));
    PlayerInfo bInfo = gameState.playerInfoByConnectionId('b');
    bInfo.connections = {'d': new ConnectionInfo('d', 100)};

    expect(gameState.isConnected('b', 'd'), isTrue);

    // Sent data again from b.
    connectionBtoC.sendAndReceivByOtherPeerNativeObject(
        {KEY_FRAME_KEY: 1, sprite.networkId.toString(): data});

    // b should not get this REMOTE_FORWARD, it is the owner of the sprite.
    expect(recentSentDataTo("b"),
        new MapKeyMatcher.doesNotContain(sprite.networkId.toString()));
    // d should NOT get it either this time, has we know there is a direct
    // connection here.
    expect(recentSentDataTo("d"),
        new MapKeyMatcher.doesNotContain(sprite.networkId.toString()));
  });

  test('Test explicit command transfer', () {
    network.peer.connectTo('b');

    for (ConnectionWrapper connection
        in network.safeActiveConnections().values) {
      connection.setHandshakeReceived();
    }

    MockRemotePlayerClientSprite sprite = new MockRemotePlayerClientSprite();
    when(mockSpriteIndex[1]).thenReturn(sprite);
    when(mockSpriteIndex[2]).thenReturn(sprite);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    network.gameState.actingCommanderId = 'b';
    expect(network.isCommander(), isFalse);
    network.gameState.addPlayerInfo(new PlayerInfo("testC", "c", 1));
    network.gameState.addPlayerInfo(new PlayerInfo("testB", "b", 2));

    expect(network.isCommander(), isFalse);
    expect(network.getServerConnection().isValidGameConnection(), isTrue);

    // We haven't finished loading yet...
    when(mockWormWorld.loaderCompleted()).thenReturn(false);

    expectWarningContaining(
        "Can not transfer command to us before loading has completed");
    fakeConnectionFactory.connections['c']['b']
        .getOtherEnd()
        .sendAndReceivByOtherPeerNativeObject(
            {TRANSFER_COMMAND: 'y', KEY_FRAME_KEY: 0});

    // We did not accept the command transfer!
    expect(network.isCommander(), isFalse);

    // Now we finished loading.
    when(mockWormWorld.loaderCompleted()).thenReturn(true);

    fakeConnectionFactory.connections['c']['b']
        .getOtherEnd()
        .sendAndReceivByOtherPeerNativeObject(
            {TRANSFER_COMMAND: 'y', KEY_FRAME_KEY: 0});

    // We accepted the command transfer.
    expect(network.isCommander(), isTrue);
  });

  test('Test find server basic', () {
    List<TestServerChannel> peers = [];
    List<String> ids = [];
    for (int i = 0; i < 4; i++) {
      TestServerChannel peer = new TestServerChannel(i.toString());
      ids.add(i.toString());
      peers.add(peer);
    }
    // Receive 4 peers.
    channel.sendOpenMessage(ids);
    expect(network.safeActiveConnections().length, equals(4));

    expect(network.findServer(), isFalse);

    // All connections got pinged.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c'].values) {
      Map data = connection.getOtherEnd().decodedRecentDataRecevied();
      data[PING] = 123;
      data[CONTAINED_DATA_RECEIPTS] = [999];
      expect(
          data,
          equals({
            PING: 123,
            CONTAINED_DATA_RECEIPTS: [999],
            KEY_FRAME_KEY: 0,
            IS_KEY_FRAME_KEY: 0
          }));
      expect(connection.getOtherEnd().dataReceivedCount, equals(1));
    }

    // Returns pongs for all connection.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c'].values) {
      connection.getOtherEnd().sendAndReceivByOtherPeerNativeObject({
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
    List<TestServerChannel> peers = [];
    List<String> ids = [];
    for (int i = 0; i < 7; i++) {
      TestServerChannel peer = new TestServerChannel(i.toString());
      ids.add(i.toString());
      peers.add(peer);
    }
    channel.sendOpenMessage(ids);

    expect(network.findServer(), isFalse);

    // Respond with a Pong - this is the server.
    GameState g = new GameState(packetListenerBindings, null);
    g.actingCommanderId = '0';
    fakeConnectionFactory.connections['c']['0']
        .getOtherEnd()
        .sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      GAME_STATE: g.toMap(),
      KEY_FRAME_KEY: 0
    });

    // We now have a server.
    expect(network.findServer(), isTrue);
    expect(network.getServerConnection(), isNotNull);
    // Close it.
    network.getServerConnection().close("Test");

    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS - 1));

    // No longer having a server.
    expect(network.findServer(), isFalse);
    expect(network.getServerConnection(), isNull);

    // This did not open more connections - as we don't know the type of the other connections yet.
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS - 1));

    // Returns pongs for all connection.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c'].values) {
      connection.getOtherEnd().sendAndReceivByOtherPeerNativeObject({
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
    fakeConnectionFactory.connections['c']['5']
        .getOtherEnd()
        .sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      GAME_STATE: g.toMap(),
      KEY_FRAME_KEY: 0
    });

    // Number 5 came through as our server :)
    expect(network.findServer(), isTrue);
    expect(network.getServerConnection(), isNotNull);

    // aaaand it's gone.
    network.getServerConnection().close("Test");

    // No server again.
    expect(network.findServer(), isFalse);

    // Returns pongs for all connections again - no server connection.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c'].values) {
      connection.getOtherEnd().sendAndReceivByOtherPeerNativeObject({
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
    channel.sendOpenMessage();
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
