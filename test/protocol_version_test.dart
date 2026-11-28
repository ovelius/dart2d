import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/network.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/gamestate.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:test/test.dart';

import 'lib/test_env.dart';
import 'lib/test_injector.dart';

void main() {
  setUpAll(() {
    configureDependencies();
  });

  group('Protocol version check', () {
    test('GameState initializes protocolVersion to GameState.PROTOCOL_VERSION', () async {
      final WormWorld world = await createTestWorld('a');
      expect(world.network().getGameState().gameStateProto.protocolVersion,
          equals(GameState.PROTOCOL_VERSION));
    });

    test('Accepts GameState with equal or lower protocolVersion', () async {
      final WormWorld worldA = await createTestWorld('p2');
      final WormWorld worldB = await createTestWorld('p3');
      final Network netA = worldA.network();
      int? mismatchVersion;
      netA.onProtocolVersionMismatch = (int v) {
        mismatchVersion = v;
      };

      netA.peer.connectTo('p3');
      final ConnectionWrapper connB = netA.peer.connections['p3']!;

      // Equal version
      worldA.packetListenerBindings.handlerFor(StateUpdate_Update.gameState)[0](
        connB,
        StateUpdate()
          ..gameState = (GameStateProto()
            ..actingCommanderId = 'p3'
            ..protocolVersion = GameState.PROTOCOL_VERSION),
      );
      expect(mismatchVersion, isNull);

      // Lower version
      worldA.packetListenerBindings.handlerFor(StateUpdate_Update.gameState)[0](
        connB,
        StateUpdate()
          ..gameState = (GameStateProto()
            ..actingCommanderId = 'p3'
            ..protocolVersion = GameState.PROTOCOL_VERSION - 1),
      );
      expect(mismatchVersion, isNull);
      expect(worldB.network().getGameState().gameStateProto.protocolVersion,
          equals(GameState.PROTOCOL_VERSION));
    });

    test('Triggers reload callback when remote protocolVersion is higher', () async {
      final WormWorld worldA = await createTestWorld('p4');
      await createTestWorld('p5');
      final Network netA = worldA.network();
      int? mismatchVersion;
      netA.onProtocolVersionMismatch = (int v) {
        mismatchVersion = v;
      };

      netA.peer.connectTo('p5');
      final ConnectionWrapper connB = netA.peer.connections['p5']!;

      worldA.packetListenerBindings.handlerFor(StateUpdate_Update.gameState)[0](
        connB,
        StateUpdate()
          ..gameState = (GameStateProto()
            ..actingCommanderId = 'p5'
            ..protocolVersion = GameState.PROTOCOL_VERSION + 1),
      );
      expect(mismatchVersion, equals(GameState.PROTOCOL_VERSION + 1));
    });
  });
}
