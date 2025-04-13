import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:test/test.dart';
import 'package:fixnum/fixnum.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/phys/vec2.dart';
import 'lib/test_mocks.mocks.dart';

class MockRemotePlayerClientSprite extends Mock implements LocalPlayerSprite {
  Vec2 size = new Vec2(1, 1);
  PlayerInfoProto info = PlayerInfoProto()
      ..connectionId = "a"
      ..spriteId = 123
      ..name = 'nameA';
}

class FakeConnectionFactory extends ConnectionFactory {
  Map<String, Map<String, TestConnection>> connections = {};

  connectTo(dynamic wrapper, Negotiator negotiator) {
    String otherPeerId = negotiator.otherId;
    String ourPeerId = negotiator.ourId;
    TestConnection testConnection = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId]![otherPeerId] = testConnection;
    wrapper.setRtcConnection(testConnection);
    wrapper.readyDataChannel(testConnection);
    wrapper.open();

    TestConnection otherEnd =
    new TestConnection(ourPeerId, new MockConnectionWrapper());
    testConnection.setOtherEnd(otherEnd);
    otherEnd.setOtherEnd(testConnection);
  }
  createInboundConnection(ConnectionWrapper wrapper, Negotiator negotiator, WebRtcDanceProto proto) {}
  handleGotAnswer(dynamic connection, dynamic sdp) {}
}

