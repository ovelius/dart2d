import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart2d/net/net.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'lib/test_mocks.mocks.dart';

int _countOpaquePixels(HTMLCanvasElement canvas,
    {int startX = 0, int? endX, int startY = 0, int? endY}) {
  final int x0 = startX.clamp(0, canvas.width);
  final int x1 = (endX ?? canvas.width).clamp(x0, canvas.width);
  final int y0 = startY.clamp(0, canvas.height);
  final int y1 = (endY ?? canvas.height).clamp(y0, canvas.height);
  if (x1 <= x0 || y1 <= y0) return 0;
  final Uint8ClampedList data = canvas.context2D
      .getImageData(x0, y0, x1 - x0, y1 - y0)
      .data
      .toDart;
  int count = 0;
  for (int i = 3; i < data.length; i += 4) {
    if (data[i] > 128) count++;
  }
  return count;
}

int _countPixelDifferences(HTMLCanvasElement a, HTMLCanvasElement b) {
  expect(a.width, equals(b.width));
  expect(a.height, equals(b.height));
  final Uint8ClampedList da =
      a.context2D.getImageData(0, 0, a.width, a.height).data.toDart;
  final Uint8ClampedList db =
      b.context2D.getImageData(0, 0, b.width, b.height).data.toDart;
  int diffs = 0;
  for (int i = 0; i < da.length; i += 4) {
    if (da[i] != db[i] ||
        da[i + 1] != db[i + 1] ||
        da[i + 2] != db[i + 2] ||
        da[i + 3] != db[i + 3]) {
      diffs++;
    }
  }
  return diffs;
}

List<double> _averageOpaqueRgb(HTMLCanvasElement canvas) {
  final Uint8ClampedList data = canvas.context2D
      .getImageData(0, 0, canvas.width, canvas.height)
      .data
      .toDart;
  double r = 0, g = 0, b = 0;
  int count = 0;
  for (int i = 0; i < data.length; i += 4) {
    if (data[i + 3] > 128) {
      r += data[i];
      g += data[i + 1];
      b += data[i + 2];
      count++;
    }
  }
  if (count == 0) return [0, 0, 0];
  return [r / count, g / count, b / count];
}

