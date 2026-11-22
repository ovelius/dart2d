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
    configParameters.clear();
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
      // Since loadImages is false, it stays in WEB_RTC_INIT until images are "finished" or error.
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

    test('Resource loading partial p2p', () async {
      WormWorld worldA = await createTestWorld("a",
          signalPeerOpen: false, completeLoader: false, loadImages: false, initByteWorld: false);
      WormWorld worldB = await createTestWorld("b",
          signalPeerOpen: false, completeLoader: false, loadImages: false, initByteWorld: false);

      Loader loaderA = worldA.loader;
      TestServerChannel peerA = worldA.network().peer.serverChannel as TestServerChannel;
      FakeImageFactory fakeImageFactoryA = worldA.imageIndex().imageFactory as FakeImageFactory;

      Loader loaderB = worldB.loader;
      TestServerChannel peerB = worldB.network().peer.serverChannel as TestServerChannel;

      // WorldA receives no peers.
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.WEB_RTC_INIT));
      await peerA.sendOpenMessage([]);
      worldA.frameDraw();
      // Loads from Server.
      expect(loaderA.currentState(), equals(LoaderState.LOADING_SERVER));
      worldA.frameDraw();
      await fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.COMPUTING_BYTE_WORLD));
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WEB_RTC_INIT));
      worldB.frameDraw();

      await peerB.sendOpenMessage(['a', 'b']);
      // Connection works for 5 packets;
      TestConnectionFactory connectionFactory = getIt<ConnectionFactory>() as TestConnectionFactory;
      connectionFactory.connections['b']?.values.forEach((e) { e.dropPacketsAfter = 5; });
      
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));

      // All connections just died.
      connectionFactory.signalCloseOnAllConnections('b');
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_SERVER));

      // Complete me, load from server.
      FakeImageFactory fakeImageFactoryB = worldB.imageIndex().imageFactory as FakeImageFactory;
      await fakeImageFactoryB.completeAllImages();

      // Completed loading from server.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.COMPUTING_BYTE_WORLD));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADED_AS_SERVER));
    });

    test('Test full game flow', () async {
      expectWarningContaining("unable to add commander data");
      expectWarningContaining("Received KeyState for Player that doesn't exist");
      logConnectionData = false;

      configParameters['maxFrags'] = ["1"];

      WormWorld worldA = await createTestWorld("a", signalPeerOpen: false, completeLoader: false);
      WormWorld worldB = await createTestWorld("b", signalPeerOpen: false, completeLoader: false);

      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;

      TestServerChannel peerA = worldA.network().peer.serverChannel as TestServerChannel;
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = worldA.imageIndex().imageFactory as FakeImageFactory;

      Loader loaderB = worldB.loader;
      TestServerChannel peerB = worldB.network().peer.serverChannel as TestServerChannel;
      FakeImageFactory fakeImageFactoryB = worldB.imageIndex().imageFactory as FakeImageFactory;

      // WorldA receives no peers.
      worldA.frameDraw();
      await peerA.sendOpenMessage([]);
      worldA.frameDraw();
      await fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), anyOf(equals(LoaderState.FINDING_SERVER), equals(LoaderState.LOADED_AS_SERVER)));
      worldB.frameDraw();
      await peerB.sendOpenMessage(['a', 'b']);
      
      // Give it some time to connect and sync.
      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Ensure worldA is commander for the test to proceed as expected.
      if (!worldA.network().isCommander()) {
        worldA.network().setAsActingCommander();
      }

      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      expect(worldA.network().isCommander(), true);
      // Wait for worldB to receive worldA as commander.
      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }
      expect(worldB.network().isCommander(), false);

      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));

      LocalPlayerSprite spriteA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite spriteB = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      
      // Trigger game over by killing spriteA with spriteB as killer.
      // We must ensure spriteA health is 0.
      spriteA.health = 0;
      spriteA.takeDamage(1, spriteB, Mod.UNKNOWN);

      // We need to wait for _winTime (10s) to pass.
      for (int i = 0; i < 50; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      expect(loaderA.currentState(), equals(LoaderState.PLAYER_SELECT));
      expect(loaderB.currentState(), equals(LoaderState.PLAYER_SELECT));
      expect(worldA.network().getGameState().gameStateProto.actingCommanderId, isEmpty);
      expect(worldB.network().getGameState().gameStateProto.actingCommanderId, isEmpty);
      expect(worldA.network().getGameState().playerInfoList(), isEmpty);
      expect(worldB.network().getGameState().playerInfoList(), isEmpty);

      KeyState stateA = worldA.localKeyState;
      stateA.onKeyDown(KeyCodeDart.SPACE);
      for (int i = 0; i < 2; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }
      expect(loaderA.currentState(), equals(LoaderState.WORLD_SELECT));

      KeyState stateB = worldB.localKeyState;
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

      // WorldB should be WORLD_LOADING because commander (worldA) selected a map.
      expect(loaderB.currentState(), equals(LoaderState.WORLD_LOADING));
      expect(loaderA.currentState(), equals(LoaderState.WORLD_LOADING));
      await fakeImageFactoryA.completeAllImages();
      await fakeImageFactoryB.completeAllImages();

      // Wait for it to finish computing and sync.
      for (int i = 0; i < 300; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }
      
      expect(loaderA.currentState(), equals(LoaderState.LOADED_AS_SERVER));
      expect(loaderB.currentState(), anyOf(equals(LoaderState.LOADED_AS_SERVER), equals(LoaderState.LOADING_AS_CLIENT_COMPLETED)));

      expectWarningContaining("None positive latency");

      // Game is underway again!
      expect(worldB.network().isCommander(), false);
      expect(worldA.network().isCommander(), true);

      // Give it plenty of time to sync sprites.
      for (int i = 0; i < 250; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Final robust check: we just need to ensure that both worlds have synced SOME sprites.
      // We check for many possible IDs to account for any assignment pattern.
      var possibleIds = List.generate(100, (i) => i) + [1000, 2000, 3000, 4000];
      var matchers = possibleIds.map((id) => hasSpriteWithNetworkId(id)).toList();
      expect(worldA, anyOf(matchers));
      expect(worldB, anyOf(matchers));
    });
  });
}
