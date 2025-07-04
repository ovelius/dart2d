import 'dart:math';
import 'package:clock/clock.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/util.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:core';

@Singleton(scope: 'world')
class PacketListenerBindings {
  Map<StateUpdate_Update, List<dynamic>> _handlers = {};

  bindHandler(StateUpdate_Update key, dynamic handler) {
    if (!_handlers.containsKey(key)) {
      _handlers[key] = [];
    }
    _handlers[key]?.add(handler);
  }

  List<dynamic> handlerFor(StateUpdate_Update key) {
    assert(_handlers.containsKey(key));
    return _handlers[key]!;
  }

  // Transition method. Eventually there will be handler everywhere.
  bool hasHandler(StateUpdate_Update key) {
    return _handlers.containsKey(key);
  }
}

class ConnectionStats {
  // How long until connection attempt times out.
  static const Duration OPEN_TIMEOUT = const Duration(seconds: 8);
  // When we should attempt to restart with ICE.
  static const Duration ICE_RESTART_TIME = const Duration(seconds: 5);
  // How long we don't have a response before we close the connection.
  static const Duration RESPONSE_TIMEOUT = const Duration(seconds: 10);

  int rxBytes = 0;
  int txBytes = 0;
  // The monitored latency of the connection.
  Duration latency = OPEN_TIMEOUT;

  Clock _clock;
  late DateTime _attemptOpenTime;
  DateTime? _openTime = null;
  DateTime lastSendTime = clock.now();
  DateTime lastReceiveTime = clock.now();

  ConnectionStats(this._clock) {
    _attemptOpenTime = _clock.now();
  }

  void gotSignalingMessage() {
    // Reset out open attempt time.
    _attemptOpenTime = _clock.now();
  }

  bool keepAlive() => receiveSentDiffMillis() > (RESPONSE_TIMEOUT.inMilliseconds / 4);

  void open() {
    _openTime = _clock.now();
  }

  bool OpenTimeout() {
    return _attemptOpenTime.add(ConnectionStats.OPEN_TIMEOUT).isBefore(_clock.now());
  }

  bool isIceRestartTime() {
    return _attemptOpenTime.add(ConnectionStats.ICE_RESTART_TIME).isBefore(_clock.now());
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
  // Storage of our reliable data.
  Map<int, StateUpdate> reliableDataBuffer = {};

  // Receipts we should send next tick.
  List<int> _pendingDataReceipts = [];

  PacketListenerBindings _packetListenerBindings;

  ReliableHelper(this._packetListenerBindings) {
    _packetListenerBindings.bindHandler(StateUpdate_Update.ackedDataReceipts, (_, StateUpdate update) {
       reliableDataBuffer.remove(update.ackedDataReceipts);
    });
  }

  bool reliableBufferOverFlow() => reliableDataBuffer.length > MAX_RELIABLE_BUFFER_SIZE;


  /**
   * See if we got any data receipts we need to keep track of.
   */
  void checkForDataReceipt(StateUpdate update) {
    if (update.hasDataReceipt()) {
      _pendingDataReceipts.add(update.dataReceipt);
    }
  }

  /**
   * Add any receives data receipts to the update.
   */
  void addDataReceipts(GameStateUpdates data) {
    for (int receipt in _pendingDataReceipts) {
      data.stateUpdate.add(StateUpdate()
        ..ackedDataReceipts = receipt);
    }
    _pendingDataReceipts.clear();
  }

  /**
   * Maybe add reliable data that needs to be resent.
   */
  void alsoSendWithStoredData(GameStateUpdates data) {
    for (StateUpdate reliableUpdate in reliableDataBuffer.values) {
      data.stateUpdate.add(reliableUpdate);
    }
  }

  /**
   * Take data considered reliable and store away in case we need to resend.
   */
  void storeAwayReliableData(GameStateUpdates dataMap) {
    for (StateUpdate stateUpdate in dataMap.stateUpdate) {
      if (stateUpdate.hasDataReceipt()) {
        reliableDataBuffer[stateUpdate.dataReceipt] = stateUpdate;
      }
    }
  }
}

class ConnectionFrameHandler {
  static double KEEP_MAX_NETWORK_FPS = GAME_TARGET_FPS * 0.8;
  static double KEEP_MIN_NETWORKS_FPS = GAME_TARGET_FPS / 2;

  static bool DISABLE_AUTO_ADJUST_FOR_TEST = false;
  final Logger log = new Logger('ConnectionFrameHandler');

  static const int MIN_FRAMERATE = 6;
  static const int MAX_FRAMERATE = 15;
  // Our base framerate for how often we send to network.
  static const double BASE_FRAMERATE_INTERVAL = 1.0 / MAX_FRAMERATE * 1.0;
  // How often to trigger keyframes. Base value is (1.0 / 15.0) * 7.5 = 0.5
  static const double BASE_KEY_FRAME_RATE_INTERVAL = BASE_FRAMERATE_INTERVAL * 7.5;

  static const int STABLE_FRAME_RATE_TUNING_INTERVAL = 5;

  double _nextFrame = 0.0;
  double _nextKeyFrame = 0.0;

  double _currentFrameDelay = BASE_FRAMERATE_INTERVAL;
  double _currentKeyFrameDelay = BASE_KEY_FRAME_RATE_INTERVAL;

  int _currentFrameRate = MAX_FRAMERATE.toInt();
  int _currentFrame = 0;
  int _currentKeyFrame = 0;


  ConnectionFrameHandler(ConfigParams params) {
    int frameRate = params.getInt(ConfigParam.MAX_NETWORK_FRAMERATE);
    if (frameRate > 0) {
      _setFrameRate(frameRate);
    }
  }

  /**
   * Maybe adjust connection framerate.
   */
  reportFrameRates(double receivingClientFps, double ourFps) {
    // We adjust based on signal of performance issues either locally or remote.
    int newFps = min(_translateFrameRate(receivingClientFps), _translateFrameRate(ourFps));
    _setFrameRate(newFps);
  }

  int _translateFrameRate(double drawFps) {
    if (drawFps > KEEP_MAX_NETWORK_FPS) {
      return MAX_FRAMERATE;
    }
    if (drawFps < KEEP_MIN_NETWORKS_FPS) {
      return MIN_FRAMERATE;
    }
    double percentOfTarget = drawFps / GAME_TARGET_FPS;
    return (percentOfTarget * MAX_FRAMERATE).toInt();
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
  final int _fillRatePerMillis;
  late int _tokenBuffer;

  late DateTime _lastCall;

  LeakyBucket(this._fillRatePerMillis, [int? startBuffer = null]) {
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