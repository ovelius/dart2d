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

    test('E2E: Client colliding with live Mystery Powerup transfers exact spinner target over network into WeaponState without local random desync', () async {
      throwIfLoggingUnexpected = false;
      // Deliberately use an unseeded / advancing Random: if Client B ever rolled
      // its own local roulette on collision, its random target would diverge from Commander A!
      WeaponState.random = Random(2026);
      final WormWorld worldA = await createTestWorld('a');
      final WormWorld worldB = await createTestWorld('b');
      final WormWorld worldC = await createTestWorld('c');
      for (final WormWorld w in <WormWorld>[worldA, worldB, worldC]) {
        w.network().disableCommandTransferHeuristicForTest = true;
        w.drawFps().setFpsForTest(60.0);
      }

      worldA.startAsServer('nameA');
      worldA.frameDraw(0.1);
      worldB.connectTo('a', 'nameB');
      worldB.network().getServerConnection()!.sendClientEnter();
      worldC.connectTo('a', 'nameC');
      worldC.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 12; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldC.frameDraw(KEY_FRAME_DEFAULT);
        for (final WormWorld w in <WormWorld>[worldA, worldB, worldC]) {
          w.drawFps().setFpsForTest(60.0);
        }
      }

      for (final WormWorld w in <WormWorld>[worldA, worldB, worldC]) {
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(700, 400));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
        w.byteWorld.fillRectAt(Vec2(0.0, 320.0), Vec2(700.0, 80.0), '#444444');
      }

      final LocalPlayerSprite playerAOnA =
          worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnA =
          worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnB =
          worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnC =
          worldC.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite playerCOnC =
          worldC.spriteIndex[playerId(2)] as LocalPlayerSprite;

      // Park A and C away from the pickup zone; place Client B well clear (> 56px) of the mystery box at x = 292.
      playerAOnA.setCenter(Vec2(60.0, 298.0));
      playerAOnA.velocity = Vec2.ZERO;
      playerCOnC.setCenter(Vec2(620.0, 298.0));
      playerCOnC.velocity = Vec2.ZERO;
      playerBOnB.setCenter(Vec2(200.0, 298.0));
      playerBOnB.velocity = Vec2.ZERO;
      playerBOnA.setCenter(Vec2(200.0, 298.0));
      playerBOnA.velocity = Vec2.ZERO;

      // Clear any background auto-spawned powerups and pause automatic spawns so only
      // our explicit test mystery boxes exist during the 3-round verification loop.
      worldA.powerupManager()!.reset();
      worldA.powerupManager()!.setNextPowerForTest(9999.0);
      for (int i = 0; i < 3; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldC.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldA.powerupManager()!.setNextPowerForTest(9999.0);
      }

      // Run multiple consecutive real pickups to prove nonce progression and zero desyncs!
      for (int round = 0; round < 3; round++) {
        worldA.powerupManager()!.setNextPowerForTest(9999.0);
        final int prevNonce = playerBOnA.weaponState!.rouletteNonce;
        // Spawn a real PowerUpType.POWERUP sprite on Commander A right in front of Client B
        // and sync it to Client B and Client C BEFORE Client B touches it!
        final Powerup mysteryBox = Powerup(
          Vec2(292.0, 320.0 - Powerup.SIZE_OFFSET.y),
          PowerUpType.POWERUP,
          worldA.imageIndex(),
        )
          ..velocity = Vec2.ZERO
          ..flags = Sprite.FLAG_NO_GRAVITY;
        worldA.addSprite(mysteryBox);
        worldA.powerupManager()!.trackPowerup(mysteryBox);

        for (int i = 0; i < 3; i++) {
          worldA.powerupManager()!.setNextPowerForTest(9999.0);
          worldA.frameDraw(KEY_FRAME_DEFAULT / 2);
          worldB.frameDraw(KEY_FRAME_DEFAULT / 2);
          worldC.frameDraw(KEY_FRAME_DEFAULT / 2);
        }
        final int boxId = mysteryBox.networkId!;
        expect(worldB.spriteIndex[boxId], isA<Powerup>(),
            reason: 'Mystery powerup must exist as a REMOTE sprite on Client B before pickup');

        // Walk Client B right onto the live Powerup on Client B FIRST before Commander A ticks!
        playerBOnB.setCenter(Vec2(305.0, 298.0));
        worldB.frameDraw(0.04);
        expect(playerBOnB.weaponState!.isRouletteSpinning, isFalse,
            reason: 'Client B must NOT locally roll its own random spinner before Commander A confirms pickup');
        expect(worldB.spriteIndex.hasSprite(boxId), isTrue,
            reason: 'Client B must wait for authoritative Commander removal of the powerup');

        // Advance Random on Client B's VM between frames so any accidental local roll would pick a different weapon,
        // then step Client B -> Commander A -> Client B so Commander A resolves the real collision!
        for (int i = 0; i < 6 && !playerBOnA.weaponState!.isRouletteSpinning; i++) {
          worldA.powerupManager()!.setNextPowerForTest(9999.0);
          worldB.frameDraw(0.05);
          worldA.frameDraw(0.05);
        }
        expect(playerBOnA.weaponState!.isRouletteSpinning, isTrue,
            reason: 'Commander A must start mystery roulette when Client B collides with Powerup');
        final int commanderTargetIdx =
            playerBOnA.weaponState!.rouletteTargetWeaponIndex;
        final String expectedWeaponName =
            playerBOnA.weaponState!.weapons[commanderTargetIdx].name;
        final int expectedNonce = playerBOnA.weaponState!.rouletteNonce;
        expect(expectedNonce, equals(prevNonce + 1));

        // Step network frames mid-spin (~0.30s in): verify spinner transferred to Client B & Client C
        // with the EXACT same target weapon and nonce!
        final FakeCanvas hudCanvas = FakeCanvas();
        for (int i = 0; i < 6; i++) {
          worldA.frameDraw(0.05);
          worldB.frameDraw(0.05);
          worldC.frameDraw(0.05);
          playerBOnB.weaponState!
              .drawWeaponHelper(hudCanvas.context2D, const Point<int>(620, 80), true);
        }
        expect(worldB.spriteIndex.hasSprite(boxId), isFalse,
            reason: 'Picked-up powerup must be removed on Client B');
        expect(playerBOnB.weaponState!.isRouletteSpinning, isTrue);
        expect(playerBOnB.weaponState!.rouletteNonce, equals(expectedNonce));
        expect(playerBOnB.weaponState!.rouletteTargetWeaponIndex,
            equals(commanderTargetIdx),
            reason: 'Client B spinner target must match Commander A target ($expectedWeaponName)');
        expect(playerBOnC.weaponState!.rouletteTargetWeaponIndex,
            equals(commanderTargetIdx));

        // Step through the end of the 1.85s spin with interleaved Client -> Commander updates
        // (verifying stale pre-reveal client packets never overwrite Commander's newly won weapon!).
        for (int i = 0; i < 36; i++) {
          worldB.frameDraw(0.05);
          worldA.frameDraw(0.05);
          worldC.frameDraw(0.05);
          playerBOnB.weaponState!
              .drawWeaponHelper(hudCanvas.context2D, const Point<int>(620, 80), true);
        }

        expect(playerBOnB.weaponState!.isRouletteSpinning, isFalse);
        expect(playerBOnB.weaponState!.completedRouletteNonce, equals(expectedNonce));
        expect(playerBOnB.weaponState!.selectedWeaponIndex, equals(commanderTargetIdx),
            reason: 'Client B must equip the exact weapon shown by the spinner ($expectedWeaponName)');
        expect(playerBOnA.weaponState!.selectedWeaponIndex, equals(commanderTargetIdx),
            reason: 'Commander A must keep the exact same weapon selected for Client B ($expectedWeaponName)');
        expect(playerBOnB.weaponState!.selectedWeaponName, equals(expectedWeaponName));
        expect(playerBOnB.weaponState!.isWeaponAvailable(commanderTargetIdx), isTrue);

        // Verify ONLY the won mystery weapon (plus 4 starters = 5 total) is available on Client B!
        final List<int> unlockedMysteryOnClient = playerBOnB.weaponState!
            .availableWeaponIndices()
            .where((int idx) => playerBOnB.weaponState!.weapons[idx].isMysteryWeapon)
            .toList();
        expect(unlockedMysteryOnClient, equals(<int>[commanderTargetIdx]));

        // Drain the won mystery weapon by firing from Client B so the next round starts clean!
        final Weapon wonOnA = playerBOnA.weaponState!.weapons[commanderTargetIdx];
        final int clip = wonOnA.shotsPerClip;
        for (int shot = 0; shot < clip; shot++) {
          wonOnA.untilNextFire = 0.0;
          playerBOnB.weaponState!.weapons[commanderTargetIdx].untilNextFire = 0.0;
          worldB.localKeyState.onKeyDown(KeyCodeDart.F);
          worldA.frameDraw(0.03);
          worldB.frameDraw(0.03);
          worldB.localKeyState.onKeyUp(KeyCodeDart.F);
          worldA.frameDraw(0.03);
          worldB.frameDraw(0.03);
        }
        // Sync depletion back to Client B.
        for (int i = 0; i < 4; i++) {
          worldA.frameDraw(0.06);
          worldB.frameDraw(0.06);
        }
        expect(playerBOnB.weaponState!.isWeaponAvailable(commanderTargetIdx), isFalse);
        playerBOnB.setCenter(Vec2(200.0, 298.0));
        playerBOnB.velocity = Vec2.ZERO;
        playerBOnA.setCenter(Vec2(200.0, 298.0));
        playerBOnA.velocity = Vec2.ZERO;
        for (int i = 0; i < 2; i++) {
          worldB.frameDraw(KEY_FRAME_DEFAULT / 2);
          worldA.frameDraw(KEY_FRAME_DEFAULT / 2);
        }
      }
    });

    test('E2E: Powerup never triggers spin when player is not inGame or after game has ended', () async {
      throwIfLoggingUnexpected = false;
      configParameters['maxFrags'] = <String>['2'];
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

      for (int i = 0; i < 10; i++) {
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

      final LocalPlayerSprite playerAOnA =
          worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnA =
          worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnB =
          worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;

      playerAOnA.setCenter(Vec2(120.0, 298.0));
      playerBOnA.setCenter(Vec2(340.0, 298.0));
      playerBOnB.setCenter(Vec2(340.0, 298.0));

      // 1. Kill Client B (so B is dead / respawning: inGame() == false) while B had an active spin!
      playerBOnA.weaponState!.triggerMysteryRoulette();
      expect(playerBOnA.weaponState!.isRouletteSpinning, isTrue);
      playerBOnA.takeDamage(500, playerAOnA, Mod.ZOOKA);
      expect(playerBOnA.inGame(), isFalse);

      // Spawn a mystery powerup directly on top of dead Client B!
      final Powerup boxOnDeadPlayer = Powerup(
        Vec2(340.0 - 18.0, 298.0 - 18.0),
        PowerUpType.POWERUP,
        worldA.imageIndex(),
      )
        ..velocity = Vec2.ZERO
        ..flags = Sprite.FLAG_NO_GRAVITY;
      worldA.addSprite(boxOnDeadPlayer);

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
      }
      expect(boxOnDeadPlayer.remove, isFalse,
          reason: 'Dead/respawning player must NOT collide with or consume powerups');
      expect(playerBOnA.weaponState!.isRouletteActive, isFalse,
          reason: 'Active spin must cancel when player is no longer inGame');
      expect(playerBOnB.weaponState!.isRouletteActive, isFalse,
          reason: 'Client B must NOT show roulette spinner while dead/out of game');

      // Respawn Client B cleanly.
      for (int i = 0; i < 30 && !playerBOnA.inGame(); i++) {
        worldA.frameDraw(0.20);
        worldB.frameDraw(0.20);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
      }
      expect(playerBOnA.inGame(), isTrue);

      // 2. End the match (A reaches maxfrags = 2 -> winnerPlayerId is set, all players inGame = false)!
      playerAOnA.weaponState!.triggerMysteryRoulette();
      expect(playerAOnA.weaponState!.isRouletteSpinning, isTrue);
      playerBOnA.takeDamage(500, playerAOnA, Mod.ZOOKA);
      expect(worldA.network().getGameState().hasWinner(), isTrue);

      // Drop mystery powerups directly onto BOTH Commander A and Client B during the game-over win screen!
      final Powerup postGameBoxA = Powerup(
        Vec2.copy(playerAOnA.position),
        PowerUpType.POWERUP,
        worldA.imageIndex(),
      )
        ..velocity = Vec2.ZERO
        ..flags = Sprite.FLAG_NO_GRAVITY;
      final Powerup postGameBoxB = Powerup(
        Vec2.copy(playerBOnA.position),
        PowerUpType.POWERUP,
        worldA.imageIndex(),
      )
        ..velocity = Vec2.ZERO
        ..flags = Sprite.FLAG_NO_GRAVITY;
      worldA.addSprite(postGameBoxA);
      worldA.addSprite(postGameBoxB);

      for (int i = 0; i < 8; i++) {
        worldA.frameDraw(0.08);
        worldB.frameDraw(0.08);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);
      }

      expect(postGameBoxA.remove, isFalse,
          reason: 'Powerup must NOT collide with commander after game has ended');
      expect(postGameBoxB.remove, isFalse,
          reason: 'Powerup must NOT collide with client after game has ended');
      expect(playerAOnA.weaponState!.isRouletteActive, isFalse,
          reason: 'Commander roulette must be inactive after game has ended');
      expect(playerBOnA.weaponState!.isRouletteActive, isFalse);
      expect(playerBOnB.weaponState!.isRouletteActive, isFalse,
          reason: 'Client roulette must be inactive after game has ended');
    });

    test('E2E: Moving client firing Spiky Hedgehog and Pigeon Strike never self-collides and summons full airstrike for client', () async {
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
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(800, 400));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
        // Solid floor + a walkable 3px step along Client B's running path!
        w.byteWorld.fillRectAt(Vec2(0.0, 320.0), Vec2(800.0, 80.0), '#444444');
        w.byteWorld.fillRectAt(Vec2(150.0, 317.0), Vec2(120.0, 3.0), '#444444');
      }

      final LocalPlayerSprite playerAOnA =
          worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnA =
          worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      final LocalPlayerSprite playerBOnB =
          worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;

      // Park Enemy A far right (x = 720, outside 92px mine proximity) during Part 1,
      // and place Client B on the left at x = 110.
      playerAOnA.setCenter(Vec2(720.0, 298.0));
      playerAOnA.velocity = Vec2.ZERO;
      playerBOnB.setCenter(Vec2(110.0, 298.0));
      playerBOnB.velocity = Vec2.ZERO;
      playerBOnA.setCenter(Vec2(110.0, 298.0));
      playerBOnA.velocity = Vec2.ZERO;

      for (int i = 0; i < 3; i++) {
        worldB.frameDraw(0.05);
        worldA.frameDraw(0.05);
      }

      // PART 1: Award Spiky Hedgehog to Client B via mystery roulette and fire BOTH mines
      // while actively running forward (D held) and holding Fire (F held across depletion)!
      final int hedgehogIdx = playerBOnA.weaponState!.weapons
          .indexWhere((Weapon w) => w.name == 'Spiky Hedgehog');
      playerBOnA.weaponState!.triggerMysteryRoulette(
        forcedWeaponIndex: hedgehogIdx,
        forcedBingoTier: BingoTier.none,
      );
      for (int i = 0; i < 40; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      expect(playerBOnB.weaponState!.selectedWeaponIndex, equals(hedgehogIdx));
      expect(playerBOnA.weaponState!.selectedWeaponIndex, equals(hedgehogIdx));

      // Aim slightly upward-right while running right at full speed and holding Fire!
      playerBOnB.gun.angle = -0.22;
      worldB.localKeyState.onKeyDown(KeyCodeDart.D);
      for (int i = 0; i < 4; i++) {
        worldB.frameDraw(0.03);
        worldA.frameDraw(0.03);
      }
      expect(playerBOnB.velocity.x, greaterThan(60.0));

      // Hold Fire across multiple frames for Shot #1, then advance past fireDelay (0.9s)
      // and hold Fire across multiple frames for Shot #2 (depleting Spiky Hedgehog while Fire stays down!).
      worldB.localKeyState.onKeyDown(KeyCodeDart.F);
      for (int i = 0; i < 5; i++) {
        worldB.frameDraw(0.03);
        worldA.frameDraw(0.03);
      }
      worldB.localKeyState.onKeyUp(KeyCodeDart.F);

      for (int i = 0; i < 16; i++) {
        worldB.frameDraw(0.06);
        worldA.frameDraw(0.06);
      }

      // Fire Shot #2 while STILL running forward and keeping Fire held for 6 frames after depletion!
      worldB.localKeyState.onKeyDown(KeyCodeDart.F);
      for (int i = 0; i < 6; i++) {
        worldB.frameDraw(0.03);
        worldA.frameDraw(0.03);
      }
      worldB.localKeyState.onKeyUp(KeyCodeDart.F);
      worldB.localKeyState.onKeyUp(KeyCodeDart.D);

      // Verify Client B took ZERO self-damage and BOTH HedgehogMines survived intact and synced to Client B!
      expect(playerBOnA.health, equals(LocalPlayerSprite.MAX_HEALTH),
          reason: 'Moving client firing Spiky Hedgehog must NOT self-collide or take self-damage');
      final List<HedgehogMine> minesOnA = worldA.spriteIndex
          .spriteIds()
          .map((int id) => worldA.spriteIndex[id])
          .whereType<HedgehogMine>()
          .toList();
      expect(minesOnA, hasLength(2),
          reason: 'Both HedgehogMines fired while moving must survive without instant self-detonation');

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 2);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 2);
      }
      final List<HedgehogMine> minesOnB = worldB.spriteIndex
          .spriteIds()
          .map((int id) => worldB.spriteIndex[id])
          .whereType<HedgehogMine>()
          .toList();
      expect(minesOnB, hasLength(2),
          reason: 'Both client-owned HedgehogMines must sync cleanly to Client B');

      // Clean up mines before Part 2 so Enemy A isn't blown up by the mines first.
      for (final HedgehogMine m in minesOnA) {
        m.remove = true;
      }
      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      // PART 2: Award Pigeon Strike (1-shot magazine!) to Client B, move & aim toward Enemy A,
      // and hold Fire across multiple frames (exact client WebRTC key-hold pattern!).
      playerBOnB.setCenter(Vec2(140.0, 295.0));
      playerBOnB.velocity = Vec2.ZERO;
      playerBOnA.setCenter(Vec2(140.0, 295.0));
      playerBOnA.velocity = Vec2.ZERO;
      playerAOnA.setCenter(Vec2(650.0, 298.0));
      playerAOnA.velocity = Vec2.ZERO;
      final int initialHealthA = playerAOnA.health;

      final int pigeonIdx = playerBOnA.weaponState!.weapons
          .indexWhere((Weapon w) => w.name == 'Pigeon Strike');
      playerBOnA.weaponState!.triggerMysteryRoulette(
        forcedWeaponIndex: pigeonIdx,
        forcedBingoTier: BingoTier.none,
      );
      for (int i = 0; i < 40; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      expect(playerBOnB.weaponState!.selectedWeaponIndex, equals(pigeonIdx));

      // Move forward while aiming an arc toward Enemy A at x = 410 and hold Fire for 6 frames!
      playerBOnB.gun.angle = -0.52;
      worldB.localKeyState.onKeyDown(KeyCodeDart.D);
      worldB.frameDraw(0.03);
      worldA.frameDraw(0.03);

      worldB.localKeyState.onKeyDown(KeyCodeDart.F);
      for (int i = 0; i < 6; i++) {
        worldB.frameDraw(0.03);
        worldA.frameDraw(0.03);
      }
      worldB.localKeyState.onKeyUp(KeyCodeDart.F);
      worldB.localKeyState.onKeyUp(KeyCodeDart.D);

      // Verify PigeonStrikeFlare spawned on Commander A for Client B and was NOT sniped by a follow-up dart!
      final List<PigeonStrikeFlare> flaresOnA = worldA.spriteIndex
          .spriteIds()
          .map((int id) => worldA.spriteIndex[id])
          .whereType<PigeonStrikeFlare>()
          .toList();
      expect(flaresOnA, hasLength(1),
          reason: 'Client B firing Pigeon Strike must spawn an intact PigeonStrikeFlare');
      final PigeonStrikeFlare flareA = flaresOnA.single;
      expect(flareA.owner?.networkId, equals(playerBOnA.networkId));
      expect(flareA.remove, isFalse);

      // Step until the flare lands near Enemy A, becomes strikeConfirmed on BOTH Commander A & Client B,
      // summons 5 BomberPigeons, and drops bombs onto Enemy A!
      final FakeCanvas clientCanvas = FakeCanvas();
      bool sawLandedMarkerOnClient = false;
      bool sawConfirmedMarkerOnClient = false;
      bool sawPigeonsOnClient = false;
      bool sawBombsOnClient = false;

      for (int i = 0; i < 110; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
        worldA.drawFps().setFpsForTest(60.0);
        worldB.drawFps().setFpsForTest(60.0);

        final PigeonStrikeFlare? flareB =
            worldB.spriteIndex[flareA.networkId!] as PigeonStrikeFlare?;
        if (flareB != null) {
          flareB.draw(clientCanvas.context2D, false);
          if (flareB.landed && !flareB.strikeConfirmed) {
            sawLandedMarkerOnClient = true;
          }
          if (flareB.strikeConfirmed) {
            sawConfirmedMarkerOnClient = true;
          }
        }
        for (final int id in worldB.spriteIndex.spriteIds()) {
          final Sprite? s = worldB.spriteIndex[id];
          if (s is BomberPigeonProjectile) {
            sawPigeonsOnClient = true;
          } else if (s is PigeonDroppingBomb) {
            sawBombsOnClient = true;
          }
        }
      }

      expect(sawLandedMarkerOnClient, isTrue,
          reason: 'Client B must see landed PigeonStrikeFlare marker arming on ground');
      expect(sawConfirmedMarkerOnClient, isTrue,
          reason: 'Client B must see confirmed INCOMING! PigeonStrikeFlare beacon');
      expect(sawPigeonsOnClient, isTrue,
          reason: 'Client B must receive BomberPigeon squadron summoned by its flare');
      expect(sawBombsOnClient, isTrue,
          reason: 'Client B must receive PigeonDroppingBombs dropped by its squadron');
      expect(playerAOnA.health, lessThan(initialHealthA),
          reason: 'Client B Pigeon Strike must deal airstrike bomb damage to Enemy A');
    });
  });
}
