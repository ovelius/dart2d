library dart2d;

import 'package:dart2d/res/imageindex.dart';
import 'package:test/test.dart';
import 'lib/test_factories.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'lib/fake_canvas.dart';
import 'package:dart2d/net/net.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/bindings/annotations.dart';

void main() {
  setUpAll((){
    configureDependencies();
    throwIfLoggingUnexpected = false;
  });
  setUp(() {
    logOutputForTest();
    expectWarningContaining('No matching sprite');
    expectWarningContaining('Duplicate handshake');
    expectWarningContaining('DO_NOT_CREATE');
    expectWarningContaining('would overwrite existing sprite');
    expectWarningContaining('None positive latency');
    clearEnvironment();
    logConnectionData = false;
    Logger.root.level = Level.INFO;
  });

  group('End2End', () {
    test('Resource loading tests p2p', () async {
      expectWarningContaining("unable to add commander data");
      expectWarningContaining("Received KeyState for Player that doesn't exist");
      logConnectionData = false;

      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b',
          signalPeerOpen: false, completeLoader: false, loadImages: false, setPlayerImage:false,
          selectMap: false,
          initByteWorld: false);

      Loader loaderB = worldB.loader;
      await signalOpen(worldB, ['a', 'b']);
      worldB.frameDraw();

      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));
      expect(worldB.network().peer.connections.length, equals(1));

      FakeImageFactory fakeImageFactory = worldB.imageIndex().imageFactory as FakeImageFactory;
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw();
        worldB.frameDraw();
        await fakeImageFactory.completeAllImages();
      }
      // TODO: This should be PLAYER_SELECT even if no images completed...
      expect(loaderB.currentState(), equals(LoaderState.PLAYER_SELECT));
    });

    test('Resource loading failing p2p', () async {
      WormWorld worldC = await createTestWorld('b',
          signalPeerOpen: false, completeLoader: false, loadImages: false, setPlayerImage:false,
          selectMap: false,
          initByteWorld: false);
      // Now comes a goofy client, unable to connect to anyone!
      Loader loaderC = worldC.loader;
      TestServerChannel peerC = worldC.network().peer.serverChannel as TestServerChannel;
      // Connections fail big time.
      TestConnectionFactory connectionFactoryC = getIt<TestConnectionFactory>();
      connectionFactoryC.expectPeerToExist = false;
      connectionFactoryC.failConnection('c', 'a').failConnection('c', 'b');

      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.WEB_RTC_INIT));
      await peerC.sendOpenMessage(['a', 'b', 'c']);
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.CONNECTING_TO_PEER));
      connectionFactoryC.signalErrorAllConnections('b');
      for (int i = 0; i < 100; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(loaderC.currentState(), equals(LoaderState.LOADING_SERVER));
      FakeImageFactory fakeImageFactoryC =  getIt<FakeImageFactory>();
      await fakeImageFactoryC.completeAllImages();
      worldC.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderC.currentState(), equals(LoaderState.PLAYER_SELECT));
    });

    test('Resource loading from cache', () async {
      WormWorld worldC = await createTestWorld('b',
          signalPeerOpen: false, completeLoader: false, loadImages: false, setPlayerImage:false,
          selectMap: false,
          initByteWorld: false);
      TestLocalStorage storage = worldC.localStorage as TestLocalStorage;
      for (String name in IMAGE_SOURCES) {
        storage["img$name"] = EMPTY_IMAGE_DATA_STRING;
        storage["timg$name"] =
            new DateTime.now().millisecondsSinceEpoch.toString();
      }
      // Now comes a goofy client, unable to connect to anyone!
      Loader loaderC = worldC.loader;
      TestServerChannel peerC = worldC.network().peer.serverChannel as TestServerChannel;
      // Connections fail big time.
      TestConnectionFactory connectionFactoryC = getIt<TestConnectionFactory>();
      connectionFactoryC.expectPeerToExist = false;
      connectionFactoryC.failConnection('c', 'a').failConnection('c', 'b');

      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.WEB_RTC_INIT));
      await peerC.sendOpenMessage(['a', 'b', 'c']);
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.CONNECTING_TO_PEER));
      connectionFactoryC.signalErrorAllConnections('b');
      // All loaded from cache!
      FakeImageFactory fakeImageFactory = worldC.imageIndex().imageFactory as FakeImageFactory;
      for (int i = 0; i < 10; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
        await fakeImageFactory.completeAllImages();
      }
      expect(loaderC.currentState(), equals(LoaderState.PLAYER_SELECT));
      expect(worldC.imageIndex().finishedLoadingImages(), isTrue);
    });

    /*
    test("TestLoadFromCache", () {
      fakeImageFactory.allowURLImages = false;
      for (String name in IMAGE_SOURCES) {
        localStorage["img$name"] = "data:image/png;base64,data$name";
        localStorage["timg$name"] =
            new DateTime.now().millisecondsSinceEpoch.toString();
      }

      index.loadImagesFromNetwork();

      fakeImageFactory.completeAllImages();

      expect(index.finishedLoadingImages(), isTrue);
    }); */

    /*
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

      peerB.sendOpenMessage(['a', 'b']);
      // Connection works for 5 packets;
      peerB.connections.forEach((e) { e.dropPacketsAfter = 5; });
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
      expectWarningContaining("Received KeyState for Player that doesn't exist");
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
      spriteA.takeDamage(spriteA.health, spriteB, Mod.UNKNOWN);

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
      stateA.onKeyDown(KeyCodeDart.SPACE);
      for (int i = 0; i < 2; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }
      expect(loaderA.currentState(), equals(LoaderState.WORLD_SELECT));

      KeyState stateB = injectorB.get(KeyState, LocalKeyState);
      stateB.onKeyDown(KeyCodeDart.SPACE);
      for (int i = 0; i < 2; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }
      expect(loaderB.currentState(), equals(LoaderState.WORLD_SELECT));

      stateA.onKeyUp(KeyCodeDart.SPACE);
      stateB.onKeyUp(KeyCodeDart.SPACE);

      stateA.onKeyDown(KeyCodeDart.SPACE);
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
    }); */
  });
}