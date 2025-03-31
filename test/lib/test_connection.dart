library test_connection;

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/config_params.dart';
import 'package:injectable/injectable.dart';
import 'test_env.dart';
import 'test_mocks.mocks.dart';
import 'test_peer.dart';
import 'dart:convert';

recentSentDataTo(id) {
  return testConnections[id]![0].recentDataSent;
}

recentReceviedDataFrom(id, [int index = 0]) {
  return testConnections[id]![index].recentDataRecevied;
}


class TestConnection {
  int dropPacketsAfter = 900000000;
  TestConnection? _otherEnd;
  String id;
  ConnectionWrapper? internalWrapper;
  bool closed = false;

  String? recentDataSent = null;
  int dataReceivedCount = 0;
  var recentDataRecevied = null;

  @override
  bool operator ==(Object other) {
    if (other is TestConnection) {
       return other.id == id;
    }
    return false;
  }

  dynamic decodedRecentDataRecevied() {
    if (recentDataRecevied == null) {
      throw new StateError("No recent data received on ${toString()}");
    }
    return jsonDecode(recentDataRecevied);
  }

  bool buffer = false;
  List<String> dataBuffer = [];

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

  sendAndReceivByOtherPeerNativeObject(Map object) {
    send(jsonEncode(object));
  }

  nativeBufferedDataAt(int pos) {
    return jsonDecode(dataBuffer[pos]);
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
  }

  sendAndReceivByOtherPeer(String jsonString) {
    if (closed) {
      throw new StateError("TestConnection is closed, can't send!");
    }
    bool drop = dropPacketsAfter <=0;
    dropPacketsAfter--;
    if (logConnectionData) {
      print("Data ${drop ? "DROPPED" : ""} ${_otherEnd} -> ${id}: ${jsonString}");
    }
    if (_otherEnd?.internalWrapper == null) {
      throw "No connection wrapper at other end, can't send data!";
    }
    if (!drop) {
      recentDataSent = jsonString;
      _otherEnd?.recentDataRecevied = jsonString;
      _otherEnd?.dataReceivedCount++;
      _otherEnd?.internalWrapper?.receiveData(jsonString);
    }
  }

  send(String string) {
    if (buffer) {
      dataBuffer.add(string);
    } else {
      sendAndReceivByOtherPeer(string);
    }
  }

  toString() => "TestConnection $id -> ${_otherEnd == null ? 'NULL' : _otherEnd?.id}";
}

class TestConnectionWrapper extends ConnectionWrapper {

  final String id;
  int sendCount = 0;
  Map? lastDataSent = null;
  List<Map> dataSent = [];

  TestConnectionWrapper(this.id) : super(MockNetwork(), MockHudMessages(), id,
      MockPacketListenerBindings(), ConfigParams({}), ConnectionFrameHandler(ConfigParams({})));

  void sampleLatency(Duration latency) {
    print("Got latency data of $latency");
  }

  sendPing([bool gameStatePing = false]) {
    print("pinged connection ${id}");
  }

  expectedLatency() => new Duration(milliseconds: 400);

  void sendData(Map data) {
    this.lastDataSent = data;
    this.dataSent.add(data);
    this.sendCount++;
  }
}

