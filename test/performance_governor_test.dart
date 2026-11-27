import 'dart:js_interop';

import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/world_generator.dart';
import 'package:dart2d/worlds/world_themes.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import 'lib/test_injector.dart';
import 'lib/test_lib.dart';

void main() {
  setUpAll(() {
    configureDependencies();
  });

  setUp(() {
    logOutputForTest();
    testConnections.clear();
    testPeers.clear();
  });

  group('PerformanceGovernor and rendering optimizations', () {
    test('PerformanceGovernor steps down quickly on low FPS and steps up slowly with hysteresis', () {
      final PerformanceGovernor gov = PerformanceGovernor();
      expect(gov.tier, equals(QualityTier.high));
      expect(gov.detailScale, equals(1.0));

      // Sustained ~40 FPS for ~0.9s -> steps down from HIGH to MEDIUM.
      for (int i = 0; i < 10; i++) {
        gov.update(0.10, 40.0);
      }
      expect(gov.tier, equals(QualityTier.medium));
      expect(gov.detailScale, closeTo(0.6, 1e-6));

      // Sustained ~24 FPS for ~0.9s -> steps down from MEDIUM to LOW.
      for (int i = 0; i < 10; i++) {
        gov.update(0.10, 24.0);
      }
      expect(gov.tier, equals(QualityTier.low));
      expect(gov.detailScale, closeTo(0.25, 1e-6));

      // Brief 1.5s recovery to 60 FPS must NOT oscillate back up yet (hysteresis!).
      for (int i = 0; i < 15; i++) {
        gov.update(0.10, 60.0);
      }
      expect(gov.tier, equals(QualityTier.low),
          reason: 'Should hold LOW tier across brief recoveries to avoid flickering');

      // Sustained 60 FPS for full ~4.5s -> climbs one step LOW -> MEDIUM.
      for (int i = 0; i < 35; i++) {
        gov.update(0.10, 60.0);
      }
      expect(gov.tier, equals(QualityTier.medium));

      // Another sustained ~4.5s at 60 FPS -> climbs MEDIUM -> HIGH.
      for (int i = 0; i < 45; i++) {
        gov.update(0.10, 60.0);
      }
      expect(gov.tier, equals(QualityTier.high));
    });

    test('ByteWorld isCanvasCollide and clearAt update collision buffer without afterData GPU readback', () async {
      final WormWorld worldA = await createTestWorld('a');
      final ByteWorld bw = worldA.byteWorld;
      bw.setWorldImage(worldA.imageIndex().imageFactory.createWithSize(240, 160));
      while (!bw.bedrockComputed()) {
        bw.bedrockStep();
      }
      bw.fillRectAt(Vec2(20.0, 20.0), Vec2(200.0, 120.0), '#66aa44');
      expect(bw.isCanvasCollide(100, 80, 10, 10), isTrue);
      expect(bw.isCanvasCollide(2, 2, 10, 10), isFalse);

      // Carve both a jagged crater (radius >= 6) with drawScorch: false and a tiny hole (radius < 6).
      bw.clearAt(Vec2(100.0, 80.0), 28.0, maxColorSamples: 0, drawScorch: false);
      expect(bw.isSolid(100, 80), isFalse);
      expect(bw.isCanvasCollide(92, 72, 16, 16), isFalse);
      // Intact terrain outside blast remains solid.
      expect(bw.isSolid(150, 80), isTrue);

      bw.clearAt(Vec2(150.0, 80.0), 4.0, maxColorSamples: 0, drawScorch: false);
      expect(bw.isSolid(150, 80), isFalse);
    });

    test('SnailProjectile step-gates terrain carving instead of re-carving stationary/tiny steps', () async {
      final WormWorld worldA = await createTestWorld('a');
      worldA.startAsServer('playerA');
      worldA.frameDraw(0.02);

      final ByteWorld bw = worldA.byteWorld;
      bw.setWorldImage(worldA.imageIndex().imageFactory.createWithSize(300, 200));
      while (!bw.bedrockComputed()) {
        bw.bedrockStep();
      }
      bw.fillRectAt(Vec2(40.0, 40.0), Vec2(220.0, 120.0), '#886644');

      final LocalPlayerSprite player =
          worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final SnailProjectile snail =
          SnailProjectile.createWithOwner(worldA, player, 12, player.gun);
      snail.setCenter(Vec2(100.0, 100.0));

      // First contact carves at x = 100.
      snail.handleWorldCollide(bw, MovingSprite.DIR_RIGHT);
      expect(bw.isSolid(100, 100), isFalse);

      // Refill center pixel & nudge snail only 1.5px (< CARVE_STEP_DISTANCE = 5.0px) -> skipped!
      bw.fillRectAt(Vec2(99.0, 99.0), Vec2(3.0, 3.0), '#886644');
      snail.setCenter(Vec2(101.5, 100.0));
      snail.handleWorldCollide(bw, MovingSprite.DIR_RIGHT);
      expect(bw.isSolid(100, 100), isTrue,
          reason: 'Snail should skip redundant terrain carves when moved < 5px');

      // Advance >= 5px -> carves next step cleanly!
      snail.setCenter(Vec2(106.0, 100.0));
      snail.handleWorldCollide(bw, MovingSprite.DIR_RIGHT);
      expect(bw.isSolid(106, 100), isFalse);
    });

    test('Viewport culls off-screen visual effects and LOW quality skips skybox animated overlays', () async {
      final WormWorld worldA = await createTestWorld('a');
      worldA.startAsServer('playerA');
      worldA.frameDraw(0.02);
      worldA.viewPoint = Vec2(0.0, 0.0);

      final ExplosionEffect nearFx =
          ExplosionEffect(Vec2(80.0, 80.0), Vec2.ZERO, 40.0);
      final ExplosionEffect farOffscreenFx =
          ExplosionEffect(Vec2(worldA.width() + 900.0, 80.0), Vec2.ZERO, 40.0);
      expect(worldA.shouldDraw(nearFx), isTrue);
      expect(worldA.shouldDraw(farOffscreenFx), isFalse,
          reason: 'Far off-screen explosion effects should be culled from Canvas2D draw');

      // Verify LOW quality skybox (`detailScale = 0.25`) skips per-frame animated cloud loops
      // so two different `time` values render identical static skybox pixels!
      final WorldThemeSpec villa = worldThemeById(WorldThemeId.villa);
      final HTMLCanvasElement lowT0 = HTMLCanvasElement()
        ..width = 200
        ..height = 120;
      final HTMLCanvasElement lowT1 = HTMLCanvasElement()
        ..width = 200
        ..height = 120;
      WorldGenerator.drawGameplaySky(lowT0.context2D, 200, 120, villa, 0.0,
          seed: 42, detailScale: 0.25);
      WorldGenerator.drawGameplaySky(lowT1.context2D, 200, 120, villa, 10.0,
          seed: 42, detailScale: 0.25);
      final d0 = lowT0.context2D.getImageData(0, 0, 200, 120).data.toDart;
      final d1 = lowT1.context2D.getImageData(0, 0, 200, 120).data.toDart;
      int diffs = 0;
      for (int i = 0; i < d0.length; i += 4) {
        if (d0[i] != d1[i] || d0[i + 1] != d1[i + 1] || d0[i + 2] != d1[i + 2]) {
          diffs++;
        }
      }
      expect(diffs, equals(0),
          reason: 'LOW quality skybox should blit only cached staticSky with zero animated loops');

      // Also exercise Particles & Hyper drawing under LOW quality tier without error!
      worldA.performanceGovernor.setTierForTest(QualityTier.low);
      worldA.drawFps().setFpsForTest(22.0);
      final LocalPlayerSprite player =
          worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final Particles rocketTrail = Particles(
        worldA,
        null,
        Vec2(60.0, 60.0),
        Vec2(120.0, 0.0),
        count: 20,
        lifeTime: 40,
      );
      final Hyper hyper = Hyper.createWithOwner(worldA, player, 30, player.gun);
      final FakeCanvas canvas = FakeCanvas();
      rocketTrail.draw(canvas.context2D, false);
      hyper.draw(canvas.context2D, false);
    });

    test('Commander sheds rendering detail earlier and more aggressively than a client', () {
      final PerformanceGovernor clientGov = PerformanceGovernor();
      final PerformanceGovernor commanderGov = PerformanceGovernor();

      // At 50.5 FPS for 0.6s: Client (>= 48 FPS) stays HIGH (1.0), whereas
      // Commander (< 53 FPS for >= 0.50s) has already stepped down to MEDIUM (0.50)!
      for (int i = 0; i < 6; i++) {
        clientGov.update(0.10, 50.5, isCommander: false);
        commanderGov.update(0.10, 50.5, isCommander: true);
      }
      expect(clientGov.tier, equals(QualityTier.high));
      expect(clientGov.detailScaleForRole(isCommander: false), equals(1.0));
      expect(commanderGov.tier, equals(QualityTier.medium));
      expect(commanderGov.detailScaleForRole(isCommander: true), closeTo(0.50, 1e-6));

      // At 37 FPS for another 0.6s: Client (>= 34 FPS) is MEDIUM (0.60), whereas
      // Commander (< 40 FPS) has already stepped down to LOW (0.20)!
      for (int i = 0; i < 10; i++) {
        clientGov.update(0.10, 37.0, isCommander: false);
        commanderGov.update(0.10, 37.0, isCommander: true);
      }
      expect(clientGov.tier, equals(QualityTier.medium));
      expect(clientGov.detailScaleForRole(isCommander: false), closeTo(0.60, 1e-6));
      expect(commanderGov.tier, equals(QualityTier.low));
      expect(commanderGov.detailScaleForRole(isCommander: true), closeTo(0.20, 1e-6));
    });

    test('PerformanceGovernor lowers rendering detail FIRST before lowering network FPS on connections', () async {
      final PerformanceGovernor gov = PerformanceGovernor();
      final ConnectionFrameHandler handler =
          ConnectionFrameHandler(ConfigParams({}));
      final bool prevDisable = ConnectionFrameHandler.DISABLE_AUTO_ADJUST_FOR_TEST;
      ConnectionFrameHandler.DISABLE_AUTO_ADJUST_FOR_TEST = false;
      try {
        // 1. Brief dip while still in HIGH tier -> network FPS stays at full 15!
        gov.update(0.20, 42.0);
        expect(gov.tier, equals(QualityTier.high));
        expect(gov.targetNetworkFrameRate(), equals(15));

        // 2. Steps rendering down to MEDIUM, and lowering draw work keeps FPS ~46 ->
        // network FPS STILL stays at full 15!
        for (int i = 0; i < 8; i++) {
          gov.update(0.12, 46.0);
        }
        expect(gov.tier, equals(QualityTier.medium));
        expect(gov.targetNetworkFrameRate(), equals(15),
            reason: 'Draw detail should absorb moderate dips while keeping 15 Hz network FPS');
        handler.reportFrameRates(60.0, gov.equivalentDrawFpsForNetwork());
        expect(handler.currentFrameRate(), equals(15));

        // 3. Even after dropping rendering to LOW, if FPS remains severely low (~22 FPS),
        // PerformanceGovernor now lowers network FPS down to MIN_FRAMERATE (6 Hz)!
        for (int i = 0; i < 15; i++) {
          gov.update(0.12, 22.0);
        }
        expect(gov.tier, equals(QualityTier.low));
        expect(gov.targetNetworkFrameRate(), equals(6));
        handler.reportFrameRates(60.0, gov.equivalentDrawFpsForNetwork());
        expect(handler.currentFrameRate(), equals(6));

        // 4. End-to-end live two-peer connection test: moderate Commander FPS dip (47 FPS)
        // lowers Commander visual tier to MEDIUM while keeping connection at 15 Hz,
        // then severe FPS drop (22 FPS) lowers connection to 6 Hz!
        throwIfLoggingUnexpected = false;
        final WormWorld worldA = await createTestWorld('a');
        final WormWorld worldB = await createTestWorld('b');
        // Re-enable auto-adjust after createTestWorld (which sets DISABLE_AUTO_ADJUST_FOR_TEST = true).
        ConnectionFrameHandler.DISABLE_AUTO_ADJUST_FOR_TEST = false;
        worldA.network().disableCommandTransferHeuristicForTest = true;
        worldB.network().disableCommandTransferHeuristicForTest = true;
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
        worldA.startAsServer('playerA');
        worldA.frameDraw(0.1);
        worldB.connectTo('a', 'playerB');
        for (int i = 0; i < 5; i++) {
          worldA.frameDraw(KEY_FRAME_DEFAULT);
          worldB.frameDraw(KEY_FRAME_DEFAULT);
        }

        final ConnectionWrapper connToB = worldA.network().peer.connections['b']!;
        expect(connToB.currentFrameRate(), equals(15));

        worldA.drawFps().setFpsForTest(47.0);
        for (int i = 0; i < 8; i++) {
          worldA.frameDraw(0.12);
          worldB.frameDraw(0.12);
        }
        expect(worldA.qualityTier, equals(QualityTier.medium));
        expect(connToB.currentFrameRate(), equals(15),
            reason: 'Connection stays at 15 Hz while Commander drops visual detail first');

        worldA.drawFps().setFpsForTest(22.0);
        for (int i = 0; i < 20; i++) {
          worldA.frameDraw(0.12);
          worldB.frameDraw(0.12);
        }
        expect(worldA.qualityTier, equals(QualityTier.low));
        expect(connToB.currentFrameRate(), equals(6),
            reason: 'Connection drops to 6 Hz once visuals are already LOW and FPS stays low');
      } finally {
        ConnectionFrameHandler.DISABLE_AUTO_ADJUST_FOR_TEST = prevDisable;
      }
    });
  });
}
