import 'dart:math';

import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/worlds/player_world_selector.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:test/test.dart';

import 'lib/test_injector.dart';
import 'lib/test_lib.dart';

void main() {
  setUpAll(() {
    configureDependencies();
  });

  setUp(() {
    logOutputForTest();
    clearEnvironment();
    testTouchSupported = true;
  });

  tearDown(() {
    clearEnvironment();
  });

  group('MobileControls layout, touch input, and gameplay integration', () {
    test('Buttons stay strictly on-screen, non-overlapping, and out of left-thumb zone across resolutions', () async {
      final WormWorld world = await createTestWorld('a');
      world.startAsServer('a');
      // Advance past the 1.0s initial spawn countdown so selfInfo.inGame == true.
      world.frameDraw(0.6);
      world.frameDraw(0.6);
      expect(world.network().getGameState().isInGame('a'), isTrue);

      final MobileControls controls = getIt<MobileControls>();
      const List<Point<int>> resolutions = <Point<int>>[
        Point<int>(568, 320), // iPhone SE (1st gen) landscape
        Point<int>(667, 375), // iPhone 8 / SE2 landscape
        Point<int>(740, 360), // Compact Android landscape
        Point<int>(844, 390), // iPhone 13/14 landscape
        Point<int>(915, 412), // Pixel landscape
        Point<int>(1024, 768), // iPad landscape
        Point<int>(1280, 720), // HD landscape
      ];

      const List<int> allButtons = <int>[
        MobileControls.JUMP_BUTTON,
        MobileControls.FIRE_BUTTON,
        MobileControls.ROPE_BUTTON,
        MobileControls.WEAPON_SELECT_BUTTON,
        MobileControls.SOUND_BUTTON,
      ];

      for (final Point<int> res in resolutions) {
        controls.updateCanvasSize(res.x, res.y);
        expect(controls.width, equals(res.x));
        expect(controls.height, equals(res.y));

        // Ensure draw() renders cleanly and preserves explicit viewport dimensions.
        controls.draw(0.016);
        expect(controls.width, equals(res.x));
        expect(controls.height, equals(res.y));

        // 1. Every button circle must fit completely inside the visible canvas.
        for (final int btn in allButtons) {
          final Point<int> pos = controls.buttonLocation(btn);
          final int r = controls.buttonRadiusFor(btn);
          expect(pos.x - r, greaterThanOrEqualTo(0),
              reason: 'Button $btn clipped left at ${res.x}x${res.y}: $pos r=$r');
          expect(pos.x + r, lessThanOrEqualTo(res.x),
              reason: 'Button $btn clipped right at ${res.x}x${res.y}: $pos r=$r');
          expect(pos.y - r, greaterThanOrEqualTo(0),
              reason: 'Button $btn clipped top at ${res.x}x${res.y}: $pos r=$r');
          expect(pos.y + r, lessThanOrEqualTo(res.y),
              reason: 'Button $btn clipped bottom at ${res.x}x${res.y}: $pos r=$r');
        }

        // 2. No two button hitboxes may overlap.
        for (int i = 0; i < allButtons.length; i++) {
          for (int j = i + 1; j < allButtons.length; j++) {
            final Point<int> a = controls.buttonLocation(allButtons[i]);
            final Point<int> b = controls.buttonLocation(allButtons[j]);
            final double dist = a.distanceTo(b);
            final int minSep =
                controls.buttonRadiusFor(allButtons[i]) + controls.buttonRadiusFor(allButtons[j]);
            expect(dist, greaterThan(minSep.toDouble()),
                reason:
                    'Buttons ${allButtons[i]} ($a) and ${allButtons[j]} ($b) overlap at ${res.x}x${res.y}');
          }
        }

        // 3. Ergonomic quadrant placement.
        for (final int actionBtn in <int>[
          MobileControls.JUMP_BUTTON,
          MobileControls.FIRE_BUTTON,
          MobileControls.ROPE_BUTTON,
        ]) {
          final Point<int> p = controls.buttonLocation(actionBtn);
          expect(p.x, greaterThan(res.x * 0.50),
              reason: 'Action button $actionBtn should be on right half at ${res.x}x${res.y}');
          expect(p.y, greaterThan(res.y * 0.35),
              reason: 'Action button $actionBtn should be in lower thumb zone at ${res.x}x${res.y}');
        }
        final Point<int> weaponPos =
            controls.buttonLocation(MobileControls.WEAPON_SELECT_BUTTON);
        expect(weaponPos.x, greaterThan(res.x * 0.70));
        expect(weaponPos.y, lessThan(res.y * 0.40));

        final Point<int> soundPos =
            controls.buttonLocation(MobileControls.SOUND_BUTTON);
        expect((soundPos.x - res.x ~/ 2).abs(), lessThanOrEqualTo(2));
        expect(soundPos.y, lessThan(res.y * 0.25));

        // 4. Left-thumb movement & aiming area must be completely button-free.
        for (double fx = 0.08; fx <= 0.42; fx += 0.08) {
          for (double fy = 0.38; fy <= 0.92; fy += 0.12) {
            final int tx = (res.x * fx).round();
            final int ty = (res.y * fy).round();
            expect(controls.isButtonTouch(tx, ty), isFalse,
                reason: 'Left-thumb point ($tx, $ty) hit a button at ${res.x}x${res.y}');
          }
        }
      }
    });

    test('Action buttons, sound toggle, multi-touch independence, cancel/death release, and portrait scoreboard', () async {
      final WormWorld world = await createTestWorld('a');
      world.startAsServer('a');
      world.frameDraw(0.6);
      world.frameDraw(0.6);
      expect(world.network().getGameState().isInGame('a'), isTrue);

      final MobileControls controls = getIt<MobileControls>();
      final KeyState keyState = world.localKeyState;
      final Sounds sounds = getIt<Sounds>();
      controls.updateCanvasSize(844, 390);

      // Verify each action button maps to its expected KeyCodeDart key.
      final Map<int, int> expectedKeyMap = <int, int>{
        MobileControls.JUMP_BUTTON: KeyCodeDart.W,
        MobileControls.FIRE_BUTTON: KeyCodeDart.F,
        MobileControls.ROPE_BUTTON: KeyCodeDart.S,
        MobileControls.WEAPON_SELECT_BUTTON: KeyCodeDart.E,
      };
      for (final MapEntry<int, int> entry in expectedKeyMap.entries) {
        final Point<int> p = controls.buttonLocation(entry.key);
        expect(keyState.keyIsDown(entry.value), isFalse);
        controls.touchDown(10, p.x, p.y);
        expect(controls.buttonIsDown(entry.key), isTrue);
        expect(keyState.keyIsDown(entry.value), isTrue);
        controls.touchUp(10);
        expect(controls.buttonIsDown(entry.key), isFalse);
        expect(keyState.keyIsDown(entry.value), isFalse);
      }

      // Sound button toggles mute state without holding any key.
      final bool initialSound = sounds.soundEnabled;
      final Point<int> soundPos =
          controls.buttonLocation(MobileControls.SOUND_BUTTON);
      controls.touchDown(11, soundPos.x, soundPos.y);
      expect(sounds.soundEnabled, equals(!initialSound));
      controls.touchUp(11);
      controls.touchDown(11, soundPos.x, soundPos.y);
      expect(sounds.soundEnabled, equals(initialSound));
      controls.touchUp(11);

      // Multi-touch: left-thumb movement (id 0) + right-thumb FIRE (id 1) + stray tap (id 2).
      controls.touchDown(0, 120, 260);
      controls.touchMove(0, 180, 240);
      expect(controls.buttonIsDown(), isTrue);
      expect(controls.getTouchDeltaForButton(), equals(const Point<int>(-60, 20)));

      // Draw virtual joystick feedback while moving.
      controls.draw(0.016);

      final Point<int> firePos = controls.buttonLocation(MobileControls.FIRE_BUTTON);
      controls.touchDown(1, firePos.x, firePos.y);
      expect(keyState.keyIsDown(KeyCodeDart.F), isTrue);
      expect(controls.buttonIsDown(), isTrue);
      expect(controls.getTouchDeltaForButton(), equals(const Point<int>(-60, 20)));

      // A second non-button tap must NOT steal or cancel finger 0's movement control.
      controls.touchDown(2, 260, 140);
      controls.touchMove(2, 270, 150);
      expect(controls.getTouchDeltaForButton(), equals(const Point<int>(-60, 20)));
      controls.touchUp(2);
      expect(controls.buttonIsDown(), isTrue);
      expect(controls.getTouchDeltaForButton(), equals(const Point<int>(-60, 20)));

      // Release FIRE while keeping movement held.
      controls.touchUp(1);
      expect(keyState.keyIsDown(KeyCodeDart.F), isFalse);
      expect(controls.buttonIsDown(), isTrue);

      // Release movement (id 0), then start a brand-new touch reusing id 0:
      // stale delta MUST NOT leak into the new touch!
      controls.touchUp(0);
      expect(controls.buttonIsDown(), isFalse);
      expect(controls.getTouchDeltaForButton(), isNull);

      controls.touchDown(0, 140, 260);
      expect(controls.buttonIsDown(), isTrue);
      expect(controls.getTouchDeltaForButton(), isNull,
          reason: 'Reused touch identifier 0 must not inherit stale delta');
      controls.touchCancel(0);
      expect(controls.buttonIsDown(), isFalse);

      // Portrait mode holds SHIFT (scoreboard) and disables gameplay button hits;
      // rotating back to landscape releases SHIFT.
      FakeScreen.mockOrientationType = 'portrait-primary';
      controls.draw(0.016);
      expect(keyState.keyIsDown(KeyCodeDart.SHIFT), isTrue);
      controls.touchDown(3, firePos.x, firePos.y);
      expect(keyState.keyIsDown(KeyCodeDart.F), isFalse);
      controls.touchUp(3);

      FakeScreen.mockOrientationType = 'landscape-primary';
      controls.draw(0.016);
      expect(keyState.keyIsDown(KeyCodeDart.SHIFT), isFalse);

      // Player leaving inGame (death) releases held touches during draw().
      controls.touchDown(4, firePos.x, firePos.y);
      expect(keyState.keyIsDown(KeyCodeDart.F), isTrue);
      world.network().getGameState().playerInfoByConnectionId('a')!.inGame = false;
      controls.draw(0.016);
      expect(keyState.keyIsDown(KeyCodeDart.F), isFalse);
      expect(controls.buttonIsDown(MobileControls.FIRE_BUTTON), isFalse);
    });

    test('Gameplay touch walk, deadzone vertical aim, jump, fire, rope, and weapon wheel work end-to-end', () async {
      final WormWorld world = await createTestWorld('a');
      world.byteWorld.setWorldImage(
          world.imageIndex().imageFactory.createWithSize(1000, 600));
      while (!world.byteWorld.bedrockComputed()) {
        world.byteWorld.bedrockStep();
      }
      world.startAsServer('a');
      world.frameDraw(0.6);
      world.frameDraw(0.6);
      expect(world.network().getGameState().isInGame('a'), isTrue);

      final MobileControls controls = getIt<MobileControls>();
      controls.updateCanvasSize(844, 390);

      final LocalPlayerSprite player =
          world.spriteIndex[playerId(0)] as LocalPlayerSprite;
      final WeaponState weaponState = player.weaponState!;
      player.position = Vec2(300.0, 200.0);
      player.velocity = Vec2(0.0, 0.0);

      // 1. Left-thumb horizontal drag right -> walks right; drag left -> walks left.
      controls.touchDown(0, 120, 280);
      controls.touchMove(0, 185, 280); // xD = -65 -> walk right
      world.frameDraw(0.02);
      expect(player.velocity.x, greaterThan(0.0));
      expect(player.angle, equals(0.0));

      controls.touchMove(0, 55, 280); // xD = +65 -> walk left
      world.frameDraw(0.02);
      expect(player.velocity.x, lessThan(0.0));
      expect(player.angle, greaterThan(0.0));
      controls.touchUp(0);

      // 2. Vertical aim drag inside 12px horizontal deadzone aims gun without walking or flipping!
      player.velocity = Vec2(0.0, 0.0);
      player.angle = 0.0;
      player.gun.angle = 0.0;
      controls.touchDown(0, 130, 280);
      controls.touchMove(0, 136, 220); // |xD| = 6 <= 12 deadzone, yD = +60 (drag up)
      player.checkControlKeys(0.02);
      expect(player.angle, equals(0.0),
          reason: 'Small horizontal jitter while aiming vertically must not flip facing');
      expect(player.velocity.x, equals(0.0),
          reason: 'Small horizontal jitter inside deadzone must not walk');
      expect(player.gun.angle, lessThan(-0.5),
          reason: 'Dragging finger upward should aim gun upward');
      controls.touchUp(0);

      // 3. JUMP button jumps when grounded.
      player.onGround = true;
      player.velocity = Vec2(0.0, 0.0);
      final Point<int> jumpPos = controls.buttonLocation(MobileControls.JUMP_BUTTON);
      controls.touchDown(1, jumpPos.x, jumpPos.y);
      player.checkControlKeys(0.02);
      expect(player.velocity.y, lessThan(0.0));
      controls.touchUp(1);

      // 4. ROPE button fires grappling hook.
      expect(player.rope, isNull);
      final Point<int> ropePos = controls.buttonLocation(MobileControls.ROPE_BUTTON);
      controls.touchDown(2, ropePos.x, ropePos.y);
      player.checkControlKeys(0.02);
      expect(player.rope, isNotNull);
      controls.touchUp(2);

      // 5. WEAPON_SELECT tap cycles weapon & opens wheel; FIRE tap while wheel is open
      //    fires the chosen weapon WITHOUT hijacking weapon selection!
      final int startWeapon = weaponState.selectedWeaponIndex;
      final Point<int> weaponBtn =
          controls.buttonLocation(MobileControls.WEAPON_SELECT_BUTTON);
      controls.touchDown(3, weaponBtn.x, weaponBtn.y);
      controls.touchUp(3);
      final int cycledWeapon = weaponState.selectedWeaponIndex;
      expect(cycledWeapon, isNot(equals(startWeapon)));
      expect(weaponState.changeTime, greaterThan(0.5));

      final int shotsBefore = weaponState.getSelectedWeapon().shotsLeft;
      final Point<int> firePos = controls.buttonLocation(MobileControls.FIRE_BUTTON);
      controls.touchDown(4, firePos.x, firePos.y);
      expect(weaponState.selectedWeaponIndex, equals(cycledWeapon),
          reason: 'Tapping FIRE while weapon wheel is open must not hijack weapon selection');
      world.frameDraw(0.02);
      expect(weaponState.getSelectedWeapon().shotsLeft, lessThan(shotsBefore),
          reason: 'Holding FIRE button should fire the equipped weapon');
      controls.touchUp(4);

      // Tapping in left-thumb walk space while wheel is open also must NOT hijack weapon!
      expect(weaponState.changeTime, greaterThan(0.2));
      controls.touchDown(5, 110, 280);
      expect(weaponState.selectedWeaponIndex, equals(cycledWeapon));
      controls.touchUp(5);

      // 6. Tapping directly on a radial weapon wheel icon selects that weapon.
      final List<int> availWeapons = weaponState.availableWeaponIndices();
      final double wheelR = min(
        WeaponState.WHEEL_SIZE.toDouble(),
        min(controls.width, controls.height) * 0.34,
      ).clamp(92.0, WeaponState.WHEEL_SIZE.toDouble());
      final int margin = (wheelR + WeaponState.ICON_SIZE_HALF + 8.0).ceil();
      final Point<int> wheelCenter = Point<int>(
        weaponBtn.x.clamp(margin, controls.width - margin),
        weaponBtn.y.clamp(margin, controls.height - margin),
      );
      const int targetSlot = 2;
      final int targetIdx = availWeapons[targetSlot];
      final double targetAngle = (pi * 2 / availWeapons.length) * targetSlot;
      final int iconTapX = (wheelCenter.x + sin(targetAngle) * wheelR).round();
      final int iconTapY = (wheelCenter.y + cos(targetAngle) * wheelR).round();
      expect(controls.isButtonTouch(iconTapX, iconTapY), isFalse);
      controls.touchDown(6, iconTapX, iconTapY);
      controls.touchUp(6);
      expect(weaponState.selectedWeaponIndex, equals(targetIdx));

      // 7. Holding WEAPON_SELECT and dragging >= 18px selects via radial drag.
      controls.touchDown(7, weaponBtn.x, weaponBtn.y);
      // Drag straight up on screen -> delta = start - current = (0, +80),
      // which matches angle pi (bottom of sin/cos wheel) rather than tap-cycled index.
      controls.touchMove(7, weaponBtn.x, weaponBtn.y - 80);
      player.checkControlKeys(0.02);
      final int expectedDragIdx = availWeapons[(availWeapons.length / 2).round()];
      expect(weaponState.selectedWeaponIndex, equals(expectedDragIdx));
      controls.touchUp(7);
    });

    test('Lobby touch character & map selection works and ignores touches once in game', () async {
      final WormWorld world = await createTestWorld(
        'a',
        setPlayerImage: false,
        selectMap: false,
        completeLoader: false,
        initByteWorld: false,
      );
      final MobileControls controls = getIt<MobileControls>();
      final PlayerWorldSelector selector = world.loader.playerWorldSelector;
      expect(selector.playerSelected(), isFalse);

      // Render character select screen so sprite positions are computed.
      world.frameDraw(0.05);
      expect(world.loader.currentState(), equals(LoaderState.PLAYER_SELECT));

      // Scan for a touch hit on one of the character sprites by double-tapping to select + confirm.
      for (int y = 120; y < 650 && !selector.playerSelected(); y += 25) {
        for (int x = 60; x < 760 && !selector.playerSelected(); x += 25) {
          controls.touchDown(0, x, y);
          controls.touchUp(0);
          controls.touchDown(0, x, y);
          controls.touchUp(0);
        }
      }
      expect(selector.playerSelected(), isTrue,
          reason: 'Double-tapping a character sprite should confirm character selection');

      // Render map select screen so _mapTileRects are populated.
      world.frameDraw(0.05);
      expect(world.loader.currentState(), equals(LoaderState.WORLD_SELECT));
      expect(selector.selectedWorldName, isNull);

      // Tap a map tile (top-left tile around (220, 180) on 800x800 canvas) twice to select.
      Point<int>? hitMapPoint;
      final int initialMap = selector.selectedMapIndex;
      for (int y = 80; y < 700 && hitMapPoint == null; y += 40) {
        for (int x = 80; x < 720; x += 40) {
          controls.touchDown(0, x, y);
          controls.touchUp(0);
          if (selector.selectedWorldName != null ||
              selector.selectedMapIndex != initialMap) {
            hitMapPoint = Point<int>(x, y);
            break;
          }
        }
      }
      expect(hitMapPoint, isNotNull, reason: 'Should hit a map tile via touch');
      if (selector.selectedWorldName == null) {
        controls.touchDown(0, hitMapPoint!.x, hitMapPoint.y);
        controls.touchUp(0);
      }
      final String? chosenWorld = selector.selectedWorldName;
      expect(chosenWorld, isNotNull);

      // Subsequent touches must not change the chosen map.
      controls.touchDown(0, 600, 600);
      controls.touchUp(0);
      expect(selector.selectedWorldName, equals(chosenWorld));
    });
  });
}
