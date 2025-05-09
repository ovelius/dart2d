library test_peer;

import 'dart:convert';

import 'package:dart2d/net/state_updates.pb.dart';
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
  Completer<List<String>> _existingPeers = Completer();

  late StreamController<Map<String, String>> _streamController;

  TestServerChannel() : this.withExplicitId(serverChannelPeerId);

  TestServerChannel.withExplicitId(this.id) {
    if (testPeers.containsKey(this.id)) {
      throw "TestPeer $this.id already exists!";
    }
    if (testPeers.containsKey(id)) {
      throw "A TestPeer with id $id already exists in ${testPeers.keys}";
    }
    testPeers[id] = this;
    _streamController = new StreamController(sync: true);
  }

  sendData(String dst, String type, String payload) {
    TestServerChannel otherChannel = testPeers[dst]!;
    Map<String, String> data = {};
    otherChannel._streamController.add(data);
  }

  Future<List<String>> openAndReadExistingPeers() {
    return _existingPeers.future;
  }

  Stream<Map<String, String>> dataStream() {
    return _streamController.stream;
  }

  void disconnect() {
    this.connectedToServer = false;
  }
  Stream<dynamic> reconnect(String id) {
    _streamController = new StreamController(sync: true);
    assert(this.id == id);
    this.connectedToServer = true;
    return _streamController.stream;
  }

  fakeIncomingConnection(String fromId) {
    WebRtcDanceProto proto = WebRtcDanceProto()
       ..sdp = "fake sdp"
       ..candidates.add("fake candidate");
    
    _streamController.add({
      'type': 'OFFER',
      'payload': base64Encode(proto.writeToBuffer()),
      'src': fromId,
      'dst': id});
  }

  Future sendOpenMessage([List<String> otherIds = const []]) async {
    Completer<void> done = Completer();
    List<String> ids = [id];
    ids.addAll(otherIds);
    _existingPeers.complete(ids);
    _existingPeers.future.then((_){
      done.complete(null);
    });
    done.future;
  }

  String toString() => "TestServerChannel(${id}) ${connections}";
}
