import 'package:test/test.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:mockito/mockito.dart';
import 'test_connection.dart';

class MockImageIndex extends Mock implements ImageIndex {}

void main() {
  const String IMAGE_DATA =
      "12345678901234567890123456789012345678901234567890";
  TestConnectionWrapper connection1;
  TestConnectionWrapper connection2;
  ChunkHelper helper;
  ChunkHelper helper2;
  ImageIndex imageIndex;
  ImageIndex imageIndex2;
  setUp(() {
    connection1 = new TestConnectionWrapper();
    connection2 = new TestConnectionWrapper();
    imageIndex = new MockImageIndex();
    imageIndex2 = new MockImageIndex();
    helper = new ChunkHelper(imageIndex, 4);
    helper2 = new ChunkHelper(imageIndex, 4);
  });
  group('Chunk helper tests', () {
    test('Reply with data', () {
      String name = imageSources[0];
      when(imageIndex.getImageDataUrl(name)).thenReturn(IMAGE_DATA);
      helper.replyWithImageData({
        IMAGE_DATA_REQUEST: {'name': name}
      }, connection1);
      // Default chunk size.
      expect(
          connection1.lastDataSent,
          equals({
            '-i': {
              'name': 'shipg01.png',
              'data': '1234',
              'start': 0,
              'size': IMAGE_DATA.length
            }
          }));
      helper.replyWithImageData({
        IMAGE_DATA_REQUEST: {'name': name, 'start': 1, 'end': 2}
      }, connection1);
      // Explicit request.
      expect(
          connection1.lastDataSent,
          equals({
            '-i': {
              'name': 'shipg01.png',
              'data': '2',
              'start': 1,
              'size': IMAGE_DATA.length
            }
          }));
      // Explicit request of final byte.
      helper.replyWithImageData({
        IMAGE_DATA_REQUEST: {'name': name, 'start': 49, 'end': 900}
      }, connection1);
      expect(
          connection1.lastDataSent,
          equals({
            '-i': {
              'name': 'shipg01.png',
              'data': '0',
              'start': 49,
              'size': IMAGE_DATA.length
            }
          }));
    });

    test('Test single load', () {
      String name = imageSources[0];
      when(imageIndex.getImageDataUrl(name)).thenReturn(IMAGE_DATA);
      Map request = helper.buildImageChunkRequest(name);
      helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
      helper.parseImageChunkResponse(connection1.lastDataSent);

      String fullData = IMAGE_DATA;
      String expectedData = fullData.substring(0, helper.chunkSize);
      expect(helper.getImageBuffer(), equals({name: expectedData}));

      while (helper.getImageBuffer().containsKey(name)) {
        Map request = helper.buildImageChunkRequest(name);
        helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
        helper.parseImageChunkResponse(connection1.lastDataSent);
      }

      expect(IMAGE_DATA, equals(fullData));
    });
    test('Test end-2-end', () {
      List connections = new List.filled(1, connection1);

      Map map = {"image1.png":1, "image2.png":2};
      when(imageIndex.getImageDataUrl("image1.png")).thenReturn(IMAGE_DATA);
      when(imageIndex.getImageDataUrl("image2.png")).thenReturn(IMAGE_DATA);
      when(imageIndex.imageIsLoaded("image2.png")).thenReturn(true);
      when(imageIndex.imageIsLoaded("image1.png")).thenReturn(false);
      when(imageIndex.allImagesByName()).thenReturn(map);
      when(imageIndex2.getImageDataUrl("image1.png")).thenReturn(IMAGE_DATA);

      // Set image to be loaded.
      when(imageIndex.addFromImageData("image1.png", IMAGE_DATA)).thenAnswer((i) {
        when(imageIndex.imageIsLoaded("image1.png")).thenReturn(true);
      });

      // Loop until completed.
      for (int i = 0; i < 20; i++) {
        if (imageIndex.imageIsLoaded("image1.png")) {
          break;
        }
        helper.requestNetworkData(connections, 0.01);
        helper2.replyWithImageData(connection1.lastDataSent, connection1);
        helper.parseImageChunkResponse(connection1.lastDataSent);
      }
      // Fully loaded.
      expect(imageIndex.imageIsLoaded("image1.png"), isTrue);
    });
  });
}
