import 'dart:math';

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/worlds/powerup_manager.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:test/test.dart';

import 'lib/test_factories.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';

void main() {
  setUpAll(() {
    configureDependencies();
  });

  setUp(() {
    logOutputForTest();
    configParameters.clear();
    clearEnvironment();
  });

  tearDown(() {
    configParameters.clear();
    clearEnvironment();
  });

  group('Weapon overhaul: starter loadout, mystery roulette, balance, and sandbox mode', () {
    test('Default loadout restricts selection to 4 starter weapons and applies Snailgun & Turbo Mole balance', () async {
      final WormWorld world = await createTestWorld('a');
      world.startAsServer('a');
      world.frameDraw(0.6);
      world.frameDraw(0.6);

      final LocalPlayerSprite player =
          world.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final WeaponState ws = player.weaponState!;

      // 1. Only Brick builder, Shotgun, Dart gun, and Zooka are selectable by default.
      final List<String> starterNames = ws
          .availableWeaponIndices()
          .map((int i) => ws.weapons[i].name)
          .toList();
      expect(
        starterNames,
        unorderedEquals(<String>[
          'Brick builder',
          'Shotgun',
          'Dart gun',
          'Zooka',
        ]),
      );

      // Cycling nextWeapon / prevWeapon never lands on a locked mystery weapon.
      final Set<String> visitedNext = <String>{};
      for (int i = 0; i < 12; i++) {
        ws.nextWeapon();
        visitedNext.add(ws.selectedWeaponName);
        expect(ws.getSelectedWeapon().isMysteryWeapon, isFalse);
      }
      expect(visitedNext, hasLength(4));

      final Set<String> visitedPrev = <String>{};
      for (int i = 0; i < 12; i++) {
        ws.prevWeapon();
        visitedPrev.add(ws.selectedWeaponName);
        expect(ws.getSelectedWeapon().isMysteryWeapon, isFalse);
      }
      expect(visitedPrev, hasLength(4));

      // Radial wheel selector only picks from the 4 starter weapons.
      for (int a = 0; a < 16; a++) {
        final double angle = (pi * 2 / 16) * a;
        ws.weaponStateSelector(
            Point<int>((cos(angle) * 120).round(), (sin(angle) * 120).round()));
        expect(ws.getSelectedWeapon().isMysteryWeapon, isFalse);
      }

      // 2. Balance checks:
      // - Snailgun: magazine lowered (4 -> 3) and half fire rate (fireDelay 0.3 -> 0.6).
      final Weapon snailgun =
          ws.weapons.firstWhere((Weapon w) => w.name == 'Snailgun');
      expect(snailgun.isMysteryWeapon, isTrue);
      expect(snailgun.shotsPerClip, equals(3));
      expect(snailgun.fireDelay, closeTo(0.6, 1e-6));

      // - Turbo Mole: magazine doubled (2 -> 4).
      final Weapon mole =
          ws.weapons.firstWhere((Weapon w) => w.name == 'Turbo Mole');
      expect(mole.isMysteryWeapon, isTrue);
      expect(mole.shotsPerClip, equals(4));
    });

    test('Mystery powerup spins Mario Kart roulette with sounds, grants one-time magazine, and disappears when empty', () async {
      final WormWorld world = await createTestWorld('a');
      world.byteWorld
          .setWorldImage(world.imageIndex().imageFactory.createWithSize(800, 500));
      while (!world.byteWorld.bedrockComputed()) {
        world.byteWorld.bedrockStep();
      }
      final Sounds sounds = getIt<Sounds>();
      final FakeSoundFactory soundFactory =
          getIt<SoundFactory>() as FakeSoundFactory;
      sounds.preloadSounds();
      await soundFactory.loadAllAudio();
      soundFactory.resetPlayedSounds();

      world.startAsServer('a');
      world.frameDraw(0.6);
      world.frameDraw(0.6);

      final LocalPlayerSprite player =
          world.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final WeaponState ws = player.weaponState!;
      final FakeCanvas canvas = FakeCanvas();

      // Remember starter weapon ("Dart gun") before picking up mystery box.
      final int dartIdx =
          ws.weapons.indexWhere((Weapon w) => w.name == 'Dart gun');
      ws.selectedWeaponIndex = dartIdx;
      ws.nextWeapon();
      ws.prevWeapon();
      expect(ws.selectedWeaponIndex, equals(dartIdx));

      // Collide with PowerUpType.POWERUP -> starts roulette spin!
      final Powerup mysteryBox =
          Powerup(Vec2.copy(player.position), PowerUpType.POWERUP, world.imageIndex());
      mysteryBox.collide(player, null, null);
      expect(mysteryBox.remove, isTrue);
      expect(ws.isRouletteSpinning, isTrue);
      expect(ws.isRouletteRevealing, isFalse);

      final int wonIdx = ws.rouletteTargetWeaponIndex;
      expect(wonIdx, greaterThanOrEqualTo(0));
      final Weapon wonWeapon = ws.weapons[wonIdx];
      expect(wonWeapon.isMysteryWeapon, isTrue);
      // Not unlocked yet while wheel is still spinning!
      expect(wonWeapon.unlocked, isFalse);

      // Step through the spin (1.85s total) and verify HUD rendering + tick sounds.
      final Set<int> displayedDuringSpin = <int>{};
      for (int i = 0; i < 18; i++) {
        ws.think(0.10);
        if (ws.isRouletteSpinning) {
          displayedDuringSpin.add(ws.rouletteDisplayWeaponIndex);
        }
        ws.drawWeaponHelper(canvas.context2D, const Point<int>(700, 80), true);
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(displayedDuringSpin.length, greaterThan(3),
          reason: 'Roulette should visibly cycle across multiple mystery weapons');
      expect(soundFactory.getTotalPlayOuts(Sound.ROULETTE_TICK), greaterThan(5),
          reason: 'Roulette should play ticking sounds as slots cycle');

      // Finish the final 0.15s -> lands on winner, plays Sound.ROULETTE_WIN, unlocks & equips!
      ws.think(0.15);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(ws.isRouletteSpinning, isFalse);
      expect(ws.isRouletteRevealing, isTrue);
      expect(soundFactory.getTotalPlayOuts(Sound.ROULETTE_WIN), equals(1));
      expect(wonWeapon.unlocked, isTrue);
      expect(wonWeapon.shotsLeft, equals(wonWeapon.shotsPerClip));
      expect(ws.selectedWeaponIndex, equals(wonIdx));
      expect(ws.availableWeaponIndices(), contains(wonIdx));
      expect(ws.availableWeaponIndices(), hasLength(5));

      // Draw winner reveal celebration banner cleanly.
      ws.drawWeaponHelper(canvas.context2D, const Point<int>(700, 80), true);

      // Drain the entire one-time magazine -> weapon must NOT reload; it disappears
      // immediately and switches back to the starter weapon (Dart gun)!
      final int totalClip = wonWeapon.shotsPerClip;
      for (int shot = 0; shot < totalClip; shot++) {
        wonWeapon.untilNextFire = 0.0;
        ws.fire();
      }
      expect(wonWeapon.shotsLeft, equals(0));
      expect(wonWeapon.unlocked, isFalse);
      expect(wonWeapon.reloading(), isFalse);
      expect(ws.isWeaponAvailable(wonIdx), isFalse);
      expect(ws.availableWeaponIndices(), hasLength(4));
      expect(ws.selectedWeaponIndex, equals(dartIdx),
          reason: 'Depleting one-time mystery magazine should revert to starter weapon');

      // Advancing 20 seconds never reloads or restores the depleted mystery weapon.
      ws.think(20.0);
      expect(wonWeapon.unlocked, isFalse);
      expect(wonWeapon.shotsLeft, equals(0));
      expect(ws.availableWeaponIndices(), hasLength(4));
    });

    test('URL parameter sandbox removes mystery powerups and unlocks all weapons permanently with normal reloads', () async {
      configParameters['sandbox'] = <String>[''];
      final WormWorld world = await createTestWorld('a');
      world.byteWorld
          .setWorldImage(world.imageIndex().imageFactory.createWithSize(800, 500));
      while (!world.byteWorld.bedrockComputed()) {
        world.byteWorld.bedrockStep();
      }
      world.startAsServer('a');
      world.frameDraw(0.6);
      world.frameDraw(0.6);

      expect(world.config().getBool(ConfigParam.SANDBOX), isTrue);
      final PowerupManager pm = world.powerupManager()!;
      expect(pm.mysteryPowerupEnabled, isFalse);
      expect(pm.spawnableTypes, isNot(contains(PowerUpType.POWERUP)));

      // Spawn many random powerups -> PowerUpType.POWERUP never appears in sandbox mode.
      for (int i = 0; i < 30; i++) {
        pm.reset();
        for (int j = 0; j < PowerupManager.MAX_POWERUPS; j++) {
          pm.addNewRandomPowerup();
        }
        for (final Powerup p in pm.activePowerups) {
          expect(p.type, isNot(equals(PowerUpType.POWERUP)));
        }
      }

      // All 14 weapons are selectable at all times in sandbox mode, and mystery
      // weapons reload normally instead of disappearing after one clip!
      final LocalPlayerSprite player =
          world.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final WeaponState ws = player.weaponState!;
      expect(ws.isSandboxMode, isTrue);
      expect(ws.availableWeaponIndices(), hasLength(ws.weapons.length));

      final int snailIdx =
          ws.weapons.indexWhere((Weapon w) => w.name == 'Snailgun');
      ws.selectedWeaponIndex = snailIdx;
      final Weapon snailgun = ws.weapons[snailIdx];
      for (int i = 0; i < snailgun.shotsPerClip; i++) {
        snailgun.untilNextFire = 0.0;
        ws.fire();
      }
      expect(snailgun.shotsLeft, equals(0));
      expect(snailgun.reloading(), isTrue,
          reason: 'In sandbox mode, mystery weapons should reload instead of disappearing');
      expect(ws.selectedWeaponIndex, equals(snailIdx));
      expect(ws.isWeaponAvailable(snailIdx), isTrue);

      ws.think(snailgun.reloadTime + 0.2);
      expect(snailgun.reloading(), isFalse);
      expect(snailgun.shotsLeft, equals(snailgun.shotsPerClip));
    });

    test('Multiplayer client picking up mystery powerup syncs roulette spin, unlocked magazine, and depletion', () async {
      throwIfLoggingUnexpected = false;
      final WormWorld worldA = await createTestWorld('a');
      final WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.drawFps().setFpsForTest(60.0);
      worldB.drawFps().setFpsForTest(60.0);

      worldA.startAsServer('nameA');
      worldA.frameDraw(0.1);
      worldB.connectTo('a', 'nameB');
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
        w.byteWorld.fillRectAt(Vec2(0.0, 320.0), Vec2(600.0, 80.0), '#444444');
      }

      final LocalPlayerSprite playerBOnA =
          worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnB =
          worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBOnB.weaponState!.availableWeaponIndices(), hasLength(4));

      // Force a deterministic 1-shot mystery weapon ("Cat litter box") on commander A
      // when Client B picks up PowerUpType.POWERUP, and verify sync to Client B!
      final int litterIdx = playerBOnA.weaponState!.weapons
          .indexWhere((Weapon w) => w.name == 'Cat litter box');
      playerBOnA.weaponState!.triggerMysteryRoulette(forcedWeaponIndex: litterIdx);
      expect(playerBOnA.weaponState!.isRouletteSpinning, isTrue);

      // Step short 60ms network frames (~0.24s < 1.85s): Client B starts spinning toward the exact same target!
      for (int i = 0; i < 4; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
      }
      expect(playerBOnB.weaponState!.rouletteTargetWeaponIndex, equals(litterIdx));
      expect(playerBOnB.weaponState!.isRouletteSpinning, isTrue);

      // Advance past ROULETTE_SPIN_DURATION (1.85s) on both worlds -> unlocks & equips on both!
      for (int i = 0; i < 36; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
      }
      expect(playerBOnA.weaponState!.isWeaponAvailable(litterIdx), isTrue);
      expect(playerBOnB.weaponState!.isWeaponAvailable(litterIdx), isTrue);
      expect(playerBOnB.weaponState!.selectedWeaponIndex, equals(litterIdx));

      // Client B presses Fire -> spends the 1-shot magazine on commander A and syncs
      // depletion back to Client B so the weapon disappears on both peers!
      worldB.localKeyState.onKeyDown(KeyCodeDart.F);
      for (int i = 0; i < 6; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
      }
      worldB.localKeyState.onKeyUp(KeyCodeDart.F);

      expect(playerBOnA.weaponState!.isWeaponAvailable(litterIdx), isFalse);
      expect(playerBOnB.weaponState!.isWeaponAvailable(litterIdx), isFalse);
      expect(playerBOnB.weaponState!.availableWeaponIndices(), hasLength(4));
      expect(playerBOnB.weaponState!.getSelectedWeapon().isMysteryWeapon, isFalse);
    });

    test('When mystery powerups are enabled, at least half of active and spawned powerups are mystery powerups', () async {
      final WormWorld world = await createTestWorld('a');
      world.byteWorld
          .setWorldImage(world.imageIndex().imageFactory.createWithSize(800, 500));
      while (!world.byteWorld.bedrockComputed()) {
        world.byteWorld.bedrockStep();
      }
      final PowerupManager pm = world.powerupManager()!;
      expect(pm.mysteryPowerupEnabled, isTrue);

      int totalSpawned = 0;
      int totalMystery = 0;
      int totalNonMystery = 0;

      // Verify across 50 full-cap batches that EVERY batch at 2 and 4 active powerups
      // has >= 50% mystery powerups, while other powerups still spawn too!
      for (int trial = 0; trial < 50; trial++) {
        pm.reset();
        pm.addNewRandomPowerup();
        pm.addNewRandomPowerup();
        final int mysteryAtTwo = pm.activePowerups
            .where((Powerup p) => p.type == PowerUpType.POWERUP)
            .length;
        expect(mysteryAtTwo, greaterThanOrEqualTo(1),
            reason: 'At least half (1 of 2) active powerups must be mystery powerups');

        pm.addNewRandomPowerup();
        pm.addNewRandomPowerup();
        expect(pm.activePowerups, hasLength(4));
        final int mysteryAtFour = pm.activePowerups
            .where((Powerup p) => p.type == PowerUpType.POWERUP)
            .length;
        expect(mysteryAtFour, greaterThanOrEqualTo(2),
            reason: 'At least half (2 of 4) active powerups must be mystery powerups');

        totalSpawned += 4;
        totalMystery += mysteryAtFour;
        totalNonMystery += (4 - mysteryAtFour);
      }

      expect(totalMystery, greaterThanOrEqualTo(totalSpawned ~/ 2));
      expect(totalNonMystery, greaterThan(0),
          reason: 'Health, shield, and jetpack powerups should still spawn alongside mystery boxes');
    });

    test('Handicap bingo probabilities scale from 5% Extra / 1% Super for leader up to 80% Superbingo at 50% behind, and Extra Bingo requires < max health', () async {
      // 1. Verify exact probability curve.
      final BingoProbabilities leaderHurt =
          WeaponState.computeBingoProbabilitiesFor(
        playerScore: 6,
        leaderScore: 6,
        maxFrags: 10,
        hasFullHealth: false,
      );
      expect(leaderHurt.extraBingo, closeTo(0.05, 1e-6));
      expect(leaderHurt.superBingo, closeTo(0.01, 1e-6));

      final BingoProbabilities leaderFullHp =
          WeaponState.computeBingoProbabilitiesFor(
        playerScore: 6,
        leaderScore: 6,
        maxFrags: 10,
        hasFullHealth: true,
      );
      expect(leaderFullHp.extraBingo, equals(0.0),
          reason: 'Extra Bingo must be 0% when player already has full health');
      expect(leaderFullHp.superBingo, closeTo(0.01, 1e-6));

      final BingoProbabilities quarterBehind =
          WeaponState.computeBingoProbabilitiesFor(
        playerScore: 4,
        leaderScore: 6,
        maxFrags: 8, // 2/8 = 25% behind
        hasFullHealth: false,
      );
      expect(quarterBehind.superBingo, greaterThan(leaderHurt.superBingo));
      expect(quarterBehind.superBingo, lessThan(0.80));
      expect(quarterBehind.extraBingo, greaterThan(leaderHurt.extraBingo));

      final BingoProbabilities halfBehindHurt =
          WeaponState.computeBingoProbabilitiesFor(
        playerScore: 2,
        leaderScore: 7,
        maxFrags: 10, // 5/10 = 50% behind -> 80% Superbingo!
        hasFullHealth: false,
      );
      expect(halfBehindHurt.superBingo, closeTo(0.80, 1e-6));
      expect(halfBehindHurt.extraBingo, greaterThan(leaderHurt.extraBingo));

      // 2. Verify Extra Bingo sound, full-health restore (without shield), and full-HP guard.
      final WormWorld world = await createTestWorld('a');
      final Sounds sounds = getIt<Sounds>();
      final FakeSoundFactory soundFactory =
          getIt<SoundFactory>() as FakeSoundFactory;
      sounds.preloadSounds();
      await soundFactory.loadAllAudio();
      soundFactory.resetPlayedSounds();

      world.startAsServer('a');
      world.frameDraw(0.6);
      world.frameDraw(0.6);

      final LocalPlayerSprite player =
          world.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final WeaponState ws = player.weaponState!;
      final FakeCanvas canvas = FakeCanvas();

      // At full health (100 HP), rolling inside the Extra Bingo band (0.03) must NOT grant Extra Bingo.
      expect(player.health, equals(LocalPlayerSprite.MAX_HEALTH));
      ws.triggerMysteryRoulette(bingoRollOverride: 0.03);
      expect(ws.rouletteBingoTier, equals(BingoTier.none));
      ws.think(2.0);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Damage player to 35 HP (0 shield) -> rolling 0.03 (between 0.01 Super and 0.06 Extra)
      // triggers Extra Bingo, plays Sound.EXTRA_BINGO, and restores full health!
      soundFactory.resetPlayedSounds();
      player.health = 35;
      player.shieldPoints = 0;
      ws.triggerMysteryRoulette(bingoRollOverride: 0.03);
      expect(ws.rouletteBingoTier, equals(BingoTier.extraBingo));

      ws.think(2.0);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(soundFactory.getTotalPlayOuts(Sound.EXTRA_BINGO), equals(1));
      expect(player.health, equals(LocalPlayerSprite.MAX_HEALTH));
      expect(player.shieldPoints, equals(0),
          reason: 'Extra Bingo restores full health only, not shield');
      expect(player.bingoEffectTier, equals(1));
      ws.drawWeaponHelper(canvas.context2D, const Point<int>(700, 80), true);
      player.draw(canvas.context2D, false);
    });

    test('Trailing player 50% behind leader rolls Superbingo (80% chance) and syncs full shield + full health + jackpot aura over network', () async {
      throwIfLoggingUnexpected = false;
      final WormWorld worldA = await createTestWorld('a');
      final WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.drawFps().setFpsForTest(60.0);
      worldB.drawFps().setFpsForTest(60.0);

      worldA.startAsServer('nameA');
      worldA.frameDraw(0.1);
      worldB.connectTo('a', 'nameB');
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
        w.byteWorld.fillRectAt(Vec2(0.0, 320.0), Vec2(600.0, 80.0), '#444444');
      }

      // Leader A has 7 frags, trailing player B has 2 frags (5/10 = 50% of maxFrags behind!).
      worldA.network().getGameState().playerInfoByConnectionId('a')!.score = 7;
      worldA.network().getGameState().playerInfoByConnectionId('b')!.score = 2;
      worldA.network().getGameState().markAsUrgent();

      final LocalPlayerSprite playerAOnA =
          worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnA =
          worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnB =
          worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;

      playerBOnA.health = 28;
      playerBOnA.shieldPoints = 0;

      // Leader A only has 1% Superbingo, whereas trailing B (50% behind) has 80% Superbingo!
      expect(playerAOnA.weaponState!.currentBingoProbabilities().superBingo,
          closeTo(0.01, 1e-6));
      expect(playerBOnA.weaponState!.currentBingoProbabilities().superBingo,
          closeTo(0.80, 1e-6));

      // A roll of 0.65 gives Leader A nothing, but gives trailing Client B a SUPERBINGO!
      expect(playerAOnA.weaponState!.rollBingoTier(0.65), equals(BingoTier.none));
      playerBOnA.weaponState!.triggerMysteryRoulette(bingoRollOverride: 0.65);
      expect(playerBOnA.weaponState!.rouletteBingoTier, equals(BingoTier.superBingo));

      // Step frames past the 1.85s spin -> Superbingo lands on both commander A and client B!
      final FakeCanvas canvas = FakeCanvas();
      for (int i = 0; i < 40; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
      }

      expect(playerBOnA.health, equals(LocalPlayerSprite.MAX_HEALTH));
      expect(playerBOnA.shieldPoints, equals(LocalPlayerSprite.MAX_SHIELD));
      expect(playerBOnB.weaponState!.rouletteBingoTier, equals(BingoTier.superBingo));
      expect(playerBOnB.health, equals(LocalPlayerSprite.MAX_HEALTH));
      expect(playerBOnB.shieldPoints, equals(LocalPlayerSprite.MAX_SHIELD));
      expect(playerBOnB.bingoEffectTier, equals(2));

      // Render both HUD showcase and world-space Superbingo aura cleanly.
      playerBOnB.weaponState!
          .drawWeaponHelper(canvas.context2D, const Point<int>(700, 80), true);
      playerBOnB.draw(canvas.context2D, false);
      playerBOnA.draw(canvas.context2D, false);
    });
  });
}
