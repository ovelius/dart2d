library test_peer;

import 'test_connection.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/net/net.dart';
import 'test_env.dart';
import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

WormWorld testWorld(String id) {
  return initTestWorld(createWorldInjector(id));
}

WormWorld initTestWorld(Injector injector) {
  WormWorld world = injector.get(WormWorld);
  Loader loader = injector.get(Loader);
  // Ensure world is contructed before running this.
  injector.get(TestServerChannel).sendOpenMessage();
  PlayerWorldSelector selector = injector.get(PlayerWorldSelector);
  Map storage = injector.get(Map, LocalStorage);
  storage['playerName'] = "name${world.network().peer.getId().toString().toUpperCase()}";
  storage['playerSprite'] = "lion88.png";
  loader.markCompleted();
  selector.setMapForTest("lion88.png");
  world.initByteWorld("lion88.png");
  ConnectionFrameHandler.DISABLE_AUTO_ADJUST_FOR_TEST = true;
  return world;
}

Map<String, TestServerChannel> testPeers = {};

class TestServerChannel extends ServerChannel {
  String id;
  List<TestConnection> connections = [];
  bool connectedToServer = false;

  StreamController<Map> _streamController;

  TestServerChannel(this.id) {
    assert(!testPeers.containsKey(id));
    testPeers[id] = this;
    _streamController = new StreamController<Map>(sync: true);
  }

  sendData(Map<dynamic, dynamic> data) {
    assert(data.containsKey('dst'), "Missing destination in servermessage?");
    TestServerChannel otherChannel = testPeers[data['dst']];
    assert(otherChannel != null, "No peer with id ${data['dst']}");
    otherChannel._streamController.add(data);
  }

  Stream<dynamic> dataStream() {
    assert(_streamController.stream != null);
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

