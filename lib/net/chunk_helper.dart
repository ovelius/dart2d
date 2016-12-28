library chunk_helper;

import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';
import 'package:di/di.dart';

@Injectable()
class ChunkHelper {
  static const int DEFAULT_CHUNK_SIZE = 1024;
  static const int MAX_CHUNK_SIZE = 65000;
  static const int MIN_CHUNK_SIZE = 100;
  // TODO: Lower with ping time?
  static const Duration IMAGE_RETRY_DURATION =
      const Duration(milliseconds: 1500);
  ImageIndex _imageIndex;
  ByteWorld _byteWorld;
  _DataCounter counter = new _DataCounter(3);
  int _chunkSize = DEFAULT_CHUNK_SIZE;
  Map<int, DateTime> _lastImageRequest = new Map();
  // Track failures by connection.
  Map<String, int> _failures = new Map();
  // Connection we requested image from.
  Map<int, String> _imageToConnection = new Map();

  // Buffer partially completed images in this map.
  Map<int, String> _imageBuffer = new Map();
  DateTime _created;
  double _timePassed = 0.0;

  // Our local cache.
  Map<int, String> _dataUrlCache = new Map();

  ChunkHelper(this._imageIndex, this._byteWorld) {
    _created = new DateTime.now();
  }

  getImageBuffer() => new Map.from(_imageBuffer);

  /**
   * Send a reply with the requested image data.
   */
  void replyWithImageData(Map dataMap, var connection) {
    Map imageDataRequest = dataMap[IMAGE_DATA_REQUEST];
    int index = imageDataRequest['index'];
    String data = _getData(index);
    int start =
        imageDataRequest.containsKey("start") ? imageDataRequest["start"] : 0;
    int end = imageDataRequest.containsKey("end")
        ? imageDataRequest["end"]
        : start + _chunkSize;
    end = min(end, data.length);

    if (start >= end) {
      throw new ArgumentError("Got request ${imageDataRequest} for data of ${data.length} calculated end $end");
    }
    String chunk = data.substring(start, end);
    connection.sendData({
      IMAGE_DATA_RESPONSE: {
        'index': index,
        'data': chunk,
        'start': start,
        'size': data.length
      }
    });
  }

  String _getData(int index) {
    if (this._dataUrlCache.containsKey(index)) {
      return _dataUrlCache[index];
    }
    String data = null;
    if (index == ImageIndex.WORLD_IMAGE_INDEX) {
      // TODO: Snapshot events during loading.
      // TODO: Empty cache after loading completed?
      data = _byteWorld.asDataUrl();
    } else {
      data = _imageIndex.getImageDataUrl(index);
    }
    _dataUrlCache[index] = data;
    return data;
  }

  /**
   * Parse response with imageData.
   */
  void parseImageChunkResponse(Map dataMap, var connection) {
    Map imageDataResponse = dataMap[IMAGE_DATA_RESPONSE];
    int index = imageDataResponse['index'];
    String data = imageDataResponse['data'];
    counter.collect(data.length);
    int start = imageDataResponse['start'];
    // Final expected siimageBufferze.
    int size = imageDataResponse['size'];
    if (!_imageBuffer.containsKey(index)) {
      print(
          "Got image data for ${index}, excpected any of ${_imageBuffer.keys}");
      return;
    }
    if (start == _imageBuffer[index].length) {
      _imageBuffer[index] = _imageBuffer[index] + data;
      if (_lastImageRequest.containsKey(index)) {
        Duration latency = _lastImageRequest[index].difference(_now());
        connection.sampleLatency(latency);
      }
      _imageToConnection.remove(index);
    } else {
      print("Dropping data for ${index}, out of order??");
    }

    // Image complete.
    if (_imageBuffer[index].length == size) {
      _imageIndex.addFromImageData(index, _imageBuffer[index]);
      _imageBuffer.remove(index);
      print("Image complete ${index} :)");
    }
  }

