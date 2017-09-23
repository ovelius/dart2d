library dart2d;

import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/net/net.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/bindings/annotations.dart';

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
      TestServerChannel peerA = injectorA.get(TestServerChannel);
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = injectorA .get(FakeImageFactory);

      WormWorld worldB = injectorB.get(WormWorld);
      Loader loaderB = worldB.loader;
      TestServerChannel peerB = injectorB.get(TestServerChannel);

      // WorldA receives no peers.
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.WEB_RTC_INIT));
      peerA.sendOpenMessage();
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
      expect(loaderB.currentState(), equals(LoaderState.WEB_RTC_INIT));
      worldB.frameDraw();
      peerB.sendOpenMessage(['a', 'b']);
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
      TestServerChannel peerC = injectorC.get(TestServerChannel);
      // Connections fail big time.
      TestConnectionFactory connectionFactoryC = injectorC.get(TestConnectionFactory);
      connectionFactoryC.failConnectionsTo
        ..add("a")
        ..add("b");
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.WEB_RTC_INIT));
      peerC.sendOpenMessage(['a', 'b', 'c']);
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.CONNECTING_TO_PEER));
      connectionFactoryC.signalErrorAllConnections('c');
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
      TestServerChannel peerA = injectorA.get(TestServerChannel);
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = injectorA.get(FakeImageFactory);

      WormWorld worldB = injectorB.get(WormWorld);
      Loader loaderB = worldB.loader;
      TestServerChannel peerB = injectorB.get(TestServerChannel);

      // WorldA receives no peers.
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.WEB_RTC_INIT));
      peerA.sendOpenMessage([]);
      worldA.frameDraw();
      // Completes loading from Server.
      expect(loaderA.currentState(), equals(LoaderState.LOADING_SERVER));
      worldA.frameDraw();
      fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WEB_RTC_INIT));
      worldB.frameDraw();
      // Connection works for 5 packets;
      droppedPacketsAfterNextConnection.add(5);
      peerB.sendOpenMessage(['a', 'b']);
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));

      // All connections just died.
      TestConnectionFactory connectionFactoryB = injectorB.get(TestConnectionFactory);
      connectionFactoryB.signalCloseOnAllConnections('b');
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_SERVER));

      // Complete me, load from server.
      FakeImageFactory fakeImageFactoryC = injectorB.get(FakeImageFactory);
      fakeImageFactoryC.completeAllImages();

      // Completed loading form server.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADED_AS_SERVER));
    });

    test('Test full game flow', () {
      expectWarningContaining("unable to add commander data");
      logConnectionData = false;
      Injector injectorA = createWorldInjector("a", false);
      Map uriParameters = injectorA.get(Map, UriParameters);
      uriParameters['maxFrags'] = ["1"];
      setPlayerNameAndSignalOpen(injectorA);
      Injector injectorB = createWorldInjector("b", false);
      uriParameters = injectorB.get(Map, UriParameters);
      uriParameters['maxFrags'] = ["1"];
      setPlayerName(injectorB);

      WormWorld worldA = injectorA.get(WormWorld);
      TestServerChannel peerA = injectorA.get(TestServerChannel);
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = injectorA .get(FakeImageFactory);

      WormWorld worldB = injectorB.get(WormWorld);
      Loader loaderB = worldB.loader;
      TestServerChannel peerB = injectorB.get(TestServerChannel);

      // WorldA receives no peers.
      worldA.frameDraw();
      peerA.sendOpenMessage([]);
      worldA.frameDraw();
      fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WEB_RTC_INIT));
      worldB.frameDraw();
      peerB.sendOpenMessage(['a', 'b']);
      expect(worldB.network().peer.connections.length, equals(1));

      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      expect(worldB.network().isCommander(), false);
      expect(worldA.network().isCommander(), true);

      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));

      LocalPlayerSprite spriteA = worldA.spriteIndex[playerId(0)];
      LocalPlayerSprite spriteB = worldA.spriteIndex[playerId(1)];
      spriteA.takeDamage(spriteA.health, spriteB);

      for (int i = 0; i < 50; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Back at selecting player.
      expect(loaderA.currentState(), equals(LoaderState.PLAYER_SELECT));
      expect(loaderB.currentState(), equals(LoaderState.PLAYER_SELECT));
      expect(worldA.network().getGameState().actingCommanderId, isNull);
      expect(worldB.network().getGameState().actingCommanderId, isNull);
      expect(worldA.network().getGameState().playerInfoList(), isEmpty);
      expect(worldB.network().getGameState().playerInfoList(), isEmpty);

      KeyState stateA = injectorA.get(KeyState, LocalKeyState);
      stateA.onKeyDown(new _fakeKeyCode(KeyCodeDart.SPACE));
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderA.currentState(), equals(LoaderState.WORLD_SELECT));

      KeyState stateB = injectorB.get(KeyState, LocalKeyState);
      stateB.onKeyDown(new _fakeKeyCode(KeyCodeDart.SPACE));
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderB.currentState(), equals(LoaderState.WORLD_SELECT));

      stateA.onKeyUp(new _fakeKeyCode(KeyCodeDart.SPACE));
      stateB.onKeyUp(new _fakeKeyCode(KeyCodeDart.SPACE));

      stateA.onKeyDown(new _fakeKeyCode(KeyCodeDart.SPACE));
      worldA.frameDraw(KEY_FRAME_DEFAULT);

      for (int i = 0; i < 50; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      expect(loaderB.currentState(), equals(LoaderState.WORLD_SELECT));
      expect(loaderA.currentState(), equals(LoaderState.WORLD_LOADING));
      fakeImageFactoryA.completeAllImages();

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));

      expectWarningContaining("None positive latency");

      for (int i = 0; i < 50; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Game is underway again!
      expect(worldB.network().isCommander(), false);
      expect(worldA.network().isCommander(), true);

      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));
    });
  });
}

class _fakeKeyCode {
  int keyCode;
  _fakeKeyCode(this.keyCode);
}