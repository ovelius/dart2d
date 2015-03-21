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
  
  group('Sprite transfer tests', () {
    test('TestBasicSpriteTransfer', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
      worldA.startAsServer("nameB");
      worldA.frameDraw();
      expect(worldA, hasSpriteWithNetworkId(0)
          .andNetworkType(NetworkType.LOCAL));
      worldB.connectTo("b", "nameA");
      worldA.frameDraw();
      worldB.frameDraw();
      expect(worldA, hasSpriteWithNetworkId(0)
               .andNetworkType(NetworkType.LOCAL));
    });
  });
}