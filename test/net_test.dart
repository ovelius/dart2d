library dart2d;

import 'package:test/test.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'fake_canvas.dart';
import 'matchers.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/worlds/worm_world.dart';
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

  group('World smoke tests', () {
    test('TestBasicSmokeConnection', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");

      // A framedraw will start worldB as server.
      worldB.frameDraw();
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
  
      worldA.connectTo("b", "nameA");
      // A framedraw twill start worldA as client.
      worldA.frameDraw();
      // ClientSpec was sent to b from a:
      expect(recentSentDataTo("b"),
          new MapKeyMatcher.containsKey(CLIENT_PLAYER_SPEC));
      expect(recentReceviedDataFrom("a"),
          new MapKeyMatcher.containsKeyWithValue(CLIENT_PLAYER_SPEC, "nameA"));
      // B responed with a server reply:
      expect(recentSentDataTo("a"),
          new MapKeyMatcher.containsKey(SERVER_PLAYER_REPLY));
      expect(recentReceviedDataFrom("b"),
          new MapKeyMatcher.containsKey(SERVER_PLAYER_REPLY));
      // Make worldB add the player to the world.
      worldB.frameDraw(0.01);
      
      // Simulate a keyframe from A and verify that it is received.
      expect(worldA.network.currentKeyFrame, equals(0));
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldA.network.currentKeyFrame, equals(1));
      expect(recentReceviedDataFrom("a"),
          new MapKeyMatcher.containsKey(IS_KEY_FRAME_KEY));
      
      expect(worldB.network.currentKeyFrame, equals(0));
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldB.network.currentKeyFrame, equals(1));
      expect(recentReceviedDataFrom("b"),
          new MapKeyMatcher.containsKey(IS_KEY_FRAME_KEY));
  
      // Run frames again to make sure sprites are added to world.
      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);
  
      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));

      // Both worlds are in the same gamestate.
      expect(worldB.network.gameState,
          isGameStateOf({playerId(0): "nameB", playerId(1): "nameA"}));
      expect(worldA.network.gameState,
          isGameStateOf({playerId(0): "nameB", playerId(1): "nameA"}));
    });

    test('TestDroppedKeyFrame', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      // First connection will drop one packet.
      droppedPacketsNextConnection.add(1);
      // Second connection will drop two.
      droppedPacketsNextConnection.add(2);
  
      worldA.connectTo("b", "nameA");
      // ClientSpec was sent to b from a:
      expect(recentSentDataTo("b"),
          new MapKeyMatcher.containsKey(CLIENT_PLAYER_SPEC));
      // But it was dropped :(
      expect(recentReceviedDataFrom("a"), equals(null));
      // Make A advance a keyframe: 
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      // No we get the stuff:
      expect(recentReceviedDataFrom("a"),
          new MapKeysMatcher.containsKeys(
              [IS_KEY_FRAME_KEY, CLIENT_PLAYER_SPEC]));
      // Reply was dropped.
      expect(recentReceviedDataFrom("b"), equals(null));
      // Advance two keyframes and data will be there!
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(recentReceviedDataFrom("b"),
          new MapKeysMatcher.containsKeys(
              [SERVER_PLAYER_REPLY, IS_KEY_FRAME_KEY, GAME_STATE]));
  
      // Game should get underway about one keyframe later.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // Game has started.
      expect(worldA.spriteIndex.count(), equals(2));
      expect(worldB.spriteIndex.count(), equals(2));
    });
  
  
    test('TestThreeWorlds', () {
      print("Testing connecting with three players");
      WormWorld worldA = testWorld("a");
      worldA.frameDraw();
     // worldA.startAsServer("nameA");

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
      expect(worldB, hasSpecifiedConnections({
          'c':ConnectionType.CLIENT_TO_CLIENT,
          'a':ConnectionType.CLIENT_TO_SERVER,
      }));
      expect(worldC, hasSpecifiedConnections({
          'b':ConnectionType.CLIENT_TO_CLIENT,
          'a':ConnectionType.CLIENT_TO_SERVER,
      }));
      // And of course the server to client connections from A.
      expect(worldA, hasSpecifiedConnections({
          'c':ConnectionType.SERVER_TO_CLIENT,
          'b':ConnectionType.SERVER_TO_CLIENT,
      }));
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
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"}));
      expect(worldB,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"}));
      expect(worldC,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"}));
    });

    test('TestFourWorldsServerDies', () {
      int PLAYER_TWO_SPRITE_FRAMES = 4;
      
      logConnectionData = false;
      print("Testing connecting with three players, server dies so a new server is elected");
      WormWorld worldA = testWorld("a");
      worldA.startGame();

      WormWorld worldB = testWorld("b");
      WormWorld worldC = testWorld("c");
      WormWorld worldD = testWorld("d");
  
      worldB.connectTo("a", "nameB");         
      worldC.connectTo("a", "nameC");
      worldD.connectTo("a", "nameD");              
     
      // Tick a few keyframes for the worlds.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);   
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);  
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01); 

      var gameState = {playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC", playerId(3): "nameD"};
      expect(worldA, isGameStateOf(gameState));
      expect(worldB, isGameStateOf(gameState));
      expect(worldC, isGameStateOf(gameState));
      expect(worldD, isGameStateOf(gameState));
      expect(worldD.spriteIndex.count(), equals(4));
      
      // Now make a drop away.
      testConnections['a'].forEach((e) { e.dropPackets = 100;});
      
      expect(worldB.spriteIndex[playerId(1)].frames,
          equals(PLAYER_TWO_SPRITE_FRAMES));
      // TODO: Check type of playerId(1).

      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);  
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
    
      expect(worldB, hasSpecifiedConnections({
         'c':ConnectionType.SERVER_TO_CLIENT,
         'd':ConnectionType.SERVER_TO_CLIENT,
      }));
      expect(worldC, hasSpecifiedConnections({
         'b':ConnectionType.CLIENT_TO_SERVER,
         'd':ConnectionType.CLIENT_TO_CLIENT,
      }));
      expect(worldD, hasSpecifiedConnections({
         'b':ConnectionType.CLIENT_TO_SERVER,
         'c':ConnectionType.CLIENT_TO_CLIENT,
      }));
      
      gameState.remove(playerId(0));
      expect(worldB, isGameStateOf(gameState));
      expect(worldC, isGameStateOf(gameState));
      expect(worldD, isGameStateOf(gameState));
      expect(worldB.spriteIndex.count(), equals(3));
      expect(worldC.spriteIndex.count(), equals(3));
      expect(worldD.spriteIndex.count(), equals(3));
      
      expect(worldB.spriteIndex[playerId(1)].frames,
          equals(PLAYER_TWO_SPRITE_FRAMES));
      // TODO: Check type of playerId(1).
            
      // Now b is having issues.
      testConnections['b'].forEach((e) { e.dropPackets = 100;});
      for (int i = 0; i < 18; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldC, hasSpecifiedConnections({ 
          'd':ConnectionType.SERVER_TO_CLIENT,
      }));
      expect(worldD, hasSpecifiedConnections({
          'c':ConnectionType.CLIENT_TO_SERVER,
      }));
      expect(worldC.spriteIndex.count(), equals(2));
      expect(worldD.spriteIndex.count(), equals(2));
      
      // Finally C is having issues.
      testConnections['c'].forEach((e) { e.dropPackets = 100;});
      for (int i = 0; i < 18; i++) {
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      // WorldD is all alone.
      expect(worldD, hasSpecifiedConnections({}));
      // Make this pass by converting the REMOTE -> REMOTE_FOWARD. 
      expect(worldD.spriteIndex.count(), equals(1));
    });

    test('TestDroppedConnection', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      worldB.startGame();
      worldA.connectTo("b", "nameA");
  
      expect(worldB.network.gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"}));
      
      for (int i = 0; i < 4; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      
      // B hasn't responded in a long time.
      expect(worldA.network.hasNetworkProblem(), equals(true));

      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      
      expect(worldB.network.gameState,
          isGameStateOf({playerId(0): "nameB"}));
      expect(worldB.spriteIndex.count(), equals(1));
    });

    test('TestThreePlayerOneJoinsLater', () {
      WormWorld worldA = testWorld("a");
      worldA.startGame();
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
        expect(worldB, hasSpecifiedConnections({
            'a':ConnectionType.CLIENT_TO_SERVER,
            'c':ConnectionType.CLIENT_TO_CLIENT,
        }));
        expect(worldC, hasSpecifiedConnections({
            'a':ConnectionType.CLIENT_TO_SERVER,
            'b':ConnectionType.CLIENT_TO_CLIENT,
        }));
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      // Should work just fine.
      expect(worldA.network.gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB", playerId(2): "nameC"}));
    });
    
    test('TestReliableMessage', () {
        logConnectionData = true;
        WormWorld worldA = testWorld("a");
        worldA.startAsServer("nameA");
        WormWorld worldB = testWorld("b");
        worldB.connectTo("a", "nameB");
        
        testConnections['b'].forEach((e) { e.dropPackets = 1;});
        
        worldA.network.sendMessage("test me");
        
        // This got dropped.
        expect(recentReceviedDataFrom("a"),
               new MapKeysMatcher.containsKeys(
                   [SERVER_PLAYER_REPLY]));
        
        worldA.frameDraw();
        worldB.frameDraw();
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        
        // After the next keyframe it gets sent.
        expect(recentReceviedDataFrom("a"),
             new MapKeysMatcher.containsKeys(
                 [MESSAGE_KEY]));
    });
    
    test('TestMaxPlayers', () {
        logConnectionData = false;
        WormWorld worldA = testWorld("a");

        worldA.startGame();

        WormWorld worldB = testWorld("b");
        WormWorld worldC = testWorld("c");
        WormWorld worldD = testWorld("d");
        WormWorld worldE = testWorld("e");
    
        worldB.connectTo("a", "nameB");         
        worldC.connectTo("a", "nameC");
        worldD.connectTo("a", "nameD");
        
        worldE.connectTo("a", "nameE");
        expect(recentSentDataTo("e"),
            new MapKeyMatcher.containsKey(SERVER_PLAYER_REJECT));
        
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldE.frameDraw(KEY_FRAME_DEFAULT + 0.01);

        expect(worldA, hasSpecifiedConnections({
            'b':ConnectionType.SERVER_TO_CLIENT ,
            'c':ConnectionType.SERVER_TO_CLIENT ,
            'd':ConnectionType.SERVER_TO_CLIENT ,
        }));
    });
  }); 
}
