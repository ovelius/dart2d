import 'package:test/test.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:mockito/mockito.dart';
import 'test_connection.dart';

class MockImageIndex extends Mock implements ImageIndex {}

void main() {
  const String IMAGE_DATA = "12345678901234567890123456789012345678901234567890";
  TestConnectionWrapper connection1;
  TestConnectionWrapper connection2;
  ChunkHelper helper;
  ImageIndex imageIndex;
  setUp(() {
    connection1 = new TestConnectionWrapper();
    connection2 = new TestConnectionWrapper();
    imageIndex = new MockImageIndex();
    helper = new ChunkHelper(imageIndex, 4);
  });
  group('Chunk helper tests', () {
     test('Build Request', () {
       String name = imageSources[0];
       expect(helper.buildImageChunkRequest(name),
           equals({'name': name, 'start': 0, 'end': 4}));
     });
     test('Reply with data', () {
       String name = imageSources[0];
       when(imageIndex.getImageDataUrl(name)).thenReturn(IMAGE_DATA);
       helper.replyWithImageData({IMAGE_DATA_REQUEST: {'name': name}}, connection1);
       // Default chunk size.
       expect(connection1.lastDataSent,
           equals({'-i': {'name': 'shipg01.png', 'data': '1234', 'start': 0, 'size': IMAGE_DATA.length}}));
       helper.replyWithImageData(
           {IMAGE_DATA_REQUEST: {'name': name, 'start':1, 'end':2}},
           connection1);
       // Explicit request.
       expect(connection1.lastDataSent,
           equals({'-i': {'name': 'shipg01.png', 'data': '2', 'start': 1, 'size': IMAGE_DATA.length}}));
       // Explicit request of final byte.
       helper.replyWithImageData(
                   {IMAGE_DATA_REQUEST: {'name': name, 'start':49, 'end':900}},
                   connection1);
       expect(connection1.lastDataSent,
           equals({'-i': {'name': 'shipg01.png', 'data': '0', 'start': 49, 'size': IMAGE_DATA.length}}));
     });
     
     test('Test end-2-end', () {
       String name = imageSources[0];
       when(imageIndex.getImageDataUrl(name)).thenReturn(IMAGE_DATA);
       Map request = helper.buildImageChunkRequest(name);
       helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
       helper.parseImageChunkResponse(connection1.lastDataSent);
       
       String fullData = IMAGE_DATA;
       String expectedData = fullData.substring(0, helper.chunkSize);
       expect(helper.imageBuffer, equals({name:expectedData}));
       
       while (helper.imageBuffer.containsKey(name)) {
         Map request = helper.buildImageChunkRequest(name);
         helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
         helper.parseImageChunkResponse(connection1.lastDataSent);         
       }
       
       expect(IMAGE_DATA, equals(fullData));
     });
  });
}