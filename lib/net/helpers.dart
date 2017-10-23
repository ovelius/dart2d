import 'dart:math';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/net/net.dart';
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

  void open() {
    _connectionOpenTimer.stop();
  }

  bool OpenTimeout() {
    return _connectionOpenTimer.elapsedMilliseconds > ConnectionStats.OPEN_TIMEOUT.inMilliseconds;
  }

  bool ReceiveTimeout() {
    // How many millis have we sent data, but not received anything back?
    int millis = lastSendTime.millisecondsSinceEpoch - lastReceiveTime.millisecondsSinceEpoch;
    return millis > RESPONSE_TIMEOUT.inMilliseconds;
  }

  String stats() => "rx/tx: ${formatBytes(rxBytes)}/${formatBytes(txBytes)}";
}

class ReliableHelper {
  // How many items the reliable buffer can contain before we consider the connection dead.
  static const int MAX_RELIABLE_BUFFER_SIZE = 80;
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