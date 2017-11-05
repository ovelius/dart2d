import 'dart:math';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/net/net.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:convert';
import 'package:di/di.dart';
import 'dart:core';

@Injectable()
class PacketListenerBindings {
  static final Set<String> IgnoreListeners = new Set.from([
    IS_KEY_FRAME_KEY,
    KEY_FRAME_KEY,
    DATA_RECEIPTS,
    CONTAINED_DATA_RECEIPTS,
    PING,
    PONG,
    KEY_FRAME_DELAY,
  ]);

  Map<String, List<dynamic>> _handlers = {};

  bindHandler(String key, dynamic handler) {
    if (!_handlers.containsKey(key)) {
      _handlers[key] = [];
    }
    _handlers[key].add(handler);
  }

  List<dynamic> handlerFor(String key) {
    assert(_handlers.containsKey(key));
    return _handlers[key];
  }

  // Transition method. Eventually there will be handler everywhere.
  bool hasHandler(String key) {
    return _handlers.containsKey(key);
  }
}

class ConnectionStats {
  // How long until connection attempt times out.
  static const Duration OPEN_TIMEOUT = const Duration(seconds: 6);
  // How long we don't have a response before we close the connection.
  static const Duration RESPONSE_TIMEOUT = const Duration(seconds: 10);

  int rxBytes = 0;
  int txBytes = 0;
  // Keep track of how long connection has been open.
  Stopwatch _connectionOpenTimer = new Stopwatch();
  // The monitored latency of the connection.
  Duration latency = OPEN_TIMEOUT;

  DateTime lastSendTime = new DateTime.now();
  DateTime lastReceiveTime = new DateTime.now();

  ConnectionStats() {
    _connectionOpenTimer.start();
  }

  bool keepAlive() => receiveSentDiffMillis() > (RESPONSE_TIMEOUT.inMilliseconds / 4);

  void open() {
    _connectionOpenTimer.stop();
  }

  bool OpenTimeout() {
    return _connectionOpenTimer.elapsedMilliseconds > ConnectionStats.OPEN_TIMEOUT.inMilliseconds;
  }

  bool ReceiveTimeout() {
    // How many millis have we sent data, but not received anything back?
    return sentReceivedDiffMillis() > RESPONSE_TIMEOUT.inMilliseconds;
  }

  int sentReceivedDiffMillis() {
    return lastSendTime.millisecondsSinceEpoch - lastReceiveTime.millisecondsSinceEpoch;
  }

  int receiveSentDiffMillis() {
    return lastReceiveTime.millisecondsSinceEpoch - lastSendTime.millisecondsSinceEpoch;
  }

  String stats() => "rx/tx: ${formatBytes(rxBytes)}/${formatBytes(txBytes)}";
}

class ReliableHelper {
  // How many items the reliable buffer can contain before we consider the connection dead.
  static const int MAX_RELIABLE_BUFFER_SIZE = 160;
  PacketListenerBindings _packetListenerBindings;
  // Storage of our reliable key data.
  Map reliableDataBuffer = {};
  // Reliable verifications.
  List<int> reliableDataToVerify = [];

  ReliableHelper(this._packetListenerBindings) {
    _packetListenerBindings.bindHandler(CONTAINED_DATA_RECEIPTS, (ConnectionWrapper c, List data) {
      reliableDataToVerify.addAll(data);
    });
    _packetListenerBindings.bindHandler(DATA_RECEIPTS, (ConnectionWrapper c, List data) {
      for (int receipt in data) {
        reliableDataBuffer.remove(receipt);
      }
    });
  }

  bool reliableBufferOverFlow() => reliableDataBuffer.length > MAX_RELIABLE_BUFFER_SIZE;

  /**
   * Append any previously received data receipts before sending.
   */
  void updateWithDataReceipts(Map data) {
    if (reliableDataToVerify.isNotEmpty) {
      data[DATA_RECEIPTS] = reliableDataToVerify;
      reliableDataToVerify = [];
    }
  }

  /**
   * Maybe add reliable data that needs to be resent.
   */
  void alsoSendWithStoredData(Map dataMap) {
    storeAwayReliableData(dataMap);
    for (int hash in new List.from(reliableDataBuffer.keys)) {
      List tuple = reliableDataBuffer[hash];
      String reliableKey = tuple[0];
      // There is more data of the same type. Merge.
      if (dataMap.containsKey(reliableKey)) {
        // Merge data with previously saved data for this key.
        dynamic mergeFunction = RELIABLE_KEYS[reliableKey];
        dataMap[reliableKey] = mergeFunction(dataMap[reliableKey], tuple[1]);
        _addContainedReceipt(dataMap, hash);
      } else {
        dataMap[reliableKey] = tuple[1];
        _addContainedReceipt(dataMap, hash);
      }
    }
  }

  void _addContainedReceipt(Map dataMap, int receipt) {
    if (dataMap[CONTAINED_DATA_RECEIPTS] == null) {
      dataMap[CONTAINED_DATA_RECEIPTS] = [];
    }
    if (!dataMap[CONTAINED_DATA_RECEIPTS].contains(receipt)) {
      dataMap[CONTAINED_DATA_RECEIPTS].add(receipt);
    }
  }

