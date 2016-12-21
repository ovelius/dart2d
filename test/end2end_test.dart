library dart2d;

import 'package:test/test.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'test_env.dart';
import 'fake_canvas.dart';
import 'matchers.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

void main() {
  setUp(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
    testConnections.clear();
    testPeers.clear();
    logConnectionData = true;
    remapKeyNamesForTest();
  });

  group('Smoke tests', () {
    test('TestBasicSmokeConnection', () {
      Injector injectorA = createWorldInjector("a", false);
      Injector injectorB = createWorldInjector("b", false);

      WormWorld worldA = injectorA.get(WormWorld);
      TestPeer peerA = injectorA.get(TestPeer);
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = injectorA.get(FakeImageFactory);

      WormWorld worldB = injectorB.get(WormWorld);
      Loader loaderB = worldB.loader;
      TestPeer peerB = injectorB.get(TestPeer);

      // WorldA receives no peers.
      expect(loaderA.describeStage(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      peerA.receiveActivePeer([]);
      worldA.frameDraw();
      // Completes loading from Server.
      expect(loaderA.describeStage(), equals(LoaderState.LOADING_SERVER));
      worldA.frameDraw();
      fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      expect(loaderA.describeStage(), equals(LoaderState.LOADING_COMPLETED));

      // WorldB receives worldA as peer.
      expect(loaderB.describeStage(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      worldB.frameDraw();
      peerB.receiveActivePeer(['a']);
      expect(loaderB.describeStage(), equals(LoaderState.LOADING_OTHER_CLIENT));
      worldB.frameDraw();
      expect(loaderB.describeStage(), equals(LoaderState.LOADING_COMPLETED));

      // Ideally this does not mean connection to a game..

      // TODO: Add tests here for
      // 1) Client dies mid loading.
      // 2) Client unable to connect.
      // 3) Grabbing world state.
    });
  });
}
