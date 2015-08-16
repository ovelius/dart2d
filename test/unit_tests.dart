import 'package:unittest/unittest.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:html';

void main() {
  ChunkHelper helper; 
  setUp(() {
    useEmptyImagesForTest();
    helper = new ChunkHelper(4);
  });
  group('Chunk helper tests', () {
     test('Test Build Request', () {
       String name = imageSources[0];
       expect(helper.buildImageChunkRequest(name),
           equals({'name': name, 'start': 0, 'end': 4}));
     });
  });
}