  void requestNetworkData(
      Map<String, ConnectionWrapper> connections, double secondsDuration) {
    requestSpecificNetworkData(
        connections, secondsDuration, _imageIndex.allImagesByName().values);
  }

  void requestSpecificNetworkData(Map<String, ConnectionWrapper> connections,
      double secondsDuration, Iterable<int> IdsToFetch) {
    _timePassed += secondsDuration;
    int requestedImages = 0;
    for (int index in IdsToFetch) {
      // Don't request more than 3 images at a time.
      if (requestedImages > 2) {
        continue;
      }
      if (!_imageIndex.imageIsLoaded(index)) {
        if (_maybeRequestImageLoad(index, connections)) {
          requestedImages++;
        }
      }
    }
  }

  DateTime _now() {
    return _created
        .add(new Duration(milliseconds: (_timePassed * 1000).toInt()));
  }

  bool _maybeRequestImageLoad(
      int index, Map<String, ConnectionWrapper> connections) {
    List<ConnectionWrapper> connectionList = new List.from(connections.values);
    DateTime lastRequest = _lastImageRequest[index];
    String connectionId = _imageToConnection[index];
    if (connectionId == null) {
      // Request larger chunk.
      this._chunkSize = min(MAX_CHUNK_SIZE, (this._chunkSize * 1.25).toInt());
      return _requestImageData(index, connectionList);
    }
    // Look if we should retry.
    ConnectionWrapper connection = connections[connectionId];
    Duration latency = _now().difference(lastRequest);
    if (latency.inMilliseconds > _connectionLatencyMillis(connection)) {
      // Request smaller chunk. This was a retry.
      _trackFailingConnection(index);
      this._chunkSize = max(MIN_CHUNK_SIZE, (_chunkSize * 0.3).toInt());
      return _requestImageData(index, connectionList);
    }
    // return true if image is not loaded. False otherwise.
    return !_imageIndex.imageIsLoaded(index);
  }

  int _connectionLatencyMillis(ConnectionWrapper wrapper) {
    if (wrapper == null) {
      return IMAGE_RETRY_DURATION.inMilliseconds;
    }
    Duration connectionLatency = wrapper.expectedLatency();
    return min(connectionLatency.inMilliseconds * 2,
        IMAGE_RETRY_DURATION.inMilliseconds);
  }

  void _trackFailingConnection(int index) {
    String failingConnection = _imageToConnection[index];
    if (failingConnection != null) {
      if (_failures.containsKey(failingConnection)) {
        _failures[failingConnection] = _failures[failingConnection] + 1;
      } else {
        _failures[failingConnection] = 1;
      }
    }
  }

  Map buildImageChunkRequest(int index) {
    if (!_imageBuffer.containsKey(index)) {
      _imageBuffer[index] = "";
    }
    String currentData = _imageBuffer[index];
    return {
      'index': index,
      'start': currentData.length,
      'end': currentData.length + _chunkSize
    };
  }

  /**
   * Request image data from a random connection.
   */
  bool _requestImageData(int index, List<dynamic> connections,
      [bool retry = false]) {
    Random r = new Random();
    // There is a case were a connection is added, but not yet ready for data transfer :/
    if (connections.length > 0) {
      var connection = connections[r.nextInt(connections.length)];
      connection.sendData({IMAGE_DATA_REQUEST: buildImageChunkRequest(index)});
      _lastImageRequest[index] = new DateTime.now();
      _imageToConnection[index] = connection.id;
      return true;
    }
    return false;
  }

  String getTransferSpeed() {
    return counter.format();
  }

  Map<String, int> failuresByConnection() => new Map.from(_failures);

  void setChunkSizeForTest(int chunkSize) {
    this._chunkSize = chunkSize;
  }
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
    if (bytesPerSecond > 2 * 1024 * 1024) {
      return "${bytesPerSecond ~/ (1024 * 1024)} MB";
    }
    if (bytesPerSecond > 2 * 1024) {
      return "${bytesPerSecond ~/ 1024} kB";
    }
    return "${bytesPerSecond} B";
  }
}
