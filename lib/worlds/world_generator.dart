import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart';

import 'world_themes.dart';

enum _BedrockStyle {
  ironVault,
  gothicRune,
  lavaForged,
  frostCrystal,
  peppermintSteel,
  titaniumHazard,
  cityGirder,
  mayanGold,
}

class GeneratedWorldResult {
  final String mapKey;
  final WorldThemeSpec theme;
  final int seed;
  final HTMLCanvasElement terrainCanvas;
  final HTMLCanvasElement bedrockCanvas;

  GeneratedWorldResult({
    required this.mapKey,
    required this.theme,
    required this.seed,
    required this.terrainCanvas,
    required this.bedrockCanvas,
  });

  String toDataUrl() => terrainCanvas.toDataUrl('image/png');
}

/// Deterministic cartoon procedural world generator for all 8 ZooBlast themes.
/// Produces both the destructible terrain canvas (rich cel-shaded Worms/Liero
/// islands, towers, caves, floating platforms, props & gimmicks) and a matching
/// thematic indestructible bedrock canvas, plus a deterministic one-time vector
/// skybox synced across the network via `gen:<theme>:<seed>`.
class WorldGenerator {
  // 30% wider than the original 1600px arenas for sprawling Worms/Liero battles!
  static const int DEFAULT_WIDTH = 2080;
  static const int DEFAULT_HEIGHT = 900;

  static final Map<String, GeneratedWorldResult> _cache = {};
  static final Map<WorldThemeId, HTMLCanvasElement> _previewCache = {};
  static final Map<String, HTMLCanvasElement> _skyCache = {};

  static GeneratedWorldResult? getCached(String mapKey) => _cache[mapKey];

  static void clearCache() {
    _cache.clear();
    _previewCache.clear();
    _skyCache.clear();
  }

  /// Generates (or returns cached) deterministic world for [mapKey] (`gen:<theme>:<seed>`).
  static GeneratedWorldResult? generateFromMapKey(
    String mapKey, {
    int width = DEFAULT_WIDTH,
    int height = DEFAULT_HEIGHT,
  }) {
    final ParsedGeneratedMap? parsed = parseGeneratedMapName(mapKey);
    if (parsed == null) return null;
    return generate(parsed.theme.id, parsed.seed,
        width: width, height: height, mapKey: mapKey);
  }

