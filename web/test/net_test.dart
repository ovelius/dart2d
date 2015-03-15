library dart2d;

import 'package:unittest/unittest.dart';
import 'package:unittest/html_config.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import '../rtc.dart';
import '../connection.dart';
import '../world.dart';
import '../gamestate.dart';
import '../net.dart';
import '../state_updates.dart';
import '../imageindex.dart';
import 'dart:js';

World testWorld(var id) {
  TestPeer peer = new TestPeer(id);
  World w = new World(400, 600, peer);
  w.hudMessages = new TestHudMessage(w);
  return w;
}

void main() {
  useHtmlConfiguration();
  setUp(() {
    testConnections.clear();
    testPeers.clear();
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
  
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
     
      // Tick a few keyframes for the worlds.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);   
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);  
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01); 
  
      // All worlds should have two connections.
      expect(worldA, hasSpecifiedConnections({
          'c':ConnectionType.SERVER_TO_CLIENT,
          'b':ConnectionType.SERVER_TO_CLIENT,
      }));
      expect(worldB, hasSpecifiedConnections({
          'c':ConnectionType.CLIENT_TO_CLIENT,
          'a':ConnectionType.CLIENT_TO_SERVER,
      }));
      expect(worldC, hasSpecifiedConnections({
          'b':ConnectionType.CLIENT_TO_CLIENT,
          'a':ConnectionType.CLIENT_TO_SERVER,
      }));

      expect(worldA,
          isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
      expect(worldB,
           isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
      expect(worldC,
              isGameStateOf({0: "nameA", 1000: "nameB", 2000: "nameC"}));
      expect(worldA, hasSpriteWithNetworkId(0));
      expect(worldA, hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT));
      
      expect(recentReceviedDataFrom("a"),
          new MapKeyMatcher.containsKey("0"));
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(recentSentDataTo("c"),
          new MapKeyMatcher.containsKey("1000"));
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(recentSentDataTo("b"),
          new MapKeyMatcher.containsKey("2000"));
  
      expect(recentReceviedDataFrom("b"),
          new MapKeyMatcher.containsKey("1000"));
      expect(recentReceviedDataFrom("c"),
          new MapKeyMatcher.containsKey("2000"));
    });

    test('TestThreeWorldsServerDies', () {
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
      
      logConnectionData = false;
      for (int i = 0; i < 40; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);  
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      logConnectionData = true;
    
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
      // FIX(erik): Why isn't GameState propagated here?
      // expect(worldC, isGameStateOf(gameState));
      // expect(worldD, isGameStateOf(gameState));
           
      // Now b is having issues.
      testConnections['b'].forEach((e) { e.dropPackets = 100;});
      logConnectionData = false;
      for (int i = 0; i < 40; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldD.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      logConnectionData = true;

      expect(worldC, hasSpecifiedConnections({ 
          'd':ConnectionType.SERVER_TO_CLIENT,
      }));
      expect(worldD, hasSpecifiedConnections({
          'c':ConnectionType.CLIENT_TO_SERVER,
      }));
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
