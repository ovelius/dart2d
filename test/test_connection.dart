library test_connection;

recentSentDataTo(id) {
  return testConnections[id][0].recentDataSent;
}

recentReceviedDataFrom(id, [int index = 0]) {
  return testConnections[id][index].recentDataRecevied;
}

Map<dynamic, List<TestConnection>> testConnections = {};

List<int> droppedPacketsNextConnection = [];

bool logConnectionData = true;

class TestConnection {
  int dropPackets = 0;
  TestConnection otherEnd;
  var id;
  var eventHandlers = {};
  
  var recentDataSent = null;
  var recentDataRecevied = null;
  
  bool buffer = false;
  List dataBuffer = [];

  TestConnection(this.id) {
    if (!testConnections.containsKey(id)) {
      testConnections[id] = [];
    }
    testConnections[id].add(this);
    if (!droppedPacketsNextConnection.isEmpty) {
      this.dropPackets = droppedPacketsNextConnection.removeAt(0);
    }
  }

  operator [](index) => id;
  
  flushBuffer() {
    dataBuffer.forEach((e) { sendAndReceivByOtherPeer(e); });
    dataBuffer.clear();
  }
  
  sendAndReceivByOtherPeer(var jsonObject) {
    if (otherEnd == null) {
      throw new StateError('otherEnd is null');
    }
    bool drop = dropPackets > 0;
    if (logConnectionData) {
      print("Data ${drop ? "DROPPED" : ""} ${otherEnd.id} -> ${id}: ${jsonObject[0]}");
    }
    recentDataSent = jsonObject[0];
    if (dropPackets > 0) {
      dropPackets--;
    } else {
      otherEnd.recentDataRecevied = jsonObject[0];
      if (!otherEnd.eventHandlers.containsKey("data")) {
        throw new StateError("otherEnd $otherEnd doesn't have a 'data' has ${otherEnd.eventHandlers.keys}");
      }
      print("trying to send ${jsonObject}");
      otherEnd.eventHandlers["data"](this, jsonObject[0]);
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
    print("$this ${methodName} ${jsonObject}");
    return "Not supported";
  }
  
  bool bindOnHandler(String methodName, var jsFunction) {
    eventHandlers[methodName] = jsFunction;
    if (methodName == "open") {
      // Signal an open connection right away.
      // But only if the other side has a data handler registered.
      jsFunction(this);
    }
    return true;
  }
  
  toString() => "TestConnection $id -> ${otherEnd.id}";
}

class TestConnectionWrapper {

  Map lastDataSent = null;
  
  void sendData(Map data) {
    this.lastDataSent = data;
  }
}