import 'package:fixnum/fixnum.dart';
import 'dart:typed_data';
import 'package:clock/clock.dart';

import 'package:dart2d/net/network.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/util.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:math';
import 'dart:core';
import 'helpers.dart';

class ConnectionWrapper {
  static bool THROW_SEND_ERRORS_FOR_TEST = false;
  final Logger log = new Logger('Connection');
  // Close connection due to inactivity.
  static const Duration LAST_RECEIVE_DATA_CLOSE_DURATION = Duration(seconds: 5);
  static const Duration KEEP_ALIVE_DURATION = Duration(seconds: 2);

  Network _network;
  ConfigParams _configParams;
  HudMessages _hudMessages;
  LeakyBucket? _ingressLimit = null;
  LeakyBucket? _egressLimit = null;
  PacketListenerBindings _packetListenerBindings;
  final String id;
  var _dataChannel;
  var _rtcConnection;
  int _sendFailures = 0;
  // True if connection was successfully opened.
  bool _opened = false;
  bool closed = false;

  bool _initialPingSent = false;
  bool _initialPongReceived = false;

  bool _handshakeReceived = false;

  // Keeping track of remote side frames, latest frame we've seen.
  int lastSeenRemoteFrame = 0;
  late DateTime _lastDataReceiveTime;
  int? _lastSeenKeyFrame = null;

  // The last frame the other side said we sent.
  late DateTime lastSentFrameTime;

  int lastDeliveredFrame = 0;
  // Time from sending to remote saying frame increased.
  Duration _frameIncrementLatencyTime = Duration.zero;

  late ConnectionStats _connectionStats;
  late ReliableHelper _reliableHelper;
  ConnectionFrameHandler _connectionFrameHandler;
  Clock _clock;

  ConnectionWrapper(this._network, this._hudMessages, this.id,
      this._packetListenerBindings, this._configParams,
      this._connectionFrameHandler, this._clock) {
    lastSentFrameTime = _clock.now();
    _lastDataReceiveTime = _clock.now();
    _connectionStats = new ConnectionStats(this._clock);
    _reliableHelper = new ReliableHelper(_packetListenerBindings);
    // Start the connection timer.
    if (_configParams.getInt(ConfigParam.INGRESS_BANDWIDTH) > 0) {
      _ingressLimit = new LeakyBucket(
          _configParams.getInt(ConfigParam.INGRESS_BANDWIDTH));
      log.info("Limit ingress bandwidth to ${_configParams.getInt(ConfigParam.INGRESS_BANDWIDTH)  / 1000 } ~kB/s");
    }
    if (_configParams.getInt(ConfigParam.EGRESS_BANDWIDTH) > 0) {
      _egressLimit = new LeakyBucket(
          _configParams.getInt(ConfigParam.EGRESS_BANDWIDTH));
      log.info("Limit egress bandwidth to ${_configParams.getInt(ConfigParam.EGRESS_BANDWIDTH)  / 1000 } ~kB/s");
    }
    log.fine("Opened connection to $id");
  }

  int currentKeyFrame() => _connectionFrameHandler.currentKeyFrame();

  int recipientFramesBehind() => (_connectionFrameHandler.currentFrame() - lastDeliveredFrame);

  bool hasReceivedFirstKeyFrame() {
    // The server does not need to wait for keyframes.
    return _lastSeenKeyFrame != null || _network.isCommander();
  }

  void close(String reason) {
    if (!closed) {
      _hudMessages.display("Connection to ${id} closed: $reason");
    }
    log.info("Closed connection to ${id} reason: ${reason}");
    closed = true;
  }

  void open() {
    _hudMessages.display("Connection to ${id} open :)");
    // Set the connection to current keyframe.
    // A faulty connection will be dropped quite fast if it lags behind in keyframes.
    _opened = true;
    _connectionStats.open();
  }

  void connectToGame(String playerName, int playerImageId) {
    // Send out local data hello. We don't do this as part of the intial handshake but over
    // the actual connection.
    ClientPlayerSpec spec = ClientPlayerSpec()
     ..name = playerName
     ..playerImageId = playerImageId;
    StateUpdate update = StateUpdate()
      ..clientPlayerSpec = spec;

    sendSingleUpdate(update);
  }

  /**
   * Send command to enter game.
   */
  void sendClientEnter() {
    StateUpdate update = StateUpdate();
    update.clientEnter = true;
    sendSingleUpdate(update);
  }

  /**
    * Send command to enter game.
    */
  void sendCommandTransfer() {
    StateUpdate update = StateUpdate();
    update.transferCommand = true;
    sendSingleUpdate(update);
  }

  /**
   * Send ping message with metadata about the connection.
   */
  void sendPing([bool gameStatePing = false]) {
    if (gameStatePing) {
      _initialPingSent = true;
      _initialPongReceived = false;
    }
    StateUpdate update = StateUpdate()
      ..ping = Int64(_clock.now().millisecondsSinceEpoch);
    sendSingleUpdate(update);
  }

