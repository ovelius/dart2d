library test_peer;

import 'package:injectable/injectable.dart';

import 'test_connection.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/net/net.dart';
import 'test_env.dart';
import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'test_injector.dart';

String serverChannelPeerId = "";
// Existing world peers.
Map<String, TestServerChannel> testPeers = {};

@Injectable(as: ServerChannel)
class TestServerChannel extends ServerChannel {
  late String id;
  List<TestConnection> connections = [];
  bool connectedToServer = false;

  late StreamController<Map> _streamController;

  TestServerChannel() {
    if (testPeers.containsKey(serverChannelPeerId)) {
      throw "TestPeer $serverChannelPeerId already exists!";
    }
    this.id = serverChannelPeerId;
    if (testPeers.containsKey(id)) {
      throw "A TestPeer with id $id already exists in ${testPeers.keys}";
    }
    testPeers[id] = this;
    _streamController = new StreamController<Map>(sync: true);
  }

  sendData(Map<dynamic, dynamic> data) {
    assert(data.containsKey('dst'), "Missing destination in server message?");
    assert(data.containsKey('src'), "Missing destination in server message?");
    TestServerChannel otherChannel = testPeers[data['dst']]!;
    otherChannel._streamController.add(data);
  }

  Stream<dynamic> dataStream() {
    return _streamController.stream;
  }

  void disconnect() {
    this.connectedToServer = false;
  }
  Stream<dynamic> reconnect(String id) {
    _streamController = new StreamController<Map>(sync: true);
    assert(this.id == id);
    this.connectedToServer = true;
    return _streamController.stream;
  }

  fakeIncomingConnection(String fromId) {
    _streamController.add({
      'type': 'OFFER',
      'payload': {
        'sdp': 'fakesdp',
      },
      'src': fromId,
      'dst': id});
  }

  void sendOpenMessage([List otherIds = const []]) {
    Map data = {
      'type':'ACTIVE_IDS',
      'id': id,
      'ids': new List.from(otherIds),
    };
    _streamController.add(data);
  }

  String toString() => "TestServerChannel(${id}) ${connections}";
}
