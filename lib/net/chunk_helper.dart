import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/util.dart';
import 'dart:convert';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/res/imageindex.dart';
import 'dart:math';
import 'dart:async';

import 'package:protobuf/protobuf.dart';

@Singleton(scope:'world')
class ChunkHelper {
  final Logger log = new Logger('ChunkHelper');
  static const int DEFAULT_CHUNK_SIZE = 1400;
  static const int MAX_CHUNK_SIZE = 65000;
  // To fit nice inside your typical MTU.
  static const int MIN_CHUNK_SIZE = 1300;
  static const int IMAGE_RETRY_DURATION_MILLIS = 1500;

  ImageIndex _imageIndex;
  ByteWorld _byteWorld;
  PacketListenerBindings _packetListenerBindings;

  DataCounter counter = new DataCounter(3);
  int _chunkSize = DEFAULT_CHUNK_SIZE;
  double _chunkSizeIncrementFactor = 1.25;
  double _chunkDecrementFactor = 0.3;
  Map<int, double> _retryTimer = new Map();
  // Track failures by connection.
  Map<String, int> _failures = new Map();
  // Connection we requested image from.
  Map<int, String> _imageToConnection = new Map();

  // Buffer partially completed images in this map.
  Map<int, String> _imageBuffer = new Map();
  Map<int, int> _imageSizes = new Map();

  // Our local cache.
  Map<int, String> _dataUrlCache = new Map();

  // Caching from Connection -> ByteWorld data.
  Map<String, String> _byteWorldDataUrlCache = new Map();

