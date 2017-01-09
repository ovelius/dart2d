library test_connection;

import 'dart:convert';

recentSentDataTo(id) {
  return testConnections[id][0].recentDataSent;
}

recentReceviedDataFrom(id, [int index = 0]) {
  return testConnections[id][index].recentDataRecevied;
}

// Map of connections from id.
Map<String, List<TestConnection>> testConnections = {};

// Next created TestConnection will drop these many packets.
List<int> droppedPacketsNextConnection = [];
// Next created TEstConnection will start to drop packets after this many
// packets.
List<int> droppedPacketsAfterNextConnection = [];

bool logConnectionData = true;

class TestConnection {
  int dropPackets = 0;
  int dropPacketsAfter = 900000000;
  TestConnection _otherEnd;
  var id;
  var eventHandlers = {};
  
  var recentDataSent = null;
  var recentDataRecevied = null;

  dynamic decodedRecentDataRecevied() => JSON.decode(recentDataRecevied);
  
  bool buffer = false;
  List dataBuffer = [];

  bool signalOpen = true;

  TestConnection(this.id) {
    if (!testConnections.containsKey(id)) {
      testConnections[id] = [];
    }
    testConnections[id].add(this);
    if (!droppedPacketsNextConnection.isEmpty) {
      this.dropPackets = droppedPacketsNextConnection.removeAt(0);
    }
    if (!droppedPacketsAfterNextConnection.isEmpty) {
      this.dropPacketsAfter = droppedPacketsAfterNextConnection.removeAt(0);
    }
  }

  setOtherEnd(TestConnection otherEnd) {
    if (otherEnd == null) {
      throw new ArgumentError("otherEnd can not be null!");
    }
    this._otherEnd = otherEnd;
  }

  operator [](index) => id;
  
  flushBuffer() {
    dataBuffer.forEach((e) { sendAndReceivByOtherPeer(e); });
    dataBuffer.clear();
  }
  
  sendAndReceivByOtherPeer(var jsonObject) {
    if (_otherEnd == null) {
      throw new StateError('_otherEnd is null: ${this.id}');
    }
    bool drop = dropPackets > 0 || dropPacketsAfter <=0;
    dropPackets--;
    dropPacketsAfter--;
    if (logConnectionData) {
      print("Data ${drop ? "DROPPED" : ""} ${_otherEnd.id} -> ${id}: ${jsonObject[0]}");
    }
    recentDataSent = jsonObject[0];
    if (!drop){
      _otherEnd.recentDataRecevied = jsonObject[0];
      if (!_otherEnd.eventHandlers.containsKey("data")) {
        throw new StateError("otherEnd $_otherEnd doesn't have a 'data' has ${_otherEnd.eventHandlers.keys}");
      }
      _otherEnd.eventHandlers["data"](this, jsonObject[0]);
    }
  }

  callMethod(String methodName, var jsonObject) {
    if (methodName == "on" && bindOnHandler(jsonObject[0], jsonObject[1])) {
      return "OK";
    }
    if (methodName == "send") {
      if (buffer) {
        dataBuffer.add(jsonObject);
      } else {
        sendAndReceivByOtherPeer(jsonObject);
      }
      return "OK";
    }
    return "Not supported";
  }
  
  bool bindOnHandler(String methodName, var jsFunction) {
    eventHandlers[methodName] = jsFunction;
    if (methodName == "open" && signalOpen) {
      // Signal an open connection right away.
      // But only if the other side has a data handler registered.
      jsFunction(this);
    }
    return true;
  }
  
  toString() => "TestConnection $id -> ${_otherEnd.id}";
}

class TestConnectionWrapper {

  final String id;
  int sendCount = 0;
  Map lastDataSent = null;
  List<Map> dataSent = [];

  TestConnectionWrapper(this.id);

  void sampleLatency(Duration latency) {
    print("Got latency data of $latency");
  }

  sendPing() {
    print("pinged connection ${id}");
  }

  expectedLatency() => new Duration(milliseconds: 400);

  void sendData(Map data) {
    this.lastDataSent = data;
    this.dataSent.add(data);
    this.sendCount++;
  }
}