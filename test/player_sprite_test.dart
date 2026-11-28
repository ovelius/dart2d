import 'dart:math';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:test/test.dart';
import 'package:web/helpers.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/util/util.dart';

import 'lib/test_mocks.mocks.dart';

void main() {
  late MockWormWorld mockWormWorld;
  late MockWormWorld mockCommanderWormWorld;
  late MockImageIndex mockImageIndex;
  late MockNetwork mockNetwork;
  late MockNetwork mockCommanderNetwork;
  late LocalPlayerSprite commanderSprite;
  late LocalPlayerSprite otherSprite;
  setUp(() {
    logOutputForTest();
    mockNetwork = new MockNetwork();
    mockCommanderNetwork = new MockNetwork();

    MockGameState gameState = MockGameState();
    when(gameState.getKeyStateFor(any)).thenReturn(KeyState.remote());
    mockWormWorld = new MockWormWorld();
    when(mockWormWorld.network()).thenReturn(mockNetwork);
    mockCommanderWormWorld = new MockWormWorld();
    when(mockCommanderNetwork.getGameState()).thenReturn(gameState);
    when(mockCommanderWormWorld.network()).thenReturn(mockCommanderNetwork);

    mockImageIndex = new MockImageIndex();
    when(mockNetwork.isCommander()).thenReturn(false);
    when(mockNetwork.getGameState()).thenReturn(gameState);
    when(mockCommanderNetwork.isCommander()).thenReturn(true);
    HTMLImageElement image2 = HTMLImageElement();
    image2.width = 10;
    image2.height = 10;
    when(mockImageIndex.getImageById(2)).thenReturn(image2);
    when(mockImageIndex.getImageById(3)).thenReturn(image2);
    when(mockImageIndex.getImageIdByName("gun.png")).thenReturn(3);
    when(mockImageIndex.getImageIdByName("shield.png")).thenReturn(3);
    commanderSprite = new LocalPlayerSprite(
        mockCommanderWormWorld, mockImageIndex, null, new PlayerInfoProto()
            ..name = "test1"
            ..connectionId =  "a", Vec2.ZERO, 2);
    otherSprite = new LocalPlayerSprite(
        mockWormWorld, mockImageIndex, null, new PlayerInfoProto()
            ..name = "test1"
            ..connectionId =  "a", Vec2.ZERO, 2);
  });
  tearDown(() {
    assertNoLoggedWarnings();
  });
  test('Test take damage', () {
    expect(otherSprite.health, equals(LocalPlayerSprite.MAX_HEALTH));
    otherSprite.takeDamage(1, commanderSprite, Mod.UNKNOWN);
    expect(otherSprite.health, equals(LocalPlayerSprite.MAX_HEALTH));

    expect(commanderSprite.health, equals(LocalPlayerSprite.MAX_HEALTH));
    commanderSprite.takeDamage(1, otherSprite, Mod.UNKNOWN);
    expect(commanderSprite.health, equals(LocalPlayerSprite.MAX_HEALTH - 1));

    commanderSprite.shieldPoints = 25;
    commanderSprite.takeDamage(25, otherSprite, Mod.UNKNOWN);
    expect(commanderSprite.health, equals(LocalPlayerSprite.MAX_HEALTH - 1));
    expect(commanderSprite.shieldPoints, equals(0));

    commanderSprite.shieldPoints = 2;
    commanderSprite.takeDamage(3, otherSprite, Mod.UNKNOWN);
    expect(commanderSprite.health, equals(LocalPlayerSprite.MAX_HEALTH - 2));
    expect(commanderSprite.shieldPoints, equals(0));
  });

  test("Test health powerup", () {
    when(mockImageIndex.getImageIdByName("health02.png")).thenReturn(3);
    commanderSprite.takeDamage(99, otherSprite, Mod.UNKNOWN);
    Powerup p = new Powerup(Vec2.ONE, PowerUpType.HEALTH, mockImageIndex);
    p.collide(commanderSprite, null, null);
    expect(commanderSprite.health, equals(LocalPlayerSprite.MAX_HEALTH));
  });

  test("Test shield powerup", () {
    when(mockImageIndex.getImageIdByName("shieldi02.png")).thenReturn(3);
    commanderSprite.takeDamage(99, otherSprite, Mod.UNKNOWN);
    Powerup p = new Powerup(Vec2.ONE, PowerUpType.SHIELD, mockImageIndex);
    p.collide(commanderSprite, null, null);
    expect(commanderSprite.shieldPoints, equals(LocalPlayerSprite.MAX_SHIELD));
  });

  test("Snailgun laser sight traces path through terrain and detects target", () {
    MockByteWorld mockByteWorld = MockByteWorld();
    when(mockByteWorld.byteWorldReady()).thenReturn(true);
    when(mockByteWorld.width).thenReturn(500);
    when(mockByteWorld.height).thenReturn(300);
    when(mockByteWorld.isSolid(any, any)).thenAnswer((inv) {
      int x = inv.positionalArguments[0] as int;
      return x >= 200 && x <= 260;
    });
    when(mockCommanderWormWorld.byteWorld).thenReturn(mockByteWorld);

    MockPeerWrapper mockPeer = MockPeerWrapper();
    when(mockPeer.getId()).thenReturn("a");
    when(mockCommanderNetwork.peer).thenReturn(mockPeer);
    when(mockCommanderNetwork.getPeer()).thenReturn(mockPeer);

    LocalPlayerSprite enemy = LocalPlayerSprite(
      mockCommanderWormWorld,
      mockImageIndex,
      null,
      PlayerInfoProto()
        ..name = "enemy"
        ..connectionId = "b"
        ..inGame = true,
      Vec2(320.0, 100.0),
      2,
    );
    MockSpriteIndex mockSprites = MockSpriteIndex();
    when(mockSprites.spriteIds()).thenReturn([1, 2]);
    when(mockSprites[1]).thenReturn(commanderSprite);
    when(mockSprites[2]).thenReturn(enemy);
    when(mockCommanderWormWorld.spriteIndex).thenReturn(mockSprites);

    commanderSprite.position = Vec2(50.0, 100.0);
    commanderSprite.gun.angle = 0.0;
    WeaponState ws = commanderSprite.weaponState!;

    // Only Snailgun should enable the laser sight.
    int snailIndex = ws.weapons.indexWhere((w) => w.name == "Snailgun");
    expect(snailIndex, greaterThanOrEqualTo(0));
    for (int i = 0; i < ws.weapons.length; i++) {
      expect(ws.weapons[i].hasLaserSight, equals(i == snailIndex));
    }

    ws.selectedWeaponIndex = snailIndex;
    LaserSightTrace trace = ws.computeLaserSightTrace();
    // Muzzle starts at center.x (71) + gun.size.x * 0.5 (30) = 101.
    expect(trace.start.x, closeTo(101.0, 0.5));
    expect(trace.start.y, closeTo(121.0, 0.5));
    // Reaches right edge of world (x = 500) -> distance ~399.
    expect(trace.totalDistance, closeTo(399.0, 0.5));
    // Detects terrain surface at x = 200 -> distance ~99 from muzzle.
    expect(trace.terrainHitDistance, isNotNull);
    expect(trace.terrainHitDistance!, closeTo(99.0, 2.0));
    // Detects enemy sitting behind the wall at x ~ 341 and turns beam green!
    expect(trace.playerHits, hasLength(1));
    expect(trace.playerHits.first.x, closeTo(341.0, 1.0));
    expect(trace.hasLivePlayerInPath, isTrue);
    expect(trace.beamColorMode, equals("green"));

    // Renders green lock-on beam cleanly on canvas.
    FakeCanvas canvas = FakeCanvas();
    ws.think(0.05);
    ws.draw(canvas.context2D);

    // When enemy is dead (!inGame) or off-axis, laser sight reverts to red!
    enemy.info.inGame = false;
    LaserSightTrace deadEnemyTrace = ws.computeLaserSightTrace();
    expect(deadEnemyTrace.hasLivePlayerInPath, isFalse);
    expect(deadEnemyTrace.beamColorMode, equals("red"));
    ws.draw(canvas.context2D);
  });

  test("Cartoon health/shield bars and mystery powerup question cloud draw cleanly", () {
    MockPeerWrapper mockPeer = MockPeerWrapper();
    when(mockPeer.getId()).thenReturn("a");
    when(mockCommanderNetwork.peer).thenReturn(mockPeer);

    FakeCanvas canvas = FakeCanvas();
    commanderSprite.health = 55;
    commanderSprite.shieldPoints = 120;
    expect(commanderSprite.drawHealthBar(canvas.context2D), isTrue);

    when(mockImageIndex.getImageIdByName("powerup.png")).thenReturn(2);
    when(mockImageIndex.getImageIdByName("powerup_swiwel.png")).thenReturn(3);
    Powerup mystery = Powerup(Vec2(120.0, 120.0), PowerUpType.POWERUP, mockImageIndex);
    mystery.frame(0.05, 1);
    mystery.draw(canvas.context2D, false);

    // Remote client reconstruction also renders mystery question cloud cleanly.
    Powerup remoteMystery = Powerup.createEmpty(mockImageIndex);
    remoteMystery.parseExtraNetworkData(mystery.addExtraNetworkData());
    remoteMystery.frame(0.05, 1);
    remoteMystery.draw(canvas.context2D, false);

    // Discreet magazine indicator renders for both small-clip pips and large-clip bar.
    WeaponState ws = commanderSprite.weaponState!;
    ws.selectedWeaponIndex = ws.weapons.indexWhere((w) => w.name == "Chicken shooter");
    ws.getSelectedWeapon().shotsLeft = 2;
    ws.draw(canvas.context2D);

    ws.selectedWeaponIndex = ws.weapons.indexWhere((w) => w.name == "Dart gun");
    ws.getSelectedWeapon().shotsLeft = 45;
    ws.draw(canvas.context2D);

    // Reloading state renders the cartoon reload pill above the clip indicator,
    // and completing reload triggers the pop-ready flash cleanly.
    ws.getSelectedWeapon().shotsLeft = 0;
    ws.getSelectedWeapon().untilReload = 1.0;
    ws.think(0.1);
    expect(ws.reloading(), isTrue);
    ws.draw(canvas.context2D);

    ws.think(1.5);
    expect(ws.reloading(), isFalse);
    ws.draw(canvas.context2D);
  });

  test("Weapon selector wheel starts with full clips and renders clip badges for every weapon", () {
    MockPeerWrapper mockPeer = MockPeerWrapper();
    when(mockPeer.getId()).thenReturn("a");
    when(mockCommanderNetwork.peer).thenReturn(mockPeer);

    final HTMLImageElement dummyIcons = HTMLImageElement()
      ..width = 1280
      ..height = 128;
    when(mockCommanderWormWorld.imageIndex()).thenReturn(mockImageIndex);
    when(mockImageIndex.getImageByName("weapon_icons.png"))
        .thenReturn(dummyIcons);

    WeaponState ws = commanderSprite.weaponState!;
    // Every weapon starts with a full clip so unselected weapons show full ammo in the wheel.
    for (final Weapon w in ws.weapons) {
      expect(w.shotsLeft, equals(w.shotsPerClip),
          reason: "Weapon ${w.name} should start loaded with full clip");
    }

    // Mix of full, partially drained, low, and reloading weapons on the wheel.
    ws.weapons[0].shotsLeft = 1; // Low clip (1/2)
    ws.weapons[2].shotsLeft = 2; // Partial clip (2/4)
    ws.weapons[3].shotsLeft = 0;
    ws.weapons[3].untilReload = 2.4; // Reloading
    ws.changeTime = WeaponState.SHOW_WEAPON_NAME_TIME;

    FakeCanvas canvas = FakeCanvas();
    ws.drawWeaponHelper(canvas.context2D, const Point(400, 400), true);
  });

  test("PlayerGunSprite renders upright aiming right and left with firing recoil", () {
    final HTMLImageElement gunImg = HTMLImageElement()
      ..width = 180
      ..height = 54;
    when(mockImageIndex.getImageById(3)).thenReturn(gunImg);

    expect(commanderSprite.gun, isA<PlayerGunSprite>());
    expect(commanderSprite.gun.size.x, equals(60.0));

    FakeCanvas canvas = FakeCanvas();
    commanderSprite.gun.angle = 0.0;
    commanderSprite.gun.frame(0.016, 1);
    commanderSprite.gun.draw(canvas.context2D, false);

    // Spend one shot -> triggers recoil kick cleanly; also verify left-aiming upright draw!
    commanderSprite.weaponState!.getSelectedWeapon().shotsLeft--;
    commanderSprite.gun.angle = -2.6;
    commanderSprite.gun.frame(0.016, 1);
    commanderSprite.gun.draw(canvas.context2D, false);
  });

  test("Static fixed-distance crosshair guide reflects straight Zooka, lobbed Banana, and short-dropped Cat Litter Box while ignoring player velocity and walls", () {
    MockByteWorld mockByteWorld = MockByteWorld();
    when(mockByteWorld.byteWorldReady()).thenReturn(true);
    when(mockByteWorld.width).thenReturn(600);
    when(mockByteWorld.height).thenReturn(400);
    // Solid wall right at x = 140 — guide must ignore terrain collisions!
    when(mockByteWorld.isSolid(any, any)).thenAnswer((inv) {
      final int x = inv.positionalArguments[0] as int;
      return x >= 140;
    });
    when(mockCommanderWormWorld.byteWorld).thenReturn(mockByteWorld);
    when(mockCommanderWormWorld.gravity).thenReturn(Vec2(0.0, 300.0));
    MockSpriteIndex mockSprites = MockSpriteIndex();
    when(mockSprites.spriteIds()).thenReturn([1]);
    when(mockSprites[1]).thenReturn(commanderSprite);
    when(mockCommanderWormWorld.spriteIndex).thenReturn(mockSprites);

    MockPeerWrapper mockPeer = MockPeerWrapper();
    when(mockPeer.getId()).thenReturn("a");
    when(mockCommanderNetwork.peer).thenReturn(mockPeer);

    commanderSprite.position = Vec2(80.0, 140.0);
    commanderSprite.velocity = Vec2.ZERO;
    commanderSprite.gun.angle = 0.0; // Aiming straight right
    final WeaponState ws = commanderSprite.weaponState!;

    // 1. Zooka goes virtually straight horizontally to fixed AIM_GUIDE_DISTANCE (ignoring solid wall at x=140).
    ws.selectedWeaponIndex = ws.weapons.indexWhere((w) => w.name == "Zooka");
    final TrajectoryGuideTrace zookaGuide = ws.computeTrajectoryGuide();
    final double muzzleY = zookaGuide.points.first.y;
    expect(zookaGuide.crosshair.x - zookaGuide.points.first.x,
        closeTo(WeaponState.AIM_GUIDE_DISTANCE, 1.5));
    expect((zookaGuide.crosshair.y - muzzleY).abs(), lessThan(2.5));

    // 2. Banana pancake curves moderately downward over the fixed guide distance.
    ws.selectedWeaponIndex =
        ws.weapons.indexWhere((w) => w.name == "Banana pancake");
    final TrajectoryGuideTrace bananaGuide = ws.computeTrajectoryGuide();
    expect(bananaGuide.crosshair.y - muzzleY, greaterThan(40.0));

    // 3. Cat litter box drops much more steeply right in front of the player!
    ws.selectedWeaponIndex =
        ws.weapons.indexWhere((w) => w.name == "Cat litter box");
    final TrajectoryGuideTrace litterGuide = ws.computeTrajectoryGuide();
    expect(litterGuide.crosshair.x, lessThan(bananaGuide.crosshair.x - 30.0));
    expect(litterGuide.crosshair.y - muzzleY, greaterThan(75.0));

    // 4. Player velocity is ignored — guide stays completely identical while moving/jumping!
    commanderSprite.velocity = Vec2(120.0, -250.0);
    ws.selectedWeaponIndex =
        ws.weapons.indexWhere((w) => w.name == "Banana pancake");
    final TrajectoryGuideTrace movingBananaGuide = ws.computeTrajectoryGuide();
    expect(movingBananaGuide.crosshair.x, closeTo(bananaGuide.crosshair.x, 1e-6));
    expect(movingBananaGuide.crosshair.y, closeTo(bananaGuide.crosshair.y, 1e-6));

    // 5. Renders cleanly for every weapon on canvas.
    FakeCanvas canvas = FakeCanvas();
    for (int i = 0; i < ws.weapons.length; i++) {
      ws.selectedWeaponIndex = i;
      ws.think(0.03);
      ws.draw(canvas.context2D);
    }
  });

  test("Spawn into game triggers short visual pop-in effect and Sound.SPAWN on inGame transition", () {
    MockPeerWrapper mockPeer = MockPeerWrapper();
    when(mockPeer.getId()).thenReturn("a");
    when(mockCommanderNetwork.peer).thenReturn(mockPeer);

    expect(commanderSprite.inGame(), isFalse);
    expect(commanderSprite.spawnEffectRemaining, equals(0.0));

    // Transitioning into game triggers the 0.65s spawn effect and plays Sound.SPAWN!
    commanderSprite.info.inGame = true;
    commanderSprite.frame(0.05, 1);
    expect(commanderSprite.spawnEffectRemaining, closeTo(0.60, 0.02));
    verify(mockCommanderWormWorld.playSound(Sound.SPAWN,
            volume: anyNamed('volume'), multiPlay: true))
        .called(1);

    // Renders backdrop beam, elastic squash-stretch player, and foreground poof/stars cleanly,
    // then expires after SPAWN_EFFECT_DURATION.
    FakeCanvas canvas = FakeCanvas();
    commanderSprite.draw(canvas.context2D, false);
    commanderSprite.frame(0.30, 1);
    commanderSprite.draw(canvas.context2D, false);
    commanderSprite.frame(0.40, 1);
    expect(commanderSprite.spawnEffectRemaining, equals(0.0));
  });

  test("Player aim speed is 2.8 rad/s, Mole tunnel radius is 25.75, and Snailgun trail is smaller", () {
    MockPeerWrapper mockPeer = MockPeerWrapper();
    when(mockPeer.getId()).thenReturn("a");
    when(mockCommanderNetwork.peer).thenReturn(mockPeer);
    when(mockCommanderWormWorld.imageIndex()).thenReturn(mockImageIndex);
    when(mockImageIndex.getImageIdByName("zooka.png")).thenReturn(3);
    when(mockImageIndex.getImageIdByName("snails.png")).thenReturn(3);

    final KeyState ks =
        mockCommanderNetwork.getGameState().getKeyStateFor("a")!;
    commanderSprite.info.inGame = true;
    commanderSprite.angle = 0.0;
    commanderSprite.gun.angle = 0.0;

    // Aim up for 0.25s -> rotates by -0.25 * 2.8 = -0.70 rad (30% slower than 4.0 rad/s).
    final int aimUpKey = commanderSprite.getControls()["Aim up"]!;
    final int aimDownKey = commanderSprite.getControls()["Aim down"]!;
    ks.keysDown[aimUpKey] = 1.0;
    commanderSprite.checkControlKeys(0.25);
    ks.keysDown.remove(aimUpKey);
    expect(commanderSprite.gun.angle, closeTo(-0.25 * LocalPlayerSprite.AIM_SPEED, 1e-6));
    expect(LocalPlayerSprite.AIM_SPEED, closeTo(2.8, 1e-6));

    // Aim down for 0.25s -> returns back to 0.0 rad.
    ks.keysDown[aimDownKey] = 1.0;
    commanderSprite.checkControlKeys(0.25);
    ks.keysDown.remove(aimDownKey);
    expect(commanderSprite.gun.angle, closeTo(0.0, 1e-6));

    // Mole tunnel radius (+5% from 24.5 -> 25.75) vs narrower Snailgun trail carve radius (13.5).
    expect(MoleDrillProjectile.TUNNEL_RADIUS, closeTo(25.75, 1e-6));
    final SnailProjectile snail = SnailProjectile.createWithOwner(
        mockCommanderWormWorld, commanderSprite, 12, commanderSprite.gun);
    expect(snail.radius, equals(SnailProjectile.TRAIL_CARVE_RADIUS));
    expect(SnailProjectile.TRAIL_CARVE_RADIUS, lessThan(15.0));
  });
}