  bool lastReceiveActivityOlderThan(int millis) {
    return _connectionStats.lastReceiveTime.millisecondsSinceEpoch < millis;
  }

  bool lastSendActivityOlderThan(int millis) {
    return _connectionStats.lastSendTime.millisecondsSinceEpoch < millis;
  }

  bool initialPongReceived() => _initialPongReceived;
  bool initialPingSent() => _initialPingSent;

  void setHandshakeReceived() {
    _handshakeReceived = true;
  }

  void resetHandshakeReceived() {
    _handshakeReceived = false;
  }

  /**
   * Client to Client connection don't need to wait for handshakes or
   * initial keyframes.
   */
  void markAsClientToClientConnection() {
    setHandshakeReceived();
    _lastSeenKeyFrame = 0;
  }

  void error(error) {
    _hudMessages.display("Connection ${id}: ${error} closing!");
    closed = true;
  }

  Random r = new Random();

  void receiveData(rawData) {
    if (_ingressLimit?.removeTokens(rawData.length) == true) {
      log.fine("Dropping due to ingress bandwidth limitation");
      return;
    }
    DateTime now = _clock.now();
    _lastDataReceiveTime = now;
    _connectionStats.lastReceiveTime = now;
    Uint8List list = rawData.asUint8List();
    _connectionStats.rxBytes += list.length;
    GameStateUpdates dataMap = GameStateUpdates.fromBuffer(list);
    assert(dataMap.hasLastFrameSeen());
    if (Logger.root.isLoggable(Level.FINE)) {
      log.fine("${id} -> ${_network.getPeer().getId()} data ${dataMap.toDebugString()}");
    }
    bool oldData = false;
    if (dataMap.frame > lastSeenRemoteFrame) {
      lastSeenRemoteFrame = dataMap.frame;
    } else if (dataMap.frame < lastSeenRemoteFrame) {
      // Basic check that we're not about to handle old data...
      oldData = true;
    }

    if (dataMap.lastFrameSeen > lastDeliveredFrame) {
      // How long time passed since we sent the keyframe?
      _frameIncrementLatencyTime = Duration(milliseconds: now.millisecondsSinceEpoch - lastSentFrameTime.millisecondsSinceEpoch);
      // How long time before the sender responded?
      sampleLatency(_frameIncrementLatencyTime);
      lastDeliveredFrame = dataMap.lastFrameSeen;
    }

    if (dataMap.hasKeyFrame()) {
      _lastSeenKeyFrame = dataMap.keyFrame;
    }

    // New path.
    for (StateUpdate update in dataMap.stateUpdate) {
      StateUpdate_Update updateType = update.whichUpdate();
      switch (updateType) {
        case StateUpdate_Update.ping:
          StateUpdate pongUpdate = StateUpdate()
            ..pong = update.ping;
          GameStateUpdates updates = GameStateUpdates()
            ..stateUpdate.add(pongUpdate);
          if (_network.isCommander()) {
            updates.stateUpdate.add(StateUpdate()
              ..gameState = _network.gameState.gameStateProto);
          }
          sendData(updates);
          continue;
        case StateUpdate_Update.pong:
          int latencyMillis = now.millisecondsSinceEpoch - update.pong.toInt();
          sampleLatency(new Duration(milliseconds: latencyMillis.toInt()));
            _initialPongReceived = true;
          continue;
        default:
      }
      if (_packetListenerBindings.hasHandler(updateType)) {
        for (dynamic handler in _packetListenerBindings.handlerFor(updateType)) {
          try {
            handler(this, update);
          } catch (e) {
            log.severe("Error handling type ${updateType} data ${update.toDebugString()}, error: $e");
            if (THROW_SEND_ERRORS_FOR_TEST) {
              throw e;
            }
          }
        }
      } else {
        throw new ArgumentError("No bound network listener for ${updateType} data: ${dataMap.toDebugString()}");
      }
    }

    // Wait for a first keyframe from this connection.
    if (!hasReceivedFirstKeyFrame()) {
      return;
    }
    // Don't continue handling data if handshake is not finished.
    if (!_handshakeReceived) {
      log.fine("not handling data ${dataMap}, handshake not received.");
      if (_network.getGameState().isInGame(_network.peer.id!) &&
          !_network.isCommander()) {
        // TODO figure out why this hack is needed...
        log.warning(
            "This is odd since connections is in the gamestate. Overriding!");
        _handshakeReceived = true;
      } else {
        return;
      }
    }

    if (!oldData) {
      _network.parseBundle(this, dataMap);
    }
  }

  void checkIfShouldClose(int keyFrame) {
    if (lastDataReceived() > LAST_RECEIVE_DATA_CLOSE_DURATION) {
      log.warning(
          "Connection to $id closed due to inactivity, last active ${lastDataReceived()} dropping");
      close("Not responding");
      return;
    }
  }

