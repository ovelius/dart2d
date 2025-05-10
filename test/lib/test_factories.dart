
import 'dart:js_interop';

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:injectable/injectable.dart';
import 'package:web/web.dart';
import 'test_connection.dart';
import 'test_peer.dart';

@Singleton(as: ConnectionFactory)
class TestConnectionFactory extends ConnectionFactory {
  bool expectPeerToExist = true;
  Map<String, Map<String, TestConnection>> connections = {};
  Map<String, List<String>> failConnectionsTo = {};

  TestConnectionFactory failConnection(String from, String to) {
    if (!failConnectionsTo.containsKey(from)) {
      failConnectionsTo[from] = [];
    }
    failConnectionsTo[from]?.add(to);
    return this;
  }

  resetFailingConnection() {
    failConnectionsTo.clear();
  }

  void signalErrorAllConnections(String to) {
    print("Object connections ${connections}");
    connections[to]?.values.forEach((c) {
      print("Signaling error on ${c}");
      c.internalWrapper?.error("Test error");
    });
  }

  void signalCloseOnAllConnections(String to) {
    connections[to]?.values.forEach((c) {
      c.internalWrapper?.close("Test");
    });
  }
  /**
   * Us trying to connect to someone.
   */
  connectTo(ConnectionWrapper wrapper, Negotiator negotiator) {
    String ourPeerId = negotiator.ourId;
    String otherPeerId = negotiator.otherId;
    print("Create outbound connection from ${ourPeerId} to ${otherPeerId}");
    TestConnection c = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId]![otherPeerId] = c;
    var jsTestConnection = createJSInteropWrapper<TestConnection>(c) as RTCPeerConnection;
    var jsTestDataChannel = createJSInteropWrapper<TestConnection>(c) as RTCDataChannel;
    wrapper.setRtcConnection(jsTestConnection);
    wrapper.readyDataChannel(jsTestDataChannel);
    TestServerChannel ourChannel = testPeers[ourPeerId]!;
    ourChannel.connections.add(c);
    if (failConnectionsTo.containsKey(ourPeerId) && failConnectionsTo[ourPeerId]!.contains(otherPeerId)) {
      print("DROPPING connection $ourPeerId -> $otherPeerId, configured to fail!");
      return;
    }
    // Signal open connection right away.
    if (expectPeerToExist && !testPeers.containsKey(otherPeerId)) {
      throw "No such test peer $otherPeerId among ${testPeers.keys}";
    }
    if (expectPeerToExist) {
      TestServerChannel otherChannel = testPeers[otherPeerId]!;
        //otherChannel.fakeIncomingConnection(ourPeerId);
        /*
        for (TestConnection otherEndConnection in otherChannel.connections) {
          if (otherEndConnection.id == ourPeerId) {
            c.setOtherEnd(otherEndConnection);
            otherEndConnection.setOtherEnd(c);
          }
        } */
      negotiator.sdpReceived("sdp_${ourPeerId}_${otherPeerId}", "offer");
      negotiator.onIceCandidate("candidate1");
      negotiator.onIceCandidate(null);
    }
   // wrapper.open();
  }
  /**
   * Callback for someone trying to connection to us.
   */
  createInboundConnection(ConnectionWrapper wrapper, Negotiator negotiator, WebRtcDanceProto proto) {
    String ourPeerId = negotiator.ourId;
    String otherPeerId = negotiator.otherId;
    print("Create inbound connection from ${otherPeerId} to ${ourPeerId}");
    TestServerChannel ourChannel = testPeers[ourPeerId]!;
    TestConnection c = new TestConnection(otherPeerId, wrapper);
    if (connections[ourPeerId] == null) {
      connections[ourPeerId] = {};
    }
    connections[ourPeerId]![otherPeerId] = c;
    var jsTestConnection = createJSInteropWrapper<TestConnection>(c) as RTCPeerConnection;
    var jsTestDataChannel = createJSInteropWrapper<TestConnection>(c) as RTCDataChannel;
    wrapper.setRtcConnection(jsTestConnection);
    wrapper.readyDataChannel(jsTestDataChannel);
    ourChannel.connections.add(c);

    negotiator.sdpReceived("sdp_${ourPeerId}_${otherPeerId}", "answer");
    negotiator.onIceCandidate("candidate1");
    negotiator.onIceCandidate(null);
  }
  /**
   * Handle receiving that answer.
   */
  handleGotAnswer(dynamic connection, WebRtcDanceProto sdp) {
    String otherPeerId = sdp.sdp.split("_")[1];
    String ourPeerId = sdp.sdp.split("_")[2];

    print("Handle got answer from ${otherPeerId} to ${ourPeerId}");

    if (!connections.containsKey(ourPeerId)) {
      throw "No connections for ${ourPeerId} among ${connections.keys}";
    }
    if (!connections[ourPeerId]!.containsKey(otherPeerId)) {
      throw "No connection to ${otherPeerId} among ${connections[ourPeerId]!}";
    }
    TestConnection connection = connections[ourPeerId]![otherPeerId]!;
    TestServerChannel otherChannel = testPeers[otherPeerId]!;
    bool found = false;
    for (TestConnection otherEndConnection in otherChannel.connections) {
      if (otherEndConnection.id == ourPeerId) {
        connection.setOtherEnd(otherEndConnection);
        otherEndConnection.setOtherEnd(connection);
        found = true;
        break;
      }
    }
    if (!found) {
      throw "Peer $otherPeerId doesn't have a connection for us among ${otherChannel.connections}";
    }
    // Handshake completed so mark both connections open.
    connection.internalWrapper!.open();
    connection.getOtherEnd()!.internalWrapper?.open();
  }

  @override
  Future<String> getStats(connection) {
    return Future.value("{\"currentRoundTripTime\":0.1}");
  }
}