  ChunkHelper(this._imageIndex, this._byteWorld, this._packetListenerBindings) {
    _packetListenerBindings.bindHandler(StateUpdate_Update.resourceRequest,
        (ConnectionWrapper connection, StateUpdate resourceRequest) {
      replyWithImageData(resourceRequest.resourceRequest, connection);
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.resourceResponse,
        (ConnectionWrapper connection, StateUpdate data) {
      parseImageChunkResponse(data.resourceResponse, connection);
      // Request new data right away.
      requestNetworkData(
          // No time has passed.
          {connection.id: connection}, 0.0);
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.clientEnter,
        (var connection, dynamic unused) {
      _byteWorldDataUrlCache.remove(connection.id);
    });
  }

  getImageBuffer() => new Map.from(_imageBuffer);
  getByteWorldCache() => new Map.from(_byteWorldDataUrlCache);

  /**
   * Send a reply with the requested image data.
   */
  void replyWithImageData(ResourceRequest request, ConnectionWrapper connection) {
    String data = _getData(request.resourceIndex, connection);
    int end = request.hasEndByte() ? request.endByte
        : request.startByte + _chunkSize;
    end = min(end, data.length);

    if (request.startByte >= end) {
      throw new ArgumentError(
          "Got request ${request.toDebugString()} for data of ${data.length} calculated end $end");
    }
    String chunk = data.substring(request.startByte, end);
    ResourceResponse response = ResourceResponse()
      ..data = utf8.encode(chunk)
      ..startByte = request.startByte
      ..resourceIndex = request.resourceIndex
      ..size = data.length;

    connection.sendSingleUpdate(StateUpdate()..resourceResponse = response);

    // Send more data immediately.
    if (request.multiply > 0 && end < data.length) {
      int size = (request.endByte - request.startByte);
      ResourceRequest newRequest = ResourceRequest()
        ..resourceIndex = request.resourceIndex
        ..multiply = request.multiply -1
        ..startByte = request.endByte
        ..endByte = request.endByte + size;
      replyWithImageData(newRequest, connection);
    }
  }

  String _getData(int index, var connection) {
    // Cached in byteworld cache.
    if (index == ImageIndex.WORLD_IMAGE_INDEX) {
      if (_byteWorldDataUrlCache.containsKey(connection.id)) {
        return _byteWorldDataUrlCache[connection.id]!;
      }
    }
    // Cached in regular cache? (Immutable)
    if (this._dataUrlCache.containsKey(index)) {
      return _dataUrlCache[index]!;
    }
    String? data = null;
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
            "Can not return data for $index, it's not loaded! Loaded is: ${_imageIndex.loadedImages}");
      }
    }
    _dataUrlCache[index] = data;
    return data;
  }

  /**
   * Parse response with imageData.
   */
  void parseImageChunkResponse(ResourceResponse response, var connection) {
    int index = response.resourceIndex;
    String data = utf8.decode(response.data);
    counter.collect(data.length);
    int start = response.startByte;
    // Final expected siimageBufferze.
    int size = response.size;
    if (!_imageSizes.containsKey(index)) {
      _imageSizes[index] = size;
    }
    if (!_imageBuffer.containsKey(index)) {
      log.warning(
          "Got image data for ${index}, excpected any of ${_imageBuffer.keys}");
      return;
    }
    if (start == _imageBuffer[index]!.length) {
      _imageBuffer[index] = _imageBuffer[index]! + data;
      _imageToConnection.remove(index);
    } else {
      log.warning("Dropping data for ${index}, out of order??");
    }

    // Image complete.
    if (_imageBuffer[index]!.length == size) {
      _imageIndex.addFromImageData(index, _imageBuffer[index]!, true);
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
    int requestedImages = 0;
    for (int index in IdsToFetch) {
      if (_retryTimer.containsKey(index)) {
        _retryTimer[index] = _retryTimer[index]! - secondsDuration;
      }
      // Don't request more than 3 images at a time.
      if (requestedImages > 2) {
        continue;
      }
      if (!_imageIndex.imageIsLoading(index)) {
        if (_maybeRequestImageLoad(index, connections, secondsDuration)) {
          requestedImages++;
        }
      }
    }
  }

  bool _maybeRequestImageLoad(
      int index, Map<String, ConnectionWrapper> connections, double duration) {
    List<ConnectionWrapper> connectionList = new List.from(connections.values);
    String? connectionId = _imageToConnection[index];
    if (connectionId == null) {
      // Request larger chunk.
      if (_chunkSize == MIN_CHUNK_SIZE) {
        _chunkSizeIncrementFactor = 1.05;
      }
      if (_chunkSize == MAX_CHUNK_SIZE) {
        _chunkDecrementFactor = 0.7;
      }
      this._chunkSize = min(MAX_CHUNK_SIZE, (_chunkSize * _chunkSizeIncrementFactor).toInt());
      return _requestImageData(index, connectionList);
    }
    // Look if we should retry.
    ConnectionWrapper? connection = connections[connectionId];
    if (connection == null) {
      // Connection removed?
      _imageToConnection.remove(index);
      return false;
    }
    double? lastRequestTimeout = _retryTimer[index];
    if (lastRequestTimeout == null || lastRequestTimeout < 0) {
      // Request smaller chunk. This was a retry.
      _trackFailingConnection(index);
      connection.sendPing();
      this._chunkSize = max(MIN_CHUNK_SIZE, (_chunkSize * _chunkDecrementFactor).toInt());
      return _requestImageData(index, connectionList);
    }
    // return true if image is not loaded. False otherwise.
    return !_imageIndex.imageIsLoaded(index);
  }

  void _trackFailingConnection(int index) {
    String? failingConnection = _imageToConnection[index];
    if (failingConnection != null) {
      if (_failures.containsKey(failingConnection)) {
        _failures[failingConnection] = _failures[failingConnection]! + 1;
      } else {
        _failures[failingConnection] = 1;
      }
    }
  }

  ResourceRequest buildImageChunkRequest(int index) {
    if (!_imageBuffer.containsKey(index)) {
      _imageBuffer[index] = "";
    }
    String currentData = _imageBuffer[index]!;
    return ResourceRequest()
        ..resourceIndex = index
        ..startByte = currentData.length
        ..endByte = currentData.length + _chunkSize;
  }

  /**
   * Request image data from a random connection.
   */
  bool _requestImageData(int index, List<dynamic> connections,
      [bool retry = false]) {
    Random r = new Random();
    // There is a case were a connection is added, but not yet ready for data transfer :/
    if (connections.length > 0) {
      ConnectionWrapper connection = connections[r.nextInt(connections.length)];
      connection.sendSingleUpdate(StateUpdate()
        ..resourceRequest =  buildImageChunkRequest(index));
      Duration connectionLatency = connection.expectedLatency();
      int millis = min(IMAGE_RETRY_DURATION_MILLIS,
          connectionLatency.inMilliseconds * 2);
      _retryTimer[index] = millis / 1000.0;
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
    return _imageBuffer[index]!.length / _imageSizes[index]!;
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

class DataCounter {
  DataCounter(this.secondsInterval) {
    _streamController = new StreamController();
  }

  int secondsInterval;
  int bytesPerSecond = 0;

  int bytesSinceLast = 0;
  DateTime lastCheck = new DateTime.now();

  late StreamController<int> _streamController;

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
