library dart2d;

import 'package:unittest/unittest.dart';
import 'package:unittest/html_config.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import '../rtc.dart';
import '../connection.dart';
import '../sprite.dart';
import '../world.dart';
import '../gamestate.dart';
import '../net.dart';
import '../state_updates.dart';
import '../imageindex.dart';
import 'dart:js';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

World testWorld(var id) {
  TestPeer peer = new TestPeer(id);
  World w = new World(400, 600, peer);
  w.hudMessages = new TestHudMessage(w);
  return w;
}

void main() {
  useHtmlConfiguration();
  setUp(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
    testConnections.clear();
    testPeers.clear();
    logConnectionData = true;
    useEmptyImagesForTest();
    remapKeyNamesForTest();
  });

  group('World smoke tests', () {
    test('TestBasicSmokeConnection', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
      // 
      worldB.startAsServer("nameB");
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldB, hasSpriteWithNetworkId(0));
  
      worldA.connectTo("b", "nameA");
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
  
      expect(worldA, hasSpriteWithNetworkId(0));
      expect(worldA, hasSpriteWithNetworkId(1000));
      expect(worldB, hasSpriteWithNetworkId(0));
      expect(worldB, hasSpriteWithNetworkId(1000));

      // Both worlds are in the same gamestate.
      expect(worldB.network.gameState,
          isGameStateOf({0: "nameB", 1000: "nameA"}));
      expect(worldA.network.gameState,
          isGameStateOf({0: "nameB", 1000: "nameA"}));
    });

    test('TestDroppedKeyFrame', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
      // First connection will drop on packet.
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
      expect(worldA.sprites.length, equals(1));
      expect(worldB.sprites.length, equals(1));
    });
  
  
    test('TestThreeWorlds', () {
      print("Testing connecting with three players");
      World worldA = testWorld("a"); 
      worldA.startAsServer("nameA");
  
      World worldB = testWorld("b");
      World worldC = testWorld("c");
  
      // b connects to a.
      worldB.connectTo("a", "nameB");
      worldA.frameDraw(0.01);
      expect(worldA, hasSpriteWithNetworkId(0).andNetworkType(NetworkType.LOCAL));
      expect(worldA, hasSpriteWithNetworkId(1000).andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(worldA, isGameStateOf({0: "nameA", 1000: "nameB"}));
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      // After worldAs keyframe worldB has the entire state of the game.
      worldB.frameDraw(0.01);
      expect(worldB, hasSpriteWithNetworkId(0).andNetworkType(NetworkType.REMOTE));
      expect(worldB, hasSpriteWithNetworkId(1000).andNetworkType(NetworkType.LOCAL));
      expect(worldB, isGameStateOf({0: "nameA", 1000: "nameB"}));

      logConnectionData = true;
      // now c connects to a.
      worldC.connectTo("a", "nameC");
      // run a frame in a to make sure the sprite is processed.
      worldA.frameDraw(0.01);
      expect(worldA, hasSpriteWithNetworkId(0).andNetworkType(NetworkType.LOCAL));
      expect(worldA, hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
          .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(worldA, hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT * 2)
          .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(worldA, isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
      // Now C runs a keyframe. This will make a forward the local player sprite in c to b. 
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(0.01);
      expect(worldB, hasSpriteWithNetworkId(0)
          .andNetworkType(NetworkType.REMOTE));
      expect(worldB, hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
          .andNetworkType(NetworkType.LOCAL));
      expect(worldB, hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT * 2)
          .andNetworkType(NetworkType.REMOTE));
      // Make server a run a keyframe to ensure gamestate if propagated.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldB, isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
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
      expect(worldC, hasSpriteWithNetworkId(0)
          .andNetworkType(NetworkType.REMOTE));
      expect(worldC, hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
          .andNetworkType(NetworkType.REMOTE));
      expect(worldC, hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT * 2)
          .andNetworkType(NetworkType.LOCAL));
      
      testConnections["a"][0].buffer = false;
      testConnections["a"][0].flushBuffer();
      
      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);
      worldC.frameDraw(0.01);
       
      // Final GameState should be consitent.
      expect(worldA,
          isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
      expect(worldB,
          isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
      expect(worldC,
          isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
    });

    test('TestThreeWorldsServerDies', () {
      logConnectionData = false;
      print("Testing connecting with three players, server dies so a new server is elected");
      World worldA = testWorld("a"); 
      worldA.startAsServer("nameA");
  
      World worldB = testWorld("b");
      World worldC = testWorld("c");
      World worldD = testWorld("d");
  
      worldB.connectTo("a", "nameB");         
      worldC.connectTo("a", "nameC");
      worldD.connectTo("a", "nameD");              
     
      // Tick a few keyframes for the worlds.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);   
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);  
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01); 

      var gameState = {0: "nameA", 1000: "nameB", 2000: "nameC", 3000: "nameD"};
      expect(worldA, isGameStateOf(gameState));
      expect(worldB, isGameStateOf(gameState));
      expect(worldC, isGameStateOf(gameState));
      expect(worldD, isGameStateOf(gameState));
      
      // Now make a drop away.
      testConnections['a'].forEach((e) { e.dropPackets = 100;});
      
      for (int i = 0; i < 40; i++) {
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
      
      gameState.remove(0);
      expect(worldB, isGameStateOf(gameState));
      expect(worldC, isGameStateOf(gameState));
      expect(worldD, isGameStateOf(gameState));
           
      // Now b is having issues.
      testConnections['b'].forEach((e) { e.dropPackets = 100;});
      for (int i = 0; i < 40; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldC, hasSpecifiedConnections({ 
          'd':ConnectionType.SERVER_TO_CLIENT,
      }));
      expect(worldD, hasSpecifiedConnections({
          'c':ConnectionType.CLIENT_TO_SERVER,
      }));
      
      // Finally C is having issues.
      testConnections['c'].forEach((e) { e.dropPackets = 100;});
      for (int i = 0; i < 40; i++) {
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldD, hasSpecifiedConnections({}));
    });

    test('TestDroppedConnection', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
      worldB.startAsServer("nameB");
      worldA.connectTo("b", "nameA");
  
      expect((worldB.network as Server).gameState,
          isGameStateOf({0: "nameB", 1000: "nameA"}));
      
      for (int i = 0; i < 40; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      
      expect((worldB.network as Server).gameState,
          isGameStateOf({0: "nameB"}));
    });
  }); 
}