// This is all silence.
const TEST_SOUND = "data:audio/ogg;base64,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";


@Singleton(as: SoundFactory)
class FakeSoundFactory extends SoundFactory {
  Map<HTMLAudioElement, int> _SOUNDS_PLAYED = {};
  List<HTMLAudioElement> _audios = [];
  Map<Sound, List<HTMLAudioElement>> _createdAudios = {};

  @override
  HTMLAudioElement createWithSrc(String src, Sound sound) {
    HTMLAudioElement el = HTMLAudioElement();
    el.src = TEST_SOUND;
    _listenForTestPlay(el, sound);
    return el;
  }

  @override
  HTMLAudioElement clone(HTMLAudioElement other, Sound sound) {
    HTMLAudioElement newElement = other.cloneNode() as HTMLAudioElement;
    _listenForTestPlay(newElement, sound);
    return newElement;
  }

  _listenForTestPlay(HTMLAudioElement el, Sound sound) {
    el.muted = true;
    el.onPlay.listen((_){
      if (!_SOUNDS_PLAYED.containsKey(el)) {
        _SOUNDS_PLAYED[el] = 0;
      }
      _SOUNDS_PLAYED[el] = _SOUNDS_PLAYED[el]! + 1;
    });
    _audios.add(el);
    if (!_createdAudios.containsKey(sound)) {
      _createdAudios[sound] = [];
    }
    _createdAudios[sound]!.add(el);
  }

  void resetPlayedSounds() {
    _SOUNDS_PLAYED.clear();
  }

  List<HTMLAudioElement>? getAudioElements(Sound sound) {
    return _createdAudios[sound];
  }

  int getTotalPlayOuts(Sound s) {
    int playOuts = 0;
    List<HTMLAudioElement>? elements = _createdAudios[s];
    if (elements == null) {
      throw "No created audio $s";
    }
    for (HTMLAudioElement el in elements) {
      playOuts += _SOUNDS_PLAYED.containsKey(el) ? _SOUNDS_PLAYED[el]! : 0;
    }
    return playOuts;
  }

  int getCreatedAudioElements(Sound s) {
    List<HTMLAudioElement>? elements = _createdAudios[s];
    if (elements == null) {
      return 0;
    }
    return elements.length;
  }

  Future loadAllAudio() async {
    List<Future> loads = [];
    for (HTMLAudioElement el in _audios) {
      loads.add(el.onCanPlay.first);
    }
    return Future.wait(loads);
  }
}
