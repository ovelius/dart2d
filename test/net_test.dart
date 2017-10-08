library dart2d;

import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/net.dart';
import 'package:di/di.dart';
import 'package:dart2d/util/util.dart';

void main() {
  setUp(() {
    logOutputForTest();
    clearEnvironment();
    logConnectionData = false;
    Logger.root.level = Level.INFO;
    remapKeyNamesForTest();
  });

  group('World 2 world network tests', () {
    test('TestBasicSmokeConnection', () {
      WormWorld worldA = testWorld("c");
      WormWorld worldB = testWorld("b");
      expect(worldA.network().getPeer().connectedToServer(), isTrue);
      expect(worldB.network().getPeer().connectedToServer(), isTrue);

      // A framedraw will start worldB as server.
      worldB.startAsServer("nameB");
      worldB.frameDraw();
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      // Locally controlled player.
      expect(worldB, controlsMatching(playerId(0))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
  
      worldA.connectTo("b", "nameC", true);
      // A framedraw twill start worldA as client.
      worldA.frameDraw();
      // ClientSpec was sent to b from a:
      expect(recentSentDataTo("b"),
          new MapKeyMatcher.containsKey(CLIENT_PLAYER_SPEC));
      expect(recentReceviedDataFrom("c"),
          new MapKeyMatcher.containsKey(CLIENT_PLAYER_SPEC));
      // B responed with a server reply:
      expect(recentSentDataTo("c"),
          new MapKeyMatcher.containsKey(SERVER_PLAYER_REPLY));
      expect(recentReceviedDataFrom("b"),
          new MapKeyMatcher.containsKey(SERVER_PLAYER_REPLY));
      // Make worldB add the player to the world.
      worldB.frameDraw(0.01);
      
      // Simulate a keyframe from A and verify that it is received.
      expect(worldA.network().currentKeyFrame, equals(0));
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldA.network().currentKeyFrame, equals(1));
      expect(recentReceviedDataFrom("c"),
          new MapKeyMatcher.containsKey(IS_KEY_FRAME_KEY));
      
      expect(worldB.network().currentKeyFrame, equals(0));
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldB.network().currentKeyFrame, equals(1));
      expect(recentReceviedDataFrom("b"),
          new MapKeyMatcher.containsKey(IS_KEY_FRAME_KEY));
  
      // Run frames again to make sure sprites are added to world.
      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);
  
      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));

      // Assert server control.
      expect(worldB, controlsMatching(playerId(0))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      // Comander takes control of weapon change and fire of weapon, and respawn
      expect(worldB, controlsMatching(playerId(1))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.SERVER_TO_OWNER_DATA)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));


      // Assert client control.
      expect(worldA, controlsMatching(playerId(1))
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          // Client also switches weapon.
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR));
      // Client has no active methods for server.
      // But listens for weapon switch in case of command transfer.
      expect(worldA, controlsMatching(playerId(0))
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      // Both worlds are in the same gamestate.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameB", playerId(1): "nameC"}));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameB", playerId(1): "nameC"}));
    });

    test('TestThreeWorlds', () {
      print("Testing connecting with three players");
      WormWorld worldA = testWorld("a");
      worldA.startAsServer("nameA");
      worldA.frameDraw();

      WormWorld worldB = testWorld("b");
      WormWorld worldC = testWorld("c");
  
      // b connects to a.
      worldB.connectTo("a", "nameB");
      worldA.frameDraw(0.01);
      expect(worldA, hasSpriteWithNetworkId(playerId(0)).andNetworkType(NetworkType.LOCAL));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)).andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(worldA, isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}));
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      // After worldAs keyframe worldB has the entire state of the game.
      worldB.frameDraw(0.01);
      expect(worldB, hasSpriteWithNetworkId(playerId(0)).andNetworkType(NetworkType.REMOTE));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)).andNetworkType(NetworkType.LOCAL));
      expect(worldB, isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}));

      logConnectionData = true;
      // now c connects to a.
      worldC.connectTo("a", "nameC");
      // run a frame in a to make sure the sprite is processed.
      worldA.frameDraw(0.01);
      expect(worldA, hasSpriteWithNetworkId(playerId(0)).andNetworkType(NetworkType.LOCAL));
      expect(worldA, hasSpriteWithNetworkId(playerId(1))
          .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(worldA, hasSpriteWithNetworkId(playerId(2))
          .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(worldA, isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"}));
      // Now C runs a keyframe. This will make a forward the local player sprite in c to b. 
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(0.01);
      expect(worldB, hasSpriteWithNetworkId(playerId(0))
          .andNetworkType(NetworkType.REMOTE));
      expect(worldB, hasSpriteWithNetworkId(playerId(1))
          .andNetworkType(NetworkType.LOCAL));
      expect(worldB, hasSpriteWithNetworkId(playerId(2))
          .andNetworkType(NetworkType.REMOTE));
      // Make server a run a keyframe to ensure gamestate if propagated.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldB, isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"}));
      // This also sets up CLIENT_TO_CLIENT connections.
      expect(worldB, hasSpecifiedConnections(['c','a']).isValidGameConnections());
      expect(worldC, hasSpecifiedConnections(['b','a']).isValidGameConnections());
      // And of course the server to client connections from A.
      expect(worldA, hasSpecifiedConnections(['b','c']).isValidGameConnections());
      // Make sure a doesn't deliver things in sync to c from b.
      // Run a keyframe in B.
      // TODO(Erik): Make c be smart enough to determine the real source of the sprite.
      // c should disregard the sprite from a since a direct connection exists to b.
      testConnections["a"][0].buffer = true;
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldC.frameDraw(0.01); // This adds the sprite from the client to client connection.
      expect(worldC, hasSpriteWithNetworkId(playerId(0))
          .andNetworkType(NetworkType.REMOTE));
      expect(worldC, hasSpriteWithNetworkId(playerId(1))
          .andNetworkType(NetworkType.REMOTE));
      expect(worldC, hasSpriteWithNetworkId(playerId(2))
          .andNetworkType(NetworkType.LOCAL));
      
      testConnections["a"][0].buffer = false;
      testConnections["a"][0].flushBuffer();
      
      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);
      worldC.frameDraw(0.01);
       
      // Final GameState should be consitent.
      expect(worldA,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"})
              .withCommanderId('a'));
      expect(worldB,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"})
              .withCommanderId('a'));
      expect(worldC,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"})
              .withCommanderId('a'));

      // Assert sprite control.
      expect(worldA, controlsMatching(playerId(0))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(worldA, controlsMatching(playerId(1))
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.SERVER_TO_OWNER_DATA)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(worldA, controlsMatching(playerId(2))
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.SERVER_TO_OWNER_DATA)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      expect(worldB, controlsMatching(playerId(0))
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(worldB, controlsMatching(playerId(1))
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(worldB, controlsMatching(playerId(2))
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      expect(worldC, controlsMatching(playerId(0))
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(worldC, controlsMatching(playerId(1))
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(worldC, controlsMatching(playerId(2))
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
    });

    test('TestFourWorldsServerDies', () {
      /// TODO assert keyStates.
      int PLAYER_TWO_SPRITE_FRAMES = 4;
      
      logConnectionData = false;
      WormWorld worldA = testWorld("a");
      worldA.startAsServer("nameA");

      WormWorld worldB = testWorld("b");
      WormWorld worldC = testWorld("c");
      WormWorld worldD = testWorld("d");
  
      worldB.connectTo("a", "nameB");         
      worldC.connectTo("a", "nameC");
      worldD.connectTo("a", "nameD");              
     
      // Tick a few keyframes for the worlds.
      logConnectionData = true;

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);   
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);  
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      logConnectionData = false;

      expect(worldA, controlsMatching(playerId(0))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      expect(worldA, hasSpecifiedConnections(['b', 'c','d']).isValidGameConnections());
      expect(worldB, hasSpecifiedConnections(['a', 'c','d']).isValidGameConnections());
      expect(worldC, hasSpecifiedConnections(['a', 'b','d']).isValidGameConnections());
      expect(worldD, hasSpecifiedConnections(['a', 'b','c']).isValidGameConnections());

      expect(worldA.spriteIndex.count(), equals(4));
      expect(worldB.spriteIndex.count(), equals(4));
      expect(worldC.spriteIndex.count(), equals(4));
      expect(worldD.spriteIndex.count(), equals(4));

      var gameState = {playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC", playerId(3): "nameD"};
      expect(worldA, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldB, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldC, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldD, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldD.spriteIndex.count(), equals(4));

      // All worlds should be disconnected from the server.
      expect(worldA, isConnectedToServer(false));
      expect(worldB, isConnectedToServer(false));
      expect(worldC, isConnectedToServer(false));
      expect(worldD, isConnectedToServer(false));
      
      // Now make a drop away.
      testConnections['a'].forEach((e) { e.signalClose(); });

      // TODO bring back!
      // expect(worldB.spriteIndex[playerId(1)].frames,
      //  equals(PLAYER_TWO_SPRITE_FRAMES));
      // TODO: Check type of playerId(1).

      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      expect(worldB, controlsMatching(playerId(1))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      gameState.remove(playerId(0));
      expect(worldB, isGameStateOf(gameState).withCommanderId('b'));
      expect(worldC, isGameStateOf(gameState).withCommanderId('b'));
      expect(worldD, isGameStateOf(gameState).withCommanderId('b'));
      expect(worldB.spriteIndex.count(), equals(3));
      expect(worldC.spriteIndex.count(), equals(3));
      expect(worldD.spriteIndex.count(), equals(3));

      // All worlds should be connected to server again.
      expect(worldB, isConnectedToServer(true));
      expect(worldC, isConnectedToServer(true));
      expect(worldD, isConnectedToServer(true));

      // TODO bring back!
      // expect(worldB.spriteIndex[playerId(1)].frames,
         // equals(PLAYER_TWO_SPRITE_FRAMES));
      // TODO: Check type of playerId(1).
            
      // Now b is having issues.
      testConnections['b'].forEach((e) { e..signalClose(); });
      for (int i = 0; i < 18; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldC.spriteIndex.count(), equals(2));
      expect(worldD.spriteIndex.count(), equals(2));

      gameState.remove(playerId(1));
      expect(worldC, isGameStateOf(gameState).withCommanderId('c'));
      expect(worldD, isGameStateOf(gameState).withCommanderId('c'));

      expect(worldC, controlsMatching(playerId(2))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      
      // Finally C is having issues.
      testConnections['c'].forEach((e) { e.signalClose(); });
      for (int i = 0; i < 18; i++) {
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      // WorldD is all alone.
      expect(worldD, hasSpecifiedConnections([]));
      // Make this pass by converting the REMOTE -> REMOTE_FOWARD. 
      expect(worldD.spriteIndex.count(), equals(1));

      gameState.remove(playerId(2));
      expect(worldD, isGameStateOf(gameState).withCommanderId('d'));

      expect(worldD, controlsMatching(playerId(3))
          .withActiveMethod(PlayerControlMethods.FIRE_KEY)
          .withActiveMethod(PlayerControlMethods.RESPAWN)
          .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
          .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
          .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
          .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
    });

    test('TestBadCommanderConnection', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      worldB.startAsServer("nameB");

      // Tick a few frames for B.
      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      worldA.connectTo("b", "nameA");
  
      expect(worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      for (int i = 0; i < 4; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      
      // B hasn't responded in a long time.
      expect(worldA.network().hasNetworkProblem(), equals(true));

      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // B now responded and we're back.
      expect(worldA.network().hasNetworkProblem(), equals(false));

      expect(worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));
      expect(worldB.spriteIndex.count(), equals(2));

      // Now B is having framerate issues.
      worldB.drawFps().setFpsForTest(2.1);

      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldB.network().slowCommandingFrames(), equals(1));

      while(worldB.network().slowCommandingFrames() > 0){
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // Commander is now a.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));

      // Because worldB is only doing 2 Fps!
      expect(worldB.network().getGameState().playerInfoByConnectionId('b').fps, equals(2));
      expect(worldA.network().getGameState().playerInfoByConnectionId('b').fps, equals(2));

      worldB.drawFps().setFpsForTest(25.0);

      // And all is well for a while.
      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      // Commander is still a.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));

      // And the FPS increased.
      expect(worldB.network().getGameState().playerInfoByConnectionId('b').fps, equals(25));
      expect(worldA.network().getGameState().playerInfoByConnectionId('b').fps, equals(25));

      // But no a is having trouble.
      worldA.drawFps().setFpsForTest(3.1);

      // Pas some time.
      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01, true);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01, true);
      }

      // Commander is now b.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));

      expect(worldB.network().getGameState().playerInfoByConnectionId('a').fps, equals(3));
      expect(worldA.network().getGameState().playerInfoByConnectionId('a').fps, equals(3));

    });

    test('TestCommanderSpriteForward', () {
      Injector injectorA = createWorldInjector('a');
      TestConnectionFactory connectionFactory = injectorA.get(TestConnectionFactory);

      WormWorld worldA = initTestWorld(injectorA);
      WormWorld worldB = testWorld("b");
      WormWorld worldC = testWorld("c");

      worldB.startAsServer("nameB");
      worldB.frameDraw();
      connectionFactory.failConnection('c', 'a').failConnection('a', 'c');

      worldA.connectTo('b');
      worldA.network().getServerConnection().sendClientEnter();
      worldC.connectTo('b');
      worldC.network().getServerConnection().sendClientEnter();

      for (int i = 0; i < 8; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldC.frameDraw(KEY_FRAME_DEFAULT);
      }

      expect(worldB, hasExactSprites([
        hasSpriteWithNetworkId(playerId(0))
            .andNetworkType(NetworkType.LOCAL),
        hasSpriteWithNetworkId(playerId(1))
            .andNetworkType(NetworkType.REMOTE_FORWARD),
        hasSpriteWithNetworkId(playerId(2))
            .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));

      expect(worldA, hasExactSprites([
        hasSpriteWithNetworkId(playerId(0))
            .andNetworkType(NetworkType.REMOTE),
        hasSpriteWithNetworkId(playerId(1))
            .andNetworkType(NetworkType.LOCAL),
        hasSpriteWithNetworkId(playerId(2))
            .andNetworkType(NetworkType.REMOTE),
      ]));

      expect(worldC, hasExactSprites([
        hasSpriteWithNetworkId(playerId(0))
            .andNetworkType(NetworkType.REMOTE),
        hasSpriteWithNetworkId(playerId(1))
            .andNetworkType(NetworkType.REMOTE),
        hasSpriteWithNetworkId(playerId(2))
            .andNetworkType(NetworkType.LOCAL),
      ]));

      Sprite spriteA = worldA.spriteIndex[playerId(1)];
      Sprite spriteC = worldC.spriteIndex[playerId(1)];
      spriteA.position.x = 99.0;
      spriteC.position.x = 88.0;

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // C received the data from A through B.
      expect(spriteA.position.x, equals(spriteC.position.x));
    });

    test('TestThreePlayerOneJoinsLater', () {
      WormWorld worldA = testWorld("a");
      worldA.startAsServer("nameA");
      WormWorld worldB = testWorld("b");
      WormWorld worldC = testWorld("c");
      worldB.connectTo("a", "nameB");
      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      
      // 20 keyframes later another player joins.
      worldC.connectTo("a", "nameC");
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        expect(worldA.spriteIndex.count(), equals(3));
        expect(worldA, hasSpecifiedConnections(['b', 'c']).isValidGameConnections());
        expect(worldB, hasSpecifiedConnections(['a', 'c']).isValidGameConnections());
        expect(worldC, hasSpecifiedConnections(['a', 'b']).isValidGameConnections());
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      // Should work just fine.
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"}));

      for (WormWorld w in [worldA, worldB, worldC]) {
        for (WormWorld w2 in [worldA, worldB, worldC]) {
          GameState gameState = w.network().getGameState();
          String id1 = w.network().getPeer().getId();
          String id2 = w2.network().getPeer().getId();
          if (id1 == id2) {
            continue;
          }
          print("verify ${id1} connected to ${id2}");
          expect(gameState.isConnected(id1, id2), isTrue);
        }
      }
    });

    test('TestMaxPlayers', () {
        logConnectionData = false;
        WormWorld worldA = testWorld("a");

        worldA.startAsServer("nameA");

        WormWorld worldB = testWorld("b");
        WormWorld worldC = testWorld("c");
        WormWorld worldD = testWorld("d");
        WormWorld worldE = testWorld("e");
    
        worldB.connectTo("a", "nameB");         
        worldC.connectTo("a", "nameC");
        worldD.connectTo("a", "nameD");

        worldE.connectTo("a", "nameE", false);
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

        expect(worldE.network().gameState.playerInfoList(), hasLength(4));
        expect(worldE.network().gameState.actingCommanderId, equals('a'));
        expect(worldE.network().getServerConnection(), isNotNull);

        worldE.network().getServerConnection().connectToGame('nameE', 2);

        expect(recentSentDataTo("e"),
            new MapKeyMatcher.containsKey(SERVER_PLAYER_REJECT));

        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldE.frameDraw(KEY_FRAME_DEFAULT + 0.01);

        // Gamestate got reset.
        expect(worldE.network().gameState.playerInfoList(), hasLength(0));
        expect(worldE.network().gameState.actingCommanderId, isNull);

        expect(worldA, hasSpecifiedConnections(['b', 'c', 'd']).isValidGameConnections());
    });
  }); 
}
