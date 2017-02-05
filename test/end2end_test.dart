library dart2d;

import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/net/net.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/loader.dart';

void main() {
  setUp(() {
    logOutputForTest();
    expectWarningContaining('No matching sprite');
    expectWarningContaining('Duplicate handshake');
    expectWarningContaining('DO_NOT_CREATE');
    expectWarningContaining('would overwrite existing sprite');
    clearEnvironment();
    logConnectionData = true;
    remapKeyNamesForTest();
  });

  tearDown((){
    assertNoLoggedWarnings();
  });

  group('End2End', () {
    test('Resource loading tests p2p', () {
      expectWarningContaining("unable to add commander data");
      logConnectionData = false;
      Injector injectorA = createWorldInjector("a", false);
      setPlayerName(injectorA);
      Injector injectorB = createWorldInjector("b", false);
      setPlayerName(injectorB);

      WormWorld worldA = injectorA.get(WormWorld);
      TestPeer peerA = injectorA.get(TestPeer);
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = injectorA .get(FakeImageFactory);

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
      worldA.frameDraw();

      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));
      worldA.frameDraw();
      expect(worldA.network().isCommander(), true);

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      worldB.frameDraw();
      peerB.receiveActivePeer(['a', 'b']);
      expect(worldB.network().peer.connections.length, equals(1));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.FINDING_SERVER));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.CONNECTING_TO_GAME));

      // Ideally this does not mean connection to a game.
      // But Game comes underway after a couple of frames.
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderB.currentState(), equals(LoaderState.LOADING_GAMESTATE));

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      expect(loaderB.currentState(), equals(LoaderState.LOADING_ENTERING_GAME));
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderB.currentState(), equals(LoaderState.LOADING_AS_CLIENT_COMPLETED));

      worldA.frameDraw();
      worldB.frameDraw();
      worldA.frameDraw();
      worldB.frameDraw();

      expect(worldB.network().isCommander(), false);
      expect(worldA.network().isCommander(), true);

      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));
    });

    test('Resource loading failing p2p', () {
      Injector injectorC = createWorldInjector("c", false);
      setPlayerName(injectorC);
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
      peerC.receiveActivePeer(['a', 'b', 'c']);
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.CONNECTING_TO_PEER));
      peerC.signalErrorAllConnections();
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.LOADING_SERVER));
      FakeImageFactory fakeImageFactoryC = injectorC.get(FakeImageFactory);
      fakeImageFactoryC.completeAllImages();
      worldC.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderC.currentState(), equals(LoaderState.LOADED_AS_SERVER));
      worldC.frameDraw(KEY_FRAME_DEFAULT);
      worldC.frameDraw(KEY_FRAME_DEFAULT);

      expect(worldC, hasSpriteWithNetworkId(playerId(0)));
      expect(worldC.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
    });
    test('Resource loading partial p2p', () {
      Injector injectorA = createWorldInjector("a", false);
      setPlayerName(injectorA);
      Injector injectorB = createWorldInjector("b", false);
      setPlayerName(injectorB);

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
      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      worldB.frameDraw();
      // Connection works for 5 packets;
      droppedPacketsAfterNextConnection.add(5);
      peerB.receiveActivePeer(['a', 'b']);
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));

      // All connections just died.
      peerB.signalCloseOnAllConnections();
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_SERVER));

      // Complete me, load from server.
      FakeImageFactory fakeImageFactoryC = injectorB.get(FakeImageFactory);
      fakeImageFactoryC.completeAllImages();

      // Completed loading form server.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADED_AS_SERVER));
    });
  });
}
