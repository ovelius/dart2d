import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:mockito/annotations.dart';
import 'package:test/test.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:mockito/mockito.dart';
import 'lib/test_lib.dart';
import 'lib/test_mocks.mocks.dart';

GameStateUpdates addResourceRequest(ResourceRequest r) {
  return GameStateUpdates()..stateUpdate.add(StateUpdate()..resourceRequest = r);
}

void main() {
  const String IMAGE_DATA =
      "12345678901234567890123456789012345678901234567890";
  const String BYTE_WORLD_IMAGE_DATA = "abcdefghijklmonpqrstuv";
  const String BYTE_WORLD_IMAGE_DATA2 = "aaaaaaaaaaaaaaaaaaa";
  late TestConnectionWrapper connection1;
  late TestConnectionWrapper connection2;
  late PacketListenerBindings packetListenerBindings;
  late ChunkHelper helper;
  late ChunkHelper helper2;
  late MockImageIndex imageIndex;
  late MockImageIndex imageIndex2;
  late ByteWorld byteWorld;
  setUp(() {
    logOutputForTest();
    MockPeerWrapper mockPeerWrapper = MockPeerWrapper();
    when(mockPeerWrapper.id).thenReturn("c");
    MockNetwork mockNetwork = MockNetwork();
    when(mockNetwork.getPeer()).thenReturn(mockPeerWrapper);
    connection1 = new TestConnectionWrapper("a", mockNetwork, Clock());
    connection2 = new TestConnectionWrapper("b", mockNetwork, Clock());
    imageIndex = new MockImageIndex();
    imageIndex2 = new MockImageIndex();
    byteWorld = new MockByteWorld();
    packetListenerBindings = new PacketListenerBindings();
    helper = new ChunkHelper(imageIndex, byteWorld, packetListenerBindings)
      ..setChunkSizeForTest(4);
    helper2 = new ChunkHelper(imageIndex2, byteWorld, packetListenerBindings)
      ..setChunkSizeForTest(4);
  });
  tearDown(() {
    assertNoLoggedWarnings();
  });
  group('Chunk helper tests', () {
    test('Reply with data', () {
      int requestedIndex = 5;
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      helper.replyWithImageData(ResourceRequest()..resourceIndex = requestedIndex, connection1);
      // Default chunk size.

      ResourceResponse req = ResourceResponse()
        ..resourceIndex = 5
        ..startByte = 0
        ..data = utf8.encode(IMAGE_DATA.substring(0, 4))
        ..size = 50;
      expect(
          connection1.lastDataSent,
          equals(
              GameStateUpdates()
                ..stateUpdate.add(
                    StateUpdate()..resourceResponse = req)
          ));
      helper.replyWithImageData(ResourceRequest()
          ..resourceIndex = requestedIndex
          ..startByte = 1
          ..endByte = 2, connection1);
      // Explicit request.
      ResourceResponse response = ResourceResponse()
        ..resourceIndex = requestedIndex
        ..startByte = 1
        ..size = 50
        ..data = [50];
      expect(
          connection1.lastDataSent,
          equals(GameStateUpdates()
            ..stateUpdate.add(StateUpdate()..resourceResponse = response)));
      // Explicit request of final byte.
      helper.replyWithImageData(
          ResourceRequest()
            ..resourceIndex = requestedIndex
            ..startByte = 49
            ..endByte = 900, connection1);
      // Explicit request.
      ResourceResponse response2 = ResourceResponse()
        ..resourceIndex = requestedIndex
        ..startByte = 49
        ..size = 50
        ..data = [48];
      expect(
          connection1.lastDataSent,
          equals(GameStateUpdates()
            ..stateUpdate.add(StateUpdate()..resourceResponse = response2)));
    });

    test('Reply with multiple responses', () {
      int requestedIndex = 5;
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      helper.replyWithImageData(ResourceRequest()
        ..resourceIndex = requestedIndex
          ..startByte = 0
          ..endByte = 1
          ..multiply = 2
          , connection1);
      // Default chunk size.

      ResourceResponse req1 = ResourceResponse()
        ..resourceIndex = 5
        ..startByte = 0
        ..data = utf8.encode(IMAGE_DATA.substring(0, 1))
        ..size = 50;
      ResourceResponse req2 = ResourceResponse()
        ..resourceIndex = 5
        ..startByte = 1
        ..data = utf8.encode(IMAGE_DATA.substring(1, 2))
        ..size = 50;
      ResourceResponse req3 = ResourceResponse()
        ..resourceIndex = 5
        ..startByte = 2
        ..data = utf8.encode(IMAGE_DATA.substring(2, 3))
        ..size = 50;
      expect(
          connection1.dataSent,
          equals([
              GameStateUpdates()
                ..stateUpdate.add(
                    StateUpdate()..resourceResponse = req1),
            GameStateUpdates()
              ..stateUpdate.add(
                  StateUpdate()..resourceResponse = req2),
            GameStateUpdates()
              ..stateUpdate.add(
                  StateUpdate()..resourceResponse = req3)]
          ));
    });

    test('Test single load', () {
      int requestedIndex = 6;
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
      when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(false);
      // Set image to be loaded.
      when(imageIndex2.addFromImageData(requestedIndex, IMAGE_DATA, true))
          .thenAnswer((i) {
        when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(true);
        return Future.value();
      });

      ResourceRequest request = helper2.buildImageChunkRequest(requestedIndex);
      helper.replyWithImageData(request, connection1);
      helper2.parseImageChunkResponse(
          connection1.lastDataSent!.stateUpdate[0].resourceResponse, connection1);

      String fullData = IMAGE_DATA;
      String expectedData = fullData.substring(0, 4);
      expect(helper2.getImageBuffer(), equals({requestedIndex: expectedData}));

      while (helper2.getCompleteRatio(requestedIndex) < 1.0) {
        print("Completed ratio is ${helper2.getCompleteRatio(requestedIndex)}");
        ResourceRequest request = helper2.buildImageChunkRequest(requestedIndex);
        helper.replyWithImageData(request, connection1);
        helper2.parseImageChunkResponse(
            connection1.lastDataSent!.stateUpdate[0].resourceResponse, connection1);
      }

      expect(IMAGE_DATA, equals(fullData));
    });

    test('Test single load missing server fallback', () {
      int requestedIndex = 6;
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      ResourceRequest request = helper.buildImageChunkRequest(requestedIndex);

      try {
        helper.replyWithImageData(request, connection1);
        fail("Should throw!");
      } catch (e) {
        expect(e, isStateError);
      }
      // We triggered the fallback to load from server.
      verify(imageIndex.loadImagesFromServer());
    });

    test('Test end-2-end', () {
      int requestedIndex = 9;
      int requestedIndex2 = 6;
      Map<String, ConnectionWrapper> connections = {"1": connection1};

      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      when(imageIndex.getImageDataUrl(requestedIndex2)).thenReturn(IMAGE_DATA);
      when(imageIndex2.imageIsLoaded(requestedIndex2)).thenReturn(true);
      when(imageIndex.imageIsLoading(requestedIndex2)).thenReturn(true);
      when(imageIndex.imageIsLoading(requestedIndex)).thenReturn(false);
      when(imageIndex.orderedImageIds()).thenReturn([requestedIndex, requestedIndex2]);
      when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(true);
      when(imageIndex2.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);

      // Set image to be loaded.
      when(imageIndex.addFromImageData(requestedIndex, IMAGE_DATA, true))
          .thenAnswer((i) {
        when(imageIndex.imageIsLoading(requestedIndex)).thenReturn(true);
        when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
        return Future.value();
      });

      // Loop until completed.
      for (int i = 0; i < 20; i++) {
        if (imageIndex.imageIsLoaded(requestedIndex)) {
          break;
        }
        helper.requestNetworkData(connections, 0.1);
        helper2.replyWithImageData(
            connection1.lastDataSent!.stateUpdate[0].resourceRequest, connection1);
        helper.parseImageChunkResponse(
            connection1.lastDataSent!.stateUpdate[0].resourceResponse, connection1);
      }
      // Fully loaded.
      expect(imageIndex.imageIsLoaded(requestedIndex), isTrue);
    });
    test('Test retries', () {
      Map<String, ConnectionWrapper> connections = {connection1.id: connection1};
      when(imageIndex.getImageDataUrl(argThat(anything)))
          .thenReturn(IMAGE_DATA);
      when(imageIndex.imageIsLoaded(argThat(anything))).thenReturn(false);
      when(imageIndex.orderedImageIds()).thenReturn([4, 6, 7, 9, 91, 31]);

      helper.requestNetworkData(connections, 0.01);
      expect(connection1.sendCount, equals(3));

      expect(connection1.dataSent,
      [addResourceRequest(ResourceRequest()
          ..resourceIndex = 4
          ..startByte = 0
          ..endByte = 5),
      addResourceRequest(ResourceRequest()
          ..resourceIndex = 6
          ..startByte = 0
          ..endByte = 6),
      addResourceRequest(ResourceRequest()
          ..resourceIndex = 7
          ..startByte = 0
          ..endByte = 7)]);
      // Should not retry, too soon.
      helper.requestNetworkData(connections, 0.01);
      expect(connection1.sendCount, equals(3));
      // Next trigger is in 3 seconds.
      helper.requestNetworkData(connections, 3.00);
      // Next trigger is in 3 seconds.
      helper.requestNetworkData(connections, 3.00);
      // 3*3
      expect(connection1.sendCount, equals(9));
      expect(helper.failuresByConnection(), equals({"a": 6}));
    });

    test('Test with byteworld state', () {
      int requestedIndex = ImageIndex.WORLD_IMAGE_INDEX;
      Map<String, ConnectionWrapper> connections = {"1": connection1};

      when(byteWorld.asDataUrl()).thenReturn(BYTE_WORLD_IMAGE_DATA);
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      when(imageIndex.orderedImageIds()).thenReturn([requestedIndex]);
      when(imageIndex2.orderedImageIds()).thenReturn([requestedIndex]);
      when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(false);

      helper.requestNetworkData(connections, 0.01);
      helper.replyWithImageData(
          connection1.lastDataSent!.stateUpdate[0].resourceRequest, connection1);
      //expect(
        //  connection1.lastDataSent,
          //GameStateUpdates());
      expect(
          helper.getByteWorldCache(), equals({'a': 'abcdefghijklmonpqrstuv'}));

      // Another connection comes along.
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      when(byteWorld.asDataUrl()).thenReturn(BYTE_WORLD_IMAGE_DATA2);
      Map<String, ConnectionWrapper> connections2 = {"2": connection2};
      helper2.requestNetworkData(connections2, 0.01);
      helper.replyWithImageData(
          connection2.lastDataSent!.stateUpdate[0].resourceRequest, connection2);
      // Gets Byteworld 2 data.
      ResourceResponse response = ResourceResponse()
        ..resourceIndex = 1
        ..startByte = 0
        ..data = [97, 97, 97, 97, 97]
        ..size = 19;
      expect(
          connection2.lastDataSent,
          equals(
            GameStateUpdates()
              ..stateUpdate.add(StateUpdate()
              ..resourceResponse = response)
          ));
      // Two versions cached.
      expect(helper.getByteWorldCache(),
          equals({'a': 'abcdefghijklmonpqrstuv', 'b': 'aaaaaaaaaaaaaaaaaaa'}));
      // Trigger a client enter for a.
      packetListenerBindings.handlerFor(StateUpdate_Update.clientEnter)[0](
          connection1, StateUpdate());
      // This cleared the cache for a.
      expect(helper.getByteWorldCache(), equals({'b': 'aaaaaaaaaaaaaaaaaaa'}));
    });
  });

}