void main() {
  setUpAll(() {
    configureDependencies();
  });

  setUp(() {
    logOutputForTest();
    clearEnvironment();
    WorldGenerator.clearCache();
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  group('WorldThemes and WorldGenerator tests', () {
    test('Defines 8 distinct themes (with Villa and low-G Lunar) and 30% wider worlds', () {
      expect(WorldGenerator.DEFAULT_WIDTH, equals(2080));
      expect(WorldGenerator.DEFAULT_HEIGHT, equals(900));

      expect(WORLD_THEMES, hasLength(8));
      final Set<String> keys = WORLD_THEMES.map((t) => t.key).toSet();
      expect(keys, hasLength(8));
      expect(
          keys,
          containsAll([
            'villa',
            'spooky',
            'volcano',
            'glacier',
            'candy',
            'lunar',
            'city',
            'jungle',
          ]));
      for (final WorldThemeSpec t in WORLD_THEMES) {
        expect(t.key.toLowerCase(), isNot(contains('pippi')));
        expect(t.name.toLowerCase(), isNot(contains('pippi')));
        expect(t.subtitle.toLowerCase(), isNot(contains('pippi')));
      }

      final WorldThemeSpec lunar = worldThemeById(WorldThemeId.lunar);
      expect(lunar.isLowGravity, isTrue);
      expect(lunar.gravity, equals(LUNAR_WORLD_GRAVITY));
      expect(lunar.gravity, lessThan(DEFAULT_WORLD_GRAVITY));

      for (final WorldThemeSpec t in WORLD_THEMES) {
        if (t.id != WorldThemeId.lunar) {
          expect(t.gravity, equals(DEFAULT_WORLD_GRAVITY));
        }
      }
    });

    test('encodeGeneratedMapName and parseGeneratedMapName roundtrip cleanly', () {
      final String encoded = encodeGeneratedMapName(WorldThemeId.lunar, 123456);
      expect(encoded, equals('gen:lunar:123456'));
      final ParsedGeneratedMap? parsed = parseGeneratedMapName(encoded);
      expect(parsed, isNotNull);
      expect(parsed!.theme.id, equals(WorldThemeId.lunar));
      expect(parsed.seed, equals(123456));
      expect(parseGeneratedMapName('world_map.png'), isNull);
      expect(parseGeneratedMapName('gen:unknown:42'), isNull);
    });

    test('Generates terrain, bedrock, previews, and gameplay sky for all 8 themes', () {
      FakeCanvas skyCanvas = FakeCanvas();
      for (final WorldThemeSpec theme in WORLD_THEMES) {
        final GeneratedWorldResult res = WorldGenerator.generate(
          theme.id,
          4242,
          width: 400,
          height: 225,
        );
        expect(res.terrainCanvas.width, equals(400));
        expect(res.terrainCanvas.height, equals(225));
        final int terrainOpaque = _countOpaquePixels(res.terrainCanvas);
        final int bedrockOpaque = _countOpaquePixels(res.bedrockCanvas);
        expect(terrainOpaque, greaterThan(5000),
            reason: 'Theme ${theme.key} should have substantial playable terrain');
        expect(bedrockOpaque, greaterThan(1000),
            reason: 'Theme ${theme.key} should include clear thematic indestructible bedrock');
        expect(terrainOpaque, greaterThan(bedrockOpaque),
            reason: 'Theme ${theme.key} should have destructible terrain beyond bedrock');

        final HTMLCanvasElement preview = WorldGenerator.getThemePreview(theme);
        expect(preview.width, greaterThan(0));
        expect(preview.height, greaterThan(0));

        WorldGenerator.drawGameplaySky(
            skyCanvas.context2D, skyCanvas.width, skyCanvas.height, theme, 1.5,
            seed: 4242);
      }
    });

    test('ByteWorld preserves generated bedrock pixels when blasting terrain', () async {
      final GeneratedWorldResult gen = WorldGenerator.generate(
        WorldThemeId.city,
        99,
        width: 320,
        height: 180,
      );
      final HTMLImageElement img = HTMLImageElement();
      img.src = gen.toDataUrl();
      await img.onLoad.first;

      final ByteWorld bw = ByteWorld(
        FakeImageFactory(),
        320,
        180,
        FakeImageDataFactory(),
        FakeCanvasFactory(),
      );
      bw.setWorldImage(img, bedrockCanvas: gen.bedrockCanvas);
      expect(bw.byteWorldReady(), isTrue);

      // Find an actual opaque bedrock pixel coordinate.
      final Uint8ClampedList bData = gen.bedrockCanvas.context2D
          .getImageData(0, 0, gen.bedrockCanvas.width, gen.bedrockCanvas.height)
          .data
          .toDart;
      int? bedrockX;
      int? bedrockY;
      for (int y = 0; y < gen.bedrockCanvas.height && bedrockX == null; y++) {
        for (int x = 0; x < gen.bedrockCanvas.width; x++) {
          if (bData[(y * gen.bedrockCanvas.width + x) * 4 + 3] > 200) {
            bedrockX = x;
            bedrockY = y;
            break;
          }
        }
      }
      expect(bedrockX, isNotNull);
      expect(bw.isSolid(bedrockX!, bedrockY!), isTrue);

      // Wait for the async _bedrockImage data URL to decode so clearAt restores bedrock.
      await Future.delayed(Duration(milliseconds: 50));

      // Blast right on top of the bedrock pixel -> bedrock must remain solid!
      bw.clearAt(Vec2(bedrockX.toDouble(), bedrockY.toDouble()), 22.0);
      expect(bw.isSolid(bedrockX, bedrockY), isTrue);
    });

    test('Mega Man 3x3 selector navigates around center player tile and selects generated map', () async {
      WormWorld worldA = await createTestWorld(
        'a',
        signalPeerOpen: true,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false,
      );
      PlayerWorldSelector selector = getIt<PlayerWorldSelector>();
      KeyState keyState = worldA.localKeyState;

      // Render Mega Man 3x3 selector with player sprite in the center.
      selector.frame(0.05);

      // Navigate with 4-way arrow keys (never lands on center).
      int initial = selector.selectedMapIndex;
      keyState.onKeyDown(KeyCodeDart.RIGHT);
      keyState.onKeyUp(KeyCodeDart.RIGHT);
      expect(selector.selectedMapIndex, isNot(equals(initial)));

      keyState.onKeyDown(KeyCodeDart.DOWN);
      keyState.onKeyUp(KeyCodeDart.DOWN);
      selector.frame(0.05);

      // Confirm selection -> produces a valid gen:<theme>:<seed> map key!
      selector.maybeSelectPlayerOrMap();
      expect(selector.selectedWorldName, isNotNull);
      expect(parseGeneratedMapName(selector.selectedWorldName), isNotNull);
    });

    test('WormWorld applies Lunar low gravity when Lunar map is active', () async {
      WormWorld worldA = await createTestWorld('a');
      worldA.startAsServer('playerA');

      // Lunar map sets low gravity.
      worldA.network().getGameState().gameStateProto.mapName =
          encodeGeneratedMapName(WorldThemeId.lunar, 777);
      worldA.frameDraw(0.02);
      expect(worldA.gravity.y, equals(LUNAR_WORLD_GRAVITY));

      // Villa map restores standard gravity.
      worldA.network().getGameState().gameStateProto.mapName =
          encodeGeneratedMapName(WorldThemeId.villa, 888);
      worldA.frameDraw(0.02);
      expect(worldA.gravity.y, equals(DEFAULT_WORLD_GRAVITY));
    });

    test('Commander preserves mapName and syncs vector skybox descriptor to remote client', () async {
      WormWorld worldA = await createTestWorld('a');
      final String lunarKey = encodeGeneratedMapName(WorldThemeId.lunar, 5150);
      worldA.network().getGameState().gameStateProto.mapName = lunarKey;
      // Calling setAsActingCommander must NOT wipe mapName!
      worldA.network().setAsActingCommander();
      expect(worldA.network().getGameState().gameStateProto.mapName, equals(lunarKey));

      // Verify a joining client receives the exact one-time vector skybox descriptor via GameStateProto.
      WormWorld worldB = await createTestWorld('b', selectMap: false);
      worldB.network().getGameState().updateFromMap(
          worldA.network().getGameState().gameStateProto);
      expect(worldB.network().getGameState().gameStateProto.mapName, equals(lunarKey));
      worldB.frameDraw(0.02);
      expect(worldB.gravity.y, equals(LUNAR_WORLD_GRAVITY));
    });

    test('End-to-end late joiner receives one-time vector skybox and Lunar low gravity over network', () async {
      expectWarningContaining('Duplicate handshake received');
      expectWarningContaining('Commander data update for missing sprite');
      final String lunarKey = encodeGeneratedMapName(WorldThemeId.lunar, 9001);

      WormWorld worldA = await createTestWorld('a');
      worldA.startAsServer('CommanderA');
      worldA.network().getGameState().gameStateProto.mapName = lunarKey;
      worldA.frameDraw(0.02);
      expect(worldA.gravity.y, equals(LUNAR_WORLD_GRAVITY));

      // Late-joining client connects over test peer transport with no pre-selected map.
      WormWorld worldB = await createTestWorld('b', selectMap: false);
      expect(worldB.network().getGameState().gameStateProto.mapName, isEmpty);

      worldB.connectTo('a', 'ClientB');
      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      // Client B received the compact `gen:lunar:9001` descriptor once via CommanderGameReply.
      expect(worldB.network().getGameState().gameStateProto.mapName,
          equals(lunarKey));
      expect(worldB.gravity.y, equals(LUNAR_WORLD_GRAVITY));
    });

    test('Commander migration preserves vector skybox descriptor and Lunar low gravity', () async {
      expectWarningContaining('Duplicate handshake received');
      expectWarningContaining('Commander data update for missing sprite');
      expectWarningContaining('Received offer from peer that has connection');
      expectWarningContaining('Not parsing gamestate from');
      expectWarningContaining('Not drawing name');
      expectWarningContaining('Dropping old data');
      final String lunarKey = encodeGeneratedMapName(WorldThemeId.lunar, 7777);

      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b', selectMap: false);
      WormWorld worldC = await createTestWorld('c', selectMap: false);

      worldA.startAsServer('nameA');
      worldA.network().getGameState().gameStateProto.mapName = lunarKey;
      worldA.frameDraw(0.02);

      worldB.connectTo('a', 'nameB');
      worldC.connectTo('a', 'nameC');
      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldB.network().getGameState().gameStateProto.mapName, equals(lunarKey));
      expect(worldC.network().getGameState().gameStateProto.mapName, equals(lunarKey));

      // Drop commander A so B/C elect a new commander.
      testConnections['a']!.forEach((e) => e.signalClose());
      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 8);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 8);
      }

      expect(worldB.isCommander || worldC.isCommander, isTrue);
      expect(worldB.network().getGameState().gameStateProto.mapName, equals(lunarKey));
      expect(worldC.network().getGameState().gameStateProto.mapName, equals(lunarKey));
      expect(worldB.gravity.y, equals(LUNAR_WORLD_GRAVITY));
      expect(worldC.gravity.y, equals(LUNAR_WORLD_GRAVITY));
    });

    test('Seeded vector skybox is pixel-deterministic, varies by seed/theme, and animates over time', () {
      final WorldThemeSpec lunar = worldThemeById(WorldThemeId.lunar);
      final WorldThemeSpec villa = worldThemeById(WorldThemeId.villa);
      final WorldThemeSpec jungle = worldThemeById(WorldThemeId.jungle);

      HTMLCanvasElement makeCanvas() => HTMLCanvasElement()
        ..width = 240
        ..height = 135;

      // Same (theme, seed, time) after cache clear -> pixel-identical across peers!
      final HTMLCanvasElement c1 = makeCanvas();
      final HTMLCanvasElement c2 = makeCanvas();
      WorldGenerator.drawGameplaySky(c1.context2D, 240, 135, lunar, 2.5, seed: 31415);
      WorldGenerator.clearCache();
      WorldGenerator.drawGameplaySky(c2.context2D, 240, 135, lunar, 2.5, seed: 31415);
      expect(_countPixelDifferences(c1, c2), equals(0),
          reason: 'Two peers with the same vector descriptor must render identical skyboxes');

      // Different seed -> deterministic vector variation (planet/star positions shift).
      final HTMLCanvasElement cDiffSeed = makeCanvas();
      WorldGenerator.drawGameplaySky(
          cDiffSeed.context2D, 240, 135, lunar, 2.5, seed: 99999);
      expect(_countPixelDifferences(c1, cDiffSeed), greaterThan(100));

      // Live animation advances over time (twinkling stars / drifting clouds).
      final HTMLCanvasElement cLater = makeCanvas();
      WorldGenerator.drawGameplaySky(
          cLater.context2D, 240, 135, villa, 0.0, seed: 123);
      final HTMLCanvasElement cLater2 = makeCanvas();
      WorldGenerator.drawGameplaySky(
          cLater2.context2D, 240, 135, villa, 12.0, seed: 123);
      expect(_countPixelDifferences(cLater, cLater2), greaterThan(50));

      // Villa vs Jungle skyboxes are clearly distinct.
      final HTMLCanvasElement cJungle = makeCanvas();
      WorldGenerator.drawGameplaySky(
          cJungle.context2D, 240, 135, jungle, 0.0, seed: 123);
      expect(_countPixelDifferences(cLater, cJungle), greaterThan(15000));
    });

    test('Default 2080x900 generation populates terrain and thematic bedrock across all 3 horizontal zones', () {
      final GeneratedWorldResult? villa =
          WorldGenerator.generateFromMapKey('gen:villa:2026');
      expect(villa, isNotNull);
      expect(villa!.terrainCanvas.width, equals(2080));
      expect(villa.terrainCanvas.height, equals(900));
      expect(villa.bedrockCanvas.width, equals(2080));
      expect(villa.bedrockCanvas.height, equals(900));

      // Split the 2080px arena into left, center, and right thirds and verify
      // both destructible terrain and thematic bedrock span the entire wider map.
      final int third = 2080 ~/ 3;
      for (int zone = 0; zone < 3; zone++) {
        final int x0 = zone * third;
        final int x1 = (zone == 2) ? 2080 : (zone + 1) * third;
        final int zoneTerrain =
            _countOpaquePixels(villa.terrainCanvas, startX: x0, endX: x1);
        final int zoneBedrock =
            _countOpaquePixels(villa.bedrockCanvas, startX: x0, endX: x1);
        expect(zoneTerrain, greaterThan(80000),
            reason: 'Zone $zone of wider 2080px Villa world should have rich terrain');
        expect(zoneBedrock, greaterThan(2000),
            reason: 'Zone $zone of wider 2080px Villa world should include bedrock');
      }
    });

    test('All 8 themes distribute bedrock across the map, are deterministic by seed, and Villa differs from Jungle', () {
      for (final WorldThemeSpec theme in WORLD_THEMES) {
        final GeneratedWorldResult a = WorldGenerator.generate(
          theme.id,
          1337,
          width: 416,
          height: 180,
        );
        // Bedrock spans left and right halves of the arena on every theme.
        final int leftBedrock =
            _countOpaquePixels(a.bedrockCanvas, startX: 0, endX: 208);
        final int rightBedrock =
            _countOpaquePixels(a.bedrockCanvas, startX: 208, endX: 416);
        expect(leftBedrock, greaterThan(400),
            reason: '${theme.key} should have bedrock in left half');
        expect(rightBedrock, greaterThan(400),
            reason: '${theme.key} should have bedrock in right half');

        // Re-generating same (theme, seed) after cache clear is pixel-identical.
        WorldGenerator.clearCache();
        final GeneratedWorldResult b = WorldGenerator.generate(
          theme.id,
          1337,
          width: 416,
          height: 180,
        );
        expect(_countPixelDifferences(a.terrainCanvas, b.terrainCanvas), equals(0),
            reason: '${theme.key} terrain must be deterministic for same seed');
        expect(_countPixelDifferences(a.bedrockCanvas, b.bedrockCanvas), equals(0),
            reason: '${theme.key} bedrock must be deterministic for same seed');
      }

      // Different seeds produce meaningfully different layouts.
      final GeneratedWorldResult villa1 =
          WorldGenerator.generate(WorldThemeId.villa, 101, width: 416, height: 180);
      final GeneratedWorldResult villa2 =
          WorldGenerator.generate(WorldThemeId.villa, 909, width: 416, height: 180);
      expect(_countPixelDifferences(villa1.terrainCanvas, villa2.terrainCanvas),
          greaterThan(2500));

      // Villa (bright sunny cottage meadow) and Jungle (deep emerald ruins) are visually distinct.
      final GeneratedWorldResult jungle =
          WorldGenerator.generate(WorldThemeId.jungle, 101, width: 416, height: 180);
      expect(_countPixelDifferences(villa1.terrainCanvas, jungle.terrainCanvas),
          greaterThan(15000));
      final List<double> villaRgb = _averageOpaqueRgb(villa1.terrainCanvas);
      final List<double> jungleRgb = _averageOpaqueRgb(jungle.terrainCanvas);
      final double colorDelta = (villaRgb[0] - jungleRgb[0]).abs() +
          (villaRgb[1] - jungleRgb[1]).abs() +
          (villaRgb[2] - jungleRgb[2]).abs();
      expect(colorDelta, greaterThan(35.0),
          reason: 'Villa and Jungle should have clearly distinct color palettes');
    });

    test('ByteWorld blasts destructible terrain while preserving thematic bedrock on Villa and Lunar', () async {
      for (final WorldThemeId themeId in const [WorldThemeId.villa, WorldThemeId.lunar]) {
        final GeneratedWorldResult gen = WorldGenerator.generate(
          themeId,
          77,
          width: 416,
          height: 180,
        );
        final HTMLImageElement img = HTMLImageElement();
        img.src = gen.toDataUrl();
        await img.onLoad.first;

        final ByteWorld bw = ByteWorld(
          FakeImageFactory(),
          416,
          180,
          FakeImageDataFactory(),
          FakeCanvasFactory(),
        );
        bw.setWorldImage(img, bedrockCanvas: gen.bedrockCanvas);
        await Future.delayed(Duration(milliseconds: 50));

        final Uint8ClampedList tData = gen.terrainCanvas.context2D
            .getImageData(0, 0, gen.terrainCanvas.width, gen.terrainCanvas.height)
            .data
            .toDart;
        final Uint8ClampedList bData = gen.bedrockCanvas.context2D
            .getImageData(0, 0, gen.bedrockCanvas.width, gen.bedrockCanvas.height)
            .data
            .toDart;

        int? bedrockX, bedrockY;
        int? destructibleX, destructibleY;
        for (int y = 4; y < 176; y++) {
          for (int x = 4; x < 412; x++) {
            final int aIdx = (y * 416 + x) * 4 + 3;
            if (bedrockX == null && bData[aIdx] > 220) {
              bedrockX = x;
              bedrockY = y;
            }
            if (destructibleX == null && tData[aIdx] > 220 && bData[aIdx] == 0) {
              // Pick a destructible pixel far from bedrock so a small blast clears it cleanly.
              bool nearBedrock = false;
              for (int dy = -6; dy <= 6 && !nearBedrock; dy++) {
                for (int dx = -6; dx <= 6; dx++) {
                  final int ny = (y + dy).clamp(0, 179);
                  final int nx = (x + dx).clamp(0, 415);
                  if (bData[(ny * 416 + nx) * 4 + 3] > 0) {
                    nearBedrock = true;
                    break;
                  }
                }
              }
              if (!nearBedrock) {
                destructibleX = x;
                destructibleY = y;
              }
            }
            if (bedrockX != null && destructibleX != null) break;
          }
          if (bedrockX != null && destructibleX != null) break;
        }

        expect(bedrockX, isNotNull);
        expect(destructibleX, isNotNull);
        expect(bw.isSolid(bedrockX!, bedrockY!), isTrue);
        expect(bw.isSolid(destructibleX!, destructibleY!), isTrue);

        // Blasting destructible terrain clears it; blasting bedrock keeps it solid!
        bw.clearAt(Vec2(destructibleX.toDouble(), destructibleY.toDouble()), 5.0);
        expect(bw.isSolid(destructibleX, destructibleY), isFalse,
            reason: 'Destructible terrain in ${themeId.name} should clear on blast');

        bw.clearAt(Vec2(bedrockX.toDouble(), bedrockY.toDouble()), 18.0);
        expect(bw.isSolid(bedrockX, bedrockY), isTrue,
            reason: 'Thematic bedrock in ${themeId.name} must survive blast');
      }
    });

    test('Mega Man 3x3 selector hops cleanly over center player cell from every outer tile', () async {
      WormWorld worldA = await createTestWorld(
        'a',
        signalPeerOpen: true,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false,
      );
      PlayerWorldSelector selector = getIt<PlayerWorldSelector>();
      KeyState keyState = worldA.localKeyState;

      // Exercise all 4 arrow directions repeatedly and ensure selection always
      // changes to a valid outer theme index in 0..7.
      const List<int> dirs = [
        KeyCodeDart.RIGHT,
        KeyCodeDart.DOWN,
        KeyCodeDart.LEFT,
        KeyCodeDart.UP,
      ];
      final Set<int> visited = {selector.selectedMapIndex};
      for (int round = 0; round < 3; round++) {
        for (final int key in dirs) {
          final int before = selector.selectedMapIndex;
          keyState.onKeyDown(key);
          keyState.onKeyUp(key);
          final int after = selector.selectedMapIndex;
          expect(after, inInclusiveRange(0, WORLD_THEMES.length - 1));
          expect(after, isNot(equals(before)));
          visited.add(after);
        }
      }
      expect(visited.length, greaterThanOrEqualTo(4));
    });

    test('All 8 themes have solid bottom edge (no under-world spawn gap) and no pre-carved ground holes', () {
      const int w = 416;
      const int h = 180;
      for (final WorldThemeSpec theme in WORLD_THEMES) {
        final GeneratedWorldResult gen =
            WorldGenerator.generate(theme.id, 4242, width: w, height: h);
        final Uint8ClampedList data = gen.terrainCanvas.context2D
            .getImageData(0, 0, w, h)
            .data
            .toDart;

        // 1. Entire bottom strip (y = h - 4 .. h - 1) must be 100% solid across all x!
        int bottomEmpty = 0;
        for (int y = h - 4; y < h; y++) {
          for (int x = 0; x < w; x++) {
            if (data[(y * w + x) * 4 + 3] <= 128) {
              bottomEmpty++;
            }
          }
        }
        expect(bottomEmpty, equals(0),
            reason: 'Theme ${theme.key} must not have an empty gap along the bottom edge');

        // 2. Deep central ground band (y = 88%..97%, x = 15%..85%) must be solid (no pre-destroyed carved tunnels!).
        int deepCenterEmpty = 0;
        for (int y = (h * 0.89).toInt(); y < h - 4; y++) {
          for (int x = (w * 0.15).toInt(); x < (w * 0.85).toInt(); x++) {
            if (data[(y * w + x) * 4 + 3] <= 128) {
              deepCenterEmpty++;
            }
          }
        }
        expect(deepCenterEmpty, equals(0),
            reason: 'Theme ${theme.key} must not have pre-destroyed carved holes in the ground');
      }
    });
  });
}
