import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/powerup_manager.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import 'lib/test_lib.dart';
import 'lib/test_mocks.mocks.dart';

void main() {
  late MockSpriteIndex mockSpriteIndex;
  late MockImageIndex mockImageIndex;
  late MockByteWorld mockByteWorld;
  late PowerupManager manager;

  setUp(() {
    logOutputForTest();
    mockSpriteIndex = MockSpriteIndex();
    mockImageIndex = MockImageIndex();
    mockByteWorld = MockByteWorld();

    HTMLImageElement img = HTMLImageElement()
      ..width = 37
      ..height = 37;
    when(mockImageIndex.getImageIdByName(any)).thenReturn(2);
    when(mockImageIndex.getImageById(any)).thenReturn(img);
    when(mockByteWorld.randomNotSolidPoint(any))
        .thenReturn(Vec2(120.0, 240.0));

    manager = PowerupManager(mockSpriteIndex, mockImageIndex, mockByteWorld);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  group('PowerupManager unit tests', () {
    test('Starts with fast spawn timer and waits until elapsed before spawning', () {
      expect(manager.activePowerups, isEmpty);
      expect(manager.nextPowerupIn,
          equals(PowerupManager.MIN_POWERUP_SPAWN_TIME));

      // Not yet elapsed -> nothing spawned.
      manager.frame(PowerupManager.MIN_POWERUP_SPAWN_TIME - 0.5);
      expect(manager.activePowerups, isEmpty);
      verifyNever(mockSpriteIndex.addSprite(any));

      // Elapsed -> spawns first powerup at ByteWorld's non-solid position.
      manager.frame(0.6);
      expect(manager.activePowerups, hasLength(1));
      expect(manager.activePowerups.first.position.x, equals(120.0));
      expect(manager.activePowerups.first.position.y, equals(240.0));
      verify(mockByteWorld.randomNotSolidPoint(Powerup.SIZE_OFFSET)).called(1);
      verify(mockSpriteIndex.addSprite(manager.activePowerups.first)).called(1);
    });

    test('Spawn interval scales monotonically from MIN to MAX with active count', () {
      double prevInterval = manager.nextSpawnInterval();
      expect(prevInterval, equals(PowerupManager.MIN_POWERUP_SPAWN_TIME));

      for (int expectedCount = 1;
          expectedCount <= PowerupManager.MAX_POWERUPS;
          expectedCount++) {
        manager.frame(manager.nextPowerupIn + 0.01);
        expect(manager.activePowerups, hasLength(expectedCount));

        double currentInterval = manager.nextSpawnInterval();
        expect(currentInterval, greaterThan(prevInterval));
        expect(manager.nextPowerupIn, closeTo(currentInterval, 0.001));
        prevInterval = currentInterval;
      }

      expect(prevInterval, equals(PowerupManager.POWERUP_SPAWN_TIME));
    });

    test('Respects MAX_POWERUPS cap and does not spawn beyond limit', () {
      for (int i = 0; i < PowerupManager.MAX_POWERUPS; i++) {
        manager.frame(manager.nextPowerupIn + 0.01);
      }
      expect(manager.activePowerups, hasLength(PowerupManager.MAX_POWERUPS));
      clearInteractions(mockSpriteIndex);

      // Advance well past several spawn intervals while at cap.
      for (int i = 0; i < 5; i++) {
        manager.frame(PowerupManager.POWERUP_SPAWN_TIME + 1.0);
      }
      expect(manager.activePowerups, hasLength(PowerupManager.MAX_POWERUPS));
      verifyNever(mockSpriteIndex.addSprite(any));
    });

    test('Prunes removed powerups and immediately shortens pending timer', () {
      // Fill to MAX_POWERUPS -> timer sits at full POWERUP_SPAWN_TIME (10s).
      for (int i = 0; i < PowerupManager.MAX_POWERUPS; i++) {
        manager.frame(manager.nextPowerupIn + 0.01);
      }
      expect(manager.nextPowerupIn, equals(PowerupManager.POWERUP_SPAWN_TIME));

      // Remove 2 powerups (4 -> 2 active): pending timer clamps down to 2-active interval.
      manager.activePowerups[0].remove = true;
      manager.activePowerups[1].remove = true;
      manager.frame(0.05);
      expect(manager.activePowerups, hasLength(2));
      final double twoActiveInterval = manager.nextSpawnInterval();
      expect(twoActiveInterval, lessThan(PowerupManager.POWERUP_SPAWN_TIME));
      expect(manager.nextPowerupIn, closeTo(twoActiveInterval - 0.05, 0.001));

      // Remove remaining powerups (2 -> 0 active): timer clamps down to MIN_POWERUP_SPAWN_TIME.
      for (final Powerup p in manager.activePowerups) {
        p.remove = true;
      }
      manager.frame(0.05);
      expect(manager.activePowerups, isEmpty);
      expect(
          manager.nextPowerupIn,
          closeTo(PowerupManager.MIN_POWERUP_SPAWN_TIME - 0.05, 0.001));
    });

    test('Removing a powerup never extends an already shorter remaining timer', () {
      for (int i = 0; i < PowerupManager.MAX_POWERUPS; i++) {
        manager.frame(manager.nextPowerupIn + 0.01);
      }
      manager.setNextPowerForTest(1.0);

      // Remove one powerup (new interval is ~8.125s, but remaining timer is only 1.0s).
      manager.activePowerups.first.remove = true;
      manager.frame(0.1);

      expect(manager.activePowerups, hasLength(PowerupManager.MAX_POWERUPS - 1));
      expect(manager.nextPowerupIn, closeTo(0.9, 0.001));
    });

    test('reset marks all active powerups for removal and restores fast spawn timer', () {
      for (int i = 0; i < 3; i++) {
        manager.frame(manager.nextPowerupIn + 0.01);
      }
      final List<Powerup> spawned = List.from(manager.activePowerups);
      expect(spawned, hasLength(3));

      manager.reset();

      for (final Powerup p in spawned) {
        expect(p.remove, isTrue);
      }
      expect(manager.activePowerups, isEmpty);
      expect(manager.nextPowerupIn,
          equals(PowerupManager.MIN_POWERUP_SPAWN_TIME));
    });

    test('trackPowerup and syncWithSpriteIndex deduplicate and adopt world powerups', () {
      Powerup remote1 = Powerup(Vec2(10.0, 20.0), PowerUpType.SHIELD, mockImageIndex)
        ..networkId = 42
        ..networkType = NetworkType.REMOTE;
      Powerup remote2 = Powerup(Vec2(30.0, 40.0), PowerUpType.JETPACK, mockImageIndex)
        ..networkId = 43
        ..networkType = NetworkType.REMOTE;

      manager.trackPowerup(remote1);
      manager.trackPowerup(remote1);
      expect(manager.activePowerups, hasLength(1));

      when(mockSpriteIndex.hasSprite(42)).thenReturn(true);
      when(mockSpriteIndex.hasSprite(43)).thenReturn(true);
      when(mockSpriteIndex.isPendingRemoval(any)).thenReturn(false);
      when(mockSpriteIndex.spriteIds()).thenReturn([42, 43]);
      when(mockSpriteIndex[42]).thenReturn(remote1);
      when(mockSpriteIndex[43]).thenReturn(remote2);
      when(mockSpriteIndex.pendingSprites()).thenReturn(const <Sprite>[]);

      manager.syncWithSpriteIndex();
      expect(manager.activePowerups, unorderedEquals([remote1, remote2]));

      remote1.remove = true;
      manager.pruneRemoved();
      expect(manager.activePowerups, equals([remote2]));
    });
  });
}
