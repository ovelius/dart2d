import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';
import 'dart:async';
import 'package:di/di.dart';

@Injectable()
class ChunkHelper {
  final Logger log = new Logger('ChunkHelper');
  static const int DEFAULT_CHUNK_SIZE = 1400;
  static const int MAX_CHUNK_SIZE = 65000;
  static const int MIN_CHUNK_SIZE = 100;
  // TODO: Lower with ping time?
  static const Duration IMAGE_RETRY_DURATION =
      const Duration(milliseconds: 1500);

  ImageIndex _imageIndex;
  ByteWorld _byteWorld;
  PacketListenerBindings _packetListenerBindings;

  _DataCounter counter = new _DataCounter(3);
  int _chunkSize = DEFAULT_CHUNK_SIZE;
  Map<int, DateTime> _lastImageRequest = new Map();
  // Track failures by connection.
  Map<String, int> _failures = new Map();
  // Connection we requested image from.
  Map<int, String> _imageToConnection = new Map();

  // Buffer partially completed images in this map.
  Map<int, String> _imageBuffer = new Map();
  Map<int, int> _imageSizes = new Map();
  DateTime _created;
  double _timePassed = 0.0;

  // Our local cache.
  Map<int, String> _dataUrlCache = new Map();

  // Caching from Connection -> ByteWorld data.
  Map<String, String> _byteWorldDataUrlCache = new Map();

  ChunkHelper(this._imageIndex, this._byteWorld, this._packetListenerBindings) {
    _created = new DateTime.now();
    _packetListenerBindings.bindHandler(IMAGE_DATA_REQUEST,
        (ConnectionWrapper connection, Map dataMap) {
      replyWithImageData(dataMap, connection);
    });
    _packetListenerBindings.bindHandler(IMAGE_DATA_RESPONSE,
        (ConnectionWrapper connection, Map dataMap) {
      parseImageChunkResponse(dataMap, connection);
      // Request new data right away.
      requestNetworkData(
          // No time has passed.
          {connection.id: connection}, 0.0);
    });
    _packetListenerBindings.bindHandler(CLIENT_PLAYER_ENTER,
        (var connection, dynamic unused) {
      _byteWorldDataUrlCache.remove(connection.id);
    });
  }

  getImageBuffer() => new Map.from(_imageBuffer);
  getByteWorldCache() => new Map.from(_byteWorldDataUrlCache);

  /**
   * Send a reply with the requested image data.
   */
  void replyWithImageData(Map imageDataRequest, var connection) {
    int index = imageDataRequest['index'];
    String data = _getData(index, connection);
    int start =
        imageDataRequest.containsKey("start") ? imageDataRequest["start"] : 0;
    int end = imageDataRequest.containsKey("end")
        ? imageDataRequest["end"]
        : start + _chunkSize;
    end = min(end, data.length);

    if (start >= end) {
      throw new ArgumentError(
          "Got request ${imageDataRequest} for data of ${data.length} calculated end $end");
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

  String _getData(int index, var connection) {
    // Cached in byteworld cache.
    if (index == ImageIndex.WORLD_IMAGE_INDEX) {
      if (_byteWorldDataUrlCache.containsKey(connection.id)) {
        return _byteWorldDataUrlCache[connection.id];
      }
    }
    // Cached in regular cache? (Immutable)
    if (this._dataUrlCache.containsKey(index)) {
      return _dataUrlCache[index];
    }
    String data = null;
    if (index == ImageIndex.WORLD_IMAGE_INDEX) {
      // Special case the mutable byteworld.
      data = _byteWorld.asDataUrl();
      _byteWorldDataUrlCache[connection.id] = data;
      return data;
    } else {
      if (_imageIndex.imageIsLoaded(index)) {
        data = _imageIndex.getImageDataUrl(index);
      } else {
        // TODO do something smarter here, like load from server?
        _imageIndex.loadImagesFromServer();
        throw new StateError(
            "Can not return data for $index, it's not loaded!");
      }
    }
    _dataUrlCache[index] = data;
    return data;
  }

  /**
   * Parse response with imageData.
   */
  void parseImageChunkResponse(Map imageDataResponse, var connection) {
    int index = imageDataResponse['index'];
    String data = imageDataResponse['data'];
    counter.collect(data.length);
    int start = imageDataResponse['start'];
    // Final expected siimageBufferze.
    int size = imageDataResponse['size'];
    if (!_imageSizes.containsKey(index)) {
      _imageSizes[index] = size;
    }
    if (!_imageBuffer.containsKey(index)) {
      log.warning(
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
      log.warning("Dropping data for ${index}, out of order??");
    }

    // Image complete.
    if (_imageBuffer[index].length == size) {
      _imageIndex.addFromImageData(index, _imageBuffer[index]);
      _imageBuffer.remove(index);
      _imageSizes.remove(index);
      log.info("Image complete ${index} :)");
    }
  }

  void requestNetworkData(
      Map<String, ConnectionWrapper> connections, double secondsDuration) {
    requestSpecificNetworkData(
        connections, secondsDuration, _imageIndex.orderedImageIds());
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
    var connection = connections[connectionId];
    if (connection == null) {
      // Connection removed?
      _imageToConnection.remove(index);
      return false;
    }
    Duration latency = _now().difference(lastRequest);
    if (latency.inMilliseconds > _connectionLatencyMillis(connection)) {
      // Request smaller chunk. This was a retry.
      _trackFailingConnection(index);
      connection.sendPing();
      this._chunkSize = max(MIN_CHUNK_SIZE, (_chunkSize * 0.3).toInt());
      return _requestImageData(index, connectionList);
    }
    // return true if image is not loaded. False otherwise.
    return !_imageIndex.imageIsLoaded(index);
  }

  int _connectionLatencyMillis(var wrapper) {
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

  double getCompleteRatio(int index) {
    if (!_imageSizes.containsKey(index)) {
      if (_imageIndex.imageIsLoaded(index)) {
        return 1.0;
      } else {
        return 0.0;
      }
    }
    return _imageBuffer[index].length / _imageSizes[index];
  }

  String getTransferSpeed() {
    return "${formatBytes(counter.getBytes())}/s";
  }

  Stream<int> bytesPerSecondSamples() => counter.readSample();

  Map<String, int> failuresByConnection() => new Map.from(_failures);

  void setChunkSizeForTest(int chunkSize) {
    this._chunkSize = chunkSize;
  }
}

class _DataCounter {
  _DataCounter(this.secondsInterval) {
    _streamController = new StreamController();
  }

  int secondsInterval;
  int bytesPerSecond = 0;

  int bytesSinceLast = 0;
  DateTime lastCheck = new DateTime.now();

  StreamController<int> _streamController;

  collect(int bytes) {
    bytesSinceLast += bytes;
  }

  int getBytes() {
    Duration diff = new DateTime.now().difference(lastCheck);
    if (diff.inSeconds >= secondsInterval) {
      lastCheck = new DateTime.now();
      bytesPerSecond = bytesSinceLast ~/ diff.inSeconds;
      bytesSinceLast = 0;
      if (_streamController.hasListener) {
        _streamController.add(bytesPerSecond);
      }
    }
    return bytesPerSecond;
  }

  Stream<int> readSample() {
    if (_streamController.hasListener) {
      _streamController.close();
      _streamController = new StreamController();
    }
    return _streamController.stream;
  }
}
