
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:injectable/injectable.dart';

import 'fake_canvas.dart';
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

  void signalErrorAllConnections(String to) {
    connections[to]?.values.forEach((c) {
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
    wrapper.setRtcConnection(c);
    wrapper.readyDataChannel(c);
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
      otherChannel.fakeIncomingConnection(ourPeerId);
      for (TestConnection otherEndConnection in otherChannel.connections) {
        if (otherEndConnection.id == ourPeerId) {
          c.setOtherEnd(otherEndConnection);
          otherEndConnection.setOtherEnd(c);
        }
      }
    }
    wrapper.open();
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
