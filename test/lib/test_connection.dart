library test_connection;

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/net.dart';
import 'test_peer.dart';
import 'dart:convert';

recentSentDataTo(id) {
  return testConnections[id][0].recentDataSent;
}

recentReceviedDataFrom(id, [int index = 0]) {
  return testConnections[id][index].recentDataRecevied;
}

// Map of connections from id.
Map<String, List<TestConnection>> testConnections = {};

bool logConnectionData = true;

class TestConnection {
  int dropPacketsAfter = 900000000;
  TestConnection _otherEnd;
  String id;
  ConnectionWrapper _internalWrapper;
  bool closed = false;

  String recentDataSent = null;
  int dataReceivedCount = 0;
  var recentDataRecevied = null;

  dynamic decodedRecentDataRecevied() {
    if (recentDataRecevied == null) {
      throw new StateError("No recent data received on ${toString()}");
    }
    return JSON.decode(recentDataRecevied);
  }

  bool buffer = false;
  List<String> dataBuffer = [];

  bool signalOpen = true;

  TestConnection(this.id, this._internalWrapper) {
    if (!testConnections.containsKey(id)) {
      testConnections[id] = [];
    }
    testConnections[id].add(this);
  }

  setOtherEnd(TestConnection otherEnd) {
    if (otherEnd == null) {
      throw new ArgumentError("otherEnd can not be null!");
    }
    this._otherEnd = otherEnd;
  }

  TestConnection getOtherEnd() => _otherEnd;

  operator [](index) => id;
  
  flushBuffer() {
    dataBuffer.forEach((e) { sendAndReceivByOtherPeer(e); });
    dataBuffer.clear();
  }

  sendAndReceivByOtherPeerNativeObject(Map object) {
    sendString(JSON.encode(object));
  }

  nativeBufferedDataAt(int pos) {
    return JSON.decode(dataBuffer[pos]);
  }

  void signalClose() {
    _internalWrapper.close("Test");
    _otherEnd._internalWrapper.close("TestOtherEnd");
  }

  void close() {
    closed = true;
  }

  sendAndReceivByOtherPeer(String jsonString) {
    if (closed) {
      throw new StateError("TestConnection is closed, can't send!");
    }
    if (_otherEnd == null) {
      throw new StateError('_otherEnd is null: ${this.id}');
    }
    bool drop = dropPacketsAfter <=0;
    dropPacketsAfter--;
    if (logConnectionData) {
      print("Data ${drop ? "DROPPED" : ""} ${_otherEnd.id} -> ${id}: ${jsonString}");
    }
    if (!drop) {
      recentDataSent = jsonString;
      _otherEnd.recentDataRecevied = jsonString;
      _otherEnd.dataReceivedCount++;
      if (_otherEnd._internalWrapper == null) {
        throw new StateError(
            "Can't send data on ${this}, receipient missing receive endpoint!");
      }
      _otherEnd._internalWrapper.receiveData(jsonString);
    }
  }

  sendString(String string) {
    if (buffer) {
      dataBuffer.add(string);
    } else {
      sendAndReceivByOtherPeer(string);
    }
  }

  toString() => "TestConnection $id -> ${_otherEnd == null ? 'NULL' : _otherEnd.id}";
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

class TestConnectionFactory extends ConnectionFactory {
  Map<String, Map<String, TestConnection>> connections = {};
  Set<String> failConnectionsTo = new Set();

  void signalErrorAllConnections(String to) {
    connections[to].values.forEach((c) {
      c._internalWrapper.error("Test error");
    });
  }

  void signalCloseOnAllConnections(String to) {
    connections[to].values.forEach((c) {
      c._internalWrapper.close("Test");
    });
  }
  /**
   * Us trying to connect to someone.
   */
  connectTo(ConnectionWrapper wrapper, String ourPeerId, String otherPeerId) {
    print("Create outbound connection from ${ourPeerId} to ${otherPeerId}");
    TestConnection c = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId][otherPeerId] = c;
    wrapper.setRtcConnection(c);
    wrapper.readyDataChannel(c);
    TestServerChannel ourChannel = testPeers[ourPeerId];
    if (ourChannel == null) {
      throw new ArgumentError("No peer with id ${ourPeerId}");
    }
    ourChannel.connections.add(c);
    if (failConnectionsTo.contains(otherPeerId)) {
      print("DROPPING connection to ${otherPeerId}, configured to fail!");
      return;
    }
    // Signal open connection right away.
    TestServerChannel otherChannel = testPeers[otherPeerId];
    if (otherChannel == null) {
      throw new ArgumentError("No peer with id ${otherPeerId}");
    }
    otherChannel.fakeIncomingConnection(ourPeerId);
    for (TestConnection otherEndConnection in otherChannel.connections) {
      if (otherEndConnection.id == ourPeerId) {
        c.setOtherEnd(otherEndConnection);
        otherEndConnection.setOtherEnd(c);
      }
    }
    wrapper.open();
    if (c._otherEnd == null) {
      throw new StateError(
          "Expected otherEnd to be set, missing among ${otherChannel.connections}");
    }
  }
  /**
   * Callback for someone trying to connection to us.
   */
  createInboundConnection(ConnectionWrapper wrapper, dynamic sdp,
      String otherPeerId, String ourPeerId) {
    print("Create inbound connection from ${otherPeerId} to ${ourPeerId}");
    TestServerChannel ourChannel = testPeers[ourPeerId];
    if (ourChannel == null) {
      throw new ArgumentError("No peer with id ${ourPeerId}");
    }
    TestConnection c = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId][otherPeerId] = c;
    wrapper.setRtcConnection(c);
    wrapper.readyDataChannel(c);
    wrapper.open();
    ourChannel.connections.add(c);
  }
  /**
   * Create and answer for our inbound connection.
   */
  handleCreateAnswer(ConnectionWrapper connection, String src, String dst) {

  }
  /**
   * Handle receiving that answer.
   */
  handleGotAnswer(dynamic connection, dynamic sdp) {

  }

  /**
   * Handle receiving ICE candidates.
   */
  handleIceCandidateReceived(dynamic connection, dynamic iceCandidate) {

  }
}