library chunk_helper;

import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';

class ChunkHelper {
  static const int DEFAULT_CHUNK_SIZE = 512;
  static const Duration IMAGE_RETRY_DURATION = const Duration(milliseconds: 3000);
  final int chunkSize;
  Map<String, DateTime> lastImageRequest = new Map();
  Map<String, String> imageBuffer = new Map();
  
  ChunkHelper([this.chunkSize = DEFAULT_CHUNK_SIZE]);
  
  /**
   * Send a reply with the requested image data.
   */
  void replyWithImageData(Map dataMap, var connection) {
    Map imageDataRequest = dataMap[IMAGE_DATA_REQUEST];
    String name = imageDataRequest['name'];
    String data = getImageDataUrl(name);
    int start = imageDataRequest.containsKey("start") ? imageDataRequest["start"] : 0;
    int end = imageDataRequest.containsKey("end") 
        ? imageDataRequest["end"]
        : start + chunkSize;
    end = min(end, data.length);

    assert(start < end);
    String chunk = data.substring(start, end);
    connection.sendData({IMAGE_DATA_RESPONSE: 
        {'name':name, 'data':chunk, 'start':start, 'size':data.length}});
  }
  
  /**
   * Parse response with imageData.
   */
  void parseImageChunkResponse(Map dataMap) {
    Map imageDataResponse = dataMap[IMAGE_DATA_RESPONSE];
    String name = imageDataResponse['name'];
    String data = imageDataResponse['data'];
    int start = imageDataResponse['start'];
    // Final expected siimageBufferze.
    int size = imageDataResponse['size'];
    if (start == imageBuffer[name].length) {
      imageBuffer[name] = imageBuffer[name] + data;
    } else {
      print("Dropping data for ${name}, out of order??");
    }

    // Image complete.
    if (imageBuffer[name].length == size) {
      addFromImageData(name, imageBuffer[name]); 
      imageBuffer.remove(name);
    }
  }
  
  void requestNetworkData(List<ConnectionWrapper> connections) {
    int requestedImages = 0;
    for (String name in imageByName.keys) {
      // Don't request more than 2 images at a time.
      if (requestedImages > 2 && loadedImages[name] != true) {
        lastImageRequest[name] = new DateTime.now();
        continue;
      }
      if (maybeRequestImageLoad(name, connections)) {
        requestedImages++; 
      }
    }
  }
  
  bool maybeRequestImageLoad(String name, List<ConnectionWrapper> connections) {
    DateTime now = new DateTime.now();
    if (loadedImages[name] != true) {
      DateTime lastRequest = lastImageRequest[name];
      if (lastRequest == null || now.difference(lastRequest).inMilliseconds > IMAGE_RETRY_DURATION.inMilliseconds) {
        return requestImageData(name, connections);
      }
    }
    return false;
  }
  
  Map buildImageChunkRequest(String name) {
    if (!imageBuffer.containsKey(name)) {
      imageBuffer[name] = "";
    }
    String currentData = imageBuffer[name];
    return {'name':name, 'start':currentData.length, 'end':currentData.length + chunkSize};
  }

  /**
   * Request image data from a random connection.
   */
  bool requestImageData(String name, List<ConnectionWrapper> connections) {
    print("requesting image ${name}");
    Random r = new Random();
    // There is a case were a connection is added, but not yet ready for data transfer :/
    if (connections.length > 0) {
      print("got these ${connections}");
      ConnectionWrapper connection = connections[r.nextInt(connections.length)];
      connection.sendData({IMAGE_DATA_REQUEST:buildImageChunkRequest(name)});
      lastImageRequest[name] = new DateTime.now();
      return true;
    }
    return false;
  }
}