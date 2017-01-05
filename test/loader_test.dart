import 'package:test/test.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:mockito/mockito.dart';
import 'lib/test_lib.dart';

class MockImageIndex extends Mock implements ImageIndex {}
class MockNetwork extends Mock implements Network {}
class MockPeerWrapper extends Mock implements PeerWrapper {}
class MockConnectionWrapper extends Mock implements ConnectionWrapper {}
class MockChunkHelper extends Mock implements ChunkHelper {}

const double TICK_TIME = 0.01;

void main() {
  Loader loader;
  MockImageIndex mockImageIndex;
  MockNetwork mockNetwork;
  MockPeerWrapper mockPeerWrapper;
  MockChunkHelper mockChunkHelper;
  void tickAndAssertState(LoaderState state) {
    loader.loaderTick(TICK_TIME);
    expect(loader.currentState(), equals(state));
  }
  setUp(() {
    mockImageIndex = new MockImageIndex();
    mockNetwork = new MockNetwork();
    mockPeerWrapper = new MockPeerWrapper();
    mockChunkHelper = new MockChunkHelper();
    loader = new Loader(new FakeCanvas(),
      mockImageIndex, mockNetwork,  mockPeerWrapper, mockChunkHelper);
    when(mockImageIndex.finishedLoadingImages()).thenReturn(false);
    when(mockPeerWrapper.connectedToServer()).thenReturn(false);
  });
  group('Loader tests', () {
    test('Base state and load from server', () {
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
      when(connection1.initialPingSent()).thenReturn(true);
      when(connection1.initialPingReceived()).thenReturn(false);
      tickAndAssertState(LoaderState.FINDING_SERVER);

      when(connection1.initialPingReceived()).thenReturn(true);
      when(connection1.isValidGameConnection()).thenReturn(false);
      when(mockNetwork.getServerConnection()).thenReturn(connection1);
      tickAndAssertState(LoaderState.CONNECTING_TO_GAME);

      when(connection1.isValidGameConnection()).thenReturn(true);
      tickAndAssertState(LoaderState.LOADING_GAMESTATE);

      when(mockImageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX)).thenReturn(true);
      tickAndAssertState(LoaderState.LOADING_GAMESTATE_COMPLETED);

      expect(loader.hasGameState(), isTrue);
    });
  });
}
