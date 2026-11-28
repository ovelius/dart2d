import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart2d/net/net.dart';
import 'package:web/web.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:test/test.dart';

import 'lib/test_env.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';

LocalPlayerSprite _addEnemyPlayer(
    WormWorld world, String connId, int netId, Vec2 pos) {
  world.network().getGameState().updateWithLocalKeyState(connId, KeyState());
  final LocalPlayerSprite enemy = LocalPlayerSprite(
    world,
    world.imageIndex(),
    null,
    PlayerInfoProto()
      ..name = connId
      ..connectionId = connId
      ..spriteId = netId
      ..inGame = true,
    pos,
    2,
  )..networkId = netId;
  world.spriteIndex[netId] = enemy;
  return enemy;
}

void main() {
  setUpAll(() {
    configureDependencies();
  });

  group('Mega Shark ultimate powerup weapon', () {
    test('Is a rare 1-shot mystery weapon that is rarer in roulette rolls', () async {
      final WormWorld world = await createTestWorld('sh1');
      world.startAsServer('name1');
      final LocalPlayerSprite player = world.playerSprite!;
      final WeaponState ws = player.weaponState!;

      final int sharkIdx = ws.weapons.indexWhere((w) => w.name == 'Mega Shark');
      expect(sharkIdx, greaterThanOrEqualTo(0));
      final sharkWeapon = ws.weapons[sharkIdx];
      expect(sharkWeapon.isMysteryWeapon, isTrue);
      expect(sharkWeapon.shotsPerClip, equals(1));
      expect(sharkWeapon.mysteryWeight, lessThan(1.0));

      int sharkRolls = 0;
      const int totalRolls = 400;
      for (int i = 0; i < totalRolls; i++) {
        ws.cancelMysteryRoulette();
        for (final w in ws.weapons) {
          if (w.isMysteryWeapon) {
            w.unlocked = false;
            w.shotsLeft = 0;
          }
        }
        final int picked = ws.triggerMysteryRoulette();
        if (picked == sharkIdx) sharkRolls++;
      }
      final double uniformShare = 1.0 / ws.mysteryWeaponIndices().length;
      expect(sharkRolls / totalRolls, lessThan(uniformShare));
    });

    test('Carried shark is visible to all players when selected and ready, and clears on fire',
        () async {
      throwIfLoggingUnexpected = false;
      final WormWorld worldA = await createTestWorld('sh2');
      final WormWorld worldB = await createTestWorld('sh3');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.drawFps().setFpsForTest(60.0);
      worldB.drawFps().setFpsForTest(60.0);

      worldA.startAsServer('nameA');
      worldA.frameDraw(0.1);
      worldB.connectTo('sh2', 'nameB');
      worldB.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 12; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
      }

      for (final WormWorld w in <WormWorld>[worldA, worldB]) {
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(600, 400));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
      }

      final LocalPlayerSprite playerAOnA = worldA.playerSprite!;
      final int sharkIdx = playerAOnA.weaponState!.weapons
          .indexWhere((w) => w.name == 'Mega Shark');

      playerAOnA.weaponState!.triggerMysteryRoulette(forcedWeaponIndex: sharkIdx);
      for (int i = 0; i < 40; i++) {
        playerAOnA.weaponState!.think(0.1);
      }
      expect(playerAOnA.weaponState!.selectedWeaponIndex, equals(sharkIdx));
      expect(playerAOnA.isCarryingReadySharkForDisplay(), isTrue);

      final ExtraSpriteData synced = playerAOnA.addExtraNetworkData();
      final LocalPlayerSprite? playerAOnB =
          worldB.spriteIndex[playerAOnA.networkId!] as LocalPlayerSprite?;
      expect(playerAOnB, isNotNull);
      playerAOnB!.parseExtraNetworkData(synced);
      expect(playerAOnB.isCarryingReadySharkForDisplay(), isTrue);

      // Verify carried shark renders frame 1 (bare eyes, no sunglasses), not frame 0!
      final HTMLCanvasElement sheetCanvas = HTMLCanvasElement()
        ..width = 250
        ..height = 50;
      sheetCanvas.context2D.fillStyle = 'rgba(255, 0, 0, 1.0)'.toJS; // Frame 0 = red
      sheetCanvas.context2D.fillRect(0, 0, 50, 50);
      sheetCanvas.context2D.fillStyle = 'rgba(0, 120, 255, 1.0)'.toJS; // Frame 1 = blue
      sheetCanvas.context2D.fillRect(50, 0, 50, 50);
      final HTMLImageElement sheetImg = HTMLImageElement()
        ..src = sheetCanvas.toDataUrl('image/png');
      await sheetImg.onLoad.first;
      final int sharkImgId = worldA.imageIndex().getImageIdByName('shark.png');
      final HTMLImageElement prevImg = worldA.imageIndex().images[sharkImgId];
      worldA.imageIndex().images[sharkImgId] = sheetImg;
      playerAOnA.setCenter(Vec2(120.0, 140.0));
      final HTMLCanvasElement drawCanvas = HTMLCanvasElement()
        ..width = 260
        ..height = 260;
      playerAOnA.draw(drawCanvas.context2D, false);
      worldA.imageIndex().images[sharkImgId] = prevImg;
      final Uint8ClampedList rgba =
          drawCanvas.context2D.getImageData(0, 0, 260, 260).data.toDart;
      int bluePixels = 0;
      int redPixels = 0;
      for (int idx = 0; idx < rgba.length; idx += 4) {
        if (rgba[idx + 3] > 200) {
          if (rgba[idx + 2] > 200 && rgba[idx] < 60) bluePixels++;
          if (rgba[idx] > 200 && rgba[idx + 2] < 60) redPixels++;
        }
      }
      expect(bluePixels, greaterThan(50));
      expect(redPixels, equals(0));

      // Also verify WeaponState.draw hides reticle AND magazine indicator above player!
      playerAOnA.weaponState!.changeTime = 0.0;
      final HTMLCanvasElement hudCanvas = HTMLCanvasElement()
        ..width = 260
        ..height = 260;
      playerAOnA.weaponState!.draw(hudCanvas.context2D);
      final Uint8ClampedList hudRgba =
          hudCanvas.context2D.getImageData(0, 0, 260, 260).data.toDart;
      int hudPixels = 0;
      for (int idx = 3; idx < hudRgba.length; idx += 4) {
        if (hudRgba[idx] > 0) hudPixels++;
      }
      expect(hudPixels, equals(0));

      playerAOnA.weaponState!.fire();
      worldA.frameDraw(0.01);
      expect(playerAOnA.isCarryingReadySharkForDisplay(), isFalse);
      final ExtraSpriteData afterFire = playerAOnA.addExtraNetworkData();
      playerAOnB.parseExtraNetworkData(afterFire);
      expect(playerAOnB.isCarryingReadySharkForDisplay(), isFalse);

      final List<HunterSharkProjectile> sharks = worldA.spriteIndex.spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<HunterSharkProjectile>()
          .toList();
      expect(sharks.length, equals(1));
    });

    test('Intro uses bare-eye frame + sunflare, then hunts nearest hostile at 2/3 speed',
        () async {
      final WormWorld world = await createTestWorld('sh4');
      world.startAsServer('name4');
      final LocalPlayerSprite owner = world.playerSprite!;
      owner.setCenter(Vec2(100.0, 200.0));

      final LocalPlayerSprite nearTarget =
          _addEnemyPlayer(world, 'enemy1', 5001, Vec2(320.0, 200.0));
      _addEnemyPlayer(world, 'enemy2', 5002, Vec2(540.0, 200.0));

      final HunterSharkProjectile shark = HunterSharkProjectile.createWithOwner(
        world,
        owner,
        owner.gun,
      );
      world.addSprite(shark);

      expect(shark.size.x, greaterThan(LocalPlayerSprite.DEFAULT_PLAYER_SIZE.x));
      expect(shark.health, equals(LocalPlayerSprite.MAX_HEALTH));
      expect(shark.explodeAfter, closeTo(60.0, 0.01));

      // Frame 1 (bare eyes) while sunglasses slide down (50% longer intro).
      shark.frame(0.60, 1);
      expect(shark.isInSunglassesIntro, isTrue);
      expect(shark.activeSpriteFrameIndex(), equals(1));
      expect(shark.sunglassesProgress, closeTo(0.60 / 1.275, 0.02));
      expect(shark.sunflareProgress, equals(0.0));
      expect(shark.velocity.sum(), equals(0.0));

      // Frame 0 + sunflare when sunglasses snap on.
      shark.frame(0.90, 1);
      expect(shark.isInSunglassesIntro, isTrue);
      expect(shark.activeSpriteFrameIndex(), equals(0));
      expect(shark.sunglassesProgress, equals(1.0));
      expect(shark.sunflareProgress, greaterThan(0.0));
      expect(shark.velocity.sum(), equals(0.0));

      // After intro ends: hunts nearTarget at 2/3 player speed (100.0).
      shark.frame(0.60, 1);
      expect(shark.isInSunglassesIntro, isFalse);
      expect(shark.activeSpriteFrameIndex(), equals(0));
      expect(shark.nearestHostileTarget(), equals(nearTarget));
      expect(shark.velocity.sum(), closeTo(HunterSharkProjectile.SWIM_SPEED, 2.0));
      expect(HunterSharkProjectile.SWIM_SPEED,
          closeTo(LocalPlayerSprite.MAX_WALK_SPEED * (2.0 / 3.0), 0.1));
      expect(shark.velocity.x, greaterThan(0.0));

      // Verify no visible health or timer bars are drawn when rendering the shark.
      final HTMLCanvasElement sharkCanvas = HTMLCanvasElement()
        ..width = 300
        ..height = 300;
      shark.setCenter(Vec2(150.0, 150.0));
      final int sharkImgId = world.imageIndex().getImageIdByName('shark.png');
      final HTMLImageElement prevImg = world.imageIndex().images[sharkImgId];
      world.imageIndex().images[sharkImgId] = HTMLImageElement();
      shark.draw(sharkCanvas.context2D, false);
      world.imageIndex().images[sharkImgId] = prevImg;
      final Uint8ClampedList barPixels =
          sharkCanvas.context2D.getImageData(0, 0, 300, 300).data.toDart;
      int nonZeroAlpha = 0;
      for (int idx = 3; idx < barPixels.length; idx += 4) {
        if (barPixels[idx] > 0) nonZeroAlpha++;
      }
      expect(nonZeroAlpha, equals(0));
    });

    test('Chews through terrain at half speed toward locked player', () async {
      final WormWorld world = await createTestWorld('sh5');
      world.startAsServer('name5');
      world.byteWorld.setWorldImage(
          world.imageIndex().imageFactory.createWithSize(600, 400));
      while (!world.byteWorld.bedrockComputed()) {
        world.byteWorld.bedrockStep();
      }
      world.byteWorld.fillRectAt(Vec2(120.0, 140.0), Vec2(60.0, 80.0), '#664422');
      expect(world.byteWorld.isSolid(150, 180), isTrue);

      final LocalPlayerSprite owner = world.playerSprite!;
      owner.setCenter(Vec2(100.0, 180.0));

      _addEnemyPlayer(world, 'enemy3', 5003, Vec2(260.0, 180.0));

      final HunterSharkProjectile shark = HunterSharkProjectile.createWithOwner(
        world,
        owner,
        owner.gun,
      );
      shark.setCenter(Vec2(150.0, 180.0));
      world.addSprite(shark);

      shark.frame(HunterSharkProjectile.INTRO_DURATION + 0.05, 1);
      shark.frame(0.20, 1);
      expect(shark.isChewingTerrain, isTrue);
      expect(shark.velocity.sum(), closeTo(HunterSharkProjectile.CHEW_SPEED, 1.0));
      expect(world.byteWorld.isSolid(150, 180), isFalse);
    });

    test('Bites only near player center, 50% slower through 5-frame jaw cycle, and owner projectiles destroy own shark',
        () async {
      final WormWorld world = await createTestWorld('sh6');
      world.startAsServer('name6');
      final LocalPlayerSprite owner = world.playerSprite!;
      owner.setCenter(Vec2(80.0, 180.0));

      final LocalPlayerSprite victim =
          _addEnemyPlayer(world, 'enemy4', 5004, Vec2(200.0, 180.0));

      final HunterSharkProjectile shark = HunterSharkProjectile.createWithOwner(
        world,
        owner,
        owner.gun,
      );
      world.addSprite(shark);

      shark.frame(HunterSharkProjectile.INTRO_DURATION + 0.05, 1);
      expect(victim.health, equals(100));

      // Edge-grazing at 32px distance must NOT trigger a bite yet.
      shark.setCenter(victim.centerPoint() + Vec2(-32.0, 0.0));
      shark.collide(victim, null, null);
      expect(victim.health, equals(100));
      expect(shark.isBiting, isFalse);

      // Move close to player center -> bites for 80 damage, stops 1.0s, animates 2 -> 3 (half-closed) -> 4 (shut).
      shark.setCenter(victim.centerPoint() + Vec2(-8.0, 0.0));
      shark.collide(victim, null, null);
      expect(victim.health, equals(20));
      expect(shark.isBiting, isTrue);
      expect(shark.activeSpriteFrameIndex(), equals(2));
      expect(shark.bitePauseRemaining, closeTo(1.00, 0.01));
      expect(shark.velocity.sum(), equals(0.0));

      shark.frame(0.35, 1);
      expect(shark.activeSpriteFrameIndex(), equals(3));
      expect(shark.bitePauseRemaining, greaterThan(0.0));
      expect(shark.velocity.sum(), equals(0.0));

      shark.frame(0.30, 1);
      expect(shark.activeSpriteFrameIndex(), equals(4));
      victim.setCenter(Vec2(380.0, 180.0));

      shark.frame(0.40, 1);
      expect(shark.bitePauseRemaining, equals(0.0));
      expect(shark.velocity.sum(), greaterThan(50.0));

      // Owner's own projectiles collide with and destroy their own shark (and a single dart only deals its 8 dmg).
      final DartProjectile singleDart = DartProjectile.createWithOwner(
        world,
        owner,
        8,
        owner.gun,
      );
      expect(singleDart.shouldDamageTarget(shark), isTrue);
      singleDart.collide(shark, null, null);
      expect(shark.health, equals(92));
      expect(shark.remove, isFalse);
      expect(singleDart.remove, isTrue);

      final WorldDamageProjectile ownShot = WorldDamageProjectile.createWithOwner(
        world,
        owner,
        55,
        positionBase: owner.gun,
      );
      expect(ownShot.shouldDamageTarget(shark), isTrue);
      ownShot.collide(shark, null, null);
      expect(shark.health, equals(37));
      expect(shark.remove, isFalse);

      final Hyper ownHyper = Hyper.createWithOwner(world, owner, 55, owner.gun);
      ownHyper.collide(shark, null, null);
      expect(shark.health, equals(0));
      expect(shark.remove, isTrue);
    });

    test('Collides and bounces with environment when no target is locked',
        () async {
      final WormWorld world = await createTestWorld('sh7');
      world.startAsServer('name7');
      world.byteWorld.setWorldImage(
          world.imageIndex().imageFactory.createWithSize(600, 400));
      while (!world.byteWorld.bedrockComputed()) {
        world.byteWorld.bedrockStep();
      }
      final LocalPlayerSprite owner = world.playerSprite!;
      owner.gun.angle = 0.0;

      final HunterSharkProjectile shark = HunterSharkProjectile.createWithOwner(
        world,
        owner,
        owner.gun,
      );
      world.addSprite(shark);

      shark.frame(HunterSharkProjectile.INTRO_DURATION + 0.05, 1);
      shark.frame(0.05, 1);
      expect(shark.nearestHostileTarget(), isNull);
      expect(shark.velocity.x, greaterThan(0.0));

      // Patrol mode and angled hunting both rotate angle to match velocity heading.
      shark.frame(0.05, 1);
      expect(shark.angle, closeTo(atan2(shark.velocity.y, shark.velocity.x), 0.01));

      shark.collide(null, world.byteWorld, MovingSprite.DIR_RIGHT);
      expect(shark.velocity.x, lessThan(0.0));

      shark.frame(0.05, 1);
      expect(shark.velocity.x, lessThan(0.0));
      expect(shark.angle, closeTo(atan2(shark.velocity.y, shark.velocity.x), 0.01));

      // Angled dive target -> angle follows diagonal velocity heading cleanly.
      final LocalPlayerSprite diveTarget =
          _addEnemyPlayer(world, 'enemy_dive', 5006, Vec2(420.0, 320.0));
      shark.setCenter(Vec2(220.0, 140.0));
      for (int i = 0; i < 8; i++) {
        shark.frame(0.05, 1);
      }
      expect(shark.nearestHostileTarget(), equals(diveTarget));
      expect(shark.velocity.x, greaterThan(0.0));
      expect(shark.velocity.y, greaterThan(0.0));
      expect(shark.angle, closeTo(atan2(shark.velocity.y, shark.velocity.x), 0.05));
    });

    test('Preserves explosion-gained speed until biting a player or chewing terrain',
        () async {
      final WormWorld world = await createTestWorld('sh8');
      world.startAsServer('name8');
      world.byteWorld.setWorldImage(
          world.imageIndex().imageFactory.createWithSize(800, 400));
      while (!world.byteWorld.bedrockComputed()) {
        world.byteWorld.bedrockStep();
      }

      final LocalPlayerSprite owner = world.playerSprite!;
      owner.setCenter(Vec2(80.0, 200.0));
      final LocalPlayerSprite target =
          _addEnemyPlayer(world, 'enemy5', 5005, Vec2(620.0, 200.0));

      final HunterSharkProjectile shark = HunterSharkProjectile.createWithOwner(
        world,
        owner,
        owner.gun,
      );
      shark.setCenter(Vec2(140.0, 200.0));
      world.addSprite(shark);

      // Finish intro and start normal swimming at SWIM_SPEED (100).
      shark.frame(HunterSharkProjectile.INTRO_DURATION + 0.05, 1);
      shark.frame(0.05, 1);
      expect(shark.velocity.sum(), closeTo(HunterSharkProjectile.SWIM_SPEED, 1.0));

      // Nearby explosion knocks speed well above SWIM_SPEED -> must NOT slow down while swimming!
      world.frameDraw(0.01); // flushes pending sprite into spriteIndex
      world.frameDraw(0.01); // registers shark in spatial grid
      world.explosionAt(
        location: shark.centerPoint() + Vec2(-18.0, -4.0),
        damage: 20,
        radius: 60.0,
        damagerDoer: owner,
        mod: Mod.HYPER,
      );
      final double boostedSpeed = shark.velocity.sum();
      expect(boostedSpeed, greaterThan(HunterSharkProjectile.SWIM_SPEED + 40.0));

      for (int i = 0; i < 6; i++) {
        shark.frame(0.05, 1);
        expect(shark.velocity.sum(), closeTo(boostedSpeed, 1.0));
      }

      // 1) Entering solid terrain (biting through terrain) slows it to CHEW_SPEED.
      world.byteWorld.fillRectAt(Vec2(320.0, 140.0), Vec2(90.0, 120.0), '#664422');
      shark.setCenter(Vec2(360.0, 200.0));
      shark.frame(0.05, 1);
      expect(shark.isChewingTerrain, isTrue);
      expect(shark.velocity.sum(), closeTo(HunterSharkProjectile.CHEW_SPEED, 1.0));

      // Boost again in open air, then verify 2) biting a player slows/stops it!
      shark.setCenter(Vec2(500.0, 200.0));
      shark.frame(0.05, 1);
      shark.velocity = Vec2(280.0, 0.0);
      shark.frame(0.05, 1);
      expect(shark.velocity.sum(), closeTo(280.0, 1.0));

      shark.setCenter(target.centerPoint() + Vec2(-6.0, 0.0));
      shark.collide(target, null, null);
      expect(shark.isBiting, isTrue);
      expect(shark.velocity.sum(), equals(0.0));
    });

    test('Client owned player and remote patrolling shark both collide with terrain', () async {
      throwIfLoggingUnexpected = false;
      final WormWorld worldA = await createTestWorld('a');
      final WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;

      for (final WormWorld w in [worldA, worldB]) {
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(500, 300));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
        w.byteWorld.fillRectAt(Vec2(0.0, 200.0), Vec2(500.0, 100.0), '#444444');
      }

      worldA.startAsServer('nameA');
      worldA.frameDraw(0.1);
      worldB.connectTo('a', 'nameB');
      worldB.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Client's own LocalPlayerSprite must have collision enabled and stop on terrain,
      // while non-owned remote player sprites on client remain non-colliding.
      final LocalPlayerSprite clientSelf =
          worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite commanderOnClient =
          worldB.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(worldB.isCommander, isFalse);
      expect(clientSelf.inGame(), isTrue);
      expect(clientSelf.collision, isTrue);
      expect(commanderOnClient.collision, isFalse);

      clientSelf.position = Vec2(120.0, 200.0 - clientSelf.size.y - 4.0);
      clientSelf.velocity = Vec2(0.0, 120.0);
      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.03);
      }
      expect(clientSelf.position.y + clientSelf.size.y, lessThanOrEqualTo(202.0),
          reason: 'Client player must collide with solid floor and not fall through');

      // Also verify a REMOTE patrolling shark on the client bounces off solid terrain.
      final HunterSharkProjectile remoteShark =
          HunterSharkProjectile(worldB, 220.0, 200.0 - HunterSharkProjectile.SHARK_HEIGHT, 0, worldB.imageIndex())
            ..networkType = NetworkType.REMOTE
            ..owner = null;
      commanderOnClient.info.inGame = false;
      clientSelf.info.inGame = false;
      worldB.addSprite(remoteShark);
      remoteShark.setCenter(Vec2(220.0, 200.0 - HunterSharkProjectile.SHARK_HEIGHT * 0.5 + 1.0));
      remoteShark.velocity = Vec2(HunterSharkProjectile.SWIM_SPEED, 80.0);
      // Advance past sunglasses intro so patrol collision is active.
      remoteShark.frame(HunterSharkProjectile.INTRO_DURATION + 0.1, 1);
      remoteShark.velocity = Vec2(HunterSharkProjectile.SWIM_SPEED, 80.0);
      remoteShark.collide(null, worldB.byteWorld, MovingSprite.DIR_BELOW);
      expect(remoteShark.velocity.y, lessThan(0.0),
          reason: 'Remote patrolling shark on client should bounce off world terrain');
    });
  });
}