  static GeneratedWorldResult generate(
    WorldThemeId themeId,
    int seed, {
    int width = DEFAULT_WIDTH,
    int height = DEFAULT_HEIGHT,
    String? mapKey,
  }) {
    final String key = mapKey ?? encodeGeneratedMapName(themeId, seed);
    final GeneratedWorldResult? existing = _cache[key];
    if (existing != null &&
        existing.terrainCanvas.width == width &&
        existing.terrainCanvas.height == height) {
      return existing;
    }

    final WorldThemeSpec theme = worldThemeById(themeId);
    final Random rng = Random(seed);

    final HTMLCanvasElement terrain = HTMLCanvasElement()
      ..width = width
      ..height = height;
    final HTMLCanvasElement bedrock = HTMLCanvasElement()
      ..width = width
      ..height = height;

    final CanvasRenderingContext2D tCtx = terrain.context2D;
    final CanvasRenderingContext2D bCtx = bedrock.context2D;
    tCtx.clearRect(0, 0, width, height);
    bCtx.clearRect(0, 0, width, height);

    final double sx = width / DEFAULT_WIDTH;
    final double sy = height / DEFAULT_HEIGHT;
    tCtx.save();
    bCtx.save();
    if (width != DEFAULT_WIDTH || height != DEFAULT_HEIGHT) {
      tCtx.scale(sx, sy);
      bCtx.scale(sx, sy);
    }

    switch (themeId) {
      case WorldThemeId.villa:
        _generateVilla(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
      case WorldThemeId.spooky:
        _generateSpooky(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
      case WorldThemeId.volcano:
        _generateVolcano(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
      case WorldThemeId.glacier:
        _generateGlacier(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
      case WorldThemeId.candy:
        _generateCandy(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
      case WorldThemeId.lunar:
        _generateLunar(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
      case WorldThemeId.city:
        _generateCity(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
      case WorldThemeId.jungle:
        _generateJungle(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
        break;
    }

    tCtx.restore();
    bCtx.restore();

    // Composite the indestructible bedrock onto the playable terrain canvas so
    // it is visible, solid, and automatically preserved on explosions.
    tCtx.save();
    tCtx.globalCompositeOperation = 'source-over';
    tCtx.drawImage(bedrock, 0, 0);
    tCtx.restore();

    final GeneratedWorldResult result = GeneratedWorldResult(
      mapKey: key,
      theme: theme,
      seed: seed,
      terrainCanvas: terrain,
      bedrockCanvas: bedrock,
    );
    if (_cache.length > 6) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
    return result;
  }

  /// Renders (and caches) a crisp Mega Man boss-tile portrait for [theme].
  static HTMLCanvasElement getThemePreview(WorldThemeSpec theme,
      {int width = 180, int height = 132}) {
    final HTMLCanvasElement? cached = _previewCache[theme.id];
    if (cached != null && cached.width == width && cached.height == height) {
      return cached;
    }
    final HTMLCanvasElement canvas = HTMLCanvasElement()
      ..width = width
      ..height = height;
    final CanvasRenderingContext2D ctx = canvas.context2D;
    final double w = width.toDouble();
    final double h = height.toDouble();

    drawGameplaySky(ctx, width, height, theme, 1.2,
        compact: true, seed: theme.id.index * 97 + 13);

    switch (theme.id) {
      case WorldThemeId.villa:
        _drawPreviewVilla(ctx, w, h);
        break;
      case WorldThemeId.spooky:
        _drawPreviewSpooky(ctx, w, h);
        break;
      case WorldThemeId.volcano:
        _drawPreviewVolcano(ctx, w, h);
        break;
      case WorldThemeId.glacier:
        _drawPreviewGlacier(ctx, w, h);
        break;
      case WorldThemeId.candy:
        _drawPreviewCandy(ctx, w, h);
        break;
      case WorldThemeId.lunar:
        _drawPreviewLunar(ctx, w, h);
        break;
      case WorldThemeId.city:
        _drawPreviewCity(ctx, w, h);
        break;
      case WorldThemeId.jungle:
        _drawPreviewJungle(ctx, w, h);
        break;
    }

    _previewCache[theme.id] = canvas;
    return canvas;
  }

  // =========================================================================
  // DETERMINISTIC ONE-TIME VECTOR SKYBOX (SYNCED VIA `gen:<theme>:<seed>`)
  // =========================================================================

  /// Draws the live themed cartoon vector skybox behind the destructible
  /// ByteWorld during gameplay (and inside Mega Man preview portraits).
  ///
  /// The static vector layers (gradients, planets/moons/sun, distant silhouettes)
  /// are deterministically generated from [seed] and cached once per
  /// `(theme, seed, width, height)` offscreen canvas, while lightweight drifting
  /// clouds, twinkling stars, embers, and aurora waves animate smoothly on top.
  static void drawGameplaySky(
    CanvasRenderingContext2D ctx,
    int width,
    int height,
    WorldThemeSpec theme,
    double time, {
    bool compact = false,
    int seed = 0,
  }) {
    if (width <= 0 || height <= 0) return;

    final String cacheKey =
        '${theme.key}:$seed:${width}x$height:${compact ? 1 : 0}';
    HTMLCanvasElement? staticSky = _skyCache[cacheKey];
    if (staticSky == null) {
      staticSky = HTMLCanvasElement()
        ..width = width
        ..height = height;
      _renderStaticVectorSkybox(
          staticSky.context2D, width, height, theme, compact, seed);
      if (_skyCache.length > 8) {
        _skyCache.remove(_skyCache.keys.first);
      }
      _skyCache[cacheKey] = staticSky;
    }

    ctx.save();
    ctx.drawImage(staticSky, 0, 0);

    final double w = width.toDouble();
    final double h = height.toDouble();

    // Lightweight live animated overlay (clouds, twinkles, embers, snow, aurora).
    switch (theme.id) {
      case WorldThemeId.villa:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.92, time * 0.85, '#ffffff',
            0.84, seed);
        break;
      case WorldThemeId.spooky:
        _drawSkyStars(ctx, w, h, compact ? 14 : 40, time, seed);
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.88, time * 0.65, '#5c3c8c',
            0.46, seed);
        break;
      case WorldThemeId.volcano:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.90, time * 0.80, '#59282c',
            0.48, seed);
        if (!compact) {
          _drawRisingEmbers(ctx, w, h, time, seed);
        }
        break;
      case WorldThemeId.glacier:
        _drawAuroraRibbon(ctx, w, h, compact, time);
        _drawSkyClouds(ctx, w, h, compact ? 0.32 : 0.82, time * 0.50, '#ffffff',
            0.66, seed);
        if (!compact) {
          _drawDriftingSnow(ctx, w, h, time, seed);
        }
        break;
      case WorldThemeId.candy:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.86, time * 0.65, '#fff0fa',
            0.86, seed);
        break;
      case WorldThemeId.lunar:
        _drawSkyStars(ctx, w, h, compact ? 22 : 70, time, seed);
        break;
      case WorldThemeId.city:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.85, time * 0.72, '#ffffff',
            0.82, seed);
        break;
      case WorldThemeId.jungle:
        _drawSkyClouds(ctx, w, h, compact ? 0.32 : 0.82, time * 0.52, '#fff8de',
            0.64, seed);
        break;
    }

    ctx.restore();
  }

  /// Renders the deterministic seeded static vector layers of a skybox once.
  static void _renderStaticVectorSkybox(
    CanvasRenderingContext2D ctx,
    int width,
    int height,
    WorldThemeSpec theme,
    bool compact,
    int seed,
  ) {
    final double w = width.toDouble();
    final double h = height.toDouble();
    final Random rng = Random(seed ^ (theme.id.index * 7919));

    final CanvasGradient sky = ctx.createLinearGradient(0, 0, 0, h);
    sky.addColorStop(0.0, theme.skyColors[0]);
    sky.addColorStop(0.55, theme.skyColors[1]);
    sky.addColorStop(1.0, theme.skyColors[2]);
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);

    switch (theme.id) {
      case WorldThemeId.villa:
        final double sunX = w * (0.76 + rng.nextDouble() * 0.12);
        final double sunY = h * (0.16 + rng.nextDouble() * 0.06);
        _drawSkySun(ctx, sunX, sunY, compact ? 16 : 44, '#ffe966');
        // Soft sunlit Swedish archipelago hills & shimmering summer bay on the horizon!
        ctx.fillStyle = 'rgba(104, 198, 224, 0.28)'.toJS;
        ctx.fillRect(0, h * 0.78, w, h * 0.22);
        _drawHorizonRidge(ctx, w, h, h * 0.74, compact ? 14 : 38,
            'rgba(96, 184, 128, 0.32)', rng);
        _drawHorizonRidge(ctx, w, h, h * 0.82, compact ? 10 : 28,
            'rgba(72, 162, 102, 0.30)', rng);
        break;
      case WorldThemeId.spooky:
        final double mx = w * (0.72 + rng.nextDouble() * 0.12);
        final double my = h * (0.20 + rng.nextDouble() * 0.07);
        final double mr = compact ? 19 : 54;
        final CanvasGradient glow =
            ctx.createRadialGradient(mx, my, mr * 0.4, mx, my, mr * 2.6);
        glow.addColorStop(0.0, 'rgba(255, 246, 185, 0.50)');
        glow.addColorStop(1.0, 'rgba(255, 246, 185, 0.0)');
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(mx, my, mr * 2.6, 0, 2 * pi);
        ctx.fill();
        ctx.fillStyle = '#fff5bd'.toJS;
        ctx.beginPath();
        ctx.arc(mx, my, mr, 0, 2 * pi);
        ctx.fill();
        // Moon craters.
        ctx.fillStyle = 'rgba(196, 182, 132, 0.36)'.toJS;
        ctx.beginPath();
        ctx.arc(mx - mr * 0.28, my - mr * 0.12, mr * 0.22, 0, 2 * pi);
        ctx.arc(mx + mr * 0.24, my + mr * 0.24, mr * 0.16, 0, 2 * pi);
        ctx.fill();
        // Distant spooky ridge & silhouetted dead castle spires.
        _drawHorizonRidge(ctx, w, h, h * 0.76, compact ? 16 : 44,
            'rgba(32, 18, 56, 0.42)', rng);
        break;
      case WorldThemeId.volcano:
        // Fiery rising glow from below + jagged distant volcanic mountain silhouettes.
        final CanvasGradient heat =
            ctx.createLinearGradient(0, h * 0.48, 0, h);
        heat.addColorStop(0.0, 'rgba(255, 110, 36, 0.0)');
        heat.addColorStop(1.0, 'rgba(255, 92, 24, 0.46)');
        ctx.fillStyle = heat;
        ctx.fillRect(0, h * 0.48, w, h * 0.52);
        // Jagged volcano cones in the distance.
        ctx.fillStyle = 'rgba(66, 20, 26, 0.42)'.toJS;
        ctx.beginPath();
        ctx.moveTo(0, h);
        for (int i = 0; i <= 8; i++) {
          final double x = (i / 8.0) * w;
          final double peak = (i.isOdd)
              ? h * (0.50 + rng.nextDouble() * 0.12)
              : h * (0.76 + rng.nextDouble() * 0.08);
          ctx.lineTo(x, peak);
        }
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.fill();
        break;
      case WorldThemeId.glacier:
        // Distant jagged snowy alpine peaks!
        ctx.fillStyle = 'rgba(130, 198, 242, 0.34)'.toJS;
        ctx.beginPath();
        ctx.moveTo(0, h);
        for (int i = 0; i <= 10; i++) {
          final double x = (i / 10.0) * w;
          final double py = i.isOdd
              ? h * (0.54 + rng.nextDouble() * 0.12)
              : h * (0.76 + rng.nextDouble() * 0.06);
          ctx.lineTo(x, py);
        }
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.fill();
        break;
      case WorldThemeId.candy:
        // Pastel rainbow arc + distant frosting hills!
        final double rx = w * 0.5;
        final double ry = h * 0.94;
        final double rr = min(w, h) * (compact ? 0.75 : 0.80);
        const List<String> bandColors = [
          'rgba(255, 118, 152, 0.25)',
          'rgba(255, 206, 98, 0.25)',
          'rgba(130, 245, 168, 0.25)',
          'rgba(116, 224, 255, 0.25)',
        ];
        final double bw = compact ? 5.0 : 15.0;
        for (int i = 0; i < bandColors.length; i++) {
          ctx.strokeStyle = bandColors[i].toJS;
          ctx.lineWidth = bw;
          ctx.beginPath();
          ctx.arc(rx, ry, rr - i * bw, pi, 2 * pi);
          ctx.stroke();
        }
        _drawHorizonRidge(ctx, w, h, h * 0.80, compact ? 12 : 34,
            'rgba(255, 156, 206, 0.28)', rng);
        break;
      case WorldThemeId.lunar:
        // Soft cosmic nebula wash!
        final CanvasGradient neb =
            ctx.createRadialGradient(w * 0.55, h * 0.35, 10, w * 0.55, h * 0.35, w * 0.55);
        neb.addColorStop(0.0, 'rgba(130, 82, 230, 0.24)');
        neb.addColorStop(0.6, 'rgba(52, 130, 220, 0.10)');
        neb.addColorStop(1.0, 'rgba(10, 16, 38, 0.0)');
        ctx.fillStyle = neb;
        ctx.fillRect(0, 0, w, h);

        // Glowing Earth-rise!
        final double px = w * (0.18 + rng.nextDouble() * 0.08);
        final double py = h * (0.22 + rng.nextDouble() * 0.07);
        final double pr = compact ? 13 : 38;
        final CanvasGradient eGlow =
            ctx.createRadialGradient(px, py, pr * 0.7, px, py, pr * 1.9);
        eGlow.addColorStop(0.0, 'rgba(102, 206, 255, 0.42)');
        eGlow.addColorStop(1.0, 'rgba(102, 206, 255, 0.0)');
        ctx.fillStyle = eGlow;
        ctx.beginPath();
        ctx.arc(px, py, pr * 1.9, 0, 2 * pi);
        ctx.fill();
        ctx.fillStyle = '#48b2ff'.toJS;
        ctx.beginPath();
        ctx.arc(px, py, pr, 0, 2 * pi);
        ctx.fill();
        ctx.fillStyle = '#5ce07a'.toJS;
        ctx.beginPath();
        ctx.arc(px - pr * 0.25, py - pr * 0.15, pr * 0.42, 0, 2 * pi);
        ctx.arc(px + pr * 0.30, py + pr * 0.22, pr * 0.32, 0, 2 * pi);
        ctx.fill();
        // White cloud swirl on Earth.
        ctx.fillStyle = 'rgba(255, 255, 255, 0.55)'.toJS;
        ctx.beginPath();
        ctx.ellipse(px + pr * 0.12, py - pr * 0.22, pr * 0.45, pr * 0.14, -0.3, 0, 2 * pi);
        ctx.fill();

        // Ringed Saturn planet on the right!
        final double sx = w * (0.76 + rng.nextDouble() * 0.08);
        final double sy = h * (0.20 + rng.nextDouble() * 0.08);
        final double sr = compact ? 10 : 28;
        ctx.strokeStyle = 'rgba(255, 224, 130, 0.78)'.toJS;
        ctx.lineWidth = compact ? 3.0 : 7.5;
        ctx.beginPath();
        ctx.ellipse(sx, sy, sr * 1.95, sr * 0.45, -0.28, 0, 2 * pi);
        ctx.stroke();
        ctx.fillStyle = '#f5a862'.toJS;
        ctx.beginPath();
        ctx.arc(sx, sy, sr, 0, 2 * pi);
        ctx.fill();
        break;
      case WorldThemeId.city:
        _drawSkySun(ctx, w * (0.15 + rng.nextDouble() * 0.10), h * 0.18,
            compact ? 14 : 38, '#fff29c');
        // Two-layer hazy distant metropolis skyline!
        final int farTowers = compact ? 9 : 18;
        final double ftw = w / farTowers;
        ctx.fillStyle = 'rgba(104, 168, 224, 0.24)'.toJS;
        for (int i = 0; i < farTowers; i++) {
          final double th = h * (0.24 + rng.nextDouble() * 0.26);
          ctx.fillRect(i * ftw + 2, h - th, ftw - 4, th);
        }
        ctx.fillStyle = 'rgba(72, 132, 192, 0.28)'.toJS;
        for (int i = 0; i < farTowers; i++) {
          final double th = h * (0.16 + rng.nextDouble() * 0.18);
          ctx.fillRect(i * ftw + 6, h - th, ftw - 8, th);
        }
        break;
      case WorldThemeId.jungle:
        _drawSkySun(ctx, w * (0.76 + rng.nextDouble() * 0.08), h * 0.17,
            compact ? 15 : 42, '#ffe878');
        // Soft sunlit canopy rays + layered misty jungle mountains!
        _drawHorizonRidge(ctx, w, h, h * 0.66, compact ? 14 : 42,
            'rgba(32, 122, 98, 0.26)', rng);
        _drawHorizonRidge(ctx, w, h, h * 0.78, compact ? 12 : 34,
            'rgba(22, 96, 74, 0.30)', rng);
        break;
    }
  }

  static void _drawHorizonRidge(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    double baseY,
    double amp,
    String color,
    Random rng,
  ) {
    final double p1 = rng.nextDouble() * 2 * pi;
    final double p2 = rng.nextDouble() * 2 * pi;
    ctx.fillStyle = color.toJS;
    ctx.beginPath();
    ctx.moveTo(0, h);
    for (int i = 0; i <= 16; i++) {
      final double u = i / 16.0;
      final double y = baseY + sin(u * pi * 3.0 + p1) * amp * 0.65 +
          cos(u * pi * 6.5 + p2) * amp * 0.35;
      ctx.lineTo(u * w, y);
    }
    ctx.lineTo(w, h);
    ctx.closePath();
    ctx.fill();
  }

  static void _drawSkySun(
      CanvasRenderingContext2D ctx, double x, double y, double r, String color) {
    final CanvasGradient halo =
        ctx.createRadialGradient(x, y, r * 0.4, x, y, r * 3.1);
    halo.addColorStop(0.0, 'rgba(255, 248, 175, 0.55)');
    halo.addColorStop(1.0, 'rgba(255, 248, 175, 0.0)');
    ctx.fillStyle = halo;
    ctx.beginPath();
    ctx.arc(x, y, r * 3.1, 0, 2 * pi);
    ctx.fill();

    ctx.fillStyle = color.toJS;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, 2 * pi);
    ctx.fill();
  }

  static void _drawSkyStars(CanvasRenderingContext2D ctx, double w, double h,
      int count, double time, int seed) {
    final int s = seed.abs() % 997;
    for (int i = 0; i < count; i++) {
      final double sx = ((i * 97 + s * 13 + 19) % 1000) / 1000.0 * w;
      final double sy = ((i * 53 + s * 7 + 11) % 740) / 1000.0 * h;
      final double twinkle =
          0.35 + 0.65 * (sin(time * 2.5 + i * 1.7 + s) * 0.5 + 0.5);
      final double sr = (i % 4 == 0 ? 2.2 : 1.3);
      ctx.fillStyle = 'rgba(255, 252, 224, $twinkle)'.toJS;
      ctx.beginPath();
      ctx.arc(sx, sy, sr, 0, 2 * pi);
      ctx.fill();
    }
  }

  static void _drawSkyClouds(CanvasRenderingContext2D ctx, double w, double h,
      double scale, double time, String color, double alpha, int seed) {
    final double offset = (seed.abs() % 100) / 100.0;
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = color.toJS;
    for (int i = 0; i < 6; i++) {
      final double speed = 0.007 + (i % 3) * 0.0045;
      final double cx =
          (((i * 0.19 + offset) + time * speed) % 1.26 - 0.13) * w;
      final double cy = h * (0.12 + (i % 3) * 0.11);
      final double s = scale * (0.72 + (i % 3) * 0.22);
      ctx.beginPath();
      ctx.arc(cx - 24 * s, cy + 4 * s, 14 * s, 0, 2 * pi);
      ctx.arc(cx - 6 * s, cy - 6 * s, 20 * s, 0, 2 * pi);
      ctx.arc(cx + 16 * s, cy - 2 * s, 17 * s, 0, 2 * pi);
      ctx.arc(cx + 30 * s, cy + 5 * s, 13 * s, 0, 2 * pi);
      ctx.fill();
    }
    ctx.restore();
  }

  static void _drawAuroraRibbon(CanvasRenderingContext2D ctx, double w, double h,
      bool compact, double time) {
    ctx.save();
    for (int band = 0; band < 2; band++) {
      ctx.strokeStyle = (band == 0
              ? 'rgba(116, 255, 212, 0.30)'
              : 'rgba(130, 210, 255, 0.24)')
          .toJS;
      ctx.lineWidth = compact ? 9 : 26;
      ctx.lineCap = 'round';
      ctx.beginPath();
      for (int i = 0; i <= 14; i++) {
        final double x = (i / 14.0) * w;
        final double y = h * (0.20 + band * 0.07) +
            sin(i * 0.6 + time * (0.65 + band * 0.2) + band) *
                (compact ? 7 : 22);
        if (i == 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawRisingEmbers(
      CanvasRenderingContext2D ctx, double w, double h, double time, int seed) {
    final int s = seed.abs() % 500;
    for (int i = 0; i < 24; i++) {
      final double u = ((i * 71 + s) % 100) / 100.0;
      final double v = 1.0 - (((i * 0.17) + time * (0.08 + (i % 3) * 0.03)) % 1.0);
      final double x = u * w + sin(time * 2.2 + i) * 14.0;
      final double y = v * h;
      ctx.fillStyle = (i.isEven
              ? 'rgba(255, 214, 78, 0.72)'
              : 'rgba(255, 118, 42, 0.65)')
          .toJS;
      ctx.beginPath();
      ctx.arc(x, y, i % 3 == 0 ? 2.6 : 1.7, 0, 2 * pi);
      ctx.fill();
    }
  }

  static void _drawDriftingSnow(
      CanvasRenderingContext2D ctx, double w, double h, double time, int seed) {
    final int s = seed.abs() % 500;
    ctx.fillStyle = 'rgba(255, 255, 255, 0.68)'.toJS;
    for (int i = 0; i < 26; i++) {
      final double u = ((i * 83 + s) % 100) / 100.0;
      final double v = ((i * 0.13) + time * (0.06 + (i % 3) * 0.025)) % 1.0;
      final double x = u * w + sin(time * 1.4 + i) * 16.0;
      final double y = v * h;
      ctx.beginPath();
      ctx.arc(x, y, i % 3 == 0 ? 2.5 : 1.6, 0, 2 * pi);
      ctx.fill();
    }
  }

  // =========================================================================
  // SHARED PROCEDURAL TERRAIN & THEMATIC BEDROCK BUILDING BLOCKS
  // =========================================================================

  static List<double> _buildHeightfield(
    int w,
    double baseY,
    double amp,
    Random rng, {
    int step = 20,
    double edgeDrop = 95.0,
    double minY = 230.0,
    double maxY = 820.0,
  }) {
    final int count = (w ~/ step) + 2;
    final double p1 = rng.nextDouble() * 2 * pi;
    final double p2 = rng.nextDouble() * 2 * pi;
    final double p3 = rng.nextDouble() * 2 * pi;
    // Higher harmonic counts suited for the 30% wider 2080px arena!
    final double f1 = 1.9 + rng.nextDouble() * 1.3;
    final double f2 = 4.2 + rng.nextDouble() * 2.0;
    final double f3 = 7.8 + rng.nextDouble() * 3.4;

    final List<double> ys = List.filled(count, baseY);
    for (int i = 0; i < count; i++) {
      final double u = (i * step) / w;
      final double wave = sin(u * pi * f1 + p1) * amp * 0.54 +
          sin(u * pi * f2 + p2) * amp * 0.31 +
          cos(u * pi * f3 + p3) * amp * 0.15;
      final double edgeDist = min(u, 1.0 - u);
      final double edgeFactor = edgeDist < 0.08 ? (1.0 - edgeDist / 0.08) : 0.0;
      final double y = (baseY + wave + edgeFactor * edgeFactor * edgeDrop)
          .clamp(minY, maxY);
      ys[i] = y;
    }
    return ys;
  }

  static double _sampleHeight(List<double> heights, double x, int step) {
    final double idx = x / step;
    final int i0 = idx.floor().clamp(0, heights.length - 1);
    final int i1 = (i0 + 1).clamp(0, heights.length - 1);
    final double t = (idx - i0).clamp(0.0, 1.0);
    return heights[i0] * (1.0 - t) + heights[i1] * t;
  }

  static void _drawCartoonGround(
    CanvasRenderingContext2D ctx,
    int w,
    int h,
    List<double> heights,
    int step,
    Random rng, {
    required String fillTop,
    required String fillMid,
    required String fillBottom,
    required String outlineColor,
    required String turfTop,
    required String turfBottom,
    required String turfOutline,
    required String pebbleColor,
    double turfThickness = 26.0,
    double bottomPadding = 0.0,
    List<String>? layerBands,
  }) {
    final double bottomY = h + 6.0 - bottomPadding;

    ctx.save();
    ctx.beginPath();
    ctx.moveTo(-4.0, bottomY);
    for (int i = 0; i < heights.length; i++) {
      ctx.lineTo((i * step).toDouble(), heights[i]);
    }
    ctx.lineTo(w + 4.0, bottomY);
    ctx.closePath();

    final CanvasGradient bodyGrad =
        ctx.createLinearGradient(0, h * 0.35, 0, bottomY);
    bodyGrad.addColorStop(0.0, fillTop);
    bodyGrad.addColorStop(0.55, fillMid);
    bodyGrad.addColorStop(1.0, fillBottom);
    ctx.fillStyle = bodyGrad;
    ctx.fill();

    // Embedded pebbles, strata & optional cake/rock bands clipped to terrain body.
    ctx.save();
    ctx.clip();

    if (layerBands != null && layerBands.isNotEmpty) {
      final double bandH = 42.0;
      for (int b = 0; b < layerBands.length; b++) {
        ctx.fillStyle = layerBands[b].toJS;
        final double by = h * 0.56 + b * bandH * 1.45;
        ctx.fillRect(0, by, w.toDouble(), bandH);
      }
    }

    ctx.fillStyle = pebbleColor.toJS;
    for (int i = 0; i < 95; i++) {
      final double px = rng.nextDouble() * w;
      final double topY = _sampleHeight(heights, px, step);
      final double py =
          topY + 32.0 + rng.nextDouble() * max(20.0, bottomY - topY - 38.0);
      final double rx = 8.0 + rng.nextDouble() * 22.0;
      final double ry = 5.0 + rng.nextDouble() * 12.0;
      ctx.beginPath();
      ctx.ellipse(px, py, rx, ry, rng.nextDouble() * pi, 0, 2 * pi);
      ctx.fill();
    }
    ctx.restore();

    ctx.strokeStyle = outlineColor.toJS;
    ctx.lineWidth = 4.5;
    ctx.stroke();

    // Scalloped cartoon turf/snow/frosting cap hugging the surface.
    ctx.beginPath();
    for (int i = 0; i < heights.length; i++) {
      final double x = (i * step).toDouble();
      final double y = heights[i] - 4.0;
      if (i == 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    for (int i = heights.length - 1; i >= 0; i--) {
      final double x = (i * step).toDouble();
      final double scallop = (i.isEven ? 1.20 : 0.72) * turfThickness;
      ctx.lineTo(x, heights[i] + scallop);
    }
    ctx.closePath();

    final CanvasGradient turfGrad =
        ctx.createLinearGradient(0, h * 0.32, 0, h * 0.85);
    turfGrad.addColorStop(0.0, turfTop);
    turfGrad.addColorStop(1.0, turfBottom);
    ctx.fillStyle = turfGrad;
    ctx.fill();
    ctx.strokeStyle = turfOutline.toJS;
    ctx.lineWidth = 3.6;
    ctx.stroke();
    ctx.restore();
  }

  static void _drawFloatingCartoonIsland(
    CanvasRenderingContext2D ctx, {
    required double cx,
    required double cy,
    required double width,
    required double height,
    required String rockTop,
    required String rockBottom,
    required String rockOutline,
    required String turfTop,
    required String turfBottom,
    required String turfOutline,
  }) {
    final double hw = width * 0.5;
    ctx.save();
    ctx.translate(cx, cy);

    final CanvasGradient rockGrad = ctx.createLinearGradient(0, 0, 0, height);
    rockGrad.addColorStop(0.0, rockTop);
    rockGrad.addColorStop(1.0, rockBottom);
    ctx.fillStyle = rockGrad;
    ctx.strokeStyle = rockOutline.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.moveTo(-hw * 0.92, 0);
    ctx.quadraticCurveTo(-hw * 0.64, height * 0.70, -hw * 0.14, height);
    ctx.quadraticCurveTo(hw * 0.18, height * 0.90, hw * 0.42, height * 0.60);
    ctx.quadraticCurveTo(hw * 0.80, height * 0.40, hw * 0.92, 0);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    final CanvasGradient turfGrad = ctx.createLinearGradient(0, -18, 0, 18);
    turfGrad.addColorStop(0.0, turfTop);
    turfGrad.addColorStop(1.0, turfBottom);
    ctx.fillStyle = turfGrad;
    ctx.strokeStyle = turfOutline.toJS;
    ctx.lineWidth = 3.4;
    ctx.beginPath();
    ctx.moveTo(-hw, 4);
    ctx.quadraticCurveTo(-hw * 0.5, -18, 0, -14);
    ctx.quadraticCurveTo(hw * 0.55, -18, hw, 4);
    ctx.quadraticCurveTo(hw * 0.68, 16, hw * 0.35, 7);
    ctx.quadraticCurveTo(0, 19, -hw * 0.35, 8);
    ctx.quadraticCurveTo(-hw * 0.72, 16, -hw, 4);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /// Draws a destructible hanging rope & wooden plank bridge between two points.
  static void _drawRopeBridge(CanvasRenderingContext2D ctx, double x0, double y0,
      double x1, double y1,
      {double sag = 28.0, String woodColor = '#b8763e'}) {
    ctx.save();
    final int planks = max(6, ((x1 - x0).abs() ~/ 22));
    // Twin sagging rope handrails.
    ctx.strokeStyle = '#5c3d1e'.toJS;
    ctx.lineWidth = 4.2;
    for (final double dy in const [-18.0, 2.0]) {
      ctx.beginPath();
      ctx.moveTo(x0, y0 + dy);
      ctx.quadraticCurveTo(
          (x0 + x1) * 0.5, (y0 + y1) * 0.5 + sag + dy, x1, y1 + dy);
      ctx.stroke();
    }
    // Wooden walkway planks.
    for (int i = 0; i <= planks; i++) {
      final double t = i / planks;
      final double px = x0 + (x1 - x0) * t;
      final double py = (1 - t) * (1 - t) * y0 +
          2 * (1 - t) * t * ((y0 + y1) * 0.5 + sag) +
          t * t * y1;
      ctx.fillStyle = woodColor.toJS;
      ctx.strokeStyle = '#331c0b'.toJS;
      ctx.lineWidth = 2.4;
      ctx.fillRect(px - 8, py - 4, 16, 10);
      ctx.strokeRect(px - 8, py - 4, 16, 10);
    }
    ctx.restore();
  }

  // -------------------------------------------------------------------------
  // UNMISTAKABLE THEMATIC INDESTRUCTIBLE BEDROCK SECTIONS
  // -------------------------------------------------------------------------

  static Map<String, String> _stylePalette(_BedrockStyle style) {
    switch (style) {
      case _BedrockStyle.ironVault:
        return {
          'top': '#747e91',
          'bottom': '#394050',
          'trim': '#f0b840',
          'rivet': '#ffe680',
          'accent': '#ffd04d',
        };
      case _BedrockStyle.gothicRune:
        return {
          'top': '#545c73',
          'bottom': '#232838',
          'trim': '#9b74e8',
          'rivet': '#d4a6ff',
          'accent': '#ff9c3b',
        };
      case _BedrockStyle.lavaForged:
        return {
          'top': '#5a4e61',
          'bottom': '#241e29',
          'trim': '#ff6a22',
          'rivet': '#ffd24d',
          'accent': '#ff8a2e',
        };
      case _BedrockStyle.frostCrystal:
        return {
          'top': '#b8f7ff',
          'bottom': '#2e8cd1',
          'trim': '#174882',
          'rivet': '#ffffff',
          'accent': '#e0fcff',
        };
      case _BedrockStyle.peppermintSteel:
        return {
          'top': '#ff7da8',
          'bottom': '#b5285c',
          'trim': '#ffffff',
          'rivet': '#fff2a6',
          'accent': '#ffffff',
        };
      case _BedrockStyle.titaniumHazard:
        return {
          'top': '#cdd9ed',
          'bottom': '#5f708a',
          'trim': '#ffbe2e',
          'rivet': '#ffe45e',
          'accent': '#242936',
        };
      case _BedrockStyle.cityGirder:
        return {
          'top': '#ffd23f',
          'bottom': '#c98812',
          'trim': '#202633',
          'rivet': '#f2f5fa',
          'accent': '#202633',
        };
      case _BedrockStyle.mayanGold:
        return {
          'top': '#d4c18c',
          'bottom': '#7a6842',
          'trim': '#ffd238',
          'rivet': '#fff099',
          'accent': '#4fd974',
        };
    }
  }

  /// Draws an unmistakable heavy armored indestructible bedrock block onto [bCtx]
  /// with double dark ink border, metallic bevel, thematic pattern, and embossed rivets.
  static void _drawBedrockBlock(
    CanvasRenderingContext2D bCtx, {
    required double x,
    required double y,
    required double w,
    required double h,
    required _BedrockStyle style,
    bool diagonalStripes = false,
  }) {
    if (w <= 8.0 || h <= 8.0) return;
    final Map<String, String> pal = _stylePalette(style);
    bCtx.save();
    final double r = max(0.0, min(9.0, min(w, h) * 0.22));

    // Metallic/stone gradient body.
    final CanvasGradient grad = bCtx.createLinearGradient(x, y, x, y + h);
    grad.addColorStop(0.0, pal['top']!);
    grad.addColorStop(1.0, pal['bottom']!);
    bCtx.fillStyle = grad;
    bCtx.beginPath();
    bCtx.roundRect(x, y, w, h, r.toJS);
    bCtx.fill();

    // Clipped thematic patterns & glossy steel bevel.
    bCtx.save();
    bCtx.beginPath();
    bCtx.roundRect(x, y, w, h, r.toJS);
    bCtx.clip();

    if (diagonalStripes ||
        style == _BedrockStyle.peppermintSteel ||
        style == _BedrockStyle.titaniumHazard) {
      bCtx.strokeStyle = (style == _BedrockStyle.peppermintSteel
              ? 'rgba(255, 255, 255, 0.55)'
              : 'rgba(16, 18, 26, 0.34)')
          .toJS;
      bCtx.lineWidth = 9.0;
      for (double sx = x - h; sx < x + w + h; sx += 24.0) {
        bCtx.beginPath();
        bCtx.moveTo(sx, y + h);
        bCtx.lineTo(sx + h, y);
        bCtx.stroke();
      }
    } else if (style == _BedrockStyle.frostCrystal) {
      // Faceted crystalline shine lines.
      bCtx.fillStyle = 'rgba(255, 255, 255, 0.28)'.toJS;
      bCtx.beginPath();
      bCtx.moveTo(x, y);
      bCtx.lineTo(x + w * 0.45, y);
      bCtx.lineTo(x + w * 0.25, y + h);
      bCtx.lineTo(x, y + h);
      bCtx.closePath();
      bCtx.fill();
    } else if (style == _BedrockStyle.ironVault) {
      // Heavy forged iron straps across the vault!
      bCtx.fillStyle = 'rgba(24, 28, 38, 0.45)'.toJS;
      bCtx.fillRect(x, y + h * 0.38, w, h * 0.24);
      bCtx.fillRect(x + w * 0.44, y, w * 0.12, h);
    }

    // Crisp specular highlight bar along top edge.
    bCtx.fillStyle = 'rgba(255, 255, 255, 0.32)'.toJS;
    bCtx.fillRect(x + 4, y + 4, w - 8, min(8.0, h * 0.26));

    // Bottom dark shadow bevel.
    bCtx.fillStyle = 'rgba(0, 0, 0, 0.28)'.toJS;
    bCtx.fillRect(x + 4, y + h - min(8.0, h * 0.24), w - 8, min(8.0, h * 0.24));
    bCtx.restore();

    // Inner bright thematic trim frame.
    bCtx.strokeStyle = pal['trim']!.toJS;
    bCtx.lineWidth = 2.8;
    bCtx.beginPath();
    bCtx.roundRect(x + 4, y + 4, w - 8, h - 8, max(0.0, r - 2).toJS);
    bCtx.stroke();

    // Heavy unmistakable outer armored border!
    bCtx.strokeStyle = '#12151f'.toJS;
    bCtx.lineWidth = 4.6;
    bCtx.beginPath();
    bCtx.roundRect(x, y, w, h, r.toJS);
    bCtx.stroke();

    // Center thematic emblem (keyhole / rune / diamond / X-bolt) for instant readability!
    final double cx = x + w * 0.5;
    final double cy = y + h * 0.5;
    if (w >= 46 && h >= 24) {
      bCtx.fillStyle = pal['accent']!.toJS;
      bCtx.strokeStyle = '#12151f'.toJS;
      bCtx.lineWidth = 2.0;
      if (style == _BedrockStyle.ironVault) {
        // Golden vault keyhole emblem!
        bCtx.beginPath();
        bCtx.arc(cx, cy - 3, 5.2, 0, 2 * pi);
        bCtx.fill();
        bCtx.stroke();
        bCtx.fillRect(cx - 2.6, cy, 5.2, 8.0);
        bCtx.strokeRect(cx - 2.6, cy, 5.2, 8.0);
      } else if (style == _BedrockStyle.gothicRune ||
          style == _BedrockStyle.lavaForged ||
          style == _BedrockStyle.mayanGold) {
        // Glowing diamond rune/gem!
        bCtx.beginPath();
        bCtx.moveTo(cx, cy - 8);
        bCtx.lineTo(cx + 8, cy);
        bCtx.lineTo(cx, cy + 8);
        bCtx.lineTo(cx - 8, cy);
        bCtx.closePath();
        bCtx.fill();
        bCtx.stroke();
      }
    }

    // Heavy embossed rivets along the edges!
    bCtx.fillStyle = pal['rivet']!.toJS;
    bCtx.strokeStyle = '#12151f'.toJS;
    bCtx.lineWidth = 1.6;
    final double inset = min(11.0, min(w, h) * 0.25);
    final int horizRivets = max(2, min(6, (w ~/ 46) + 1));
    for (int i = 0; i < horizRivets; i++) {
      final double rx = x + inset + (w - inset * 2) * (i / (horizRivets - 1));
      for (final double ry in [y + inset, y + h - inset]) {
        bCtx.beginPath();
        bCtx.arc(rx, ry, 3.6, 0, 2 * pi);
        bCtx.fill();
        bCtx.stroke();
      }
    }
    bCtx.restore();
  }

  /// Draws a classic Worms/Liero indestructible steel truss girder/bridge onto [bCtx]!
  static void _drawBedrockGirder(
    CanvasRenderingContext2D bCtx, {
    required double x,
    required double y,
    required double w,
    double h = 30.0,
    required _BedrockStyle style,
  }) {
    final Map<String, String> pal = _stylePalette(style);
    bCtx.save();
    // Solid backing web so projectiles never clip through girder gaps.
    bCtx.fillStyle = pal['bottom']!.toJS;
    bCtx.fillRect(x + 2, y + 2, w - 4, h - 4);

    // X-bracing diagonal truss struts!
    final int bays = max(3, (w ~/ 34));
    final double bayW = (w - 16) / bays;
    bCtx.strokeStyle = pal['top']!.toJS;
    bCtx.lineWidth = 4.2;
    for (int i = 0; i < bays; i++) {
      final double bx = x + 8 + i * bayW;
      bCtx.beginPath();
      bCtx.moveTo(bx, y + 6);
      bCtx.lineTo(bx + bayW, y + h - 6);
      bCtx.moveTo(bx + bayW, y + 6);
      bCtx.lineTo(bx, y + h - 6);
      bCtx.stroke();
    }

    // Top & bottom thick armored flanges.
    for (final double fy in [y, y + h - 9.0]) {
      final CanvasGradient fl = bCtx.createLinearGradient(x, fy, x, fy + 9);
      fl.addColorStop(0.0, pal['top']!);
      fl.addColorStop(1.0, pal['bottom']!);
      bCtx.fillStyle = fl;
      bCtx.fillRect(x, fy, w, 9.0);
      bCtx.strokeStyle = '#12151f'.toJS;
      bCtx.lineWidth = 3.2;
      bCtx.strokeRect(x, fy, w, 9.0);
    }

    // End-cap plates with bright bolts!
    for (final double ex in [x, x + w - 12.0]) {
      bCtx.fillStyle = pal['trim']!.toJS;
      bCtx.fillRect(ex, y, 12.0, h);
      bCtx.strokeStyle = '#12151f'.toJS;
      bCtx.lineWidth = 3.2;
      bCtx.strokeRect(ex, y, 12.0, h);
    }

    // Rivets along top flange.
    bCtx.fillStyle = pal['rivet']!.toJS;
    bCtx.strokeStyle = '#12151f'.toJS;
    bCtx.lineWidth = 1.4;
    for (double rx = x + 18; rx < x + w - 14; rx += 26) {
      bCtx.beginPath();
      bCtx.arc(rx, y + 4.5, 2.8, 0, 2 * pi);
      bCtx.fill();
      bCtx.stroke();
    }
    bCtx.restore();
  }

  /// Draws an indestructible armored vertical pillar/monolith with plinth & cap!
  static void _drawBedrockPillar(
    CanvasRenderingContext2D bCtx, {
    required double cx,
    required double topY,
    required double height,
    double width = 44.0,
    required _BedrockStyle style,
  }) {
    // Main armored column shaft.
    _drawBedrockBlock(
      bCtx,
      x: cx - width * 0.5,
      y: topY + 12,
      w: width,
      h: max(20.0, height - 24),
      style: style,
    );
    // Wider top capital & bottom base plinth!
    _drawBedrockBlock(
      bCtx,
      x: cx - width * 0.66,
      y: topY,
      w: width * 1.32,
      h: 18,
      style: style,
    );
    _drawBedrockBlock(
      bCtx,
      x: cx - width * 0.66,
      y: topY + height - 18,
      w: width * 1.32,
      h: 18,
      style: style,
    );
  }

  /// Draws an arched indestructible vault roof (e.g. cellar vault / dungeon arch)
  /// that shields a hollow tunnel or bunker underneath!
  static void _drawBedrockArchVault(
    CanvasRenderingContext2D bCtx, {
    required double cx,
    required double y,
    required double span,
    double thickness = 26.0,
    required _BedrockStyle style,
  }) {
    final Map<String, String> pal = _stylePalette(style);
    final double rOuter = span * 0.5;
    final double rInner = max(14.0, rOuter - thickness);
    bCtx.save();
    bCtx.beginPath();
    bCtx.arc(cx, y, rOuter, pi * 1.06, pi * 1.94);
    bCtx.arc(cx, y, rInner, pi * 1.94, pi * 1.06, true);
    bCtx.closePath();

    final CanvasGradient g =
        bCtx.createLinearGradient(cx, y - rOuter, cx, y - rInner * 0.5);
    g.addColorStop(0.0, pal['top']!);
    g.addColorStop(1.0, pal['bottom']!);
    bCtx.fillStyle = g;
    bCtx.fill();

    // Keystone & iron band dividers along the arch.
    bCtx.strokeStyle = pal['trim']!.toJS;
    bCtx.lineWidth = 3.2;
    for (int i = 1; i <= 5; i++) {
      final double a = pi * (1.08 + i * 0.14);
      bCtx.beginPath();
      bCtx.moveTo(cx + cos(a) * rInner, y + sin(a) * rInner);
      bCtx.lineTo(cx + cos(a) * rOuter, y + sin(a) * rOuter);
      bCtx.stroke();
    }

    bCtx.strokeStyle = '#12151f'.toJS;
    bCtx.lineWidth = 4.4;
    bCtx.beginPath();
    bCtx.arc(cx, y, rOuter, pi * 1.06, pi * 1.94);
    bCtx.arc(cx, y, rInner, pi * 1.94, pi * 1.06, true);
    bCtx.closePath();
    bCtx.stroke();

    // Bright rivets along the arch spine.
    bCtx.fillStyle = pal['rivet']!.toJS;
    bCtx.lineWidth = 1.4;
    final double rMid = (rOuter + rInner) * 0.5;
    for (int i = 0; i < 5; i++) {
      final double a = pi * (1.16 + i * 0.17);
      bCtx.beginPath();
      bCtx.arc(cx + cos(a) * rMid, y + sin(a) * rMid, 3.4, 0, 2 * pi);
      bCtx.fill();
      bCtx.stroke();
    }
    bCtx.restore();
  }

  // -------------------------------------------------------------------------
  // SHARED NATURE PROPS
  // -------------------------------------------------------------------------

  static void _drawPalmTree(CanvasRenderingContext2D ctx, double x, double y,
      double scale, double lean) {
    ctx.save();
    ctx.translate(x, y);
    ctx.strokeStyle = '#472a12'.toJS;
    ctx.lineWidth = 14.0 * scale;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(0, 4);
    ctx.quadraticCurveTo(lean * 0.4, -44 * scale, lean, -88 * scale);
    ctx.stroke();

    ctx.strokeStyle = '#9c6635'.toJS;
    ctx.lineWidth = 9.0 * scale;
    ctx.beginPath();
    ctx.moveTo(0, 4);
    ctx.quadraticCurveTo(lean * 0.4, -44 * scale, lean, -88 * scale);
    ctx.stroke();

    ctx.translate(lean, -88 * scale);
    const List<double> angles = [-2.6, -1.85, -1.0, -0.25, 0.45, 1.05];
    for (int i = 0; i < angles.length; i++) {
      ctx.save();
      ctx.rotate(angles[i]);
      ctx.fillStyle = (i.isEven ? '#4fd647' : '#38b53a').toJS;
      ctx.strokeStyle = '#184f1a'.toJS;
      ctx.lineWidth = 2.6 * scale;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.quadraticCurveTo(22 * scale, -14 * scale, 48 * scale, 5 * scale);
      ctx.quadraticCurveTo(22 * scale, 6 * scale, 0, 0);
      ctx.fill();
      ctx.stroke();
      ctx.restore();
    }
    ctx.fillStyle = '#633c1b'.toJS;
    ctx.strokeStyle = '#29170a'.toJS;
    ctx.lineWidth = 2.0 * scale;
    for (final double cx in const [-5.0, 5.0]) {
      ctx.beginPath();
      ctx.arc(cx * scale, 6 * scale, 6 * scale, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawPineTree(
    CanvasRenderingContext2D ctx,
    double x,
    double y,
    double scale, {
    required String leafLight,
    required String leafDark,
    required String outline,
    bool snowyCap = false,
  }) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#734624'.toJS;
    ctx.strokeStyle = '#2b180b'.toJS;
    ctx.lineWidth = 2.4 * scale;
    ctx.fillRect(-6 * scale, -18 * scale, 12 * scale, 22 * scale);
    ctx.strokeRect(-6 * scale, -18 * scale, 12 * scale, 22 * scale);

    for (int tier = 0; tier < 3; tier++) {
      final double ty = (-18 - tier * 20) * scale;
      final double tw = (34 - tier * 7) * scale;
      final double th = (32 - tier * 3) * scale;
      ctx.fillStyle = (tier.isEven ? leafDark : leafLight).toJS;
      ctx.strokeStyle = outline.toJS;
      ctx.lineWidth = 2.8 * scale;
      ctx.beginPath();
      ctx.moveTo(0, ty - th);
      ctx.lineTo(-tw, ty);
      ctx.lineTo(tw, ty);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      if (snowyCap) {
        ctx.fillStyle = '#ffffff'.toJS;
        ctx.beginPath();
        ctx.moveTo(0, ty - th);
        ctx.lineTo(-tw * 0.45, ty - th * 0.52);
        ctx.lineTo(tw * 0.45, ty - th * 0.52);
        ctx.closePath();
        ctx.fill();
      }
    }
    ctx.restore();
  }

  // =========================================================================
  // 1. VILLA — WHIMSICAL CROOKED SWEDISH GARDEN COTTAGE
  // =========================================================================
  static void _generateVilla(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights =
        _buildHeightfield(w, h * 0.65, 95.0, rng, step: step, edgeDrop: 95.0);

    // Flatten a nice sunny plateau for the crooked villa around 0.34*w!
    final double villaX = w * (0.31 + rng.nextDouble() * 0.06);
    final double villaGroundY = _sampleHeight(heights, villaX, step).clamp(500.0, 610.0);
    for (int i = 0; i < heights.length; i++) {
      final double x = (i * step).toDouble();
      final double dx = (x - villaX).abs();
      if (dx < 165.0) {
        final double blend = max(0.0, 1.0 - dx / 165.0);
        heights[i] = heights[i] * (1.0 - blend) + villaGroundY * blend;
      }
    }

    // Sunny Swedish summer meadow soil & lush bright grass!
    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#c48f58',
      fillMid: '#9c6839',
      fillBottom: '#6b4222',
      outlineColor: '#3b2210',
      turfTop: '#a4f754',
      turfBottom: '#42ba38',
      turfOutline: '#1c5c19',
      pebbleColor: 'rgba(84, 52, 24, 0.30)',
      turfThickness: 30.0,
    );

    // Wildflower meadow tufts (daisies, buttercups, red poppies) all along the hills!
    const List<String> flowerColors = ['#ffffff', '#ffe44d', '#ff5978', '#80d8ff'];
    for (int i = 0; i < 42; i++) {
      final double fx = 40.0 + rng.nextDouble() * (w - 80.0);
      if ((fx - villaX).abs() < 155.0) continue;
      final double fy = _sampleHeight(heights, fx, step);
      ctx.fillStyle = flowerColors[i % flowerColors.length].toJS;
      ctx.strokeStyle = '#2d471d'.toJS;
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.arc(fx, fy - 5, 4.5, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = '#ffd230'.toJS;
      ctx.beginPath();
      ctx.arc(fx, fy - 5, 1.8, 0, 2 * pi);
      ctx.fill();
    }

    // White wooden garden picket fence stretches!
    _drawPicketFence(ctx, heights, step, w * 0.08, w * 0.21);
    _drawPicketFence(ctx, heights, step, w * 0.47, w * 0.58);

    // HERO CENTERPIECE: Crooked Multi-Story Colorful Wooden Villa + Spotted Horse on Porch!
    _drawCrookedVilla(ctx, villaX, villaGroundY + 6.0);
    _drawSpottedHorse(ctx, villaX + 112, villaGroundY - 2.0, 1.0);

    // GIMMICK 2: Giant Gnarled Lemonade/Soda Tree with dangling glass bottles & hollow hideout!
    final double treeX = w * (0.64 + rng.nextDouble() * 0.04);
    final double treeY = _sampleHeight(heights, treeX, step) + 6.0;
    _drawSodaTree(ctx, treeX, treeY);

    // GIMMICK 3: Overflowing Pirate Gold Treasure Chest on the right meadow ridge!
    final double chestX = w * (0.81 + rng.nextDouble() * 0.04);
    final double chestY = _sampleHeight(heights, chestX, step) + 2.0;
    _drawTreasureChest(ctx, chestX, chestY, 1.15);

    // Cute apple trees on the left & right hills!
    _drawAppleTree(ctx, w * 0.13, _sampleHeight(heights, w * 0.13, step) + 4, 0.95);
    _drawAppleTree(ctx, w * 0.91, _sampleHeight(heights, w * 0.91, step) + 4, 0.90);

    // 3 Floating sunlit meadow hillocks + wooden rope bridge connecting sky islands!
    final List<List<double>> islands = [
      [w * 0.16, h * 0.27, 250.0, 92.0],
      [w * 0.53, h * 0.22, 285.0, 98.0],
      [w * 0.84, h * 0.29, 245.0, 90.0],
    ];
    for (int i = 0; i < islands.length; i++) {
      final List<double> isl = islands[i];
      _drawFloatingCartoonIsland(
        ctx,
        cx: isl[0],
        cy: isl[1],
        width: isl[2],
        height: isl[3],
        rockTop: '#b57b4a',
        rockBottom: '#6c4427',
        rockOutline: '#3a2211',
        turfTop: '#a4f754',
        turfBottom: '#42ba38',
        turfOutline: '#1c5c19',
      );
      if (i != 1) {
        _drawAppleTree(ctx, isl[0] + (i == 0 ? -38 : 34), isl[1] - 10, 0.62);
      } else {
        // Mini pirate flag & lookout barrel on center sky-island!
        _drawGardenFlag(ctx, isl[0], isl[1] - 12);
      }
    }
    // Rope bridge spanning from left island toward center island!
    _drawRopeBridge(
      ctx,
      islands[0][0] + 105,
      islands[0][1] - 4,
      islands[1][0] - 125,
      islands[1][1] - 4,
      sag: 38.0,
    );

    // THEMATIC INDESTRUCTIBLE BEDROCK (7 CLEAR SECTIONS):
    // 1. Iron-bound stone cellar vault arch protecting the villa's secret cellar!
    _drawBedrockArchVault(
      bCtx,
      cx: villaX,
      y: villaGroundY + 122,
      span: 184.0,
      thickness: 26.0,
      style: _BedrockStyle.ironVault,
    );
    // 2-3. Reinforced stone-and-iron villa foundation pillars on left & right of porch.
    _drawBedrockBlock(
      bCtx,
      x: villaX - 126,
      y: villaGroundY + 12,
      w: 102,
      h: 32,
      style: _BedrockStyle.ironVault,
    );
    _drawBedrockBlock(
      bCtx,
      x: villaX + 34,
      y: villaGroundY + 12,
      w: 112,
      h: 32,
      style: _BedrockStyle.ironVault,
    );
    // 4. Heavy gold-trimmed pirate treasure-vault slab beneath the overflowing chest!
    _drawBedrockBlock(
      bCtx,
      x: chestX - 64,
      y: chestY + 24,
      w: 128,
      h: 36,
      style: _BedrockStyle.ironVault,
    );
    // 5. Armored iron root-cellar roof girder under the lemonade tree!
    _drawBedrockGirder(
      bCtx,
      x: treeX - 82,
      y: treeY + 46,
      w: 164,
      h: 28,
      style: _BedrockStyle.ironVault,
    );
    // 6. Reinforced garden bridge girder connecting villa hill & right meadow!
    _drawBedrockGirder(
      bCtx,
      x: w * 0.455,
      y: h * 0.49,
      w: 175,
      h: 28,
      style: _BedrockStyle.ironVault,
    );
    // 7. Heavy iron-banded sky-island anchor beneath the center floating hillock!
    _drawBedrockBlock(
      bCtx,
      x: islands[1][0] - 54,
      y: islands[1][1] + 24,
      w: 108,
      h: 28,
      style: _BedrockStyle.ironVault,
    );
  }

  static void _drawCrookedVilla(
      CanvasRenderingContext2D ctx, double cx, double baseY) {
    ctx.save();
    ctx.translate(cx, baseY);

    // Wooden porch/veranda deck extending to the right (where the spotted horse stands!).
    ctx.fillStyle = '#d99852'.toJS;
    ctx.strokeStyle = '#3b210e'.toJS;
    ctx.lineWidth = 3.8;
    ctx.fillRect(-130, -14, 286, 18);
    ctx.strokeRect(-130, -14, 286, 18);

    // Porch awning posts & mint-green scalloped overhang roof on the right!
    ctx.fillStyle = '#f5f2e6'.toJS;
    ctx.fillRect(142, -96, 10, 84);
    ctx.strokeRect(142, -96, 10, 84);
    ctx.fillStyle = '#6be09a'.toJS;
    ctx.beginPath();
    ctx.moveTo(64, -108);
    ctx.lineTo(164, -90);
    ctx.lineTo(164, -76);
    ctx.lineTo(64, -84);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Main crooked 2-story sunny-yellow clapboard house body!
    ctx.fillStyle = '#ffe054'.toJS;
    ctx.strokeStyle = '#3b2410'.toJS;
    ctx.lineWidth = 4.2;
    ctx.beginPath();
    ctx.moveTo(-116, -14);
    ctx.lineTo(-124, -172);
    ctx.lineTo(84, -178);
    ctx.lineTo(76, -14);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Horizontal clapboard plank lines + mint-green corner trims!
    ctx.strokeStyle = 'rgba(184, 128, 22, 0.35)'.toJS;
    ctx.lineWidth = 2.0;
    for (double y = -34; y > -168; y -= 18) {
      ctx.beginPath();
      ctx.moveTo(-116, y);
      ctx.lineTo(76, y);
      ctx.stroke();
    }
    ctx.fillStyle = '#5ee09e'.toJS;
    ctx.strokeStyle = '#1f4f36'.toJS;
    ctx.lineWidth = 3.0;
    ctx.fillRect(-124, -172, 16, 158);
    ctx.strokeRect(-124, -172, 16, 158);
    ctx.fillRect(64, -178, 16, 164);
    ctx.strokeRect(64, -178, 16, 164);

    // Quirky crooked pink-and-mint upper lookout turret on the left!
    ctx.fillStyle = '#ff92b8'.toJS;
    ctx.strokeStyle = '#4a1b2e'.toJS;
    ctx.lineWidth = 3.6;
    ctx.beginPath();
    ctx.moveTo(-112, -172);
    ctx.lineTo(-106, -242);
    ctx.lineTo(-42, -246);
    ctx.lineTo(-46, -172);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Crooked red-and-white striped main gabled roof!
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(-142, -168);
    ctx.lineTo(-20, -252);
    ctx.lineTo(106, -174);
    ctx.closePath();
    ctx.fillStyle = '#e84848'.toJS;
    ctx.fill();
    ctx.save();
    ctx.clip();
    ctx.fillStyle = '#fff5e4'.toJS;
    for (double sx = -150; sx < 120; sx += 28) {
      ctx.fillRect(sx, -260, 12, 110);
    }
    ctx.restore();
    ctx.strokeStyle = '#471212'.toJS;
    ctx.lineWidth = 4.2;
    ctx.stroke();
    ctx.restore();

    // Pointy mint-blue turret roof cap + whimsical crooked brick chimney!
    ctx.fillStyle = '#4ec4e8'.toJS;
    ctx.strokeStyle = '#173f54'.toJS;
    ctx.lineWidth = 3.6;
    ctx.beginPath();
    ctx.moveTo(-118, -240);
    ctx.lineTo(-78, -296);
    ctx.lineTo(-32, -242);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#c45242'.toJS;
    ctx.strokeStyle = '#3b1510'.toJS;
    ctx.lineWidth = 3.2;
    ctx.beginPath();
    ctx.moveTo(24, -220);
    ctx.lineTo(36, -278);
    ctx.lineTo(62, -274);
    ctx.lineTo(54, -206);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Cute crooked windows with pink shutters!
    for (final List<double> win in const [
      [-76.0, -138.0],
      [12.0, -140.0],
      [-76.0, -214.0],
    ]) {
      ctx.fillStyle = '#ff7eb0'.toJS;
      ctx.strokeStyle = '#4a1b2e'.toJS;
      ctx.lineWidth = 2.4;
      ctx.fillRect(win[0] - 24, win[1] - 14, 10, 30);
      ctx.strokeRect(win[0] - 24, win[1] - 14, 10, 30);
      ctx.fillRect(win[0] + 14, win[1] - 14, 10, 30);
      ctx.strokeRect(win[0] + 14, win[1] - 14, 10, 30);

      ctx.fillStyle = '#fff5b8'.toJS;
      ctx.fillRect(win[0] - 14, win[1] - 14, 28, 30);
      ctx.strokeRect(win[0] - 14, win[1] - 14, 28, 30);
      ctx.beginPath();
      ctx.moveTo(win[0], win[1] - 14);
      ctx.lineTo(win[0], win[1] + 16);
      ctx.moveTo(win[0] - 14, win[1] + 1);
      ctx.lineTo(win[0] + 14, win[1] + 1);
      ctx.stroke();
    }

    // Carve a hollow playable ground-floor doorway/parlor room so animals can fight inside!
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(-20, -54, 34, pi, 2 * pi);
    ctx.lineTo(14, -14);
    ctx.lineTo(-54, -14);
    ctx.closePath();
    ctx.fill();

    ctx.restore();
  }

  /// Draws a charming white cartoon horse with playful black polka dots on the veranda!
  static void _drawSpottedHorse(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(s, s);
    ctx.strokeStyle = '#24242b'.toJS;
    ctx.lineWidth = 3.0;

    // 4 sturdy white legs with dark hooves.
    for (final double lx in const [-20.0, -10.0, 10.0, 20.0]) {
      ctx.fillStyle = '#ffffff'.toJS;
      ctx.fillRect(lx - 3.5, -24, 7, 22);
      ctx.strokeRect(lx - 3.5, -24, 7, 22);
      ctx.fillStyle = '#363640'.toJS;
      ctx.fillRect(lx - 4, -5, 8, 5);
    }
    // Swishy tail.
    ctx.strokeStyle = '#363640'.toJS;
    ctx.lineWidth = 4.5;
    ctx.beginPath();
    ctx.moveTo(-24, -36);
    ctx.quadraticCurveTo(-36, -30, -34, -16);
    ctx.stroke();

    // Plump white horse body + neck & friendly head.
    ctx.fillStyle = '#ffffff'.toJS;
    ctx.strokeStyle = '#24242b'.toJS;
    ctx.lineWidth = 3.2;
    ctx.beginPath();
    ctx.ellipse(0, -34, 26, 15, 0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Neck & head.
    ctx.beginPath();
    ctx.moveTo(14, -40);
    ctx.lineTo(26, -64);
    ctx.lineTo(42, -56);
    ctx.lineTo(38, -46);
    ctx.lineTo(26, -46);
    ctx.lineTo(22, -32);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Playful black polka dots across body & neck!
    ctx.fillStyle = '#24242b'.toJS;
    for (final List<double> dot in const [
      [-12.0, -38.0, 3.8],
      [-2.0, -29.0, 4.4],
      [8.0, -39.0, 3.5],
      [15.0, -30.0, 3.2],
      [-16.0, -28.0, 2.8],
      [21.0, -50.0, 2.6],
    ]) {
      ctx.beginPath();
      ctx.arc(dot[0], dot[1], dot[2], 0, 2 * pi);
      ctx.fill();
    }
    // Cute eye & bright red bridle!
    ctx.fillStyle = '#24242b'.toJS;
    ctx.beginPath();
    ctx.arc(31, -56, 2.2, 0, 2 * pi);
    ctx.fill();
    ctx.strokeStyle = '#e84848'.toJS;
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    ctx.moveTo(35, -47);
    ctx.lineTo(38, -56);
    ctx.stroke();
    ctx.restore();
  }

  /// Draws a giant gnarled soda/lemonade tree with hollow hideout nook & hanging glass bottles!
  static void _drawSodaTree(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);

    // Wide gnarled trunk with spreading roots.
    ctx.fillStyle = '#8c5a32'.toJS;
    ctx.strokeStyle = '#361f0e'.toJS;
    ctx.lineWidth = 4.2;
    ctx.beginPath();
    ctx.moveTo(-46, 8);
    ctx.quadraticCurveTo(-30, -40, -26, -124);
    ctx.lineTo(28, -124);
    ctx.quadraticCurveTo(32, -40, 48, 8);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Lush puffy multi-lobe summer canopy!
    const List<List<double>> puffs = [
      [-64.0, -148.0, 56.0],
      [0.0, -176.0, 68.0],
      [66.0, -146.0, 54.0],
      [-32.0, -118.0, 46.0],
      [36.0, -118.0, 46.0],
    ];
    for (int i = 0; i < puffs.length; i++) {
      ctx.fillStyle = (i.isEven ? '#5ee048' : '#3eb836').toJS;
      ctx.strokeStyle = '#184f18'.toJS;
      ctx.lineWidth = 3.8;
      ctx.beginPath();
      ctx.arc(puffs[i][0], puffs[i][1], puffs[i][2], 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }

    // Dangling shiny green glass lemonade/soda bottles hanging from the branches!
    for (final List<double> b in const [
      [-68.0, -114.0],
      [-18.0, -138.0],
      [32.0, -142.0],
      [74.0, -112.0],
    ]) {
      ctx.fillStyle = '#70f58c'.toJS;
      ctx.strokeStyle = '#195428'.toJS;
      ctx.lineWidth = 2.2;
      ctx.fillRect(b[0] - 4, b[1] - 12, 8, 16);
      ctx.strokeRect(b[0] - 4, b[1] - 12, 8, 16);
      ctx.fillStyle = '#ffe854'.toJS;
      ctx.fillRect(b[0] - 2.5, b[1] - 17, 5, 5);
    }

    // Carve a hollow tree-trunk hideout hole!
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.ellipse(0, -42, 18, 26, 0, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  static void _drawTreasureChest(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(s, s);
    // Open curved chest lid.
    ctx.fillStyle = '#8f4d22'.toJS;
    ctx.strokeStyle = '#2e1608'.toJS;
    ctx.lineWidth = 3.2;
    ctx.beginPath();
    ctx.arc(0, -34, 28, pi, 2 * pi);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    // Glittering mound of gold coins + big red ruby!
    ctx.fillStyle = '#ffd83b'.toJS;
    for (final List<double> c in const [
      [-16.0, -32.0],
      [-6.0, -37.0],
      [5.0, -38.0],
      [16.0, -32.0],
      [0.0, -31.0],
    ]) {
      ctx.beginPath();
      ctx.arc(c[0], c[1], 7.5, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    ctx.fillStyle = '#ff3864'.toJS;
    ctx.beginPath();
    ctx.moveTo(0, -46);
    ctx.lineTo(7, -38);
    ctx.lineTo(0, -30);
    ctx.lineTo(-7, -38);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    // Chest wooden base with golden metal bands!
    ctx.fillStyle = '#a85d28'.toJS;
    ctx.fillRect(-30, -32, 60, 34);
    ctx.strokeRect(-30, -32, 60, 34);
    ctx.fillStyle = '#ffce38'.toJS;
    ctx.fillRect(-30, -20, 60, 7);
    ctx.fillRect(-6, -32, 12, 18);
    ctx.strokeRect(-6, -32, 12, 18);
    ctx.restore();
  }

  static void _drawAppleTree(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(s, s);
    ctx.fillStyle = '#855029'.toJS;
    ctx.strokeStyle = '#331c0b'.toJS;
    ctx.lineWidth = 3.2;
    ctx.fillRect(-10, -48, 20, 52);
    ctx.strokeRect(-10, -48, 20, 52);

    ctx.fillStyle = '#52cf40'.toJS;
    ctx.strokeStyle = '#184d16'.toJS;
    ctx.lineWidth = 3.4;
    ctx.beginPath();
    ctx.arc(-20, -64, 24, 0, 2 * pi);
    ctx.arc(18, -62, 24, 0, 2 * pi);
    ctx.arc(0, -82, 28, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Bright red apples!
    ctx.fillStyle = '#ff4444'.toJS;
    for (final List<double> a in const [
      [-16.0, -68.0],
      [14.0, -58.0],
      [2.0, -84.0],
      [-4.0, -54.0],
    ]) {
      ctx.beginPath();
      ctx.arc(a[0], a[1], 5.5, 0, 2 * pi);
      ctx.fill();
    }
    ctx.restore();
  }

  static void _drawPicketFence(CanvasRenderingContext2D ctx, List<double> heights,
      int step, double x0, double x1) {
    ctx.save();
    ctx.fillStyle = '#fffaf0'.toJS;
    ctx.strokeStyle = '#4a453c'.toJS;
    ctx.lineWidth = 2.2;
    for (double x = x0; x <= x1; x += 16.0) {
      final double y = _sampleHeight(heights, x, step) + 2.0;
      ctx.beginPath();
      ctx.moveTo(x - 4.5, y);
      ctx.lineTo(x - 4.5, y - 22);
      ctx.lineTo(x, y - 29);
      ctx.lineTo(x + 4.5, y - 22);
      ctx.lineTo(x + 4.5, y);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawGardenFlag(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#f5f0e0'.toJS;
    ctx.strokeStyle = '#33281c'.toJS;
    ctx.lineWidth = 2.6;
    ctx.fillRect(-3, -64, 6, 66);
    ctx.strokeRect(-3, -64, 6, 66);
    // Cheerful yellow/blue pennants!
    ctx.fillStyle = '#389cff'.toJS;
    ctx.beginPath();
    ctx.moveTo(3, -62);
    ctx.lineTo(44, -52);
    ctx.lineTo(3, -40);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#ffe040'.toJS;
    ctx.fillRect(3, -53, 28, 4.5);
    ctx.restore();
  }

  // =========================================================================
  // 2. SPOOKY CASTLE (Spökslott & Pumpaland)
  // =========================================================================
  static void _generateSpooky(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights =
        _buildHeightfield(w, h * 0.68, 95.0, rng, step: step, edgeDrop: 90.0);

    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#564770',
      fillMid: '#3a2f52',
      fillBottom: '#231b36',
      outlineColor: '#120d1f',
      turfTop: '#8462d4',
      turfBottom: '#46307d',
      turfOutline: '#1d1238',
      pebbleColor: 'rgba(20, 14, 34, 0.44)',
      turfThickness: 26.0,
    );

    final double cryptX = w * 0.5;
    final double cryptY = _sampleHeight(heights, cryptX, step) + 106.0;

    // 4 crooked gothic castle towers spread across the 2080px skyline!
    final List<double> towerXs = [
      w * (0.16 + rng.nextDouble() * 0.03),
      w * (0.39 + rng.nextDouble() * 0.03),
      w * (0.61 + rng.nextDouble() * 0.03),
      w * (0.83 + rng.nextDouble() * 0.03),
    ];
    final List<double> towerTops = [];
    for (int i = 0; i < towerXs.length; i++) {
      final double tx = towerXs[i];
      final double baseY = _sampleHeight(heights, tx, step) + 12.0;
      final double tw = (i == 1 || i == 2 ? 156.0 : 124.0);
      final double th =
          (i == 1 ? 270.0 : (i == 2 ? 245.0 : 195.0)) + rng.nextDouble() * 30.0;
      towerTops.add(baseY - th);
      _drawSpookyTower(ctx, tx, baseY, tw, th, rng);
    }

    // Rickety haunted wooden catwalk bridges linking the side towers!
    _drawRopeBridge(
      ctx,
      towerXs[0] + 58,
      towerTops[0] + 44,
      towerXs[1] - 74,
      towerTops[1] + 58,
      sag: 24.0,
      woodColor: '#694e78',
    );
    _drawRopeBridge(
      ctx,
      towerXs[2] + 74,
      towerTops[2] + 54,
      towerXs[3] - 58,
      towerTops[3] + 42,
      sag: 24.0,
      woodColor: '#694e78',
    );

    // GIMMICK: Giant Hollow Jack-o'-Lantern Hideout & Bubbling Witch Cauldron!
    final double giantPumpX = w * 0.50;
    final double giantPumpY = _sampleHeight(heights, giantPumpX, step) + 4.0;
    _drawGiantHollowPumpkin(ctx, giantPumpX, giantPumpY);

    final double cauldronX = w * 0.28;
    _drawWitchCauldron(ctx, cauldronX, _sampleHeight(heights, cauldronX, step) + 2);

    // Gnarled dead trees, glowing jack-o'-lanterns & tilted gravestones!
    for (int i = 0; i < 7; i++) {
      final double px = w * (0.07 + i * 0.145 + rng.nextDouble() * 0.02);
      if ((px - giantPumpX).abs() < 80) continue;
      final double py = _sampleHeight(heights, px, step);
      if (i % 3 == 0) {
        _drawDeadTree(ctx, px, py + 4, 0.95);
      } else if (i % 3 == 1) {
        _drawPumpkin(ctx, px, py - 6, 1.05);
      } else {
        _drawGravestone(ctx, px, py - 2, (rng.nextDouble() - 0.5) * 0.28);
      }
    }

    // 3 Floating haunted stone ledges in the moonlight!
    for (int i = 0; i < 3; i++) {
      final double lx = w * (0.27 + i * 0.23);
      final double ly = h * (0.22 + (i == 1 ? -0.04 : 0.06));
      _drawFloatingCartoonIsland(
        ctx,
        cx: lx,
        cy: ly,
        width: 205.0,
        height: 78.0,
        rockTop: '#54466b',
        rockBottom: '#2c233d',
        rockOutline: '#120d1f',
        turfTop: '#8462d4',
        turfBottom: '#46307d',
        turfOutline: '#1d1238',
      );
      _drawPumpkin(ctx, lx + (i.isEven ? -40 : 40), ly - 16, 0.95);
    }

    // THEMATIC INDESTRUCTIBLE BEDROCK (7 CLEAR SECTIONS):
    // 1-4. Forged black-iron rune foundations anchoring every gothic tower!
    for (int i = 0; i < towerXs.length; i++) {
      final double tx = towerXs[i];
      final double baseY = _sampleHeight(heights, tx, step) + 18.0;
      _drawBedrockBlock(
        bCtx,
        x: tx - 56,
        y: baseY,
        w: 112,
        h: 34,
        style: _BedrockStyle.gothicRune,
      );
    }
    // 5. Arched gothic dungeon vault ceiling shielding the center crypt!
    _drawBedrockArchVault(
      bCtx,
      cx: cryptX,
      y: cryptY + 12,
      span: 196.0,
      thickness: 26.0,
      style: _BedrockStyle.gothicRune,
    );
    // 6. Heavy wrought-iron sky-bridge girder spanning between the two central keep towers!
    _drawBedrockGirder(
      bCtx,
      x: towerXs[1] + 74,
      y: min(towerTops[1], towerTops[2]) + 72,
      w: (towerXs[2] - towerXs[1]) - 148,
      h: 28,
      style: _BedrockStyle.gothicRune,
    );
    // 7. Armored gothic crypt pillar on the right wing!
    _drawBedrockPillar(
      bCtx,
      cx: w * 0.72,
      topY: h * 0.68,
      height: 120,
      width: 44,
      style: _BedrockStyle.gothicRune,
    );
  }

  static void _drawSpookyTower(CanvasRenderingContext2D ctx, double cx,
      double baseY, double w, double h, Random rng) {
    final double x = cx - w * 0.5;
    final double topY = baseY - h;

    ctx.save();
    final CanvasGradient wall = ctx.createLinearGradient(x, topY, x + w, topY);
    wall.addColorStop(0.0, '#6a5d88');
    wall.addColorStop(0.6, '#4d4169');
    wall.addColorStop(1.0, '#362d4d');
    ctx.fillStyle = wall;
    ctx.strokeStyle = '#151024'.toJS;
    ctx.lineWidth = 4.0;
    ctx.fillRect(x, topY, w, h);
    ctx.strokeRect(x, topY, w, h);

    // Stone brick accents.
    ctx.strokeStyle = 'rgba(20, 12, 36, 0.35)'.toJS;
    ctx.lineWidth = 2.0;
    for (double by = topY + 26; by < baseY - 20; by += 26) {
      ctx.beginPath();
      ctx.moveTo(x + 4, by);
      ctx.lineTo(x + w - 4, by);
      ctx.stroke();
    }

    // Battlements.
    const int merlons = 4;
    final double mw = w / (merlons * 2 - 1);
    for (int i = 0; i < merlons; i++) {
      final double mx = x + i * mw * 2;
      ctx.fillStyle = '#5e517c'.toJS;
      ctx.strokeStyle = '#151024'.toJS;
      ctx.lineWidth = 3.2;
      ctx.fillRect(mx - 2, topY - 18, mw + 4, 20);
      ctx.strokeRect(mx - 2, topY - 18, mw + 4, 20);
    }

    // Crooked witch-hat spire + tattered banner!
    final double tilt = (rng.nextDouble() - 0.5) * 32.0;
    ctx.fillStyle = '#2d1c4a'.toJS;
    ctx.beginPath();
    ctx.moveTo(x - 14, topY - 16);
    ctx.lineTo(cx + tilt, topY - 102);
    ctx.lineTo(x + w + 14, topY - 16);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Tattered orange/purple pennant atop the spire!
    ctx.fillStyle = '#ff7b24'.toJS;
    ctx.beginPath();
    ctx.moveTo(cx + tilt, topY - 102);
    ctx.lineTo(cx + tilt + 34, topY - 94);
    ctx.lineTo(cx + tilt, topY - 82);
    ctx.closePath();
    ctx.fill();

    // Glowing yellow haunted arched windows.
    for (int row = 0; row < 2; row++) {
      final double wy = topY + 42.0 + row * 72.0;
      if (wy + 34 > baseY - 18) continue;
      ctx.fillStyle = '#ffcf4d'.toJS;
      ctx.strokeStyle = '#19112b'.toJS;
      ctx.lineWidth = 3.0;
      ctx.beginPath();
      ctx.arc(cx, wy, 15, pi, 2 * pi);
      ctx.lineTo(cx + 15, wy + 24);
      ctx.lineTo(cx - 15, wy + 24);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }

    // Hollow playable guard-room archway at base of tower!
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(cx, baseY - 40, w * 0.28, pi, 2 * pi);
    ctx.lineTo(cx + w * 0.28, baseY - 10);
    ctx.lineTo(cx - w * 0.28, baseY - 10);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  static void _drawGiantHollowPumpkin(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#3b8c32'.toJS;
    ctx.strokeStyle = '#183814'.toJS;
    ctx.lineWidth = 3.6;
    ctx.fillRect(-8, -108, 16, 24);
    ctx.strokeRect(-8, -108, 16, 24);

    ctx.fillStyle = '#ff7d1a'.toJS;
    ctx.strokeStyle = '#3b1804'.toJS;
    ctx.lineWidth = 4.2;
    ctx.beginPath();
    ctx.ellipse(0, -44, 68, 52, 0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Pumpkin rib lines.
    ctx.strokeStyle = '#b54608'.toJS;
    ctx.lineWidth = 2.6;
    for (final double rx in const [28.0, 50.0]) {
      ctx.beginPath();
      ctx.ellipse(0, -44, rx, 50, 0, 0, 2 * pi);
      ctx.stroke();
    }

    // Hollow grinning doorway inside the giant pumpkin!
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(0, -30, 26, pi, 2 * pi);
    ctx.lineTo(26, -4);
    ctx.lineTo(-26, -4);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  static void _drawWitchCauldron(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    // Glowing neon-green potion bubbles!
    ctx.fillStyle = '#6eff54'.toJS;
    ctx.strokeStyle = '#195414'.toJS;
    ctx.lineWidth = 2.6;
    for (final List<double> b in const [
      [-14.0, -46.0, 10.0],
      [4.0, -52.0, 12.0],
      [18.0, -44.0, 8.0],
      [-2.0, -68.0, 6.0],
    ]) {
      ctx.beginPath();
      ctx.arc(b[0], b[1], b[2], 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    // Iron cauldron pot.
    ctx.fillStyle = '#2d3140'.toJS;
    ctx.strokeStyle = '#0f111a'.toJS;
    ctx.lineWidth = 3.6;
    ctx.beginPath();
    ctx.arc(0, -22, 30, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.fillRect(-34, -44, 68, 10);
    ctx.strokeRect(-34, -44, 68, 10);
    ctx.restore();
  }

  static void _drawDeadTree(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(s, s);
    ctx.strokeStyle = '#261a33'.toJS;
    ctx.lineWidth = 11.0;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(0, 4);
    ctx.quadraticCurveTo(-8, -42, 4, -84);
    ctx.moveTo(-2, -46);
    ctx.quadraticCurveTo(-30, -64, -42, -92);
    ctx.moveTo(2, -56);
    ctx.quadraticCurveTo(28, -74, 44, -98);
    ctx.stroke();
    // Glowing spooky eyes in trunk!
    ctx.fillStyle = '#ffe84d'.toJS;
    ctx.beginPath();
    ctx.arc(-4, -34, 2.6, 0, 2 * pi);
    ctx.arc(4, -34, 2.6, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  static void _drawPumpkin(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#3b8c32'.toJS;
    ctx.strokeStyle = '#183814'.toJS;
    ctx.lineWidth = 2.4 * s;
    ctx.fillRect(-3 * s, -24 * s, 6 * s, 9 * s);
    ctx.strokeRect(-3 * s, -24 * s, 6 * s, 9 * s);

    ctx.fillStyle = '#ff851b'.toJS;
    ctx.strokeStyle = '#3b1804'.toJS;
    ctx.lineWidth = 3.0 * s;
    ctx.beginPath();
    ctx.ellipse(0, -6 * s, 18 * s, 14 * s, 0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#fff066'.toJS;
    ctx.beginPath();
    ctx.moveTo(-8 * s, -9 * s);
    ctx.lineTo(-4 * s, -13 * s);
    ctx.lineTo(-2 * s, -8 * s);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(8 * s, -9 * s);
    ctx.lineTo(4 * s, -13 * s);
    ctx.lineTo(2 * s, -8 * s);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.arc(0, -3 * s, 7 * s, 0.15 * pi, 0.85 * pi);
    ctx.fill();
    ctx.restore();
  }

  static void _drawGravestone(
      CanvasRenderingContext2D ctx, double x, double y, double angle) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(angle);
    ctx.fillStyle = '#8b8ca3'.toJS;
    ctx.strokeStyle = '#242533'.toJS;
    ctx.lineWidth = 3.0;
    ctx.beginPath();
    ctx.arc(0, -24, 15, pi, 2 * pi);
    ctx.lineTo(15, 4);
    ctx.lineTo(-15, 4);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.strokeStyle = '#3b3c4d'.toJS;
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    ctx.moveTo(0, -26);
    ctx.lineTo(0, -10);
    ctx.moveTo(-6, -20);
    ctx.lineTo(6, -20);
    ctx.stroke();
    ctx.restore();
  }

  // =========================================================================
  // 3. VOLCANO CRATER (Vulkan & Lavakrater)
  // =========================================================================
  static void _generateVolcano(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights =
        _buildHeightfield(w, h * 0.62, 115.0, rng, step: step, edgeDrop: 95.0);

    // Sculpt a dramatic double-caldera volcanic ridge across the 2080px arena!
    for (int i = 0; i < heights.length; i++) {
      final double u = (i * step) / w;
      final double dCenter = (u - 0.5).abs();
      if (dCenter < 0.12) {
        heights[i] += (1.0 - dCenter / 0.12) * 155.0;
      } else if (dCenter < 0.28) {
        heights[i] -= sin(((dCenter - 0.12) / 0.16) * pi) * 145.0;
      }
      heights[i] = heights[i].clamp(210.0, h - 105.0);
    }

    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#6b4244',
      fillMid: '#4a292d',
      fillBottom: '#2b161a',
      outlineColor: '#170a0d',
      turfTop: '#ff7b2e',
      turfBottom: '#b83228',
      turfOutline: '#381010',
      pebbleColor: 'rgba(255, 130, 48, 0.25)',
      turfThickness: 22.0,
    );

    // Glowing cartoon lava veins & magma cascades!
    ctx.save();
    ctx.globalCompositeOperation = 'source-atop';
    for (int v = 0; v < 10; v++) {
      final double vx = w * (0.08 + v * 0.095);
      final double vy = _sampleHeight(heights, vx, step) + 30.0;
      ctx.strokeStyle = '#ff9824'.toJS;
      ctx.lineWidth = 8.0;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(vx, vy);
      ctx.quadraticCurveTo(vx + (rng.nextDouble() - 0.5) * 100, vy + 95,
          vx + (rng.nextDouble() - 0.5) * 70, h.toDouble());
      ctx.stroke();

      ctx.strokeStyle = '#fff078'.toJS;
      ctx.lineWidth = 2.8;
      ctx.stroke();
    }
    ctx.restore();

    // GIMMICK 1: Giant Fossil Ribcage Bridge arching over the central lava caldera!
    _drawFossilRibBridge(ctx, w * 0.50, h * 0.57, 250.0);

    // GIMMICK 2: Glowing Magma Crystal Clusters & Steaming Fumarole Chimneys!
    for (int i = 0; i < 6; i++) {
      final double cx = w * (0.11 + i * 0.155);
      final double cy = _sampleHeight(heights, cx, step) + 4.0;
      if (i == 1 || i == 4) {
        _drawFumaroleChimney(ctx, cx, cy);
      } else {
        _drawCrystalCluster(ctx, cx, cy, '#ff8e2b', '#ffe866', '#4a140c');
      }
    }

    // 4 Floating obsidian-and-lava sky islets!
    for (int i = 0; i < 4; i++) {
      final double ix = w * (0.15 + i * 0.235 + (rng.nextDouble() - 0.5) * 0.03);
      final double iy = h * (0.24 + (i.isOdd ? -0.04 : 0.05));
      _drawFloatingCartoonIsland(
        ctx,
        cx: ix,
        cy: iy,
        width: 225.0,
        height: 84.0,
        rockTop: '#5e3b3e',
        rockBottom: '#2d181c',
        rockOutline: '#170a0d',
        turfTop: '#ff8a36',
        turfBottom: '#c23426',
        turfOutline: '#381010',
      );
      if (i.isEven) {
        _drawCrystalCluster(ctx, ix + 34, iy - 10, '#ff6a22', '#fff078', '#42100a');
      }
    }

    // THEMATIC INDESTRUCTIBLE BEDROCK (7 CLEAR SECTIONS):
    // 1-4. Forged volcanic iron-basalt blast pillars with fiery runes!
    for (int i = 0; i < 4; i++) {
      final double bx = w * (0.14 + i * 0.24);
      final double by = min(h - 145.0, _sampleHeight(heights, bx, step) + 38.0);
      _drawBedrockPillar(
        bCtx,
        cx: bx,
        topY: by,
        height: 108,
        width: 50,
        style: _BedrockStyle.lavaForged,
      );
    }
    // 5. Armored heat-shielded magma bridge girder across the central caldera!
    _drawBedrockGirder(
      bCtx,
      x: w * 0.5 - 92,
      y: h * 0.62,
      w: 184,
      h: 30,
      style: _BedrockStyle.lavaForged,
    );
    // 6-7. Volcanic bunker arch vaults shielding the left & right lava tubes!
    _drawBedrockArchVault(
      bCtx,
      cx: w * 0.31,
      y: h * 0.72,
      span: 164,
      thickness: 24,
      style: _BedrockStyle.lavaForged,
    );
    _drawBedrockArchVault(
      bCtx,
      cx: w * 0.69,
      y: h * 0.73,
      span: 164,
      thickness: 24,
      style: _BedrockStyle.lavaForged,
    );
  }

  static void _drawFossilRibBridge(
      CanvasRenderingContext2D ctx, double cx, double y, double span) {
    ctx.save();
    // Curved pale bone spine walkway.
    ctx.strokeStyle = '#3b2e26'.toJS;
    ctx.lineWidth = 16.0;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(cx - span * 0.5, y + 18);
    ctx.quadraticCurveTo(cx, y - 24, cx + span * 0.5, y + 18);
    ctx.stroke();

    ctx.strokeStyle = '#efe5cf'.toJS;
    ctx.lineWidth = 10.0;
    ctx.stroke();

    // Arching fossil ribs along the spine!
    for (int i = -3; i <= 3; i++) {
      final double rx = cx + i * (span / 8.0);
      final double ry = y - 4 + (i.abs() * 4.5);
      ctx.strokeStyle = '#3b2e26'.toJS;
      ctx.lineWidth = 10.0;
      ctx.beginPath();
      ctx.moveTo(rx, ry);
      ctx.quadraticCurveTo(rx - 12, ry - 42, rx + 8, ry - 54);
      ctx.stroke();
      ctx.strokeStyle = '#f5eedc'.toJS;
      ctx.lineWidth = 5.5;
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawFumaroleChimney(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#472a2e'.toJS;
    ctx.strokeStyle = '#1a0a0d'.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.moveTo(-30, 8);
    ctx.lineTo(-18, -56);
    ctx.lineTo(18, -56);
    ctx.lineTo(30, 8);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    // Glowing lava mouth rim!
    ctx.fillStyle = '#ff9824'.toJS;
    ctx.beginPath();
    ctx.ellipse(0, -56, 17, 6, 0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  static void _drawCrystalCluster(CanvasRenderingContext2D ctx, double x,
      double y, String mainColor, String brightColor, String outline) {
    ctx.save();
    ctx.translate(x, y);
    const List<List<double>> shards = [
      [-18.0, -34.0, -0.32, 13.0],
      [0.0, -50.0, 0.04, 16.0],
      [18.0, -36.0, 0.30, 13.0],
    ];
    for (final List<double> sh in shards) {
      ctx.save();
      ctx.rotate(sh[2]);
      ctx.fillStyle = mainColor.toJS;
      ctx.strokeStyle = outline.toJS;
      ctx.lineWidth = 3.0;
      ctx.beginPath();
      ctx.moveTo(-sh[3] * 0.5, 4);
      ctx.lineTo(-sh[3] * 0.45, sh[1] * 0.72);
      ctx.lineTo(0, sh[1]);
      ctx.lineTo(sh[3] * 0.45, sh[1] * 0.72);
      ctx.lineTo(sh[3] * 0.5, 4);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = brightColor.toJS;
      ctx.beginPath();
      ctx.moveTo(-2, 0);
      ctx.lineTo(-2, sh[1] * 0.74);
      ctx.lineTo(0, sh[1] * 0.92);
      ctx.lineTo(3, sh[1] * 0.65);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  // =========================================================================
  // 4. FROSTY GLACIER (Arktisk Isglaciär)
  // =========================================================================
  static void _generateGlacier(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights =
        _buildHeightfield(w, h * 0.63, 125.0, rng, step: step, edgeDrop: 100.0);

    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#7be0ff',
      fillMid: '#3da8e6',
      fillBottom: '#1d6ab5',
      outlineColor: '#0e3466',
      turfTop: '#ffffff',
      turfBottom: '#c8f2ff',
      turfOutline: '#2a75b8',
      pebbleColor: 'rgba(255, 255, 255, 0.30)',
      turfThickness: 30.0,
    );

    // GIMMICK 1: Frozen Arctic Ship Hull sticking diagonally out of an icy slope!
    final double shipX = w * 0.31;
    _drawFrozenShip(ctx, shipX, _sampleHeight(heights, shipX, step) + 8.0);

    // GIMMICK 2: Striped Arctic Lighthouse on the right glacier peak!
    final double lightX = w * 0.77;
    _drawArcticLighthouse(ctx, lightX, _sampleHeight(heights, lightX, step) + 8.0);

    // GIMMICK 3: Igloo Village + Cheerful Snowmen + Snowy Pine Forest + Ice Crystals!
    final double iglooX = w * 0.54;
    _drawIgloo(ctx, iglooX, _sampleHeight(heights, iglooX, step) + 6, 1.35);
    _drawIgloo(ctx, iglooX + 92, _sampleHeight(heights, iglooX + 92, step) + 6, 0.85);

    _drawSnowman(ctx, w * 0.15, _sampleHeight(heights, w * 0.15, step) + 2, 1.05);
    _drawSnowman(ctx, w * 0.66, _sampleHeight(heights, w * 0.66, step) + 2, 0.95);

    for (final double frac in const [0.08, 0.21, 0.44, 0.88, 0.94]) {
      final double tx = w * frac;
      _drawPineTree(
        ctx,
        tx,
        _sampleHeight(heights, tx, step) + 2,
        0.92 + rng.nextDouble() * 0.28,
        leafLight: '#5ce0b0',
        leafDark: '#2b9c88',
        outline: '#124a48',
        snowyCap: true,
      );
    }

    // 4 Floating ice plateaus with giant hanging icicles!
    for (int i = 0; i < 4; i++) {
      final double ix = w * (0.15 + i * 0.235 + (rng.nextDouble() - 0.5) * 0.03);
      final double iy = h * (0.24 + (i.isOdd ? -0.04 : 0.06));
      _drawFloatingCartoonIsland(
        ctx,
        cx: ix,
        cy: iy,
        width: 235.0,
        height: 82.0,
        rockTop: '#74d9ff',
        rockBottom: '#2979c7',
        rockOutline: '#0e3466',
        turfTop: '#ffffff',
        turfBottom: '#c9f2ff',
        turfOutline: '#2a75b8',
      );
      _drawIcicles(ctx, ix - 80, iy + 52, 160, 7);
      if (i == 1) {
        _drawCrystalCluster(ctx, ix, iy - 12, '#80f4ff', '#ffffff', '#144c82');
      }
    }

    // THEMATIC INDESTRUCTIBLE BEDROCK (7 CLEAR SECTIONS):
    // 1-3. Faceted diamond-ice crystal pillars locked in steel frames!
    for (final double frac in const [0.18, 0.50, 0.84]) {
      final double bx = w * frac;
      final double by = min(h - 145.0, _sampleHeight(heights, bx, step) + 34.0);
      _drawBedrockPillar(
        bCtx,
        cx: bx,
        topY: by,
        height: 102,
        width: 48,
        style: _BedrockStyle.frostCrystal,
      );
    }
    // 4-5. Reinforced iron ship-keel & lighthouse foundations!
    _drawBedrockBlock(
      bCtx,
      x: shipX - 66,
      y: _sampleHeight(heights, shipX, step) + 14,
      w: 132,
      h: 34,
      style: _BedrockStyle.frostCrystal,
    );
    _drawBedrockBlock(
      bCtx,
      x: lightX - 52,
      y: _sampleHeight(heights, lightX, step) + 12,
      w: 104,
      h: 34,
      style: _BedrockStyle.frostCrystal,
    );
    // 6-7. Armored frost-steel glacier sky-bridges!
    _drawBedrockGirder(
      bCtx,
      x: w * 0.34,
      y: h * 0.42,
      w: 170,
      h: 28,
      style: _BedrockStyle.frostCrystal,
    );
    _drawBedrockGirder(
      bCtx,
      x: w * 0.62,
      y: h * 0.40,
      w: 165,
      h: 28,
      style: _BedrockStyle.frostCrystal,
    );
  }

  static void _drawFrozenShip(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(-0.22);
    // Wooden mast & tattered white sail!
    ctx.fillStyle = '#734420'.toJS;
    ctx.strokeStyle = '#291508'.toJS;
    ctx.lineWidth = 3.2;
    ctx.fillRect(-5, -135, 10, 105);
    ctx.strokeRect(-5, -135, 10, 105);

    ctx.fillStyle = '#e8f6ff'.toJS;
    ctx.strokeStyle = '#265c8c'.toJS;
    ctx.beginPath();
    ctx.moveTo(5, -126);
    ctx.quadraticCurveTo(56, -98, 42, -52);
    ctx.lineTo(5, -62);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Tilted wooden ship hull + portholes!
    ctx.fillStyle = '#9e5a2b'.toJS;
    ctx.strokeStyle = '#30190a'.toJS;
    ctx.lineWidth = 4.0;
    ctx.beginPath();
    ctx.moveTo(-78, -36);
    ctx.lineTo(86, -42);
    ctx.lineTo(62, 6);
    ctx.lineTo(-56, 6);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#ffd24d'.toJS;
    for (final double px in const [-32.0, 0.0, 32.0]) {
      ctx.beginPath();
      ctx.arc(px, -18, 7, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawArcticLighthouse(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    // Striped red & white tapered tower!
    ctx.beginPath();
    ctx.moveTo(-32, 6);
    ctx.lineTo(-20, -148);
    ctx.lineTo(20, -148);
    ctx.lineTo(32, 6);
    ctx.closePath();
    ctx.fillStyle = '#ffffff'.toJS;
    ctx.fill();
    ctx.save();
    ctx.clip();
    ctx.fillStyle = '#e84848'.toJS;
    for (double sy = -132; sy < 10; sy += 42) {
      ctx.fillRect(-40, sy, 80, 20);
    }
    ctx.restore();
    ctx.strokeStyle = '#1b263b'.toJS;
    ctx.lineWidth = 3.8;
    ctx.stroke();

    // Glowing yellow beacon lantern room + dome cap!
    ctx.fillStyle = '#fff066'.toJS;
    ctx.fillRect(-16, -176, 32, 28);
    ctx.strokeRect(-16, -176, 32, 28);
    ctx.fillStyle = '#e84848'.toJS;
    ctx.beginPath();
    ctx.arc(0, -176, 20, pi, 2 * pi);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  static void _drawSnowman(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(s, s);
    ctx.fillStyle = '#ffffff'.toJS;
    ctx.strokeStyle = '#256099'.toJS;
    ctx.lineWidth = 3.0;
    ctx.beginPath();
    ctx.arc(0, -14, 18, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(0, -38, 13, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    // Red scarf!
    ctx.fillStyle = '#ff4a5e'.toJS;
    ctx.fillRect(-13, -30, 26, 6);
    // Carrot nose!
    ctx.fillStyle = '#ff8c24'.toJS;
    ctx.beginPath();
    ctx.moveTo(4, -39);
    ctx.lineTo(20, -36);
    ctx.lineTo(4, -33);
    ctx.closePath();
    ctx.fill();
    // Top hat!
    ctx.fillStyle = '#262b38'.toJS;
    ctx.fillRect(-13, -52, 26, 4);
    ctx.fillRect(-9, -68, 18, 16);
    ctx.restore();
  }

  static void _drawIcicles(CanvasRenderingContext2D ctx, double startX,
      double y, double span, int count) {
    ctx.save();
    ctx.fillStyle = '#c9f6ff'.toJS;
    ctx.strokeStyle = '#1b5e9c'.toJS;
    ctx.lineWidth = 2.4;
    for (int i = 0; i < count; i++) {
      final double ix = startX + (i + 0.5) * (span / count);
      final double len = 24.0 + (i % 3) * 14.0;
      ctx.beginPath();
      ctx.moveTo(ix - 8, y);
      ctx.lineTo(ix, y + len);
      ctx.lineTo(ix + 8, y);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawIgloo(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#e8fbff'.toJS;
    ctx.strokeStyle = '#256aa8'.toJS;
    ctx.lineWidth = 3.4 * s;
    ctx.beginPath();
    ctx.arc(0, 0, 40 * s, pi, 2 * pi);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Hollow entrance tunnel arch!
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(14 * s, 0, 15 * s, pi, 2 * pi);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  // =========================================================================
  // 5. CANDY KINGDOM (Godis- & Pannkaksland)
  // =========================================================================
  static void _generateCandy(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights =
        _buildHeightfield(w, h * 0.65, 110.0, rng, step: step, edgeDrop: 90.0);

    // Multi-layer Neapolitan cake terrain (chocolate, vanilla cream, strawberry)!
    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#9c5b3a',
      fillMid: '#784226',
      fillBottom: '#4a2614',
      outlineColor: '#29130a',
      turfTop: '#ff9ad2',
      turfBottom: '#f25ca2',
      turfOutline: '#8c1d54',
      pebbleColor: 'rgba(255, 224, 150, 0.25)',
      turfThickness: 34.0,
      layerBands: const ['#fff2c9', '#ff9ec9', '#8a4c2e'],
    );

    // Sprinkles & glossy cherries across the frosting!
    const List<String> sprinkleColors = [
      '#ffe44d',
      '#5cf2ff',
      '#7dff74',
      '#ffffff',
      '#ff6b4a',
    ];
    for (int i = 0; i < 110; i++) {
      final double sx = rng.nextDouble() * w;
      final double sy =
          _sampleHeight(heights, sx, step) + 4.0 + rng.nextDouble() * 20.0;
      ctx.save();
      ctx.translate(sx, sy);
      ctx.rotate(rng.nextDouble() * pi);
      ctx.fillStyle = sprinkleColors[i % sprinkleColors.length].toJS;
      ctx.beginPath();
      ctx.roundRect(-5.5, -2.4, 11, 4.8, 2.4.toJS);
      ctx.fill();
      ctx.restore();
    }

    // GIMMICK 1: Gingerbread Cottage with hollow archway + Giant Cupcake Tower!
    final double gHouseX = w * 0.28;
    _drawGingerbreadHouse(ctx, gHouseX, _sampleHeight(heights, gHouseX, step) + 6);

    final double cupX = w * 0.72;
    _drawGiantCupcake(ctx, cupX, _sampleHeight(heights, cupX, step) + 8);

    // GIMMICK 2: Arched Red-and-White Candy Cane Bridge spanning the center valley!
    _drawCandyCaneBridge(ctx, w * 0.50, h * 0.56, 260.0);

    // GIMMICK 3: 4 GIANT FLOATING FROSTED DONUTS (with genuine playable holes!)
    final List<List<double>> donuts = [
      [w * 0.16, h * 0.29, 82.0, 29.0],
      [w * 0.39, h * 0.22, 92.0, 33.0],
      [w * 0.62, h * 0.24, 90.0, 32.0],
      [w * 0.84, h * 0.30, 82.0, 28.0],
    ];
    const List<String> glazes = ['#ff6eb8', '#66ecff', '#ffe054', '#7dff74'];
    for (int i = 0; i < donuts.length; i++) {
      final double dx = donuts[i][0] + (rng.nextDouble() - 0.5) * 30;
      final double dy = donuts[i][1] + (rng.nextDouble() - 0.5) * 24;
      _drawFrostedDonut(ctx, dx, dy, donuts[i][2], donuts[i][3], glazes[i]);
    }

    // Giant swirled lollipops & stacked golden waffles along the hills!
    for (int i = 0; i < 6; i++) {
      final double lx = w * (0.09 + i * 0.162 + rng.nextDouble() * 0.02);
      if ((lx - gHouseX).abs() < 85 || (lx - cupX).abs() < 85) continue;
      final double ly = _sampleHeight(heights, lx, step);
      _drawLollipop(ctx, lx, ly, i.isEven ? '#ff5488' : '#4be6ff', 1.05);
    }

    // THEMATIC INDESTRUCTIBLE BEDROCK (7 CLEAR SECTIONS):
    // 1-4. Steel-riveted peppermint candy blocks along the hills!
    for (int i = 0; i < 4; i++) {
      final double bx = w * (0.14 + i * 0.24);
      final double by = min(h - 95.0, _sampleHeight(heights, bx, step) + 44.0);
      _drawBedrockBlock(
        bCtx,
        x: bx - 56,
        y: by,
        w: 112,
        h: 36,
        style: _BedrockStyle.peppermintSteel,
        diagonalStripes: true,
      );
    }
    // 5-6. Armored peppermint sky-girders connecting the floating donuts!
    _drawBedrockGirder(
      bCtx,
      x: w * 0.24,
      y: h * 0.39,
      w: 175,
      h: 28,
      style: _BedrockStyle.peppermintSteel,
    );
    _drawBedrockGirder(
      bCtx,
      x: w * 0.70,
      y: h * 0.39,
      w: 175,
      h: 28,
      style: _BedrockStyle.peppermintSteel,
    );
    // 7. Reinforced peppermint arch vault shielding the center valley!
    _drawBedrockArchVault(
      bCtx,
      cx: w * 0.50,
      y: h * 0.76,
      span: 180,
      thickness: 26,
      style: _BedrockStyle.peppermintSteel,
    );
  }

  static void _drawGingerbreadHouse(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#c47438'.toJS;
    ctx.strokeStyle = '#4a230b'.toJS;
    ctx.lineWidth = 4.0;
    ctx.fillRect(-66, -110, 132, 112);
    ctx.strokeRect(-66, -110, 132, 112);

    // Frosted white icing roof with colorful gumdrops!
    ctx.fillStyle = '#fff5fa'.toJS;
    ctx.strokeStyle = '#8c1d54'.toJS;
    ctx.lineWidth = 4.0;
    ctx.beginPath();
    ctx.moveTo(-82, -106);
    ctx.lineTo(0, -176);
    ctx.lineTo(82, -106);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    const List<String> drops = ['#ff4d79', '#ffe047', '#5ce6ff', '#78f266'];
    for (int i = 0; i < 4; i++) {
      ctx.fillStyle = drops[i].toJS;
      ctx.beginPath();
      ctx.arc(-45 + i * 30, -116 - (i == 1 || i == 2 ? 22 : 0), 9, pi, 2 * pi);
      ctx.fill();
    }

    // Hollow cookie doorway!
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(0, -34, 24, pi, 2 * pi);
    ctx.lineTo(24, 2);
    ctx.lineTo(-24, 2);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  static void _drawGiantCupcake(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    // Striped pastel cupcake paper wrapper!
    ctx.fillStyle = '#5ee0ff'.toJS;
    ctx.strokeStyle = '#195478'.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.moveTo(-58, -74);
    ctx.lineTo(58, -74);
    ctx.lineTo(42, 6);
    ctx.lineTo(-42, 6);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Swirled pink frosting crown!
    ctx.fillStyle = '#ff85c4'.toJS;
    ctx.strokeStyle = '#8c1d54'.toJS;
    ctx.beginPath();
    ctx.arc(-28, -82, 34, 0, 2 * pi);
    ctx.arc(28, -82, 34, 0, 2 * pi);
    ctx.arc(0, -112, 38, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Glossy red cherry on top!
    ctx.fillStyle = '#ff2e4c'.toJS;
    ctx.strokeStyle = '#5c0c18'.toJS;
    ctx.lineWidth = 3.0;
    ctx.beginPath();
    ctx.arc(0, -156, 16, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  static void _drawCandyCaneBridge(
      CanvasRenderingContext2D ctx, double cx, double y, double span) {
    ctx.save();
    ctx.strokeStyle = '#6e1634'.toJS;
    ctx.lineWidth = 22.0;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(cx - span * 0.5, y + 20);
    ctx.quadraticCurveTo(cx, y - 34, cx + span * 0.5, y + 20);
    ctx.stroke();

    ctx.strokeStyle = '#ffffff'.toJS;
    ctx.lineWidth = 15.0;
    ctx.stroke();

    ctx.strokeStyle = '#ff4466'.toJS;
    ctx.lineWidth = 15.0;
    ctx.setLineDash([14.toJS, 14.toJS].toJS);
    ctx.stroke();
    ctx.restore();
  }

  static void _drawFrostedDonut(
    CanvasRenderingContext2D ctx,
    double cx,
    double cy,
    double outerR,
    double innerR,
    String glazeColor,
  ) {
    ctx.save();
    ctx.fillStyle = '#e8a85c'.toJS;
    ctx.strokeStyle = '#5c3114'.toJS;
    ctx.lineWidth = 4.0;
    ctx.beginPath();
    ctx.arc(cx, cy, outerR, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = glazeColor.toJS;
    ctx.beginPath();
    ctx.arc(cx, cy - 3, outerR * 0.86, 0, 2 * pi);
    ctx.fill();

    for (int i = 0; i < 16; i++) {
      final double a = (i / 16.0) * 2 * pi;
      final double r = innerR + (outerR - innerR) * (0.35 + (i % 3) * 0.16);
      ctx.save();
      ctx.translate(cx + cos(a) * r, cy + sin(a) * r);
      ctx.rotate(a + 0.6);
      ctx.fillStyle = (i.isEven ? '#ffffff' : '#ffe854').toJS;
      ctx.fillRect(-5, -2, 10, 4);
      ctx.restore();
    }

    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(cx, cy, innerR, 0, 2 * pi);
    ctx.fill();

    ctx.globalCompositeOperation = 'source-over';
    ctx.strokeStyle = '#5c3114'.toJS;
    ctx.lineWidth = 3.5;
    ctx.beginPath();
    ctx.arc(cx, cy, innerR, 0, 2 * pi);
    ctx.stroke();
    ctx.restore();
  }

  static void _drawLollipop(CanvasRenderingContext2D ctx, double x, double y,
      String color, double s) {
    ctx.save();
    ctx.translate(x, y);
    ctx.strokeStyle = '#ffffff'.toJS;
    ctx.lineWidth = 6.5 * s;
    ctx.beginPath();
    ctx.moveTo(0, 6);
    ctx.lineTo(0, -56 * s);
    ctx.stroke();

    ctx.fillStyle = color.toJS;
    ctx.strokeStyle = '#47152e'.toJS;
    ctx.lineWidth = 3.2 * s;
    ctx.beginPath();
    ctx.arc(0, -68 * s, 22 * s, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    ctx.strokeStyle = '#ffffff'.toJS;
    ctx.lineWidth = 3.2 * s;
    ctx.beginPath();
    ctx.arc(0, -68 * s, 12 * s, 0, 1.5 * pi);
    ctx.stroke();
    ctx.restore();
  }

  // =========================================================================
  // 6. LUNAR BASE (Rymd- & Månkrater — LOW GRAVITY!)
  // =========================================================================
  static void _generateLunar(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights =
        _buildHeightfield(w, h * 0.67, 105.0, rng, step: step, edgeDrop: 90.0);

    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#d8d6c2',
      fillMid: '#aba998',
      fillBottom: '#78766a',
      outlineColor: '#36363d',
      turfTop: '#f2efd8',
      turfBottom: '#c9c6b0',
      turfOutline: '#4f4e52',
      pebbleColor: 'rgba(84, 82, 76, 0.34)',
      turfThickness: 24.0,
    );

    // Classic cheese-moon craters!
    ctx.save();
    ctx.globalCompositeOperation = 'source-atop';
    for (int i = 0; i < 28; i++) {
      final double cx = rng.nextDouble() * w;
      final double topY = _sampleHeight(heights, cx, step);
      final double cy =
          topY + 34.0 + rng.nextDouble() * max(20.0, h - topY - 68.0);
      final double r = 14.0 + rng.nextDouble() * 26.0;
      ctx.fillStyle = 'rgba(92, 90, 84, 0.45)'.toJS;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, 2 * pi);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 252, 232, 0.48)'.toJS;
      ctx.lineWidth = 2.6;
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.88, 0.1 * pi, 0.9 * pi);
      ctx.stroke();
    }
    ctx.restore();

    // 7 Floating low-gravity moon asteroids staggered across the wide space sky!
    final List<List<double>> asteroids = [
      [w * 0.13, h * 0.30, 74.0, 44.0],
      [w * 0.28, h * 0.19, 68.0, 40.0],
      [w * 0.44, h * 0.33, 88.0, 50.0],
      [w * 0.58, h * 0.18, 72.0, 42.0],
      [w * 0.72, h * 0.32, 84.0, 48.0],
      [w * 0.86, h * 0.21, 70.0, 42.0],
      [w * 0.92, h * 0.42, 58.0, 36.0],
    ];
    for (final List<double> a in asteroids) {
      _drawMoonAsteroid(ctx, a[0], a[1], a[2], a[3]);
    }

    // GIMMICK 1: Retro Red-and-White Cartoon Rocket Ship standing on a launchpad!
    final double rocketX = w * 0.50;
    final double rocketY = _sampleHeight(heights, rocketX, step) + 4.0;
    _drawLunarRocket(ctx, rocketX, rocketY);

    // GIMMICK 2: 2 Glass-Domed Lunar Colony Habitats + Moon Rover + Radar Dishes + Flag!
    final double dome1X = w * 0.24;
    _drawLunarDome(ctx, dome1X, _sampleHeight(heights, dome1X, step) + 6);
    final double dome2X = w * 0.76;
    _drawLunarDome(ctx, dome2X, _sampleHeight(heights, dome2X, step) + 6);

    final double roverX = w * 0.36;
    _drawMoonRover(ctx, roverX, _sampleHeight(heights, roverX, step) + 2);

    _drawSatelliteDish(ctx, w * 0.14, _sampleHeight(heights, w * 0.14, step) + 2);
    _drawSatelliteDish(ctx, w * 0.64, _sampleHeight(heights, w * 0.64, step) + 2);
    _drawLunarFlag(ctx, w * 0.87, _sampleHeight(heights, w * 0.87, step) + 2);

    // THEMATIC INDESTRUCTIBLE BEDROCK (8 CLEAR SECTIONS):
    // 1. Massive riveted titanium launchpad with yellow/black hazard stripes under the Rocket!
    _drawBedrockBlock(
      bCtx,
      x: rocketX - 74,
      y: rocketY + 4,
      w: 148,
      h: 34,
      style: _BedrockStyle.titaniumHazard,
      diagonalStripes: true,
    );
    // 2-3. Armored titanium colony pad foundations beneath both biodomes!
    _drawBedrockBlock(
      bCtx,
      x: dome1X - 60,
      y: _sampleHeight(heights, dome1X, step) + 8,
      w: 120,
      h: 32,
      style: _BedrockStyle.titaniumHazard,
      diagonalStripes: true,
    );
    _drawBedrockBlock(
      bCtx,
      x: dome2X - 60,
      y: _sampleHeight(heights, dome2X, step) + 8,
      w: 120,
      h: 32,
      style: _BedrockStyle.titaniumHazard,
      diagonalStripes: true,
    );
    // 4-5. Space-station titanium truss girders bridging high craters & asteroids!
    _drawBedrockGirder(
      bCtx,
      x: w * 0.30,
      y: h * 0.44,
      w: 175,
      h: 28,
      style: _BedrockStyle.titaniumHazard,
    );
    _drawBedrockGirder(
      bCtx,
      x: w * 0.58,
      y: h * 0.44,
      w: 175,
      h: 28,
      style: _BedrockStyle.titaniumHazard,
    );
    // 6-7. Metallic asteroid reactor cores inside the two largest asteroids!
    _drawBedrockBlock(
      bCtx,
      x: asteroids[2][0] - 40,
      y: asteroids[2][1] - 14,
      w: 80,
      h: 28,
      style: _BedrockStyle.titaniumHazard,
    );
    _drawBedrockBlock(
      bCtx,
      x: asteroids[4][0] - 40,
      y: asteroids[4][1] - 14,
      w: 80,
      h: 28,
      style: _BedrockStyle.titaniumHazard,
    );
    // 8. Left-side outpost landing pad!
    _drawBedrockBlock(
      bCtx,
      x: w * 0.08,
      y: _sampleHeight(heights, w * 0.11, step) + 26,
      w: 112,
      h: 30,
      style: _BedrockStyle.titaniumHazard,
      diagonalStripes: true,
    );
  }

  static void _drawLunarRocket(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    // Red rocket tail fins!
    ctx.fillStyle = '#e84848'.toJS;
    ctx.strokeStyle = '#241a26'.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.moveTo(-24, -44);
    ctx.lineTo(-52, 4);
    ctx.lineTo(-18, -8);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(24, -44);
    ctx.lineTo(52, 4);
    ctx.lineTo(18, -8);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Sleek white rocket fuselage!
    ctx.fillStyle = '#f2f6ff'.toJS;
    ctx.beginPath();
    ctx.moveTo(0, -162);
    ctx.quadraticCurveTo(36, -110, 28, -14);
    ctx.lineTo(-28, -14);
    ctx.quadraticCurveTo(-36, -110, 0, -162);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Red nose cone!
    ctx.fillStyle = '#e84848'.toJS;
    ctx.beginPath();
    ctx.moveTo(0, -162);
    ctx.quadraticCurveTo(18, -138, 22, -118);
    ctx.lineTo(-22, -118);
    ctx.quadraticCurveTo(-18, -138, 0, -162);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Glowing cyan porthole!
    ctx.fillStyle = '#5ee8ff'.toJS;
    ctx.beginPath();
    ctx.arc(0, -82, 13, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  static void _drawMoonRover(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#ffd23f'.toJS;
    ctx.strokeStyle = '#242938'.toJS;
    ctx.lineWidth = 3.2;
    ctx.fillRect(-34, -28, 68, 18);
    ctx.strokeRect(-34, -28, 68, 18);
    // Antenna mast.
    ctx.beginPath();
    ctx.moveTo(-20, -28);
    ctx.lineTo(-26, -54);
    ctx.stroke();
    ctx.fillStyle = '#ff5468'.toJS;
    ctx.beginPath();
    ctx.arc(-26, -56, 4.5, 0, 2 * pi);
    ctx.fill();
    // 3 chunky moon wheels!
    ctx.fillStyle = '#384052'.toJS;
    for (final double wx in const [-24.0, 0.0, 24.0]) {
      ctx.beginPath();
      ctx.arc(wx, -8, 10, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawLunarFlag(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#dce4f2'.toJS;
    ctx.strokeStyle = '#242a38'.toJS;
    ctx.lineWidth = 2.6;
    ctx.fillRect(-3, -72, 6, 74);
    ctx.strokeRect(-3, -72, 6, 74);
    ctx.fillStyle = '#ffe047'.toJS;
    ctx.fillRect(3, -70, 44, 26);
    ctx.strokeRect(3, -70, 44, 26);
    ctx.fillStyle = '#26345c'.toJS;
    ctx.beginPath();
    ctx.arc(25, -57, 7, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  static void _drawMoonAsteroid(
      CanvasRenderingContext2D ctx, double cx, double cy, double rx, double ry) {
    ctx.save();
    ctx.translate(cx, cy);
    final CanvasGradient grad =
        ctx.createRadialGradient(-rx * 0.25, -ry * 0.3, 6, 0, 0, rx);
    grad.addColorStop(0.0, '#f0edd6');
    grad.addColorStop(0.65, '#b8b5a2');
    grad.addColorStop(1.0, '#78766b');
    ctx.fillStyle = grad;
    ctx.strokeStyle = '#36363d'.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.ellipse(0, 0, rx, ry, 0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = 'rgba(84, 82, 74, 0.45)'.toJS;
    ctx.beginPath();
    ctx.arc(-rx * 0.32, -ry * 0.12, ry * 0.28, 0, 2 * pi);
    ctx.arc(rx * 0.26, ry * 0.18, ry * 0.22, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  static void _drawLunarDome(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    final CanvasGradient glass =
        ctx.createRadialGradient(-16, -26, 6, 0, -10, 56);
    glass.addColorStop(0.0, '#c2f7ff');
    glass.addColorStop(0.6, '#58c4f2');
    glass.addColorStop(1.0, '#2a6cb5');
    ctx.fillStyle = glass;
    ctx.strokeStyle = '#183052'.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.arc(0, 0, 52, pi, 2 * pi);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Mini green alien plant inside the habitat!
    ctx.fillStyle = '#5ee86e'.toJS;
    ctx.beginPath();
    ctx.arc(-12, -16, 10, 0, 2 * pi);
    ctx.arc(10, -22, 8, 0, 2 * pi);
    ctx.fill();

    ctx.fillStyle = '#c8d2e0'.toJS;
    ctx.fillRect(-56, -10, 112, 16);
    ctx.strokeRect(-56, -10, 112, 16);
    ctx.restore();
  }

  static void _drawSatelliteDish(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.strokeStyle = '#323c4d'.toJS;
    ctx.lineWidth = 6.0;
    ctx.beginPath();
    ctx.moveTo(0, 4);
    ctx.lineTo(0, -34);
    ctx.stroke();

    ctx.fillStyle = '#e0e8f5'.toJS;
    ctx.strokeStyle = '#222c3d'.toJS;
    ctx.lineWidth = 3.2;
    ctx.beginPath();
    ctx.arc(0, -48, 24, 0.2 * pi, 1.15 * pi);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  // =========================================================================
  // 7. CARTOON CITY (Storstads-Takåsar)
  // =========================================================================
  static void _generateCity(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    // Solid urban street & foundation extending flush to the bottom edge!
    final double streetY = h - 122.0;
    ctx.fillStyle = '#586275'.toJS;
    ctx.strokeStyle = '#1b202e'.toJS;
    ctx.lineWidth = 4.2;
    ctx.fillRect(-4.0, streetY, w.toDouble() + 8.0, (h - streetY) + 8.0);
    ctx.strokeRect(-4.0, streetY, w.toDouble() + 8.0, (h - streetY) + 8.0);

    // Yellow dashed road lane markings along top of street!
    ctx.fillStyle = '#ffe047'.toJS;
    for (double rx = 26; rx < w - 26; rx += 64) {
      ctx.fillRect(rx, streetY + 10, 32, 6);
    }

    // 8 colorful detailed cartoon skyscrapers spanning the 2080px skyline!
    const List<List<String>> palettes = [
      ['#f26a5a', '#c4453a'],
      ['#5ab2f2', '#347ec2'],
      ['#f5c542', '#cc9620'],
      ['#6ad482', '#3aa354'],
      ['#a67ef2', '#6f4bc4'],
      ['#ff9848', '#cf6a22'],
      ['#f274b0', '#ba417b'],
      ['#52d4cc', '#289994'],
    ];
    const int buildingCount = 8;
    final double slotW = (w - 110.0) / buildingCount;
    final List<double> roofYs = [];
    final List<double> bXs = [];
    final List<double> bWs = [];

    for (int i = 0; i < buildingCount; i++) {
      final double bw = slotW * (0.68 + rng.nextDouble() * 0.14);
      final double bx = 55.0 + i * slotW + (slotW - bw) * 0.5;
      final double bh = 250.0 + rng.nextDouble() * 305.0;
      final double by = streetY - bh;
      roofYs.add(by);
      bXs.add(bx);
      bWs.add(bw);

      final List<String> pal = palettes[(i + rng.nextInt(3)) % palettes.length];
      final CanvasGradient bGrad =
          ctx.createLinearGradient(bx, by, bx + bw, by);
      bGrad.addColorStop(0.0, pal[0]);
      bGrad.addColorStop(1.0, pal[1]);
      ctx.fillStyle = bGrad;
      ctx.strokeStyle = '#1b202e'.toJS;
      ctx.lineWidth = 4.2;
      ctx.fillRect(bx, by, bw, bh);
      ctx.strokeRect(bx, by, bw, bh);

      // Rooftop ledge cap.
      ctx.fillStyle = '#d6deeb'.toJS;
      ctx.fillRect(bx - 6, by - 10, bw + 12, 14);
      ctx.strokeRect(bx - 6, by - 10, bw + 12, 14);

      // Striped storefront awning at street level!
      ctx.fillStyle = (i.isEven ? '#ff4d5e' : '#38b5ff').toJS;
      ctx.fillRect(bx + 10, streetY - 28, bw - 20, 14);
      ctx.strokeRect(bx + 10, streetY - 28, bw - 20, 14);

      // Grid of glowing & sky-reflected windows.
      final int cols = max(2, (bw ~/ 42));
      final int rows = max(3, ((bh - 42) ~/ 52));
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final double wx = bx + 14 + c * ((bw - 28) / cols);
          final double wy = by + 18 + r * ((bh - 58) / rows);
          final bool lit = rng.nextDouble() > 0.36;
          ctx.fillStyle = (lit ? '#fff29c' : '#2d466b').toJS;
          ctx.strokeStyle = '#1b202e'.toJS;
          ctx.lineWidth = 2.0;
          ctx.fillRect(wx, wy, 22, 26);
          ctx.strokeRect(wx, wy, 22, 26);
        }
      }

      // GIMMICK 2: Rooftop Water Towers, Neon Billboards & Antennas!
      if (i == 1 || i == 6) {
        _drawWaterTower(ctx, bx + bw * 0.5, by - 10);
      } else if (i == 3 || i == 5) {
        _drawRooftopBillboard(
            ctx, bx + bw * 0.5, by - 10, i == 3 ? 'ZOO!' : 'BLAST!');
      }

      // THEMATIC BEDROCK: Riveted yellow construction I-beam inside each skyscraper!
      _drawBedrockBlock(
        bCtx,
        x: bx + 10,
        y: by + bh * 0.48,
        w: bw - 20,
        h: 28,
        style: _BedrockStyle.cityGirder,
        diagonalStripes: true,
      );
    }

    // GIMMICK 3: Giant Yellow Construction Crane arching over the skyline!
    final double craneX = bXs[2] + bWs[2] * 0.5;
    final double craneTopY = min(roofYs[2], roofYs[3]) - 95.0;
    _drawBedrockPillar(
      bCtx,
      cx: craneX,
      topY: max(85.0, craneTopY),
      height: max(80.0, roofYs[2] - max(85.0, craneTopY)),
      width: 30,
      style: _BedrockStyle.cityGirder,
    );
    _drawBedrockGirder(
      bCtx,
      x: craneX - 60,
      y: max(85.0, craneTopY),
      w: 310,
      h: 26,
      style: _BedrockStyle.cityGirder,
    );

    // Armored steel sky-bridge truss girders connecting skyscrapers across the alleys!
    for (int i = 0; i < buildingCount - 1; i += 2) {
      final double bridgeY = min(roofYs[i], roofYs[i + 1]) + 72.0;
      final double startX = bXs[i] + bWs[i] - 8.0;
      final double spanW = (bXs[i + 1] + 8.0) - startX;
      if (spanW > 24.0) {
        _drawBedrockGirder(
          bCtx,
          x: startX,
          y: bridgeY,
          w: spanW,
          h: 28,
          style: _BedrockStyle.cityGirder,
        );
      }
    }

    // Armored steel subway roof girders protecting the underground tunnel!
    _drawBedrockGirder(
      bCtx,
      x: w * 0.30,
      y: streetY + 18,
      w: 220,
      h: 24,
      style: _BedrockStyle.cityGirder,
    );
    _drawBedrockGirder(
      bCtx,
      x: w * 0.62,
      y: streetY + 18,
      w: 220,
      h: 24,
      style: _BedrockStyle.cityGirder,
    );
  }

  static void _drawWaterTower(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    // Steel stilts.
    ctx.strokeStyle = '#242938'.toJS;
    ctx.lineWidth = 4.2;
    ctx.beginPath();
    ctx.moveTo(-22, 0);
    ctx.lineTo(-14, -30);
    ctx.moveTo(22, 0);
    ctx.lineTo(14, -30);
    ctx.moveTo(0, 0);
    ctx.lineTo(0, -30);
    ctx.stroke();

    // Wooden barrel tank.
    ctx.fillStyle = '#b8763e'.toJS;
    ctx.strokeStyle = '#361e0d'.toJS;
    ctx.lineWidth = 3.2;
    ctx.fillRect(-24, -72, 48, 42);
    ctx.strokeRect(-24, -72, 48, 42);
    // Cone roof.
    ctx.fillStyle = '#6e7b91'.toJS;
    ctx.beginPath();
    ctx.moveTo(-28, -72);
    ctx.lineTo(0, -96);
    ctx.lineTo(28, -72);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  static void _drawRooftopBillboard(
      CanvasRenderingContext2D ctx, double x, double y, String label) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#364054'.toJS;
    ctx.fillRect(-26, -24, 6, 26);
    ctx.fillRect(20, -24, 6, 26);

    ctx.fillStyle = '#ff4f79'.toJS;
    ctx.strokeStyle = '#1b202e'.toJS;
    ctx.lineWidth = 3.6;
    ctx.beginPath();
    ctx.roundRect(-52, -74, 104, 52, 8.0.toJS);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#fff36b'.toJS;
    ctx.font = '900 22px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, 0, -47);
    ctx.restore();
  }

  // =========================================================================
  // 8. JUNGLE TEMPLE (Djungeltempel & Ruiner)
  // =========================================================================
  static void _generateJungle(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights =
        _buildHeightfield(w, h * 0.65, 118.0, rng, step: step, edgeDrop: 100.0);

    // Rich deep emerald rainforest terrain (distinctly darker/lusher than Villa!).
    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#7a6345',
      fillMid: '#54422c',
      fillBottom: '#332618',
      outlineColor: '#1a120a',
      turfTop: '#3ecf5e',
      turfBottom: '#1a7538',
      turfOutline: '#0d3b1c',
      pebbleColor: 'rgba(38, 28, 14, 0.40)',
      turfThickness: 32.0,
    );

    // 2 Massive Stepped Mayan/Aztec Stone Pyramids with hollow inner treasure rooms!
    final List<double> pyrXs = [
      w * (0.26 + rng.nextDouble() * 0.04),
      w * (0.72 + rng.nextDouble() * 0.04),
    ];
    for (final double px in pyrXs) {
      final double baseY = _sampleHeight(heights, px, step) + 18.0;
      _drawJunglePyramid(ctx, px, baseY, 260.0, 190.0);
    }

    // GIMMICK 1: Giant Carved Stone Tiki Statue with glowing emerald eyes in center valley!
    final double tikiX = w * 0.50;
    _drawTikiStatue(ctx, tikiX, _sampleHeight(heights, tikiX, step) + 8.0);

    // GIMMICK 2: Lush Bamboo Clusters, Giant Palms & Hanging Rope Vine Bridges!
    for (final double frac in const [0.10, 0.41, 0.59, 0.89]) {
      final double px = w * frac;
      final double py = _sampleHeight(heights, px, step);
      _drawPalmTree(ctx, px, py, 1.05, (frac < 0.5 ? 28 : -28));
      _drawBambooCluster(ctx, px + 36, py + 4);
    }

    // 3 Overgrown floating jungle cliff ledges linked by vine bridges!
    final List<List<double>> ledges = [
      [w * 0.18, h * 0.25, 240.0, 88.0],
      [w * 0.50, h * 0.21, 250.0, 90.0],
      [w * 0.82, h * 0.26, 240.0, 88.0],
    ];
    for (int i = 0; i < ledges.length; i++) {
      final List<double> l = ledges[i];
      _drawFloatingCartoonIsland(
        ctx,
        cx: l[0],
        cy: l[1],
        width: l[2],
        height: l[3],
        rockTop: '#806d52',
        rockBottom: '#473826',
        rockOutline: '#1f160c',
        turfTop: '#3ecf5e',
        turfBottom: '#1a7538',
        turfOutline: '#0d3b1c',
      );
      _drawPalmTree(ctx, l[0], l[1] - 12, 0.78, i == 0 ? 20 : -20);
    }
    _drawRopeBridge(
      ctx,
      ledges[0][0] + 108,
      ledges[0][1] - 2,
      ledges[1][0] - 114,
      ledges[1][1] - 2,
      sag: 34.0,
      woodColor: '#8c6239',
    );
    _drawRopeBridge(
      ctx,
      ledges[1][0] + 114,
      ledges[1][1] - 2,
      ledges[2][0] - 108,
      ledges[2][1] - 2,
      sag: 34.0,
      woodColor: '#8c6239',
    );

    // THEMATIC INDESTRUCTIBLE BEDROCK (8 CLEAR SECTIONS):
    // 1-2. Gold-inlaid ancient temple doorway lintels & bases inside both pyramids!
    for (final double px in pyrXs) {
      final double baseY = _sampleHeight(heights, px, step);
      _drawBedrockBlock(
        bCtx,
        x: px - 68,
        y: baseY - 46,
        w: 136,
        h: 34,
        style: _BedrockStyle.mayanGold,
      );
      _drawBedrockPillar(
        bCtx,
        cx: px - 68,
        topY: baseY - 16,
        height: 98,
        width: 42,
        style: _BedrockStyle.mayanGold,
      );
      _drawBedrockPillar(
        bCtx,
        cx: px + 68,
        topY: baseY - 16,
        height: 98,
        width: 42,
        style: _BedrockStyle.mayanGold,
      );
    }
    // 7. Ancient gold-trimmed temple vault arch shielding the underground chamber!
    _drawBedrockArchVault(
      bCtx,
      cx: w * 0.50,
      y: h * 0.75,
      span: 190,
      thickness: 26,
      style: _BedrockStyle.mayanGold,
    );
    // 8. Sacred golden temple altar bridge in the center sky!
    _drawBedrockGirder(
      bCtx,
      x: w * 0.50 - 95,
      y: h * 0.39,
      w: 190,
      h: 28,
      style: _BedrockStyle.mayanGold,
    );
  }

  static void _drawJunglePyramid(CanvasRenderingContext2D ctx, double cx,
      double baseY, double baseW, double totalH) {
    const int tiers = 4;
    final double tierH = totalH / tiers;
    ctx.save();
    for (int t = 0; t < tiers; t++) {
      final double tw = baseW * (1.0 - t * 0.19);
      final double ty = baseY - (t + 1) * tierH;
      final CanvasGradient st =
          ctx.createLinearGradient(cx - tw * 0.5, ty, cx + tw * 0.5, ty);
      st.addColorStop(0.0, '#c9ba92');
      st.addColorStop(1.0, '#8c7d58');
      ctx.fillStyle = st;
      ctx.strokeStyle = '#332b1c'.toJS;
      ctx.lineWidth = 3.8;
      ctx.fillRect(cx - tw * 0.5, ty, tw, tierH + 2);
      ctx.strokeRect(cx - tw * 0.5, ty, tw, tierH + 2);

      // Mossy vine overhang on tier lip!
      ctx.fillStyle = '#38ba48'.toJS;
      ctx.fillRect(cx - tw * 0.5 + 4, ty, tw - 8, 8);
    }
    // Gleaming golden Mayan sun idol at summit!
    ctx.fillStyle = '#ffd638'.toJS;
    ctx.strokeStyle = '#4a3208'.toJS;
    ctx.lineWidth = 3.2;
    ctx.fillRect(cx - 22, baseY - totalH - 26, 44, 26);
    ctx.strokeRect(cx - 22, baseY - totalH - 26, 44, 26);

    // Hollow inner temple chamber at ground level!
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(cx, baseY - 22, 30, pi, 2 * pi);
    ctx.lineTo(cx + 30, baseY + 4);
    ctx.lineTo(cx - 30, baseY + 4);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  static void _drawTikiStatue(CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#9e9278'.toJS;
    ctx.strokeStyle = '#2e291e'.toJS;
    ctx.lineWidth = 4.0;
    ctx.beginPath();
    ctx.roundRect(-36, -124, 72, 128, 10.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Glowing emerald eyes!
    ctx.fillStyle = '#45ff82'.toJS;
    ctx.fillRect(-22, -96, 16, 12);
    ctx.strokeRect(-22, -96, 16, 12);
    ctx.fillRect(6, -96, 16, 12);
    ctx.strokeRect(6, -96, 16, 12);

    // Carved wide stone grin!
    ctx.fillStyle = '#2e291e'.toJS;
    ctx.fillRect(-24, -52, 48, 18);
    ctx.fillStyle = '#e8dfc8'.toJS;
    for (int t = -18; t <= 12; t += 12) {
      ctx.fillRect(t.toDouble(), -50, 8, 14);
    }
    ctx.restore();
  }

  static void _drawBambooCluster(
      CanvasRenderingContext2D ctx, double x, double y) {
    ctx.save();
    ctx.translate(x, y);
    for (final List<double> b in const [
      [-10.0, 84.0, -0.08],
      [0.0, 98.0, 0.04],
      [11.0, 76.0, 0.10],
    ]) {
      ctx.save();
      ctx.translate(b[0], 0);
      ctx.rotate(b[2]);
      ctx.fillStyle = '#6de04e'.toJS;
      ctx.strokeStyle = '#184f18'.toJS;
      ctx.lineWidth = 2.4;
      ctx.fillRect(-4, -b[1], 8, b[1] + 4);
      ctx.strokeRect(-4, -b[1], 8, b[1] + 4);
      ctx.restore();
    }
    ctx.restore();
  }

  // =========================================================================
  // MEGA MAN 3x3 BOSS-PORTRAIT MINI DIORAMAS (180 x 132)
  // =========================================================================

  static void _drawPreviewVilla(CanvasRenderingContext2D ctx, double w, double h) {
    // Sunny Swedish garden hill.
    ctx.fillStyle = '#5ee048'.toJS;
    ctx.strokeStyle = '#1c5c19'.toJS;
    ctx.lineWidth = 2.6;
    ctx.beginPath();
    ctx.arc(w * 0.5, h * 1.15, w * 0.62, pi, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Cute miniature crooked yellow villa with red-and-white roof!
    ctx.save();
    ctx.translate(w * 0.44, h * 0.84);
    ctx.scale(0.32, 0.32);
    _drawCrookedVilla(ctx, 0, 0);
    _drawSpottedHorse(ctx, 114, -4, 1.15);
    ctx.restore();
  }

  static void _drawPreviewSpooky(CanvasRenderingContext2D ctx, double w, double h) {
    ctx.fillStyle = '#423363'.toJS;
    ctx.beginPath();
    ctx.arc(w * 0.5, h * 1.05, w * 0.55, pi, 2 * pi);
    ctx.fill();
    ctx.fillStyle = '#5a4c7a'.toJS;
    ctx.strokeStyle = '#151024'.toJS;
    ctx.lineWidth = 2.4;
    ctx.fillRect(w * 0.33, h * 0.42, w * 0.34, h * 0.45);
    ctx.strokeRect(w * 0.33, h * 0.42, w * 0.34, h * 0.45);
    ctx.fillStyle = '#2a1847'.toJS;
    ctx.beginPath();
    ctx.moveTo(w * 0.28, h * 0.42);
    ctx.lineTo(w * 0.53, h * 0.16);
    ctx.lineTo(w * 0.72, h * 0.42);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#ffd24d'.toJS;
    ctx.fillRect(w * 0.45, h * 0.52, w * 0.10, h * 0.14);
    _drawPumpkin(ctx, w * 0.24, h * 0.82, 0.65);
  }

  static void _drawPreviewVolcano(CanvasRenderingContext2D ctx, double w, double h) {
    ctx.fillStyle = '#593338'.toJS;
    ctx.strokeStyle = '#1a0b0e'.toJS;
    ctx.lineWidth = 2.6;
    ctx.beginPath();
    ctx.moveTo(w * 0.08, h);
    ctx.lineTo(w * 0.38, h * 0.36);
    ctx.lineTo(w * 0.62, h * 0.36);
    ctx.lineTo(w * 0.92, h);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#ff7b24'.toJS;
    ctx.beginPath();
    ctx.arc(w * 0.5, h * 0.36, 18, pi, 2 * pi);
    ctx.fill();
    ctx.fillStyle = '#fff066'.toJS;
    ctx.beginPath();
    ctx.arc(w * 0.5, h * 0.34, 10, 0, 2 * pi);
    ctx.fill();
  }

  static void _drawPreviewGlacier(CanvasRenderingContext2D ctx, double w, double h) {
    _drawFloatingCartoonIsland(ctx,
        cx: w * 0.5,
        cy: h * 0.64,
        width: w * 0.76,
        height: h * 0.30,
        rockTop: '#74d9ff',
        rockBottom: '#2979c7',
        rockOutline: '#0e3466',
        turfTop: '#ffffff',
        turfBottom: '#c9f2ff',
        turfOutline: '#2a75b8');
    _drawIgloo(ctx, w * 0.46, h * 0.60, 0.55);
    _drawSnowman(ctx, w * 0.70, h * 0.60, 0.55);
  }

  static void _drawPreviewCandy(CanvasRenderingContext2D ctx, double w, double h) {
    _drawFrostedDonut(ctx, w * 0.5, h * 0.54, 38, 13, '#ff6eb8');
    _drawLollipop(ctx, w * 0.20, h * 0.88, '#4be6ff', 0.55);
    _drawLollipop(ctx, w * 0.80, h * 0.88, '#ffe054', 0.55);
  }

  static void _drawPreviewLunar(CanvasRenderingContext2D ctx, double w, double h) {
    _drawMoonAsteroid(ctx, w * 0.5, h * 0.78, 66, 26);
    _drawMoonAsteroid(ctx, w * 0.20, h * 0.34, 22, 13);
    ctx.save();
    ctx.translate(w * 0.52, h * 0.64);
    ctx.scale(0.36, 0.36);
    _drawLunarRocket(ctx, 0, 0);
    ctx.restore();
  }

  static void _drawPreviewCity(CanvasRenderingContext2D ctx, double w, double h) {
    const List<List<dynamic>> bldgs = [
      [0.10, 0.44, 0.24, '#f26a5a'],
      [0.36, 0.26, 0.28, '#5ab2f2'],
      [0.66, 0.38, 0.24, '#f5c542'],
    ];
    for (final List<dynamic> b in bldgs) {
      final double bx = (b[0] as double) * w;
      final double by = (b[1] as double) * h;
      final double bw = (b[2] as double) * w;
      ctx.fillStyle = (b[3] as String).toJS;
      ctx.strokeStyle = '#1b202e'.toJS;
      ctx.lineWidth = 2.4;
      ctx.fillRect(bx, by, bw, h - by);
      ctx.strokeRect(bx, by, bw, h - by);
      ctx.fillStyle = '#fff29c'.toJS;
      for (double wy = by + 8; wy < h - 14; wy += 14) {
        ctx.fillRect(bx + 6, wy, 8, 8);
        ctx.fillRect(bx + bw - 14, wy, 8, 8);
      }
    }
  }

  static void _drawPreviewJungle(CanvasRenderingContext2D ctx, double w, double h) {
    ctx.save();
    ctx.translate(w * 0.52, h * 0.88);
    ctx.scale(0.42, 0.42);
    _drawJunglePyramid(ctx, 0, 0, 220, 155);
    ctx.restore();
    _drawPalmTree(ctx, w * 0.16, h * 0.84, 0.44, 12);
  }
}
