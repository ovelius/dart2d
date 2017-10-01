import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:mockito/mockito.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/util/util.dart';

void main() {
  MockWormWorld mockWormWorld;
  MockWormWorld mockCommanderWormWorld;
  MockImageIndex mockImageIndex;
  MockNetwork mockNetwork;
  MockNetwork mockCommanderNetwork;
  LocalPlayerSprite commanderSprite;
  LocalPlayerSprite otherSprite;
  setUp(() {
    logOutputForTest();
    mockNetwork = new MockNetwork();
    mockCommanderNetwork = new MockNetwork();

    mockWormWorld = new MockWormWorld();
    when(mockWormWorld.network()).thenReturn(mockNetwork);
    mockCommanderWormWorld = new MockWormWorld();
    when(mockCommanderWormWorld.network()).thenReturn(mockCommanderNetwork);

    mockImageIndex = new MockImageIndex();
    when(mockNetwork.isCommander()).thenReturn(false);
    when(mockCommanderNetwork.isCommander()).thenReturn(true);
    when(mockImageIndex.getImageById(2)).thenReturn(new FakeImage());
    when(mockImageIndex.getImageById(3)).thenReturn(new FakeImage());
    when(mockImageIndex.getImageIdByName("gun.png")).thenReturn(3);
    when(mockImageIndex.getImageIdByName("shield.png")).thenReturn(3);
    commanderSprite = new LocalPlayerSprite(
        mockCommanderWormWorld, mockImageIndex, null, new PlayerInfo("test1", "a", 1), Vec2.ZERO, 2);
    otherSprite = new LocalPlayerSprite(
        mockWormWorld, mockImageIndex, null, new PlayerInfo("test1", "a", 1), Vec2.ZERO, 2);
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
}