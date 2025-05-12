library test_connection;

import 'dart:js_interop';

import 'package:clock/clock.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/config_params.dart';
import 'test_env.dart';
import 'test_mocks.mocks.dart';

GameStateUpdates recentSentDataTo(id) {
  return GameStateUpdates.fromBuffer(testConnections[id]![0].recentDataSent!);
}

GameStateUpdates recentReceviedDataFrom(id, [int index = 0]) {
  return GameStateUpdates.fromBuffer(testConnections[id]![index].recentDataRecevied!);
}

class PacketWrapper {
  PacketWrapper(this._data);
  List<int> _data;
  dynamic asUint8List() {
    return _data;
  }
}

@JSExport()
class TestConnection {
  int dropPacketsAfter = 900000000;
  TestConnection? _otherEnd;
  String id;
  ConnectionWrapper? internalWrapper;
  bool closed = false;

  List<int>? recentDataSent = null;
  int dataReceivedCount = 0;
  var recentDataRecevied = null;

  @override
  bool operator ==(Object other) {
    if (other is TestConnection) {
       return other.id == id;
    }
    return false;
  }

  bool buffer = false;
  List<List<int>> dataBuffer = [];

  bool signalOpen = true;

  TestConnection(this.id, this.internalWrapper) {
    if (!testConnections.containsKey(id)) {
      testConnections[id] = [];
    }
    testConnections[id]!.add(this);
  }

  setOtherEnd(TestConnection otherEnd) {
    this._otherEnd = otherEnd;
  }

  TestConnection? getOtherEnd() => _otherEnd;

  operator [](index) => id;
  
  flushBuffer() {
    dataBuffer.forEach((e) { sendAndReceivByOtherPeer(e); });
    dataBuffer.clear();
  }

  sendAndReceivByOtherPeerNativeObject(GameStateUpdates data) {
    send(data.writeToBuffer());
  }

  GameStateUpdates nativeBufferedDataAt(int pos) {
    return GameStateUpdates.fromBuffer(dataBuffer[pos]);
  }

  void signalClose() {
    if (internalWrapper == null) {
      throw "No internal wrapper to signal close to!";
    }
    internalWrapper?.close("Test");
    _otherEnd?.internalWrapper?.close("TestOtherEnd");
    }

  void close() {
    closed = true;
    // Other ends also gets closed.
    if (_otherEnd != null && !_otherEnd!.closed) {
      _otherEnd?.close();
    }
  }

  sendAndReceivByOtherPeer(List<int> data) {
    GameStateUpdates update = GameStateUpdates.fromBuffer(data);
    for (StateUpdate update in update.stateUpdate) {
      if (update.whichUpdate() == StateUpdate_Update.notSet) {
        throw "Missing update type in $update!";
      }
    }
    if (closed) {
      throw new StateError("TestConnection ${this} is closed, can't send!");
    }
    bool drop = dropPacketsAfter <=0;
    dropPacketsAfter--;
    if (logConnectionData) {
      print("Data ${drop ? "DROPPED" : ""} ${_otherEnd} -> ${id}: ${update.toDebugString()}");
    }
    if (_otherEnd?.internalWrapper == null) {
      throw "${id}: No connection wrapper at other end ${_otherEnd}, can't send data $update!";
    }
    if (!drop) {
      recentDataSent = data;
      _otherEnd?.recentDataRecevied = data;
      _otherEnd?.dataReceivedCount++;
      _otherEnd?.internalWrapper?.receiveData(PacketWrapper(data));
    }
  }

  send(List<int> data) {
    GameStateUpdates update = GameStateUpdates.fromBuffer(data);
    for (StateUpdate update in update.stateUpdate) {
      if (update.whichUpdate() == StateUpdate_Update.notSet) {
        throw "Missing update type in $update!";
      }
    }
    if (buffer) {
      dataBuffer.add(data);
    } else {
      sendAndReceivByOtherPeer(data);
    }
  }

  toString() => "TestConnection $id -> ${_otherEnd == null ? 'NULL' : _otherEnd?.id}";
}

class TestConnectionWrapper extends ConnectionWrapper {

  final String id;
  int sendCount = 0;
  GameStateUpdates? lastDataSent = null;
  List<GameStateUpdates> dataSent = [];

  TestConnectionWrapper(this.id, MockNetwork mockNetwork, Clock clock) : super(mockNetwork, MockHudMessages(), id,
      MockPacketListenerBindings(), ConfigParams({}), ConnectionFrameHandler(ConfigParams({})), clock);

  void sampleLatency(Duration latency) {
    print("Got latency data of $latency");
  }

  sendPing([bool gameStatePing = false]) {
    print("pinged connection ${id}");
  }

  expectedLatency() => new Duration(milliseconds: 400);

  void sendData(GameStateUpdates data) {
    this.lastDataSent = data;
    this.dataSent.add(data);
    this.sendCount++;
  }
}

