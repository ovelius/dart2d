import 'package:test/test.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/util/gamestate.dart';
import 'lib/test_lib.dart';

class MockConnectionWrapper extends Mock implements ConnectionWrapper {}

const double TICK_TIME = 0.01;

void main() {
  Loader loader;
  MockImageIndex mockImageIndex;
  MockNetwork mockNetwork;
  MockPeerWrapper mockPeerWrapper;
  MockChunkHelper mockChunkHelper;
  MockGameState mockGameState;
  Map localStorage;
  void tickAndAssertState(LoaderState state) {
    loader.loaderTick(TICK_TIME);
    expect(loader.currentState(), equals(state));
  }
  setUp(() {
    logOutputForTest();
    localStorage = {};
    mockImageIndex = new MockImageIndex();
    mockNetwork = new MockNetwork();
    mockPeerWrapper = new MockPeerWrapper();
    mockChunkHelper = new MockChunkHelper();
    mockGameState = new MockGameState();
    when(mockNetwork.getPeer()).thenReturn(mockPeerWrapper);
    when(mockNetwork.getGameState()).thenReturn(mockGameState);
    when(mockPeerWrapper.getId()).thenReturn('b');
    loader = new Loader(localStorage, new MockKeyState(), new FakeCanvas(),
      mockImageIndex, mockNetwork, mockChunkHelper);
    // TODO actually test this.
    localStorage['playerSprite'] = 'playerSprite';
    when(mockImageIndex.finishedLoadingImages()).thenReturn(false);
    when(mockPeerWrapper.connectedToServer()).thenReturn(false);
  });
  tearDown((){
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
      when(mockImageIndex.imageIsLoaded(1)).thenReturn(false);
      when(mockNetwork.hasOpenConnection()).thenReturn(false);
      // Loaded from server, assert we'll start as server.
      tickAndAssertState(LoaderState.LOADED_AS_SERVER);
      expect(loader.loadedAsServer(), isTrue);
    });

    test('Base state and load from other client', () {
      MockConnectionWrapper connection1 = new MockConnectionWrapper();
      Map connections = {
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
      when(mockImageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX)).thenReturn(false);
      when(mockNetwork.findServer()).thenReturn(false);
      tickAndAssertState(LoaderState.FINDING_SERVER);

      when(mockNetwork.findServer()).thenReturn(true);
      when(mockNetwork.getServerConnection()).thenReturn(connection1);
      when(connection1.isValidGameConnection()).thenReturn(false);
      tickAndAssertState(LoaderState.CONNECTING_TO_GAME);

      when(connection1.isValidGameConnection()).thenReturn(true);
      when(mockChunkHelper.getCompleteRatio(ImageIndex.WORLD_IMAGE_INDEX)).thenReturn(0.5);
      tickAndAssertState(LoaderState.LOADING_GAMESTATE);

      when(mockImageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX)).thenReturn(true);
      when(mockGameState.playerInfoByConnectionId('b')).thenReturn(null);

      tickAndAssertState(LoaderState.LOADING_ENTERING_GAME);
      verify(connection1.sendClientEnter());

      PlayerInfo info = new PlayerInfo(null, null, null);
      when(mockGameState.playerInfoByConnectionId('b')).thenReturn(info);

      tickAndAssertState(LoaderState.LOADING_ENTERING_GAME);

      info.inGame = true;

      tickAndAssertState(LoaderState.LOADING_AS_CLIENT_COMPLETED);

      expect(loader.hasGameState(), isTrue);
    });
  });
}
