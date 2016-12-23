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
    clearEnvironment();
    logConnectionData = true;
    remapKeyNamesForTest();
  });

  group('End2End', () {
    test('Resource loading tests p2p', () {
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
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      peerA.receiveActivePeer([]);
      worldA.frameDraw();
      // Completes loading from Server.
      expect(loaderA.currentState(), equals(LoaderState.LOADING_SERVER));
      worldA.frameDraw();
      fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADING_COMPLETED));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      worldB.frameDraw();
      peerB.receiveActivePeer(['a']);
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_COMPLETED));

      // Ideally this does not mean connection to a game.
      // But Game comes underway after a couple of frames.
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));
    });

    test('Resource loading failing p2p', () {
      Injector injectorC = createWorldInjector("c", false);
      // Now comes a goofy client, unable to connect to anyone!
      WormWorld worldC = injectorC.get(WormWorld);
      Loader loaderC = worldC.loader;
      TestPeer peerC = injectorC.get(TestPeer);
      // Connections fail big time.
      peerC.failConnectionsTo
        ..add("a")
        ..add("b");
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      peerC.receiveActivePeer(['a', 'b']);
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.CONNECTING_TO_PEER));
      peerC.signalErrorAllConnections();
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.LOADING_SERVER));
      FakeImageFactory fakeImageFactoryC = injectorC.get(FakeImageFactory);
      fakeImageFactoryC.completeAllImages();
      worldC.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderC.currentState(), equals(LoaderState.LOADING_COMPLETED));

      expect(worldC, hasSpriteWithNetworkId(playerId(0)));
      expect(worldC.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
    });
    test('Resource loading partial p2p', () {
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
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      peerA.receiveActivePeer([]);
      worldA.frameDraw();
      // Completes loading from Server.
      expect(loaderA.currentState(), equals(LoaderState.LOADING_SERVER));
      worldA.frameDraw();
      fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADING_COMPLETED));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      worldB.frameDraw();
      // Connection works for 5 packets;
      droppedPacketsAfterNextConnection.add(5);
      peerB.receiveActivePeer(['a']);
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));

      peerB.signalCloseOnAllConnections();
      for (int i = 0; i < 2; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      // Complete me, load from server.
    });
    // TODO: Add tests here for
    // 1) Client dies mid loading.
    // 2) Grabbing world state.
    // 3) Disconnect/reconnect the RTC peer when max players is reached.
  });
}
