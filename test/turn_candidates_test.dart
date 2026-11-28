import 'package:clock/clock.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/helpers.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/peer.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import 'lib/test_env.dart';
import 'lib/test_factories.dart';
import 'lib/test_injector.dart';

void main() {
  setUpAll(() {
    configureDependencies();
  });

  group('TURN ICE restart', () {
    test('Waits 200ms after first TURN candidate before firing CANDIDATES', () async {
      final Negotiator negotiator = Negotiator('a', 'b');
      WebRtcDanceProto? sentProto;
      negotiator.onIceRestartCompleted((WebRtcDanceProto proto) {
        sentProto = proto;
      });

      negotiator.restartingIce();
      expect(negotiator.turnCandidateGathered, isFalse);

      // Non-relay candidate does not trigger TURN state.
      negotiator.onIceCandidate('candidate:1 1 udp 2122260223 192.168.1.2 5000 typ host');
      expect(negotiator.turnCandidateGathered, isFalse);
      expect(sentProto, isNull);

      // First TURN relay candidate sets flag, but waits 200ms.
      negotiator.onIceCandidate('candidate:2 1 udp 16777215 1.2.3.4 3478 typ relay');
      expect(negotiator.turnCandidateGathered, isTrue);
      expect(sentProto, isNull);

      await Future.delayed(const Duration(milliseconds: 250));
      expect(sentProto, isNotNull);
      expect(sentProto!.candidates.length, equals(2));
    });

    test('OpenTimeout extends by 4s when turnCandidateGathered is true', () {
      DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
      final Clock fakeClock = Clock(() => now);
      final ConnectionStats stats = ConnectionStats(fakeClock);

      // At +9s: timed out without TURN candidate, not timed out with TURN candidate.
      now = now.add(const Duration(seconds: 9));
      expect(stats.OpenTimeout(turnCandidateGathered: false), isTrue);
      expect(stats.OpenTimeout(turnCandidateGathered: true), isFalse);

      // At +13s: timed out even with 4s TURN extension (8s + 4s = 12s).
      now = now.add(const Duration(seconds: 4));
      expect(stats.OpenTimeout(turnCandidateGathered: true), isTrue);
    });

    test('PeerWrapper handles incoming CANDIDATES and forwards to connection', () async {
      final WormWorld worldA = await createTestWorld('t1');
      await createTestWorld('t2');
      final PeerWrapper peerA = worldA.network().peer;

      peerA.connectTo('t2');
      final ConnectionWrapper conn = peerA.connections['t2']!;
      expect(conn, isNotNull);
      conn.setRtcConnection(RTCPeerConnection());

      final WebRtcNegotiationProto candidatesMsg = WebRtcNegotiationProto()
        ..type = WebRtcNegotiationProto_Type.CANDIDATES
        ..src = 't2'
        ..dst = 't1'
        ..danceProto = (WebRtcDanceProto()
          ..candidates.add('candidate:2 1 udp 16777215 1.2.3.4 3478 typ relay'));

      // Should handle CANDIDATES without throwing and call addIceCandidate on rtcConnection.
      worldA.packetListenerBindings.handlerFor(StateUpdate_Update.negotiation)[0](
        conn,
        StateUpdate()..negotiation = candidatesMsg,
      );
    });
  });
}
