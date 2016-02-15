import 'package:test/test.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/connection.dart';
import 'test_connection.dart';
import 'dart:html';

void main() {
  TestConnectionWrapper connection1;
  TestConnectionWrapper connection2;
  ChunkHelper helper; 
  setUp(() {
    useEmptyImagesForTest();
    connection1 = new TestConnectionWrapper();
    connection2 = new TestConnectionWrapper();
    helper = new ChunkHelper(4);
  });
  group('Chunk helper tests', () {
     test('Build Request', () {
       String name = imageSources[0];
       expect(helper.buildImageChunkRequest(name),
           equals({'name': name, 'start': 0, 'end': 4}));
     });
     test('Reply with data', () {
       String name = imageSources[0];
       helper.replyWithImageData({IMAGE_DATA_REQUEST: {'name': name}}, connection1);
       // Default chunk size.
       expect(connection1.lastDataSent,
           equals({'-i': {'name': 'shipg01.png', 'data': 'data', 'start': 0, 'size': 574}}));
       helper.replyWithImageData(
           {IMAGE_DATA_REQUEST: {'name': name, 'start':1, 'end':2}},
           connection1);
       // Explicit request.
       expect(connection1.lastDataSent,
           equals({'-i': {'name': 'shipg01.png', 'data': 'a', 'start': 1, 'size': 574}}));
       // Explicit request of final byte.
       helper.replyWithImageData(
                   {IMAGE_DATA_REQUEST: {'name': name, 'start':573, 'end':900}},                 
                   connection1);
       expect(connection1.lastDataSent,
           equals({'-i': {'name': 'shipg01.png', 'data': 'C', 'start': 573, 'size': 574}}));
     });
     
     test('Test end-2-end', () {
       String name = imageSources[0];
       Map request = helper.buildImageChunkRequest(name);
       helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
       helper.parseImageChunkResponse(connection1.lastDataSent);
       
       String fullData = getImageDataUrl(name);
       String expectedData = fullData.substring(0, helper.chunkSize);
       expect(helper.imageBuffer, equals({name:expectedData}));
       
       while (helper.imageBuffer.containsKey(name)) {
         Map request = helper.buildImageChunkRequest(name);
         helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
         helper.parseImageChunkResponse(connection1.lastDataSent);         
       }
       
       expect(getImageDataUrl(name), equals(fullData));
     });
  });
}