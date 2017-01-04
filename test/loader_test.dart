import 'package:test/test.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:mockito/mockito.dart';
import 'lib/test_lib.dart';

class MockImageIndex extends Mock implements ImageIndex {}
class MockNetwork extends Mock implements Network {}
class MockPeerWrapper extends Mock implements PeerWrapper {}

void main() {
  Loader loader;
  MockImageIndex mockImageIndex = new MockImageIndex();
  MockNetwork mockNetwork = new MockNetwork();
  MockPeerWrapper mockPeerWrapper = new MockPeerWrapper();
  void tickAndAssertState(LoaderState state) {
    loader.loaderTick();
    expect(loader.currentState(), equals(state));
  }
  setUp(() {
    loader = new Loader(new FakeCanvas(),
      mockImageIndex, mockNetwork,  mockPeerWrapper);
  });
  group('Loader tests', () {
    test('Base state and load from server', () {
      when(mockImageIndex.finishedLoadingImages()).thenReturn(false);
      when(mockPeerWrapper.connectedToServer()).thenReturn(false);
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
      when(mockNetwork.hasConnections()).thenReturn(false);
      // Loaded from server, assert we'll start as server.
      tickAndAssertState(LoaderState.LOADED_AS_SERVER);
      expect(loader.loadedAsServer(), isTrue);
    });
  });
}
