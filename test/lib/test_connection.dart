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
  late TestConnection _otherEnd;
  String id;
  ConnectionWrapper? _internalWrapper;
  bool closed = false;

  String? recentDataSent = null;
  int dataReceivedCount = 0;
  var recentDataRecevied = null;

  dynamic decodedRecentDataRecevied() {
    if (recentDataRecevied == null) {
      throw new StateError("No recent data received on ${toString()}");
    }
    return jsonDecode(recentDataRecevied);
  }

  bool buffer = false;
  List<String> dataBuffer = [];

  bool signalOpen = true;

  TestConnection(this.id, this._internalWrapper) {
    if (this._internalWrapper is MockConnectionWrapper) {
      throw ArgumentError("Only allows real ConnectionWrapper! Got: ${this._internalWrapper}!");
    }
    if (!testConnections.containsKey(id)) {
      testConnections[id] = [];
    }
    testConnections[id]!.add(this);
  }

  setOtherEnd(TestConnection otherEnd) {
    this._otherEnd = otherEnd;
  }

  TestConnection getOtherEnd() => _otherEnd;

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
    if (_internalWrapper == null) {
      throw "No internal wrapper to signal close to!";
    }
    _internalWrapper?.close("Test");
    _otherEnd._internalWrapper?.close("TestOtherEnd");
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
      print("Data ${drop ? "DROPPED" : ""} ${_otherEnd.id} -> ${id}: ${jsonString}");
    }
    if (_otherEnd._internalWrapper == null) {
      throw "No connection wrapper at other end, can't send data!";
    }
    if (!drop) {
      recentDataSent = jsonString;
      _otherEnd.recentDataRecevied = jsonString;
      _otherEnd.dataReceivedCount++;
      _otherEnd._internalWrapper?.receiveData(jsonString);
    }
  }

  send(String string) {
    if (buffer) {
      dataBuffer.add(string);
    } else {
      sendAndReceivByOtherPeer(string);
    }
  }

  toString() => "TestConnection $id -> ${_otherEnd == null ? 'NULL' : _otherEnd.id}";
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


@Singleton(as: ConnectionFactory)
class TestConnectionFactory extends ConnectionFactory {
  Map<String, Map<String, TestConnection>> connections = {};
  Map<String, List<String>> failConnectionsTo = {};

  TestConnectionFactory failConnection(String from, String to) {
    if (!failConnectionsTo.containsKey(from)) {
      failConnectionsTo[from] = [];
    }
    failConnectionsTo[from]?.add(to);
    return this;
  }

  void signalErrorAllConnections(String to) {
    connections[to]?.values.forEach((c) {
      c._internalWrapper?.error("Test error");
    });
  }

  void signalCloseOnAllConnections(String to) {
    connections[to]?.values.forEach((c) {
      c._internalWrapper?.close("Test");
    });
  }
  /**
   * Us trying to connect to someone.
   */
  connectTo(dynamic wrapper, String ourPeerId, String otherPeerId) {
    print("Create outbound connection from ${ourPeerId} to ${otherPeerId}");
    TestConnection c = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId]![otherPeerId] = c;
    wrapper.setRtcConnection(c);
    wrapper.readyDataChannel(c);
    TestServerChannel ourChannel = testPeers[ourPeerId]!;
    ourChannel.connections.add(c);
    if (failConnectionsTo.containsKey(ourPeerId) && failConnectionsTo[ourPeerId]!.contains(otherPeerId)) {
      print("DROPpiNG connection $ourPeerId -> $otherPeerId, configured to fail!");
      return;
    }
    // Signal open connection right away.
    TestServerChannel otherChannel = testPeers[otherPeerId]!;
    otherChannel.fakeIncomingConnection(ourPeerId);
    for (TestConnection otherEndConnection in otherChannel.connections) {
      if (otherEndConnection.id == ourPeerId) {
        c.setOtherEnd(otherEndConnection);
        otherEndConnection.setOtherEnd(c);
      }
    }
    wrapper.open();
  }
  /**
   * Callback for someone trying to connection to us.
   */
  createInboundConnection(dynamic wrapper, dynamic sdp,
      String otherPeerId, String ourPeerId) {
    print("Create inbound connection from ${otherPeerId} to ${ourPeerId}");
    TestServerChannel ourChannel = testPeers[ourPeerId]!;
    TestConnection c = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId]![otherPeerId] = c;
    wrapper.setRtcConnection(c);
    wrapper.readyDataChannel(c);
    wrapper.open();
    ourChannel.connections.add(c);
  }
  /**
   * Create and answer for our inbound connection.
   */
  handleCreateAnswer(dynamic connection, String src, String dst) {

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