void main() {
  final FAKE_ENABLED_KEYS = {'1': true};
  late PacketListenerBindings packetListenerBindings;
  late MockHudMessages mockHudMessages;
  late MockSpriteIndex mockSpriteIndex;
  late MockImageIndex mockImageIndex;
  late MockFpsCounter mockFpsCounter;
  late MockKeyState mockKeyState;
  late TestServerChannel channelC;
  late TestServerChannel channelB;
  late FakeConnectionFactory fakeConnectionFactory;
  late GameState gameState;
  late Network network;
  late MockWormWorld mockWormWorld;

  setUpAll((){
    configureDependencies();
  });

  setUp(() {
    logOutputForTest();
    clearEnvironment();
    mockHudMessages = new MockHudMessages();
    mockImageIndex = new MockImageIndex();
    mockSpriteIndex = new MockSpriteIndex();
    mockFpsCounter = new MockFpsCounter();
    mockWormWorld = new MockWormWorld();
    mockKeyState = new MockKeyState();
    packetListenerBindings = new PacketListenerBindings();
    gameState = new GameState(packetListenerBindings, mockSpriteIndex);
    channelC = new TestServerChannel.withExplicitId("c");
    channelB = new TestServerChannel.withExplicitId("b");

    when(mockFpsCounter.fps()).thenReturn(15.0);
    when(mockWormWorld.imageIndex()).thenReturn(mockImageIndex);
    channelC.sendOpenMessage();
    when(mockSpriteIndex.spriteIds()).thenReturn([]);
    when(mockKeyState.getEnabledState()).thenReturn(FAKE_ENABLED_KEYS);

    fakeConnectionFactory = new FakeConnectionFactory();
    network = new Network(
        new FakeGaReporter(),
        fakeConnectionFactory,
        mockHudMessages,
        gameState,
        packetListenerBindings,
        mockFpsCounter,
        channelC,
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
    network.frame(duration, []);
  }


  test('Test connection setup', () {
    frame();
    network.peer.connectTo('b');

    expect(fakeConnectionFactory.connections, {
      'c': {'b': TestConnection('b', null)},
    });

    TestConnection connection = fakeConnectionFactory.connections['c']!['b']!;
    expect(connection.getOtherEnd(), isNotNull);
  });

  test('Test many connections different types', () {
    List<TestServerChannel> peers = [];
    List<String> ids = [];
    for (int i = 0; i < 10; i++) {
      serverChannelPeerId = "channel-$i";
      TestServerChannel peer = new TestServerChannel();
      ids.add(i.toString());
      peers.add(peer);
    }
    channelC.sendOpenMessage(ids);
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS));

    frame();

    expectWarningContaining("CLIENT_TO_SERVER connection without being server");

    for (TestConnection connection
        in fakeConnectionFactory.connections['c']!.values) {
      connection.sendAndReceivByOtherPeerNativeObject(
        GameStateUpdates()
      );
    }

    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS));

    // We got a gamestate with commanderId set.
    // TODO set more!
    network.gameState.gameStateProto.actingCommanderId = '0';
    // And we now have a server connection.
    expect(network.getServerConnection(), isNotNull);

    // Close down every connection.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c']!.values) {
      connection.signalClose();
    }
    expect(network.safeActiveConnections().length, equals(0));
  });


  test('Test no game no active commander', () {
    network.peer.connectTo('b');
    expect(network.isCommander(), isFalse);
    expect(network.safeActiveConnections(), hasLength(1));

    fakeConnectionFactory.connections['c']!['b']!
        .sendAndReceivByOtherPeerNativeObject(
      GameStateUpdates()
    );

    // Now close it.
    fakeConnectionFactory.connections['c']!['b']!.signalClose();
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
        in fakeConnectionFactory.connections['c']!.values) {
      connection.sendAndReceivByOtherPeerNativeObject(
        GameStateUpdates()
            ..stateUpdate.add(StateUpdate()..ping = Int64(111))
      );
    }

    MockLocalPlayerSprite sprite = MockLocalPlayerSprite();
    when(mockSpriteIndex[1]).thenReturn(sprite);
    when(mockSpriteIndex[2]).thenReturn(sprite);
    when(mockSpriteIndex[3]).thenReturn(sprite);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    network.gameState.gameStateProto.actingCommanderId = 'b';
    network.gameState.addPlayerInfo(PlayerInfoProto("testC", "b", 1));
    network.gameState.addPlayerInfo(PlayerInfoProto("testB", "d", 2));
    network.gameState.addPlayerInfo(PlayerInfoProto("testB", "c", 3));

    expect(network.getServerConnection(), isNotNull);
    network.getServerConnection()!.setHandshakeReceived();
    expect(network.getServerConnection()!.isValidGameConnection(), isTrue);
    expect(network.gameState.isInGame('c'), isTrue);

    frame();

    expect(network.isCommander(), isFalse);
    network.getServerConnection()!.close("Test");

    frame();

    // We are now the commander.
    expect(network.isCommander(), isTrue);

    // Assert state of connections.
    expect(network.safeActiveConnections(), hasLength(1));
    expect(network.getServerConnection(), isNull);
  });

  /*
  test('Test network sprite types', () {
    serverChannelPeerId = "d";
    TestServerChannel channelD = TestServerChannel();
    // Connect to two peers.
    network.peer.connectTo('b');
    network.peer.connectTo('d');

    network.gameState.gameStateProto.actingCommanderId = 'c';
    gameState.addPlayerInfo(PlayerInfoProto("testC", "c", 1));
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

    List<dynamic> data = propertiesToIntList(sprite, false);
    TestConnection connectionBtoC =
        fakeConnectionFactory.connections['c']!['b']!.getOtherEnd()!;
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

    gameState.addPlayerInfo(PlayerInfoProto("testB", "b", sprite.networkId!));
    PlayerInfoProto bInfo = gameState.playerInfoByConnectionId('b')!;
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

    MockLocalPlayerSprite sprite = MockLocalPlayerSprite();
    when(mockSpriteIndex[1]).thenReturn(sprite);
    when(mockSpriteIndex[2]).thenReturn(sprite);
    when(mockImageIndex.getImageById(any)).thenReturn(new FakeImage());

    network.gameState.actingCommanderId = 'b';
    expect(network.isCommander(), isFalse);
    network.gameState.addPlayerInfo(PlayerInfoProto("testC", "c", 1));
    network.gameState.addPlayerInfo(PlayerInfoProto("testB", "b", 2));

    expect(network.isCommander(), isFalse);
    expect(network.getServerConnection()!.isValidGameConnection(), isTrue);

    // We haven't finished loading yet...
    when(mockWormWorld.loaderCompleted()).thenReturn(false);

    expectWarningContaining(
        "Can not transfer command to us before loading has completed");
    fakeConnectionFactory.connections['c']!['b']!
        .getOtherEnd()!
        .sendAndReceivByOtherPeerNativeObject(
            {TRANSFER_COMMAND: 'y', KEY_FRAME_KEY: 0});

    // We did not accept the command transfer!
    expect(network.isCommander(), isFalse);

    // Now we finished loading.
    when(mockWormWorld.loaderCompleted()).thenReturn(true);

    fakeConnectionFactory.connections['c']!['b']!
        .getOtherEnd()!
        .sendAndReceivByOtherPeerNativeObject(
            {TRANSFER_COMMAND: 'y', KEY_FRAME_KEY: 0});

    // We accepted the command transfer.
    expect(network.isCommander(), isTrue);
  }); */

  test('Test find server basic', () {
    List<TestServerChannel> peers = [];
    List<String> ids = [];
    for (int i = 0; i < 4; i++) {
      serverChannelPeerId = "peer-$i";
      TestServerChannel peer = new TestServerChannel();
      ids.add(serverChannelPeerId);
      peers.add(peer);
    }
    // Receive 4 peers.
    channelC.sendOpenMessage(ids);
    expect(network.safeActiveConnections().length, equals(4));

    expect(network.findActiveGameConnection(), isFalse);

    // All connections got pinged.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c']!.values) {
      Map data = connection.getOtherEnd()!.decodedRecentDataRecevied();
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
      expect(connection.getOtherEnd()!.dataReceivedCount, equals(1));
    }

    // Returns pongs for all connection.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c']!.values) {
      connection.getOtherEnd()!.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        KEY_FRAME_KEY: 0
      });
    }

    // Search complete, we didn't find a server :(
    for (int i = 0; i < 4; i++) {
      expect(network.findActiveGameConnection(), isTrue);
    }
    expect(network.getServerConnection(), isNull);
    // No connetions closed.
    expect(network.safeActiveConnections().length, equals(4));
  });

  test('Test find server close/open connections', () {
    List<TestServerChannel> peers = [];
    List<String> ids = [];
    for (int i = 0; i < 7; i++) {
      serverChannelPeerId = "channel-$i";
      TestServerChannel peer = new TestServerChannel();
      ids.add(i.toString());
      peers.add(peer);
    }
    channelC.sendOpenMessage(ids);

    expect(network.findActiveGameConnection(), isFalse);

    // Respond with a Pong - this is the server.
    GameState g = new GameState(packetListenerBindings, MockSpriteIndex());
    g.gameStateProto.actingCommanderId = '0';
    fakeConnectionFactory.connections['c']!['0']!
        .getOtherEnd()!
        .sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      GAME_STATE: g.toMap(),
      KEY_FRAME_KEY: 0
    });

    // We now have a server.
    expect(network.findActiveGameConnection(), isTrue);
    expect(network.getServerConnection(), isNotNull);
    // Close it.
    network.getServerConnection()!.close("Test");

    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS - 1));

    // No longer having a server.
    expect(network.findActiveGameConnection(), isFalse);
    expect(network.getServerConnection(), isNull);

    // This did not open more connections - as we don't know the type of the other connections yet.
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS - 1));

    // Returns pongs for all connection.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c']!.values) {
      connection.getOtherEnd()!.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        KEY_FRAME_KEY: 0
      });
    }

    // Still false.
    expect(network.findActiveGameConnection(), isFalse);
    expect(network.findActiveGameConnection(), isFalse);
    expect(network.findActiveGameConnection(), isFalse);

    // We're back at max connections again.
    expect(network.safeActiveConnections().length,
        equals(PeerWrapper.MAX_AUTO_CONNECTIONS));

    // Respond with a Pong - this is the server.
    print("Connetions ${network.safeActiveConnections().keys}");
    g.actingCommanderId = '5';
    fakeConnectionFactory.connections['c']!['5']!
        .getOtherEnd()!
        .sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      GAME_STATE: g.toMap(),
      KEY_FRAME_KEY: 0
    });

    // Number 5 came through as our server :)
    expect(network.findActiveGameConnection(), isTrue);
    expect(network.getServerConnection(), isNotNull);

    // aaaand it's gone.
    network.getServerConnection()!.close("Test");

    // No server again.
    expect(network.findActiveGameConnection(), isFalse);

    // Returns pongs for all connections again - no server connection.
    for (TestConnection connection
        in fakeConnectionFactory.connections['c']!.values) {
      connection.getOtherEnd()!.sendAndReceivByOtherPeerNativeObject({
        PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
        KEY_FRAME_KEY: 0
      });
    }

    // We gave up finding a server.
    expectWarningContaining(
        "didn't find any servers, and not able to connect to any more peers. Giving up");
    expect(network.findActiveGameConnection(), isTrue);
    expect(network.getServerConnection(), isNull);
  });

  test('Find server at max players, closes connection', () {
    List<TestServerChannel> peers = [];
    List<String> ids = [];
    for (int i = 0; i < 7; i++) {
      serverChannelPeerId = "channel-$i";
      TestServerChannel peer = new TestServerChannel();
      ids.add(i.toString());
      peers.add(peer);
    }
    channelC.sendOpenMessage(ids);

    expect(network.findActiveGameConnection(), isFalse);

    // Respond with a Pong - this is the server.
    GameState g = new GameState(packetListenerBindings, MockSpriteIndex());
    for (int i = 0; i < 20; i++) {
      g.addPlayerInfo(PlayerInfo("test_$i", "abcc_$i", i*i));
    }
    g.actingCommanderId = '0';
    fakeConnectionFactory.connections['c']!['0']!
        .getOtherEnd()!
        .sendAndReceivByOtherPeerNativeObject({
      PONG: (new DateTime.now().millisecondsSinceEpoch - 1000),
      GAME_STATE: g.toMap(),
      KEY_FRAME_KEY: 0
    });

    // No game connection.
    expect(network.findActiveGameConnection(), isFalse);
    // And we closed it.
    expect(network.safeActiveConnections().containsKey("o"),
        isFalse);
  });

  test('Test find server no peers', () {
    channelC.sendOpenMessage();
    expect(network.findActiveGameConnection(), isTrue);
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
  frame(double duration, int frameStep, [Vec2? gravity]) {
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