  /**
   * Take data considered reliable and store away in case we need to resend.
   */
  void storeAwayReliableData(Map dataMap) {
    for (String reliableKey in RELIABLE_KEYS.keys) {
      if (dataMap.containsKey(reliableKey)) {
        Object data = dataMap[reliableKey];
        int jsonHash = JSON.encode(data).hashCode;
        reliableDataBuffer[jsonHash] = [reliableKey, data];
        _addContainedReceipt(dataMap, jsonHash);
      }
    }
  }
}

class ConnectionFrameHandler {
  static bool DISABLE_AUTO_ADJUST_FOR_TEST = false;
  final Logger log = new Logger('ConnectionFrameHandler');

  static const int MIN_FRAMERATE = 6;
  static const int MAX_FRAMERATE = 15;
  // Our base framerate for how often we send to network.
  static const double BASE_FRAMERATE_INTERVAL = 1.0 / MAX_FRAMERATE * 1.0;
  // How often to trigger keyframes. Base value is (1.0 / 15.0) * 7.5 = 0.5
  static const double BASE_KEY_FRAME_RATE_INTERVAL = BASE_FRAMERATE_INTERVAL * 7.5;

  static const int STABLE_FRAME_RATE_TUNING_INTERVAL = 6;

  double _nextFrame = 0.0;
  double _nextKeyFrame = 0.0;

  double _currentFrameDelay = BASE_FRAMERATE_INTERVAL;
  double _currentKeyFrameDelay = BASE_KEY_FRAME_RATE_INTERVAL;

  int _currentFrameRate = MAX_FRAMERATE.toInt();
  int _currentFrame = 0;
  int _currentKeyFrame = 0;

  // How many frames in a row we've considered the connection to be stable.
  int _stableFrames = 0;

  ConnectionFrameHandler(ConfigParams params) {
    int frameRate = params.getInt(ConfigParam.MAX_NETWORK_FRAMERATE);
    if (frameRate > 0) {
      _setFrameRate(frameRate);
    }
  }

  /**
   * Maybe adjust connection framerate.
   */
  reportConnectionMetrics(int framesBehind, int latencyMillis) {
    // Being 0 or 1 keyframes behind is quite normal.
    if (framesBehind <= 1) {
      _stableFrames++;
      if (_stableFrames > STABLE_FRAME_RATE_TUNING_INTERVAL) {
        // Try to increase framerate again.
        _setFrameRate(_currentFrameRate + 1);
        _stableFrames = 0;
      }
    }
    // Being more than 1 keyframe behind shouldn't really happen.
    // Reduce framerate.
    if (framesBehind > 1) {
      _stableFrames = 0;
      // Reduce framerate.
      _setFrameRate(_currentFrameRate - min(framesBehind, 5));
    }
  }

  _setFrameRate(int rate) {
    if (rate > MAX_FRAMERATE) {
      rate = MAX_FRAMERATE;
    }
    if (rate < MIN_FRAMERATE) {
      rate = MIN_FRAMERATE;
    }
    if (DISABLE_AUTO_ADJUST_FOR_TEST) {
      log.info("TEST ONLY: Want to set new connection framerate to ${rate}");
      return;
    }
    _currentFrameRate = rate;
    _currentFrameDelay = 1.0 / _currentFrameRate;
    _currentKeyFrameDelay = _currentFrameDelay * 7.5;
  }

  /**
   * Tick the connection lifetime. Return true if data should be sent.
   */
  bool tick(double duration) {
    if (_nextFrame < 0) {
      _currentFrame++;
      _nextFrame += _currentFrameDelay;
    }
    if (_nextKeyFrame < 0) {
      _currentKeyFrame++;
      _nextKeyFrame += _currentKeyFrameDelay;
    }
    _nextFrame -= duration;
    _nextKeyFrame -= duration;
    // Consider frame if keyframe or regular frame.
    return _nextFrame < 0 || _nextKeyFrame < 0;
  }

  bool keyFrame() {
    return _nextKeyFrame < 0;
  }

  int currentKeyFrame() => _currentKeyFrame;
  int currentFrame() => _currentFrame;
  int currentFrameRate() => _currentFrameRate;
}

class LeakyBucket {
  int _fillRatePerMillis;
  int _tokenBuffer;

  DateTime _lastCall;

  LeakyBucket(this._fillRatePerMillis, [int startBuffer]) {
    _tokenBuffer = _fillRatePerMillis;
    if (startBuffer != null) {
      _tokenBuffer = startBuffer;
    }
    _lastCall = new DateTime.now();
  }

  bool removeTokens(int tokens) {
    DateTime now = new DateTime.now();
    int durationMillis =
    (now.millisecondsSinceEpoch - _lastCall.millisecondsSinceEpoch);
    _lastCall = now;

    _tokenBuffer += (_fillRatePerMillis  * durationMillis).toInt();
    // Max out to one second of buffer.
    _tokenBuffer = min(_fillRatePerMillis * 1000, _tokenBuffer);

    if (_tokenBuffer < tokens) {
      return false;
    }
    _tokenBuffer -= tokens;
    return true;
  }
}