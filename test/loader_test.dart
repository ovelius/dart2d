import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:test/test.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:mockito/mockito.dart';
import 'dart:async';
import 'package:web/web.dart';
import 'lib/test_lib.dart';
import 'lib/test_mocks.mocks.dart';

const double TICK_TIME = 0.01;

void main() {
  late Loader loader;
  late MockImageIndex mockImageIndex;
  late MockNetwork mockNetwork;
  late MockPeerWrapper mockPeerWrapper;
  late MockChunkHelper mockChunkHelper;
  late MockGameState mockGameState;
  late MockPlayerWorldSelector selector;
  late MockByteWorld byteWorld;
  late LocalStorage localStorage;
  late StreamController<int> streamController;
  void tickAndAssertState(LoaderState state) {
    loader.loaderTick(TICK_TIME);
    expect(loader.currentState(), equals(state));
  }

  setUp(() {
    logOutputForTest();
    localStorage = new TestLocalStorage();
    streamController = new StreamController(sync: true);
    mockImageIndex = new MockImageIndex();
    mockNetwork = new MockNetwork();
    mockPeerWrapper = new MockPeerWrapper();
    mockChunkHelper = new MockChunkHelper();
    mockGameState = new MockGameState();
    selector = new MockPlayerWorldSelector();
    byteWorld = new MockByteWorld();
    when(mockNetwork.getPeer()).thenReturn(mockPeerWrapper);
    when(mockNetwork.getGameState()).thenReturn(mockGameState);
    when(mockGameState.gameStateProto).thenReturn(
      GameStateProto()..mapName = "test"
    );
    when(mockNetwork.safeActiveConnections()).thenReturn({});
    when(mockPeerWrapper.getId()).thenReturn('b');
    when(mockChunkHelper.bytesPerSecondSamples())
        .thenAnswer((_) => streamController.stream);
    when(mockImageIndex.playerResourcesLoaded()).thenReturn(false);
    when(selector.worldSelectedAndLoaded()).thenReturn(false);
    loader = new Loader(localStorage, new FakeCanvas(), selector,
        mockImageIndex, mockNetwork, mockChunkHelper, byteWorld);
    // TODO actually test this.
    localStorage['playerSprite'] = 'playerSprite';
    when(mockImageIndex.finishedLoadingImages()).thenReturn(false);
    when(mockPeerWrapper.connectedToServer()).thenReturn(false);
  });
  tearDown(() {
    assertNoLoggedWarnings();
  });
  group('Loader tests', () {
    test('Base state and load from server', () {
      tickAndAssertState(LoaderState.WAITING_FOR_NAME);
      localStorage['playerName'] = "playerA";
      // Wait for init.
      tickAndAssertState(LoaderState.WEB_RTC_INIT);
      when(mockPeerWrapper.connectedToServer()).thenReturn(true);
      when(mockPeerWrapper.hasReceivedActiveIds()).thenReturn(false);
      // Wait for peer data.
      tickAndAssertState(LoaderState.WAITING_FOR_PEER_DATA);
      when(mockPeerWrapper.hasReceivedActiveIds()).thenReturn(true);
      when(mockPeerWrapper.connectionsExhausted()).thenReturn(false);
      when(mockNetwork.hasOpenConnection()).thenReturn(false);
      // Connect to received peers.
      tickAndAssertState(LoaderState.CONNECTING_TO_PEER);
      when(mockPeerWrapper.connectionsExhausted()).thenReturn(true);
      when(mockImageIndex.imagesIndexed()).thenReturn(false);
      // Use server when connections exhausted.
      tickAndAssertState(LoaderState.LOADING_SERVER);
      when(mockImageIndex.finishedLoadingImages()).thenReturn(true);
      when(mockImageIndex.playerResourcesLoaded()).thenReturn(true);
      when(mockImageIndex.imageIsLoaded(1)).thenReturn(false);
      when(mockNetwork.findActiveGameConnection()).thenReturn(true);

      tickAndAssertState(LoaderState.WORLD_SELECT);
      when(selector.selectedWorldName).thenReturn("something");
      when(mockImageIndex.getImageByName("something"))
          .thenReturn(HTMLImageElement());
      tickAndAssertState(LoaderState.WORLD_LOADING);
      when(selector.worldSelectedAndLoaded()).thenReturn(true);
      // Loaded from server, assert we'll start as server.
      tickAndAssertState(LoaderState.COMPUTING_BYTE_WORLD);

      when(byteWorld.byteWorldReady()).thenReturn(true);
      tickAndAssertState(LoaderState.LOADED_AS_SERVER);
      expect(loader.loadedAsServer(), isTrue);
    });

    test('Start loading from client, fallback server', () {
      MockConnectionWrapper connection1 = new MockConnectionWrapper();
      Map<String, ConnectionWrapper> connections = {
        'a': connection1,
      };
      tickAndAssertState(LoaderState.WAITING_FOR_NAME);
      localStorage['playerName'] = "playerA";
      when(mockPeerWrapper.connectedToServer()).thenReturn(true);
      when(mockPeerWrapper.hasReceivedActiveIds()).thenReturn(true);
      when(mockNetwork.hasOpenConnection()).thenReturn(false);
      when(mockPeerWrapper.connectionsExhausted()).thenReturn(false);
      tickAndAssertState(LoaderState.CONNECTING_TO_PEER);
      when(mockNetwork.hasOpenConnection()).thenReturn(true);
      when(mockImageIndex.imagesIndexed()).thenReturn(false);
      when(mockNetwork.safeActiveConnections()).thenReturn(connections);
      tickAndAssertState(LoaderState.LOADING_OTHER_CLIENT);
      // Now drops connection.
      when(mockNetwork.hasOpenConnection()).thenReturn(false);
      // Trying to connect again.
      tickAndAssertState(LoaderState.CONNECTING_TO_PEER);
      // Now screwed, back to loading server.
      when(mockPeerWrapper.connectionsExhausted()).thenReturn(true);
      tickAndAssertState(LoaderState.LOADING_SERVER);
    });

    test('Start loading from client too slow so, fallback to server', () {
      MockConnectionWrapper connection1 = new MockConnectionWrapper();
      Map<String, ConnectionWrapper> connections = {
        'a': connection1,
      };
      tickAndAssertState(LoaderState.WAITING_FOR_NAME);
      localStorage['playerName'] = "playerA";
      when(mockPeerWrapper.connectedToServer()).thenReturn(true);
      when(mockPeerWrapper.hasReceivedActiveIds()).thenReturn(true);
      when(mockNetwork.hasOpenConnection()).thenReturn(false);
      when(mockPeerWrapper.connectionsExhausted()).thenReturn(false);
      tickAndAssertState(LoaderState.CONNECTING_TO_PEER);
      when(mockNetwork.hasOpenConnection()).thenReturn(true);
      when(mockImageIndex.imagesIndexed()).thenReturn(false);
      when(mockNetwork.safeActiveConnections()).thenReturn(connections);
      tickAndAssertState(LoaderState.LOADING_OTHER_CLIENT);

      for (int i = 0; i < SAMPLES_BEFORE_FALLBACK; i++) {
        streamController.add(ACCEPTABLE_TRANSFER_SPEED_BYTES_SECOND - 1);
      }
      // Falling back to using server.
      tickAndAssertState(LoaderState.LOADING_SERVER);
    });

    test('Resends game connect', () {
      MockConnectionWrapper connection1 = new MockConnectionWrapper();
      Map<String, ConnectionWrapper> connections = {
        'a': connection1,
      };
      localStorage['playerName'] = "playerA";
      when(mockPeerWrapper.connectedToServer()).thenReturn(true);
      when(mockPeerWrapper.hasReceivedActiveIds()).thenReturn(true);
      when(mockNetwork.hasOpenConnection()).thenReturn(true);
      when(mockImageIndex.imagesIndexed()).thenReturn(true);
      when(mockNetwork.safeActiveConnections()).thenReturn(connections);
      when(mockImageIndex.finishedLoadingImages()).thenReturn(true);
      when(mockNetwork.findActiveGameConnection()).thenReturn(true);
      when(mockNetwork.getServerConnection()).thenReturn(connection1);
      when(connection1.isValidGameConnection()).thenReturn(false);

      tickAndAssertState(LoaderState.CONNECTING_TO_GAME);

      verify(connection1.connectToGame("playerA", 0));

      loader.loaderTick(CLIENT_CONNECT_RETRY_TIMER + 0.3);

      // Got sent again.
      verify(connection1.connectToGame("playerA", 0));
    });

    test('Base state and load from other client', () {
      MockConnectionWrapper connection1 = new MockConnectionWrapper();
      when(connection1.initialPongReceived()).thenReturn(false);
      Map<String, ConnectionWrapper> connections = {
        'a': connection1,
      };
      tickAndAssertState(LoaderState.WAITING_FOR_NAME);
      localStorage['playerName'] = "playerA";
      when(mockPeerWrapper.connectedToServer()).thenReturn(true);
      when(mockPeerWrapper.hasReceivedActiveIds()).thenReturn(true);
      when(mockNetwork.hasOpenConnection()).thenReturn(false);
      when(mockPeerWrapper.connectionsExhausted()).thenReturn(false);
      tickAndAssertState(LoaderState.CONNECTING_TO_PEER);
      when(mockNetwork.hasOpenConnection()).thenReturn(true);
      when(mockImageIndex.imagesIndexed()).thenReturn(false);
      when(mockNetwork.safeActiveConnections()).thenReturn(connections);
      tickAndAssertState(LoaderState.LOADING_OTHER_CLIENT);
      // We requested data.
      verify(mockChunkHelper.requestNetworkData(connections, TICK_TIME));

      when(mockImageIndex.finishedLoadingImages()).thenReturn(true);
      when(mockImageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX))
          .thenReturn(false);
      when(mockNetwork.findActiveGameConnection()).thenReturn(false);
      tickAndAssertState(LoaderState.FINDING_SERVER);

      when(mockNetwork.findActiveGameConnection()).thenReturn(true);
      when(mockNetwork.getServerConnection()).thenReturn(connection1);
      when(connection1.isValidGameConnection()).thenReturn(false);
      tickAndAssertState(LoaderState.CONNECTING_TO_GAME);

      when(connection1.isValidGameConnection()).thenReturn(true);
      when(mockChunkHelper.getCompleteRatio(ImageIndex.WORLD_IMAGE_INDEX))
          .thenReturn(0.5);
      tickAndAssertState(LoaderState.LOADING_GAMESTATE);

      when(mockImageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX))
          .thenReturn(true);
      when(mockImageIndex.getImageById(ImageIndex.WORLD_IMAGE_INDEX))
          .thenReturn(HTMLImageElement());
      when(mockGameState.playerInfoByConnectionId('b')).thenReturn(null);

      tickAndAssertState(LoaderState.COMPUTING_BYTE_WORLD);
      when(byteWorld.byteWorldReady()).thenReturn(true);

      tickAndAssertState(LoaderState.LOADING_ENTERING_GAME);
      verify(connection1.sendClientEnter());

      PlayerInfoProto info = new PlayerInfoProto()
        ..name = "test";
      when(mockGameState.playerInfoByConnectionId('b')).thenReturn(info);

      tickAndAssertState(LoaderState.LOADING_ENTERING_GAME);

      info.inGame = true;

      tickAndAssertState(LoaderState.LOADING_AS_CLIENT_COMPLETED);

      expect(loader.hasGameState(), isTrue);
    });

    test('server disconnect start as server', () {
      MockConnectionWrapper connection1 = new MockConnectionWrapper();
      Map<String, ConnectionWrapper> connections = {
        'a': connection1,
      };
      tickAndAssertState(LoaderState.WAITING_FOR_NAME);
      localStorage['playerName'] = "playerA";

      when(mockNetwork.safeActiveConnections()).thenReturn(connections);
      when(mockNetwork.hasOpenConnection()).thenReturn(true);
      when(mockPeerWrapper.connectedToServer()).thenReturn(true);
      when(mockImageIndex.imagesIndexed()).thenReturn(true);
      when(mockPeerWrapper.hasReceivedActiveIds()).thenReturn(true);
      when(mockNetwork.getServerConnection()).thenReturn(connection1);
      when(mockNetwork.findActiveGameConnection()).thenReturn(true);
      when(connection1.isValidGameConnection()).thenReturn(false);
      when(mockImageIndex.finishedLoadingImages()).thenReturn(true);
      when(connection1.isValidGameConnection()).thenReturn(true);
      when(mockImageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX))
          .thenReturn(true);
      when(mockImageIndex.getImageById(ImageIndex.WORLD_IMAGE_INDEX))
          .thenReturn(HTMLImageElement());
      PlayerInfoProto info = new PlayerInfoProto()
         ..name = "test"
         ..connectionId = 'b';
      when(mockGameState.playerInfoByConnectionId('b')).thenReturn(info);

      tickAndAssertState(LoaderState.COMPUTING_BYTE_WORLD);
      when(byteWorld.byteWorldReady()).thenReturn(true);
      // Last phase of entering a game.
      tickAndAssertState(LoaderState.LOADING_ENTERING_GAME);
      // Connection fail so we fallback to server path.
      when(mockNetwork.getServerConnection()).thenReturn(null);
      tickAndAssertState(LoaderState.WORLD_SELECT);
    });
  });
}
