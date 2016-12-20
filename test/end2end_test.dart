library dart2d;

import 'package:test/test.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'test_env.dart';
import 'fake_canvas.dart';
import 'matchers.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:di/di.dart';
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

  group('Smoke tests', () {
    test('TestBasicSmokeConnection', () {
      Injector injectorA = createWorldInjector("a");
      Injector injectorB = createWorldInjector("b");


    });
  });
}
