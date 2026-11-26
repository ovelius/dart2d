import 'package:dart2d/net/state_updates.pb.dart';
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
    // Detects enemy sitting behind the wall at x ~ 341.
    expect(trace.playerHits, hasLength(1));
    expect(trace.playerHits.first.x, closeTo(341.0, 1.0));

    // Renders cleanly on canvas.
    FakeCanvas canvas = FakeCanvas();
    ws.think(0.05);
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
    ws.selectedWeaponIndex = ws.weapons.indexWhere((w) => w.name == "Shotgun");
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
}