  /**
   * Advance connection time. Maybe send data. Maybe send keyframe.
   */
  void tick(double duration, List<int> removals) {
    // Tickle connection with some data in case it's about to go cold.
    if (lastDataReceived() > KEEP_ALIVE_DURATION) {
      sendPing();
    }

    if (!_connectionFrameHandler.tick(duration)) {
      // Don't send any data this tick.
      return;
    }
    GameStateUpdates data = GameStateUpdates()
      ..frame = _connectionFrameHandler.currentFrame();
    if (_connectionFrameHandler.keyFrame()) {
      _network.stateBundle(true, data, removals);
      data.keyFrame = _connectionFrameHandler.currentKeyFrame();
      // Maybe adjust connection framerate.
      _connectionFrameHandler.reportFramesBehind(recipientFramesBehind(),
          _frameIncrementLatencyTime.inMilliseconds);
    } else {
      // Send regular data.
      _network.stateBundle(false, data, removals);
    }

    if (!_handshakeReceived && !_connectionFrameHandler.keyFrame()) {
      // Don't send delta updates if not a valid game connection.
      return;
    }
    sendData(data);
  }

  void sendSingleUpdate(StateUpdate singleUpdate) {
    assert(singleUpdate.whichUpdate() != StateUpdate_Update.notSet);
    GameStateUpdates g = GameStateUpdates();
    g.stateUpdate.add(singleUpdate);
    sendData(g);
  }

  void sendData(GameStateUpdates data) {
    if (_reliableHelper.reliableBufferOverFlow()) {
      log.warning(
          "Connection to $id too many reliable packets behind ${_reliableHelper.reliableDataBuffer.length}, dropping!");
      close("Reliable overflow");
      return;
    }
    if (_connectionStats.ReceiveTimeout()) {
      log.warning(
          "Connection to $id not responsive, dropping!");
      close("Not responding receive timeout");
    }

    DateTime now = new DateTime.now();
    _connectionStats.lastSendTime = now;
    _reliableHelper.storeAwayReliableData(data);

    assert(_dataChannel != null);
    data.lastFrameSeen = lastSeenRemoteFrame;
    if (data.hasKeyFrame()) {
      // Check how many keyframes the remote peer is currenlty behind.
      // We might decide to close the connection because of this.
      checkIfShouldClose(data.keyFrame);
      // Make a defensive copy in case of keyframe.
      // Then add previous data to it.
      _reliableHelper.alsoSendWithStoredData(data);
    } else {
      // Store away any reliable data sent.
      _reliableHelper.storeAwayReliableData(data);
    }
    Uint8List dataBytes = data.writeToBuffer();


    if (_egressLimit?.removeTokens(dataBytes.length) == true) {
      log.fine("Dropping due to egress bandwith limitation");
      return;
    }
    _connectionStats.txBytes += dataBytes.length;

    try {
      if (Logger.root.isLoggable(Level.FINE)) {
        log.fine("${id} -> ${_network.getPeer().getId()} data ${data}");
      }
      _dataChannel.send(dataBytes);
      _sendFailures = 0;
    } catch (e, _) {
      if (THROW_SEND_ERRORS_FOR_TEST) {
        log.severe("Error sending ${data}!");
        throw e;
      }
      if (++_sendFailures > 2) {
        log.severe("Failed to send to $id: $e, closing connection");
        close("Failed to send data");
      }
    }
  }

  void readyDataChannel(var dataChannel) {
    _dataChannel = dataChannel;
  }

  bool hasReadyDataChannel() => _dataChannel != null;

  void setRtcConnection(var rtcConnection) {
    _rtcConnection = rtcConnection;
  }

  Duration lastDataReceived() {
    return Duration(milliseconds: _clock
        .now()
        .millisecondsSinceEpoch - _lastDataReceiveTime.millisecondsSinceEpoch);
  }

  bool isActiveConnection() {
    return _opened && !closed && _dataChannel != null && _rtcConnection != null;
  }

  bool wasOpen() => _opened;

  bool isClosedConnection() {
    if (closed) {
      return true;
    }
    // Timed out waiting to become open.
    if (!_opened && _connectionStats.OpenTimeout()) {
      return true;
    }

    return _connectionStats.ReceiveTimeout();
  }

  bool isValidGameConnection() {
    return !isClosedConnection() && this._handshakeReceived;
  }

  void sampleLatency(Duration latency) {
    if (latency.inMilliseconds < 0) {
      log.warning("None positive latency of $latency ignored");
      return;
    }
    this._connectionStats.latency = latency;
  }

  Duration expectedLatency() => _connectionStats.latency;

  ReliableHelper reliableHelper() => _reliableHelper;

  dynamic rtcConnection() => _rtcConnection;

  int currentFrameRate() => _connectionFrameHandler.currentFrameRate();

  toString() => "Connection to ${id} FR:${_connectionFrameHandler.currentFrameRate()} ms:${_frameIncrementLatencyTime.inMilliseconds}  GC: ${isValidGameConnection()} pi/Po ${_initialPingSent}/${_initialPongReceived}";

  String stats() => _connectionStats.stats();

  String frameStats() => "Frames S/D: ${_connectionFrameHandler.currentFrame()}/${lastDeliveredFrame} R: ${lastSeenRemoteFrame}";
}
