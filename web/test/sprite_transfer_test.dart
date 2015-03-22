import 'package:unittest/unittest.dart';
import 'package:unittest/html_config.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import '../rtc.dart';
import '../connection.dart';
import '../sprite.dart';
import '../playersprite.dart';
import '../world.dart';
import '../gamestate.dart';
import '../net.dart';
import '../state_updates.dart';
import '../imageindex.dart';
import 'dart:js';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

void main() {
  useHtmlConfiguration();
  setUp(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
    testConnections.clear();
    testPeers.clear();
    logConnectionData = false;
    useEmptyImagesForTest();
    remapKeyNamesForTest();
  });
  
  group('Sprite transfer tests', () {
    test('TestBasicSpriteTransfer', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      expect(worldA, hasSpriteWithNetworkId(0)
          .andNetworkType(NetworkType.LOCAL));
      worldB.connectTo("a", "nameA");
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldA, hasExactSprites([
          hasSpriteWithNetworkId(0)
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
              .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldB, hasExactSprites([
            hasSpriteWithNetworkId(0)
                .andNetworkType(NetworkType.REMOTE),
            hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
                .andNetworkType(NetworkType.LOCAL),
      ]));
      expect(worldB.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT],
          hasType('RemotePlayerSprite'));
      expect(worldA.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT],
          hasType('RemotePlayerServerSprite'));
      expect(worldB.sprites[0],
          hasType('MovingSprite'));
      expect(worldA.sprites[0],
          hasType('LocalPlayerSprite'));
    });
  });
}