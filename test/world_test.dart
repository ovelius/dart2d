import 'package:test/test.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/phys/vec2.dart';

late ByteWorld byteWorld;

void main() {
  setUpAll(() {
    configureDependencies();
  });

  setUp(() {
    logOutputForTest();
    testConnections.clear();
    testPeers.clear();
  });

  group('ByteWorld tests', () {
    test('TestFloodFill', () {
      // TODO: fix.
      // canvas.fillRect(1, 1, 100, 100);
      // expect(WorldPhys.isConnected(byteWorld, 2, 2), equals({'x':1, 'x2':100, 'y':1, 'y2': 100}));
    });
    test('TestDontDrawOutsideScreen', () async {
      WormWorld worldA = await createTestWorld("a");
      worldA.viewPoint = new Vec2();
      worldA.startAsServer("a");
      worldA.frameDraw();
      worldA.spriteIndex[playerId(0)]!.position = new Vec2();
      
      _TestSprite sprite = new _TestSprite.withVecPosition(new Vec2());
      
      worldA.addSprite(sprite);
      worldA.frameDraw();

      expect(sprite.drawCalls, equals(1));
      expect(sprite.frameCalls, equals(1));
      
      sprite.position = new Vec2(worldA.width() * 1.0, worldA.height() * 1.0);
      
      worldA.frameDraw();
      expect(sprite.drawCalls, equals(2));
      expect(sprite.frameCalls, equals(2));
      
      sprite.position = new Vec2(worldA.width() * 1.0 + 1, worldA.height() * 1.0 + 1);
           
      worldA.frameDraw();
      expect(sprite.drawCalls, equals(2));
      expect(sprite.frameCalls, equals(3));
    });

    test('TestVelcityAndDamageFromExplosion', () async {
      WormWorld worldA = await createTestWorld("a");
      worldA.viewPoint = new Vec2();
      worldA.startAsServer("a");
      // Insert player sprite to world.
      worldA.frameDraw();
      // Map out sprites in SpartialGrid.
      worldA.frameDraw();
      LocalPlayerSprite player = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      player.position = new Vec2();
      player.velocity = new Vec2();

      // 10 damage at 0 distance.
      int damageDone = 10;
      worldA.explosionAt(location: player.centerPoint(), damage: damageDone, radius:  10.0, damagerDoer: player);

      expect(player.velocity.x, equals(0));
      expect(player.velocity.y, equals(0));
      expect(player.health, equals(LocalPlayerSprite.MAX_HEALTH - damageDone));

      // 10 damage at 20 distance to the left.
      worldA.explosionAt(location: player.centerPoint() + new Vec2(-40.0, 0), damage: damageDone, radius:  50.0, damagerDoer: player);

      // Momentum to the right.
      expect(player.velocity.x, equals(240.0));
      expect(player.velocity.y, equals(0));
      expect(player.health, equals(
          LocalPlayerSprite.MAX_HEALTH - damageDone - 6));

      player.velocity = new Vec2();
      // 10 damage at 20 distance to the left.
      worldA.explosionAt(location: player.centerPoint() + new Vec2(30.0, 30.0), damage: damageDone, radius:  50.0, damagerDoer: player);
      // Momentum up to the left.
      expect(player.velocity.x.toInt(), equals(-120));
      expect(player.velocity.y.toInt(), equals(-120));
      expect(player.health, equals(
          LocalPlayerSprite.MAX_HEALTH - damageDone - 10));
    });

    test('TestClearAtOutOfBoundsDoesNotThrow', () async {
      WormWorld worldA = await createTestWorld("a");
      ByteWorld bw = worldA.byteWorld;

      // Completely outside each edge, touching edges (width/height == 0), and zero radius.
      bw.clearAt(new Vec2(-50.0, 2.0), 10.0);
      bw.clearAt(new Vec2(-10.0, 2.0), 10.0);
      bw.clearAt(new Vec2(bw.width + 50.0, 2.0), 10.0);
      bw.clearAt(new Vec2(bw.width + 10.0, 2.0), 10.0);
      bw.clearAt(new Vec2(2.0, -50.0), 10.0);
      bw.clearAt(new Vec2(2.0, -10.0), 10.0);
      bw.clearAt(new Vec2(2.0, bw.height + 50.0), 10.0);
      bw.clearAt(new Vec2(2.0, bw.height + 10.0), 10.0);
      bw.clearAt(new Vec2(2.0, 2.0), 0.0);
    });

    test('TestBrickBuilderAlignsWithSurroundingBricks', () async {
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("a");
      worldA.frameDraw();

      // Use a large enough blank ByteWorld for multi-brick alignment tests.
      ByteWorld bw = worldA.byteWorld;
      bw.setWorldImage(worldA.imageIndex().imageFactory.createWithSize(500, 300));
      while (!bw.bedrockComputed()) {
        bw.bedrockStep();
      }
      LocalPlayerSprite player = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;

      bool isBrickPixel(int x, int y) {
        var px = bw.getImageDataFor(x, y, 1, 1);
        return px[0] == BrickBuilder.COLOR_R &&
            px[1] == BrickBuilder.COLOR_G &&
            px[2] == BrickBuilder.COLOR_B &&
            px[3] > 200;
      }

      bool isWhiteMortar(int x, int y) {
        var px = bw.getImageDataFor(x, y, 1, 1);
        return px[0] == 255 && px[1] == 255 && px[2] == 255 && px[3] > 200;
      }

      void fireBrickAt(double cx, double cy, double vx, double vy) {
        BrickBuilder b = BrickBuilder.createWithOwner(worldA, player, 2, player.gun);
        b.position = new Vec2(cx - b.size.x / 2, cy - b.size.y / 2);
        b.velocity = new Vec2(vx, vy);
        b.explode();
      }

      const int bwW = BrickBuilder.BRICK_WIDTH;
      const int bwH = BrickBuilder.BRICK_HEIGHT;
      const int stepX = BrickBuilder.STEP_X;
      const int stepY = BrickBuilder.STEP_Y;
      const int baseX = 200;
      const int baseY = 150;

      // 1. Place base brick with origin (baseX, baseY).
      fireBrickAt(baseX + bwW / 2, baseY + bwH / 2, 0.0, 100.0);
      expect(isBrickPixel(baseX, baseY), isTrue);
      expect(isBrickPixel(baseX + bwW - 1, baseY + bwH - 1), isTrue);
      expect(isWhiteMortar(baseX - 1, baseY), isTrue);
      expect(isWhiteMortar(baseX + bwW, baseY), isTrue);

      // 2. Hit slightly off-center on top edge -> aligns directly above with 1px mortar at y = baseY - 1.
      fireBrickAt(baseX + bwW * 0.7, baseY - 2.0, 0.0, 500.0);
      expect(isBrickPixel(baseX, baseY - stepY), isTrue);
      expect(isBrickPixel(baseX + bwW - 1, baseY - 2), isTrue);
      expect(isWhiteMortar(baseX + bwW ~/ 2, baseY - 1), isTrue);
      expect(isBrickPixel(baseX + bwW ~/ 2, baseY), isTrue); // Original brick top row untouched.

      // 3. Hit bottom edge -> aligns directly below with 1px mortar at y = baseY + bwH.
      fireBrickAt(baseX + bwW * 0.25, baseY + bwH + 1.0, 0.0, -500.0);
      expect(isBrickPixel(baseX, baseY + stepY), isTrue);
      expect(isBrickPixel(baseX + bwW - 1, baseY + stepY + bwH - 1), isTrue);
      expect(isWhiteMortar(baseX + bwW ~/ 2, baseY + bwH), isTrue);

      // 4. Hit right edge -> aligns directly to the right with 1px mortar at x = baseX + bwW.
      fireBrickAt(baseX + bwW + 2.0, baseY + bwH / 2, -500.0, 0.0);
      expect(isBrickPixel(baseX + stepX, baseY), isTrue);
      expect(isBrickPixel(baseX + stepX + bwW - 1, baseY + bwH - 1), isTrue);
      expect(isWhiteMortar(baseX + bwW, baseY + bwH ~/ 2), isTrue);

      // 5. High-speed shot from left penetrating slightly inside base brick near top-left -> aligns to LEFT.
      fireBrickAt(baseX + 6.0, baseY + 2.0, 500.0, 0.0);
      expect(isBrickPixel(baseX - stepX, baseY), isTrue);
      expect(isBrickPixel(baseX - 2, baseY + bwH - 1), isTrue);
      expect(isWhiteMortar(baseX - 1, baseY + bwH ~/ 2), isTrue);

      // 6. Hit top of the right-hand brick even after cratering its right end -> recovers left mortar edge and aligns above.
      bw.clearAt(new Vec2((baseX + stepX + bwW - 5).toDouble(), (baseY + bwH / 2).toDouble()), 10.0);
      fireBrickAt(baseX + stepX + 12.0, baseY - 2.0, 0.0, 500.0);
      expect(isBrickPixel(baseX + stepX, baseY - stepY), isTrue);
      expect(isBrickPixel(baseX + stepX + bwW - 1, baseY - 2), isTrue);
      expect(isWhiteMortar(baseX + bwW, baseY - stepY + bwH ~/ 2), isTrue); // Aligned cleanly with top-center brick's mortar!
    });

    test('TestRealisticDestructionScorchesSamplesAndSpawnsDebris', () async {
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("a");
      worldA.frameDraw();

      ByteWorld bw = worldA.byteWorld;
      bw.setWorldImage(worldA.imageIndex().imageFactory.createWithSize(300, 300));
      while (!bw.bedrockComputed()) {
        bw.bedrockStep();
      }
      // Paint solid bright green terrain across the center.
      bw.fillRectAt(Vec2(40.0, 40.0), Vec2(220.0, 220.0), "rgb(100, 190, 80)");

      // Blast a 35px crater in the middle.
      worldA.clearWorldArea(Vec2(150.0, 150.0), 35.0, Vec2(10.0, -10.0));
      worldA.frameDraw(0.05);

      // Center of crater must be carved hollow (not solid).
      expect(bw.isSolid(150, 150), isFalse);

      // Verify a TerrainDebrisEffect was spawned with sampled terrain chunks.
      bool hasDebris = worldA.spriteIndex
          .spriteIds()
          .any((id) => worldA.spriteIndex[id] is TerrainDebrisEffect);
      expect(hasDebris, isTrue, reason: "Expected TerrainDebrisEffect on solid terrain blast");

      // Verify the rim right outside the carved edge is darkened/scorched vs intact terrain.
      var intactPx = bw.getImageDataFor(50, 50, 1, 1);
      int intactLuma = intactPx[0] + intactPx[1] + intactPx[2];
      bool foundScorchedRim = false;
      for (int dx = 28; dx <= 46; dx++) {
        if (bw.isSolid(150 + dx, 150)) {
          var rimPx = bw.getImageDataFor(150 + dx, 150, 1, 1);
          if (rimPx[0] + rimPx[1] + rimPx[2] < intactLuma - 30) {
            foundScorchedRim = true;
          }
          break;
        }
      }
      expect(foundScorchedRim, isTrue, reason: "Expected charred scorch darkening on crater rim");

      // Advance past debris lifetime and verify cleanup.
      for (int i = 0; i < 35; i++) {
        worldA.frameDraw(0.05);
      }
      expect(
          worldA.spriteIndex.spriteIds().any((id) => worldA.spriteIndex[id] is TerrainDebrisEffect),
          isFalse);
    });

    test('TestDebrisScaledByExplosionTypeAndFps', () async {
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("a");
      worldA.frameDraw();

      ByteWorld bw = worldA.byteWorld;
      bw.setWorldImage(worldA.imageIndex().imageFactory.createWithSize(400, 400));
      while (!bw.bedrockComputed()) {
        bw.bedrockStep();
      }
      bw.fillRectAt(Vec2(20.0, 20.0), Vec2(360.0, 360.0), "rgb(120, 160, 90)");

      // 1. Full explosion at 60 FPS -> full debris count.
      worldA.drawFps().setFpsForTest(60.0);
      worldA.clearWorldArea(Vec2(100.0, 100.0), 40.0, Vec2.ZERO, true);
      worldA.frameDraw(0.01);
      TerrainDebrisEffect fullDebris = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<TerrainDebrisEffect>()
          .last;
      expect(fullDebris.chunkCount, greaterThanOrEqualTo(10));

      // 2. Carving (non-exploding) hit at 60 FPS -> heavily reduced debris.
      worldA.clearWorldArea(Vec2(220.0, 100.0), 19.0, Vec2.ZERO, false);
      worldA.frameDraw(0.01);
      TerrainDebrisEffect carveDebris = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<TerrainDebrisEffect>()
          .last;
      expect(carveDebris.chunkCount, lessThanOrEqualTo(3));
      expect(carveDebris.chunkCount, lessThan(fullDebris.chunkCount));

      // 3. Low FPS (< 25) -> skips spawning debris completely.
      int beforeCount = worldA.spriteIndex
          .spriteIds()
          .where((id) => worldA.spriteIndex[id] is TerrainDebrisEffect)
          .length;
      worldA.drawFps().setFpsForTest(20.0);
      worldA.clearWorldArea(Vec2(300.0, 200.0), 40.0, Vec2.ZERO, true);
      worldA.frameDraw(0.01);
      int afterCount = worldA.spriteIndex
          .spriteIds()
          .where((id) => worldA.spriteIndex[id] is TerrainDebrisEffect)
          .length;
      expect(afterCount, equals(beforeCount));

      // 4. Mid FPS (30) -> reduced debris budget compared to 60 FPS.
      worldA.drawFps().setFpsForTest(30.0);
      worldA.clearWorldArea(Vec2(100.0, 260.0), 40.0, Vec2.ZERO, true);
      worldA.frameDraw(0.01);
      TerrainDebrisEffect lowFpsDebris = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<TerrainDebrisEffect>()
          .last;
      expect(lowFpsDebris.chunkCount, lessThan(fullDebris.chunkCount));
      expect(lowFpsDebris.chunkCount, greaterThan(0));
    });

    test('TestDeathCameraZoomOutAndZoomInOnSpawn', () async {
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("a");
      worldA.frameDraw();

      // Use a battlefield larger than the viewport so zooming out reveals the whole map.
      ByteWorld bw = worldA.byteWorld;
      int mapW = (worldA.width() * 2).toInt();
      int mapH = (worldA.height() * 2).toInt();
      bw.setWorldImage(worldA.imageIndex().imageFactory.createWithSize(mapW, mapH));
      while (!bw.bedrockComputed()) {
        bw.bedrockStep();
      }
      double expectedMinZoom = 0.5;

      LocalPlayerSprite player = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      // Finish initial 1.0s match-join spawn so player is alive in game first.
      for (int i = 0; i < 12; i++) {
        worldA.frameDraw(0.1);
      }
      expect(player.inGame(), isTrue);
      expect(worldA.cameraZoom, closeTo(1.0, 0.001));

      // Kill the player.
      player.takeDamage(LocalPlayerSprite.MAX_HEALTH + 10, player, Mod.ZOOKA);
      expect(player.inGame(), isFalse);

      // Early in death (0.3s): stay zoomed in to watch the KO pop.
      for (int i = 0; i < 15; i++) {
        worldA.frameDraw(0.02);
      }
      expect(worldA.cameraZoom, closeTo(1.0, 0.01));

      // Mid-death (~2.2s elapsed): zoomed all the way out to reveal the entire battlefield.
      for (int i = 0; i < 95; i++) {
        worldA.frameDraw(0.02);
      }
      expect(worldA.cameraZoom, closeTo(expectedMinZoom, 0.02));

      // Sprites at far corners of the battlefield should be drawn while zoomed out.
      _TestSprite farSprite = _TestSprite.withVecPosition(Vec2(mapW - 10.0, mapH - 10.0));
      expect(worldA.shouldDraw(farSprite), isTrue);

      // Zoom-in phase (~3.8s elapsed): camera is zooming back in toward the new spawn point.
      for (int i = 0; i < 80; i++) {
        worldA.frameDraw(0.02);
      }
      expect(worldA.cameraZoom, greaterThan(expectedMinZoom + 0.1));
      expect(worldA.cameraZoom, lessThan(1.0));

      // Complete respawn (~5.1s elapsed): player is back in game at full 1.0 zoom.
      for (int i = 0; i < 70; i++) {
        worldA.frameDraw(0.02);
      }
      expect(player.inGame(), isTrue);
      expect(worldA.cameraZoom, closeTo(1.0, 0.001));
    });
  });
}

class _TestSprite extends MovingSprite {
  int drawCalls = 0;
  int frameCalls = 0;
  _TestSprite.withVecPosition(Vec2 position)
        : super(position, new Vec2(1.0, 1.0), SpriteType.RECT);
  
  @override
  frame(double duration, int frameStep, [Vec2? gravity]) {
    frameCalls++;
  }
  
  @override
  draw(var context, bool debug) {
    drawCalls++;
  }
}
