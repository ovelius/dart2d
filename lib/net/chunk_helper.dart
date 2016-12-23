library chunk_helper;

import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';
import 'package:di/di.dart';

@Injectable()
class ChunkHelper {
  static const int DEFAULT_CHUNK_SIZE = 512;
  static const int MAX_CHUNK_SIZE = 65000;
  static const Duration IMAGE_RETRY_DURATION =
      const Duration(milliseconds: 1500);
  ImageIndex _imageIndex;
  _DataCounter counter = new _DataCounter(3);
  int chunkSize;
  Map<String, DateTime> _lastImageRequest = new Map();
  // Track failures by connection.
  Map<String, int> _failures = new Map();
  // Connection we requested image from.
  Map<String, String> _imageToConnection = new Map();

  Map<String, String> _imageBuffer = new Map();
  DateTime _created;
  double _timePassed = 0.0;
  
  ChunkHelper(this._imageIndex, [this.chunkSize = DEFAULT_CHUNK_SIZE]) {
    _created = new DateTime.now();
  }

  getImageBuffer() => new Map.from(_imageBuffer);

  /**
   * Send a reply with the requested image data.
   */
  void replyWithImageData(Map dataMap, var connection) {
    Map imageDataRequest = dataMap[IMAGE_DATA_REQUEST];
    String name = imageDataRequest['name'];
    String data = _imageIndex.getImageDataUrl(name);
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
    counter.collect(data.length);
    int start = imageDataResponse['start'];
    // Final expected siimageBufferze.
    int size = imageDataResponse['size'];
    if (!_imageBuffer.containsKey(name)) {
      print("Got image data for ${name}, excpected any of ${_imageBuffer.keys}");
      return;
    }
    if (start == _imageBuffer[name].length) {
      _imageBuffer[name] = _imageBuffer[name] + data;
      _lastImageRequest.remove(name);
      _imageToConnection.remove(name);
    } else {
      print("Dropping data for ${name}, out of order??");
    }

    // Image complete.
    if (_imageBuffer[name].length == size) {
      _imageIndex.addFromImageData(name, _imageBuffer[name]);
      _imageBuffer.remove(name);
      print("Image complete ${name} :)");
    }
  }
  
  void requestNetworkData(List<ConnectionWrapper> connections,
      double secondsDuration) {
    _timePassed += secondsDuration;
    int requestedImages = 0;
    for (String name in _imageIndex.allImagesByName().keys) {
      // Don't request more than 2 images at a time.
      if (requestedImages > 2 && !_imageIndex.imageIsLoaded(name)) {
        _lastImageRequest[name] = new DateTime.now();
        continue;
      }
      if (_maybeRequestImageLoad(name, connections)) {
        requestedImages++; 
      }
    }
  }

  DateTime _now() {
    return _created.add(new Duration(milliseconds: (_timePassed * 1000).toInt()));
  }

  bool _maybeRequestImageLoad(String name, List<ConnectionWrapper> connections) {
    if (!_imageIndex.imageIsLoaded(name)) {
      DateTime lastRequest = _lastImageRequest[name];
      if (lastRequest == null) {
        // Request larger chunk.
        this.chunkSize = min(MAX_CHUNK_SIZE, (this.chunkSize * 1.25).toInt());
        return _requestImageData(name, connections);
      } else if (_now().difference(lastRequest).inMilliseconds > IMAGE_RETRY_DURATION.inMilliseconds) {
        // Request smaller chunk. This was a retry.
        _trackFailingConnection(name);
        this.chunkSize = (this.chunkSize * 0.3).toInt();
        return _requestImageData(name, connections);
      }     
    }
    return false;
  }

  void _trackFailingConnection(String imageName) {
    String failingConnection = _imageToConnection[imageName];
    if (failingConnection != null) {
      if (_failures.containsKey(failingConnection)) {
        _failures[failingConnection] = _failures[failingConnection] + 1;
      } else {
        _failures[failingConnection] = 1;
      }
    }
  }
  
  Map buildImageChunkRequest(String name) {
    if (!_imageBuffer.containsKey(name)) {
      _imageBuffer[name] = "";
    }
    String currentData = _imageBuffer[name];
    return {'name':name, 'start':currentData.length, 'end':currentData.length + chunkSize};
  }

  /**
   * Request image data from a random connection.
   */
  bool _requestImageData(String name, List<dynamic> connections,
      [bool retry = false]) {
    Random r = new Random();
    // There is a case were a connection is added, but not yet ready for data transfer :/
    if (connections.length > 0) {
      var connection = connections[r.nextInt(connections.length)];
      connection.sendData({IMAGE_DATA_REQUEST:buildImageChunkRequest(name)});
      _lastImageRequest[name] = new DateTime.now();
      _imageToConnection[name] = connection.id;
      return true;
    }
    return false;
  }
  
  String getTransferSpeed() {
    return counter.format();
  }

  Map<String, int> failuresByConnection() => new Map.from(_failures);
}

class _DataCounter {
  _DataCounter(this.secondsInterval);

  int secondsInterval;
  int bytesPerSecond = 0;
  
  int bytesSinceLast = 0;
  DateTime lastCheck = new DateTime.now();

  collect(int bytes) {
    bytesSinceLast += bytes;
  }
  
  int getBytes() {
    Duration diff = new DateTime.now().difference(lastCheck);
    if (diff.inSeconds >= secondsInterval) {
      lastCheck = new DateTime.now();
      bytesPerSecond = bytesSinceLast ~/ diff.inSeconds;
      bytesSinceLast = 0;
    }
    return bytesPerSecond;
  }

  String format() {
    int bytesPerSecond = getBytes();
    if (bytesPerSecond > 2*1024*1024) {
      return "${bytesPerSecond ~/ (1024 * 1024)} MB";
    }
    if (bytesPerSecond > 2*1024) {
      return "${bytesPerSecond ~/ 1024} kB";
    }
    return "${bytesPerSecond} B";
  }
}