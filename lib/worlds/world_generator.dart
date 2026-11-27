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
  toyBrick,
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
      case WorldThemeId.toyland:
        _generateToyland(tCtx, bCtx, DEFAULT_WIDTH, DEFAULT_HEIGHT, rng);
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
      case WorldThemeId.toyland:
        _drawPreviewToyland(ctx, w, h);
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
    double detailScale = 1.0,
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

    // At LOW quality tier, render only the cached offscreen static skybox (`1 drawImage`,
    // zero per-frame animated vector loops) to immediately recover frame rate!
    if (!compact && detailScale <= 0.35) {
      ctx.restore();
      return;
    }

    final double w = width.toDouble();
    final double h = height.toDouble();
    final double skyLod = compact ? 1.0 : detailScale.clamp(0.45, 1.0);

    // Lightweight live animated overlay (clouds, twinkles, embers, snow, aurora).
    switch (theme.id) {
      case WorldThemeId.villa:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.92, time * 0.85, '#ffffff',
            0.84, seed,
            detailScale: skyLod);
        break;
      case WorldThemeId.spooky:
        _drawSkyStars(
            ctx, w, h, ((compact ? 14 : 40) * skyLod).round(), time, seed);
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.88, time * 0.65, '#5c3c8c',
            0.46, seed,
            detailScale: skyLod);
        _drawDriftingSpookyGhosts(ctx, w, h, time, seed, compact,
            detailScale: skyLod);
        break;
      case WorldThemeId.volcano:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.90, time * 0.80, '#59282c',
            0.48, seed,
            detailScale: skyLod);
        if (!compact) {
          _drawRisingEmbers(ctx, w, h, time, seed, detailScale: skyLod);
        }
        break;
      case WorldThemeId.glacier:
        _drawAuroraRibbon(ctx, w, h, compact, time, detailScale: skyLod);
        _drawSkyClouds(ctx, w, h, compact ? 0.32 : 0.82, time * 0.50, '#ffffff',
            0.66, seed,
            detailScale: skyLod);
        if (!compact) {
          _drawDriftingSnow(ctx, w, h, time, seed, detailScale: skyLod);
        }
        break;
      case WorldThemeId.candy:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.86, time * 0.65, '#fff0fa',
            0.86, seed,
            detailScale: skyLod);
        break;
      case WorldThemeId.lunar:
        _drawSkyStars(
            ctx, w, h, ((compact ? 22 : 70) * skyLod).round(), time, seed);
        break;
      case WorldThemeId.toyland:
        _drawSkyClouds(ctx, w, h, compact ? 0.34 : 0.86, time * 0.70, '#ffffff',
            0.86, seed,
            detailScale: skyLod);
        if (!compact) {
          _drawFloatingToyBalloons(ctx, w, h, time, seed, detailScale: skyLod);
        }
        break;
      case WorldThemeId.jungle:
        _drawSkyClouds(ctx, w, h, compact ? 0.32 : 0.82, time * 0.52, '#fff8de',
            0.64, seed,
            detailScale: skyLod);
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
      case WorldThemeId.toyland:
        final double sunX = w * (0.14 + rng.nextDouble() * 0.10);
        final double sunY = h * (0.16 + rng.nextDouble() * 0.05);
        _drawSkySun(ctx, sunX, sunY, compact ? 15 : 42, '#ffe85c');
        // Festive colorful playroom bunting garlands across the upper sky!
        _drawToySkyBunting(ctx, w, h, compact, rng);
        // Distant pastel toy-block castle silhouettes & Ferris wheel on the horizon!
        _drawToyHorizonCastle(ctx, w, h, compact, rng);
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
      double scale, double time, String color, double alpha, int seed,
      {double detailScale = 1.0}) {
    final double offset = (seed.abs() % 100) / 100.0;
    final int cloudCount = max(2, (6 * detailScale).round());
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = color.toJS;
    for (int i = 0; i < cloudCount; i++) {
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
      bool compact, double time,
      {double detailScale = 1.0}) {
    ctx.save();
    final int bands = detailScale < 0.8 ? 1 : 2;
    for (int band = 0; band < bands; band++) {
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
      CanvasRenderingContext2D ctx, double w, double h, double time, int seed,
      {double detailScale = 1.0}) {
    final int s = seed.abs() % 500;
    final int count = max(6, (24 * detailScale).round());
    for (int i = 0; i < count; i++) {
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
      CanvasRenderingContext2D ctx, double w, double h, double time, int seed,
      {double detailScale = 1.0}) {
    final int s = seed.abs() % 500;
    final int count = max(6, (26 * detailScale).round());
    ctx.fillStyle = 'rgba(255, 255, 255, 0.68)'.toJS;
    for (int i = 0; i < count; i++) {
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
      case _BedrockStyle.toyBrick:
        return {
          'top': '#ff4d4d',
          'bottom': '#c41e28',
          'trim': '#ffe047',
          'rivet': '#48b8ff',
          'accent': '#ffe047',
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

    // GIMMICK 2: Giant Half-Buried Ossuary Skull & Grinning Skeletons across the graveyard!
    final double giantSkullX = w * 0.72;
    _drawGiantSpookySkull(
        ctx, giantSkullX, _sampleHeight(heights, giantSkullX, step) + 10.0, 1.0);

    for (final List<double> sk in [
      [w * 0.11, 1.0, 1.0],
      [w * 0.34, 0.95, -1.0],
      [w * 0.56, 0.95, 1.0],
      [w * 0.89, 1.0, -1.0],
    ]) {
      final double sx = sk[0];
      final double sy = _sampleHeight(heights, sx, step) + 2.0;
      _drawCartoonSkeleton(ctx, sx, sy, sk[1], facingLeft: sk[2] < 0);
    }
    // Bony lookout skeletons perched atop gothic castle battlements!
    _drawCartoonSkeleton(
        ctx, towerXs[0], towerTops[0] - 2.0, 0.82, facingLeft: false);
    _drawCartoonSkeleton(
        ctx, towerXs[2], towerTops[2] - 2.0, 0.82, facingLeft: true);

    // Gnarled dead trees, glowing jack-o'-lanterns & tilted gravestones!
    for (int i = 0; i < 7; i++) {
      final double px = w * (0.07 + i * 0.145 + rng.nextDouble() * 0.02);
      if ((px - giantPumpX).abs() < 80 || (px - giantSkullX).abs() < 75) {
        continue;
      }
      final double py = _sampleHeight(heights, px, step);
      if (i % 3 == 0) {
        _drawDeadTree(ctx, px, py + 4, 0.95);
      } else if (i % 3 == 1) {
        _drawPumpkin(ctx, px, py - 6, 1.05);
      } else {
        _drawGravestone(ctx, px, py - 2, (rng.nextDouble() - 0.5) * 0.28);
      }
    }

    // 3 Floating haunted stone ledges in the moonlight + solid ectoplasm ghosts!
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
      _drawPumpkin(ctx, lx + (i.isEven ? -44 : 44), ly - 16, 0.92);
      _drawCartoonSkeleton(
          ctx, lx + (i.isEven ? 34 : -34), ly - 12, 0.78, facingLeft: i.isOdd);
    }

    // Hovering solid cartoon bedsheet ghosts haunting the castle alleys & mid-air!
    _drawSolidSpookyGhost(ctx, w * 0.19, h * 0.40, 1.05, facingLeft: false);
    _drawSolidSpookyGhost(ctx, w * 0.50, h * 0.36, 1.15, facingLeft: true);
    _drawSolidSpookyGhost(ctx, w * 0.80, h * 0.41, 1.0, facingLeft: true);

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

  /// Animated translucent ghosts drifting across the moonlit Spooky skybox!
  static void _drawDriftingSpookyGhosts(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    double time,
    int seed,
    bool compact, {
    double detailScale = 1.0,
  }) {
    final int count = compact ? 2 : max(2, (5 * detailScale).round());
    final int s = seed.abs() % 500;
    final double scale = compact ? 0.45 : 1.0;
    ctx.save();
    for (int i = 0; i < count; i++) {
      final double dir = i.isEven ? 1.0 : -1.0;
      final double speed = 0.014 + (i % 3) * 0.005;
      final double rawU =
          ((i * 0.23 + (s % 97) / 97.0) + time * speed * dir) % 1.24;
      final double u = (rawU < 0 ? rawU + 1.24 : rawU) - 0.12;
      final double gx = u * w;
      final double gy = h * (0.18 + (i % 3) * 0.12) +
          sin(time * 2.1 + i * 1.7) * (compact ? 4.0 : 12.0);

      ctx.save();
      ctx.translate(gx, gy);
      ctx.scale(dir < 0 ? -scale : scale, scale);
      ctx.globalAlpha = compact ? 0.55 : 0.46;

      // Soft ectoplasm aura.
      ctx.fillStyle = 'rgba(164, 245, 255, 0.30)'.toJS;
      ctx.beginPath();
      ctx.arc(0, -2, 24, 0, 2 * pi);
      ctx.fill();

      // Wavy ghost sheet silhouette.
      ctx.fillStyle = '#e8fbff'.toJS;
      ctx.beginPath();
      ctx.arc(0, -8, 13, pi, 2 * pi);
      ctx.lineTo(13, 10);
      ctx.quadraticCurveTo(8, 5, 4, 11);
      ctx.quadraticCurveTo(0, 5, -4, 11);
      ctx.quadraticCurveTo(-8, 5, -13, 10);
      ctx.closePath();
      ctx.fill();

      // Hollow spooky eyes & 'O' mouth.
      ctx.fillStyle = '#241645'.toJS;
      ctx.beginPath();
      ctx.ellipse(-4.2, -9, 2.2, 3.2, 0, 0, 2 * pi);
      ctx.ellipse(4.2, -9, 2.2, 3.2, 0, 0, 2 * pi);
      ctx.ellipse(0.5, -2.5, 2.5, 3.4, 0, 0, 2 * pi);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  /// Draws a solid destructible cartoon ghost hovering in the Spooky arena!
  static void _drawSolidSpookyGhost(
    CanvasRenderingContext2D ctx,
    double cx,
    double cy,
    double s, {
    bool facingLeft = false,
  }) {
    ctx.save();
    ctx.translate(cx, cy);
    ctx.scale(facingLeft ? -s : s, s);

    final CanvasGradient body = ctx.createLinearGradient(0, -40, 0, 34);
    body.addColorStop(0.0, '#f4ffff');
    body.addColorStop(0.65, '#c7f5ff');
    body.addColorStop(1.0, '#8ad9f5');
    ctx.fillStyle = body;
    ctx.strokeStyle = '#1d1438'.toJS;
    ctx.lineWidth = 3.8;

    // Classic domed ghost body with stubby outstretched arms & wavy tail!
    ctx.beginPath();
    ctx.arc(0, -12, 28, pi, 2 * pi);
    // Right stubby arm.
    ctx.quadraticCurveTo(42, -8, 40, 2);
    ctx.quadraticCurveTo(36, 10, 27, 6);
    ctx.lineTo(28, 28);
    // Scalloped sheet hem.
    ctx.quadraticCurveTo(18, 18, 10, 30);
    ctx.quadraticCurveTo(0, 18, -10, 30);
    ctx.quadraticCurveTo(-18, 18, -28, 28);
    ctx.lineTo(-27, 6);
    // Left stubby arm.
    ctx.quadraticCurveTo(-38, 10, -40, 0);
    ctx.quadraticCurveTo(-40, -10, -28, -12);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Spooky glowing eyes & wailing mouth!
    ctx.fillStyle = '#1d1438'.toJS;
    ctx.beginPath();
    ctx.ellipse(-8, -14, 5.2, 7.2, -0.1, 0, 2 * pi);
    ctx.ellipse(9, -14, 5.2, 7.2, 0.1, 0, 2 * pi);
    ctx.fill();
    ctx.fillStyle = '#7affd4'.toJS;
    ctx.beginPath();
    ctx.arc(-7, -15, 2.0, 0, 2 * pi);
    ctx.arc(10, -15, 2.0, 0, 2 * pi);
    ctx.fill();

    ctx.fillStyle = '#1d1438'.toJS;
    ctx.beginPath();
    ctx.ellipse(1, 2, 7.0, 9.0, 0, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  /// Draws a giant half-buried grinning cartoon bone skull & crossed femurs!
  static void _drawGiantSpookySkull(
      CanvasRenderingContext2D ctx, double cx, double baseY, double s) {
    ctx.save();
    ctx.translate(cx, baseY);
    ctx.scale(s, s);
    ctx.strokeStyle = '#1c132b'.toJS;
    ctx.lineWidth = 4.0;

    // Crossed femur bones jutting out behind the giant cranium!
    ctx.fillStyle = '#e8dec8'.toJS;
    for (final double rot in const [-0.46, 0.46]) {
      ctx.save();
      ctx.translate(0, -34);
      ctx.rotate(rot);
      ctx.fillRect(-68, -7, 136, 14);
      ctx.strokeRect(-68, -7, 136, 14);
      for (final double ex in const [-68.0, 68.0]) {
        for (final double ey in const [-6.0, 6.0]) {
          ctx.beginPath();
          ctx.arc(ex, ey, 8.0, 0, 2 * pi);
          ctx.fill();
          ctx.stroke();
        }
      }
      ctx.restore();
    }

    // Giant ivory cranium + blocky grinning jaw!
    final CanvasGradient bone = ctx.createLinearGradient(0, -96, 0, 4);
    bone.addColorStop(0.0, '#fff9eb');
    bone.addColorStop(1.0, '#cfc2a6');
    ctx.fillStyle = bone;
    ctx.beginPath();
    ctx.arc(0, -50, 46, pi * 0.88, pi * 2.12);
    ctx.lineTo(32, -4);
    ctx.lineTo(-32, -4);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Dark eye sockets with eerie purple pinpoints + triangular nose!
    ctx.fillStyle = '#1c132b'.toJS;
    ctx.beginPath();
    ctx.ellipse(-16, -48, 11, 13, -0.12, 0, 2 * pi);
    ctx.ellipse(16, -48, 11, 13, 0.12, 0, 2 * pi);
    ctx.fill();
    ctx.fillStyle = '#d47aff'.toJS;
    ctx.beginPath();
    ctx.arc(-16, -48, 3.5, 0, 2 * pi);
    ctx.arc(16, -48, 3.5, 0, 2 * pi);
    ctx.fill();

    ctx.fillStyle = '#1c132b'.toJS;
    ctx.beginPath();
    ctx.moveTo(0, -38);
    ctx.lineTo(7, -26);
    ctx.lineTo(-7, -26);
    ctx.closePath();
    ctx.fill();

    // Grinning teeth row!
    ctx.fillStyle = '#fffdf5'.toJS;
    for (double tx = -22; tx <= 14; tx += 9) {
      ctx.fillRect(tx, -20, 8, 13);
      ctx.strokeRect(tx, -20, 8, 13);
    }
    ctx.restore();
  }

  /// Draws a full standing cartoon skeleton (skull, ribcage, pelvis, waving arms)!
  static void _drawCartoonSkeleton(
    CanvasRenderingContext2D ctx,
    double x,
    double y,
    double s, {
    bool facingLeft = false,
  }) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(facingLeft ? -s : s, s);
    ctx.strokeStyle = '#1a1129'.toJS;
    ctx.fillStyle = '#f7f0de'.toJS;
    ctx.lineWidth = 2.8;
    ctx.lineCap = 'round';

    // Leg bones.
    for (final double lx in const [-7.0, 7.0]) {
      ctx.fillRect(lx - 2.5, -24, 5, 24);
      ctx.strokeRect(lx - 2.5, -24, 5, 24);
    }
    // Pelvis & spine.
    ctx.beginPath();
    ctx.roundRect(-11, -30, 22, 8, 4.0.toJS);
    ctx.fill();
    ctx.stroke();
    ctx.fillRect(-2.5, -58, 5, 28);
    ctx.strokeRect(-2.5, -58, 5, 28);

    // 3 curved ribs!
    for (int r = 0; r < 3; r++) {
      final double ry = -54.0 + r * 7.5;
      ctx.beginPath();
      ctx.roundRect(-13, ry, 26, 4.5, 2.2.toJS);
      ctx.fill();
      ctx.stroke();
    }

    // Waving bony arms!
    ctx.strokeStyle = '#1a1129'.toJS;
    ctx.lineWidth = 6.5;
    ctx.beginPath();
    ctx.moveTo(-12, -53);
    ctx.lineTo(-23, -40);
    ctx.moveTo(12, -53);
    ctx.lineTo(24, -68);
    ctx.stroke();
    ctx.strokeStyle = '#f7f0de'.toJS;
    ctx.lineWidth = 3.2;
    ctx.stroke();

    // Grinning skull head!
    ctx.strokeStyle = '#1a1129'.toJS;
    ctx.lineWidth = 2.8;
    ctx.fillStyle = '#fff9eb'.toJS;
    ctx.beginPath();
    ctx.arc(0, -72, 13, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.fillRect(-7, -63, 14, 7);
    ctx.strokeRect(-7, -63, 14, 7);

    ctx.fillStyle = '#1a1129'.toJS;
    ctx.beginPath();
    ctx.arc(-4.5, -73, 3.2, 0, 2 * pi);
    ctx.arc(4.5, -73, 3.2, 0, 2 * pi);
    ctx.fill();
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

    // GIMMICK 1B: Giant Dinosaur Skeletons (T-Rex, Triceratops Skull, & Embedded Ammonites/Bones)!
    ctx.save();
    ctx.globalCompositeOperation = 'source-atop';
    for (int f = 0; f < 8; f++) {
      final double fx = w * (0.10 + f * 0.112);
      final double fy = _sampleHeight(heights, fx, step) + 64.0 + (f % 3) * 32.0;
      _drawEmbeddedDinoFossil(ctx, fx, min(h - 48.0, fy), isSpiral: f.isEven);
    }
    ctx.restore();

    final double trexX = w * 0.23;
    _drawTRexSkeleton(
        ctx, trexX, _sampleHeight(heights, trexX, step) + 8.0, 1.0,
        facingLeft: false);

    final double trikeX = w * 0.77;
    _drawTriceratopsSkullFossil(
        ctx, trikeX, _sampleHeight(heights, trikeX, step) + 10.0, 1.05,
        facingLeft: true);

    // GIMMICK 2: Glowing Magma Crystal Clusters & Steaming Fumarole Chimneys!
    for (int i = 0; i < 6; i++) {
      final double cx = w * (0.11 + i * 0.155);
      if ((cx - trexX).abs() < 88 || (cx - trikeX).abs() < 82) continue;
      final double cy = _sampleHeight(heights, cx, step) + 4.0;
      if (i == 1 || i == 4) {
        _drawFumaroleChimney(ctx, cx, cy);
      } else {
        _drawCrystalCluster(ctx, cx, cy, '#ff8e2b', '#ffe866', '#4a140c');
      }
    }

    // 4 Floating obsidian-and-lava sky islets (+ skeletal Pterodactyl roost)!
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
      if (i == 1) {
        _drawPterodactylSkeleton(ctx, ix, iy - 16, 0.92);
      } else if (i.isEven) {
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

  /// Draws a massive towering T-Rex fossil skeleton standing on a volcanic ridge!
  static void _drawTRexSkeleton(
    CanvasRenderingContext2D ctx,
    double x,
    double groundY,
    double s, {
    bool facingLeft = false,
  }) {
    ctx.save();
    ctx.translate(x, groundY);
    ctx.scale(facingLeft ? -s : s, s);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    void boneStroke(void Function() pathFn, double width) {
      ctx.strokeStyle = '#291a16'.toJS;
      ctx.lineWidth = width + 5.0;
      ctx.beginPath();
      pathFn();
      ctx.stroke();
      ctx.strokeStyle = '#f5ebd6'.toJS;
      ctx.lineWidth = width;
      ctx.stroke();
    }

    // 1. Sweeping segmented dinosaur tail ramp (-120..0) + arched spine & neck (0..42)!
    boneStroke(() {
      ctx.moveTo(-122, -16);
      ctx.quadraticCurveTo(-64, -34, -18, -74);
      ctx.quadraticCurveTo(14, -96, 36, -128);
    }, 9.0);

    // Vertebrae dorsal spikes along tail & back.
    for (int v = 0; v < 8; v++) {
      final double t = v / 7.0;
      final double vx = -104.0 + t * 130.0;
      final double vy = -22.0 - t * 88.0;
      boneStroke(() {
        ctx.moveTo(vx, vy);
        ctx.lineTo(vx - 4, vy - 11);
      }, 4.5);
    }

    // 2. Powerful hind leg bones & 3-toed talons!
    for (final double dx in const [-16.0, 6.0]) {
      boneStroke(() {
        ctx.moveTo(dx, -72);
        ctx.lineTo(dx - 12, -38);
        ctx.lineTo(dx + 6, -8);
        ctx.lineTo(dx + 20, -2);
      }, 8.0);
    }

    // 3. Curved thoracic dinosaur ribs + tiny 2-clawed T-Rex arms!
    for (int r = 0; r < 5; r++) {
      final double rx = -10.0 + r * 9.5;
      final double ry = -78.0 - r * 7.5;
      boneStroke(() {
        ctx.moveTo(rx, ry);
        ctx.quadraticCurveTo(rx + 8, ry + 20, rx - 4, ry + 34);
      }, 5.0);
    }
    boneStroke(() {
      ctx.moveTo(30, -106);
      ctx.lineTo(46, -94);
      ctx.lineTo(52, -98);
    }, 4.2);

    // 4. Fierce fossilized T-Rex skull with fenestrae & jagged teeth!
    ctx.fillStyle = '#f7efe0'.toJS;
    ctx.strokeStyle = '#291a16'.toJS;
    ctx.lineWidth = 3.8;
    // Upper cranium & snout.
    ctx.beginPath();
    ctx.moveTo(26, -152);
    ctx.lineTo(86, -146);
    ctx.lineTo(90, -126);
    ctx.lineTo(32, -124);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Open lower mandible jaw.
    ctx.beginPath();
    ctx.moveTo(30, -122);
    ctx.lineTo(82, -108);
    ctx.lineTo(78, -100);
    ctx.lineTo(26, -112);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Sharp ivory teeth!
    ctx.fillStyle = '#ffffff'.toJS;
    for (double tx = 48; tx <= 82; tx += 9) {
      ctx.beginPath();
      ctx.moveTo(tx, -125);
      ctx.lineTo(tx + 3.5, -116);
      ctx.lineTo(tx + 7, -125);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }

    // Dark skull eye & temporal fenestra sockets.
    ctx.fillStyle = '#291a16'.toJS;
    ctx.beginPath();
    ctx.ellipse(46, -138, 7.5, 6.5, -0.15, 0, 2 * pi);
    ctx.ellipse(68, -136, 6.5, 4.8, 0, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  /// Draws a giant half-buried Triceratops horned fossil skull & crest!
  static void _drawTriceratopsSkullFossil(
    CanvasRenderingContext2D ctx,
    double x,
    double groundY,
    double s, {
    bool facingLeft = false,
  }) {
    ctx.save();
    ctx.translate(x, groundY);
    ctx.scale(facingLeft ? -s : s, s);
    ctx.fillStyle = '#f2e8d0'.toJS;
    ctx.strokeStyle = '#291a16'.toJS;
    ctx.lineWidth = 3.8;
    ctx.lineJoin = 'round';

    // Trailing spine vertebrae emerging behind the frill.
    for (int i = 0; i < 4; i++) {
      ctx.beginPath();
      ctx.roundRect(-92.0 + i * 16.0, -28.0 - i * 4.0, 14, 20, 4.0.toJS);
      ctx.fill();
      ctx.stroke();
    }

    // Broad scalloped Triceratops bony neck frill!
    ctx.beginPath();
    ctx.moveTo(-18, -18);
    ctx.quadraticCurveTo(-56, -68, -22, -96);
    ctx.quadraticCurveTo(8, -100, 14, -52);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Beaked horned skull!
    ctx.beginPath();
    ctx.moveTo(-12, -58);
    ctx.lineTo(58, -32);
    ctx.lineTo(66, -12);
    ctx.lineTo(-8, -8);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Two long sweeping brow horns + nose horn!
    ctx.fillStyle = '#fff9eb'.toJS;
    ctx.beginPath();
    ctx.moveTo(8, -62);
    ctx.lineTo(68, -96);
    ctx.lineTo(20, -50);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(42, -38);
    ctx.lineTo(64, -58);
    ctx.lineTo(54, -28);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Hollow eye socket.
    ctx.fillStyle = '#291a16'.toJS;
    ctx.beginPath();
    ctx.arc(12, -40, 8.0, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  /// Draws a skeletal winged Pterodactyl fossil perched atop an obsidian sky islet!
  static void _drawPterodactylSkeleton(
      CanvasRenderingContext2D ctx, double cx, double y, double s) {
    ctx.save();
    ctx.translate(cx, y);
    ctx.scale(s, s);
    ctx.strokeStyle = '#291a16'.toJS;
    ctx.fillStyle = '#f5ebd6'.toJS;
    ctx.lineWidth = 3.2;
    ctx.lineCap = 'round';

    // Outstretched bony wing spars!
    for (final double side in const [-1.0, 1.0]) {
      ctx.strokeStyle = '#291a16'.toJS;
      ctx.lineWidth = 7.5;
      ctx.beginPath();
      ctx.moveTo(0, -26);
      ctx.lineTo(side * 38, -54);
      ctx.lineTo(side * 76, -28);
      ctx.stroke();
      ctx.strokeStyle = '#f5ebd6'.toJS;
      ctx.lineWidth = 3.8;
      ctx.stroke();
    }

    // Ribbed torso & long crested beak skull!
    ctx.strokeStyle = '#291a16'.toJS;
    ctx.lineWidth = 3.0;
    ctx.fillRect(-5, -42, 10, 34);
    ctx.strokeRect(-5, -42, 10, 34);
    ctx.beginPath();
    ctx.moveTo(-18, -62);
    ctx.lineTo(0, -56);
    ctx.lineTo(38, -48);
    ctx.lineTo(0, -42);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /// Draws an embedded ammonite spiral shell or dino femur fossil inside volcanic rock!
  static void _drawEmbeddedDinoFossil(
      CanvasRenderingContext2D ctx, double x, double y,
      {bool isSpiral = true}) {
    ctx.save();
    ctx.translate(x, y);
    ctx.strokeStyle = 'rgba(245, 232, 204, 0.42)'.toJS;
    ctx.lineWidth = 3.5;
    ctx.lineCap = 'round';
    if (isSpiral) {
      ctx.beginPath();
      for (int i = 0; i <= 26; i++) {
        final double a = i * 0.42;
        final double r = 2.0 + i * 0.85;
        if (i == 0) {
          ctx.moveTo(cos(a) * r, sin(a) * r);
        } else {
          ctx.lineTo(cos(a) * r, sin(a) * r);
        }
      }
      ctx.stroke();
    } else {
      ctx.rotate(-0.28);
      ctx.beginPath();
      ctx.moveTo(-22, 0);
      ctx.lineTo(22, 0);
      ctx.stroke();
      ctx.fillStyle = 'rgba(245, 232, 204, 0.42)'.toJS;
      for (final double ex in const [-24.0, 24.0]) {
        ctx.beginPath();
        ctx.arc(ex, -4, 5, 0, 2 * pi);
        ctx.arc(ex, 4, 5, 0, 2 * pi);
        ctx.fill();
      }
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
    final double gHouseX = w * 0.25;
    _drawGingerbreadHouse(ctx, gHouseX, _sampleHeight(heights, gHouseX, step) + 6);

    final double cupX = w * 0.74;
    _drawGiantCupcake(ctx, cupX, _sampleHeight(heights, cupX, step) + 8);

    // GIMMICK 1B: Rich Candy Variations — Triple-Scoop Ice Cream Cone, Segmented Chocolate Bar
    // Ramp, Pastel French Macaron Stack, Giant Gummy Bears, Licorice Allsorts & Wrapped Bonbons!
    final double coneX = w * 0.11;
    _drawIceCreamConeTower(
        ctx, coneX, _sampleHeight(heights, coneX, step) + 10.0);

    final double chocoX = w * 0.40;
    _drawChocolateBarRamp(
        ctx, chocoX, _sampleHeight(heights, chocoX, step) + 10.0, -0.26);

    final double macaronX = w * 0.61;
    _drawMacaronStack(
        ctx, macaronX, _sampleHeight(heights, macaronX, step) + 8.0);

    final double licoriceX = w * 0.89;
    _drawLicoriceAllsortsStack(
        ctx, licoriceX, _sampleHeight(heights, licoriceX, step) + 8.0);

    // Giant glossy Gummy Bears in 4 fruity flavors!
    _drawGummyBear(ctx, w * 0.18, _sampleHeight(heights, w * 0.18, step) + 4.0,
        '#ff5277', '#b8143a', 1.05, 0.08);
    _drawGummyBear(ctx, w * 0.50, _sampleHeight(heights, w * 0.50, step) + 4.0,
        '#68f27c', '#1c9636', 1.12, -0.06);
    _drawGummyBear(ctx, w * 0.82, _sampleHeight(heights, w * 0.82, step) + 4.0,
        '#ffe047', '#cc8800', 1.05, -0.10);

    // GIMMICK 2: Arched Red-and-White Candy Cane Bridge spanning the center valley!
    _drawCandyCaneBridge(ctx, w * 0.50, h * 0.56, 260.0);

    // GIMMICK 3: GIANT FLOATING FROSTED DONUTS + TWISTED-WRAPPER HARD CANDY PLATFORMS!
    final List<List<double>> donuts = [
      [w * 0.16, h * 0.29, 80.0, 28.0],
      [w * 0.39, h * 0.21, 90.0, 32.0],
      [w * 0.62, h * 0.23, 88.0, 31.0],
      [w * 0.84, h * 0.29, 80.0, 27.0],
    ];
    const List<String> glazes = ['#ff6eb8', '#66ecff', '#ffe054', '#7dff74'];
    for (int i = 0; i < donuts.length; i++) {
      final double dx = donuts[i][0] + (rng.nextDouble() - 0.5) * 26;
      final double dy = donuts[i][1] + (rng.nextDouble() - 0.5) * 20;
      _drawFrostedDonut(ctx, dx, dy, donuts[i][2], donuts[i][3], glazes[i]);
    }

    // Floating twisted-wrapper hard candy bonbons in mid-air!
    _drawWrappedBonbonCandy(
        ctx, w * 0.28, h * 0.35, '#ff62b0', '#fff0fa', 1.05, -0.08);
    _drawWrappedBonbonCandy(
        ctx, w * 0.50, h * 0.16, '#4be6ff', '#fff9d2', 1.10, 0.0);
    _drawWrappedBonbonCandy(
        ctx, w * 0.73, h * 0.35, '#b26bff', '#ffe866', 1.05, 0.08);

    // Giant swirled lollipops & candy corn peaks along the hills!
    for (int i = 0; i < 6; i++) {
      final double lx = w * (0.06 + i * 0.168 + rng.nextDouble() * 0.015);
      if ((lx - gHouseX).abs() < 80 ||
          (lx - cupX).abs() < 80 ||
          (lx - coneX).abs() < 55 ||
          (lx - chocoX).abs() < 65 ||
          (lx - macaronX).abs() < 60) {
        continue;
      }
      final double ly = _sampleHeight(heights, lx, step);
      if (i.isOdd) {
        _drawCandyCornCluster(ctx, lx, ly + 4.0);
      } else {
        _drawLollipop(ctx, lx, ly, i % 4 == 0 ? '#ff5488' : '#4be6ff', 1.05);
      }
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

  /// Draws a glossy translucent-style giant cartoon Gummy Bear!
  static void _drawGummyBear(
    CanvasRenderingContext2D ctx,
    double x,
    double groundY,
    String lightColor,
    String darkColor,
    double s,
    double tilt,
  ) {
    ctx.save();
    ctx.translate(x, groundY);
    ctx.rotate(tilt);
    ctx.scale(s, s);

    final CanvasGradient g = ctx.createLinearGradient(-22, -78, 22, 0);
    g.addColorStop(0.0, lightColor);
    g.addColorStop(1.0, darkColor);
    ctx.fillStyle = g;
    ctx.strokeStyle = '#380e24'.toJS;
    ctx.lineWidth = 3.4;

    // Chubby ears.
    for (final double ex in const [-15.0, 15.0]) {
      ctx.beginPath();
      ctx.arc(ex, -72, 9.0, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    // Plump gummy torso & feet.
    ctx.beginPath();
    ctx.roundRect(-24, -48, 48, 46, 18.0.toJS);
    ctx.fill();
    ctx.stroke();
    for (final double fx in const [-16.0, 16.0]) {
      ctx.beginPath();
      ctx.arc(fx, -8, 10.5, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(fx * 1.25, -34, 8.5, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    // Round gummy head!
    ctx.beginPath();
    ctx.arc(0, -58, 20.0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Jelly gloss highlights & cute face!
    ctx.fillStyle = 'rgba(255, 255, 255, 0.45)'.toJS;
    ctx.beginPath();
    ctx.ellipse(-7, -65, 5.5, 3.5, -0.4, 0, 2 * pi);
    ctx.ellipse(-8, -28, 5.0, 10.0, -0.15, 0, 2 * pi);
    ctx.fill();

    ctx.fillStyle = '#380e24'.toJS;
    ctx.beginPath();
    ctx.arc(-7, -58, 2.5, 0, 2 * pi);
    ctx.arc(7, -58, 2.5, 0, 2 * pi);
    ctx.arc(0, -52, 3.2, 0, 2 * pi);
    ctx.fill();
    ctx.restore();
  }

  /// Draws a giant twisted-wrapper hard candy bonbon platform!
  static void _drawWrappedBonbonCandy(
    CanvasRenderingContext2D ctx,
    double cx,
    double cy,
    String mainColor,
    String stripeColor,
    double s,
    double angle,
  ) {
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(angle);
    ctx.scale(s, s);
    ctx.strokeStyle = '#47152e'.toJS;
    ctx.lineWidth = 3.4;

    // Left & right crinkled fan wrapper tails!
    ctx.fillStyle = mainColor.toJS;
    for (final double side in const [-1.0, 1.0]) {
      ctx.beginPath();
      ctx.moveTo(side * 34, 0);
      ctx.lineTo(side * 66, -20);
      ctx.lineTo(side * 60, -6);
      ctx.lineTo(side * 68, 0);
      ctx.lineTo(side * 60, 6);
      ctx.lineTo(side * 66, 20);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }

    // Plump oval hard-candy body with diagonal sugar stripes!
    ctx.beginPath();
    ctx.ellipse(0, 0, 38, 24, 0, 0, 2 * pi);
    ctx.fill();
    ctx.save();
    ctx.clip();
    ctx.fillStyle = stripeColor.toJS;
    for (double sx = -42; sx <= 36; sx += 18) {
      ctx.beginPath();
      ctx.moveTo(sx, -28);
      ctx.lineTo(sx + 9, -28);
      ctx.lineTo(sx - 5, 28);
      ctx.lineTo(sx - 14, 28);
      ctx.closePath();
      ctx.fill();
    }
    ctx.fillStyle = 'rgba(255, 255, 255, 0.42)'.toJS;
    ctx.beginPath();
    ctx.ellipse(-8, -10, 18, 5, -0.15, 0, 2 * pi);
    ctx.fill();
    ctx.restore();

    ctx.beginPath();
    ctx.ellipse(0, 0, 38, 24, 0, 0, 2 * pi);
    ctx.stroke();
    ctx.restore();
  }

  /// Draws a tall crispy waffle-cone triple-scoop ice cream tower!
  static void _drawIceCreamConeTower(
      CanvasRenderingContext2D ctx, double x, double groundY) {
    ctx.save();
    ctx.translate(x, groundY);
    ctx.strokeStyle = '#4a230b'.toJS;
    ctx.lineWidth = 3.6;

    // Golden waffle cone base!
    ctx.fillStyle = '#e09b48'.toJS;
    ctx.beginPath();
    ctx.moveTo(-36, -86);
    ctx.lineTo(36, -86);
    ctx.lineTo(14, 6);
    ctx.lineTo(-14, 6);
    ctx.closePath();
    ctx.fill();
    ctx.save();
    ctx.clip();
    ctx.strokeStyle = 'rgba(110, 52, 14, 0.45)'.toJS;
    ctx.lineWidth = 2.0;
    for (double d = -90; d <= 50; d += 16) {
      ctx.beginPath();
      ctx.moveTo(-40, d);
      ctx.lineTo(40, d + 48);
      ctx.moveTo(40, d);
      ctx.lineTo(-40, d + 48);
      ctx.stroke();
    }
    ctx.restore();
    ctx.strokeStyle = '#4a230b'.toJS;
    ctx.lineWidth = 3.6;
    ctx.stroke();

    // Rolled wafer stick jutting out the top!
    ctx.save();
    ctx.translate(18, -168);
    ctx.rotate(0.35);
    ctx.fillStyle = '#f2be72'.toJS;
    ctx.fillRect(-6, -34, 12, 44);
    ctx.strokeRect(-6, -34, 12, 44);
    ctx.restore();

    // 3 stacked scoops: Mint-chip, Mango-gold, Strawberry!
    const List<List<dynamic>> scoops = [
      [0.0, -98.0, 36.0, '#72f2b8'],
      [-6.0, -134.0, 31.0, '#ffd84d'],
      [4.0, -166.0, 26.0, '#ff78b4'],
    ];
    for (final List<dynamic> sc in scoops) {
      ctx.fillStyle = (sc[3] as String).toJS;
      ctx.beginPath();
      ctx.arc(sc[0] as double, sc[1] as double, sc[2] as double, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    // Chocolate chips on mint scoop!
    ctx.fillStyle = '#4a230b'.toJS;
    for (final List<double> ch in const [
      [-14.0, -100.0],
      [8.0, -94.0],
      [16.0, -106.0],
    ]) {
      ctx.beginPath();
      ctx.arc(ch[0], ch[1], 3.2, 0, 2 * pi);
      ctx.fill();
    }
    ctx.restore();
  }

  /// Draws a giant segmented milk-chocolate bar angled as a climbable ramp!
  static void _drawChocolateBarRamp(
      CanvasRenderingContext2D ctx, double x, double groundY, double tilt) {
    ctx.save();
    ctx.translate(x, groundY);
    ctx.rotate(tilt);

    // Molded cocoa slab.
    ctx.fillStyle = '#6e3619'.toJS;
    ctx.strokeStyle = '#2b1105'.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.roundRect(-64, -92, 128, 86, 6.0.toJS);
    ctx.fill();
    ctx.stroke();

    // 2x4 beveled chocolate pips!
    for (int r = 0; r < 2; r++) {
      for (int c = 0; c < 4; c++) {
        final double px = -56.0 + c * 28.5;
        final double py = -84.0 + r * 36.0;
        ctx.fillStyle = '#874522'.toJS;
        ctx.fillRect(px, py, 24, 30);
        ctx.strokeRect(px, py, 24, 30);
        ctx.fillStyle = 'rgba(255, 210, 175, 0.25)'.toJS;
        ctx.fillRect(px + 3, py + 3, 18, 5);
      }
    }

    // Torn golden foil & pink paper wrapper around the lower half!
    ctx.fillStyle = '#ffd845'.toJS;
    ctx.beginPath();
    ctx.moveTo(-68, -36);
    ctx.lineTo(-32, -48);
    ctx.lineTo(4, -34);
    ctx.lineTo(38, -46);
    ctx.lineTo(68, -32);
    ctx.lineTo(68, 4);
    ctx.lineTo(-68, 4);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#ff5c9e'.toJS;
    ctx.fillRect(-68, -20, 136, 24);
    ctx.strokeRect(-68, -20, 136, 24);
    ctx.restore();
  }

  /// Draws a stack of 3 pastel French Macaron cookies!
  static void _drawMacaronStack(
      CanvasRenderingContext2D ctx, double x, double groundY) {
    ctx.save();
    ctx.translate(x, groundY);
    const List<List<dynamic>> macs = [
      [0.0, -18.0, 50.0, '#b98aff', '#fff5fa'],
      [6.0, -54.0, 44.0, '#6ef2b8', '#fff8cc'],
      [-4.0, -86.0, 38.0, '#ff9c6e', '#ffffff'],
    ];
    ctx.strokeStyle = '#471b33'.toJS;
    ctx.lineWidth = 3.2;
    for (final List<dynamic> m in macs) {
      final double mx = m[0] as double;
      final double my = m[1] as double;
      final double hw = m[2] as double;
      final String shell = m[3] as String;
      final String cream = m[4] as String;

      // Bottom shell.
      ctx.fillStyle = shell.toJS;
      ctx.beginPath();
      ctx.roundRect(mx - hw, my + 4, hw * 2, 13, 6.5.toJS);
      ctx.fill();
      ctx.stroke();
      // Cream filling.
      ctx.fillStyle = cream.toJS;
      ctx.beginPath();
      ctx.roundRect(mx - hw * 0.94, my - 3, hw * 1.88, 9, 4.5.toJS);
      ctx.fill();
      ctx.stroke();
      // Domed top shell.
      ctx.fillStyle = shell.toJS;
      ctx.beginPath();
      ctx.roundRect(mx - hw, my - 16, hw * 2, 15, 7.5.toJS);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  /// Draws a colorful stack of classic layered Licorice Allsorts cubes!
  static void _drawLicoriceAllsortsStack(
      CanvasRenderingContext2D ctx, double x, double groundY) {
    ctx.save();
    ctx.translate(x, groundY);
    ctx.strokeStyle = '#1c1218'.toJS;
    ctx.lineWidth = 3.2;
    const List<List<dynamic>> blocks = [
      [-4.0, -44.0, 68.0, 46.0, '#ff74b8', '#262026', '#ffe44d'],
      [6.0, -84.0, 54.0, 40.0, '#5ce6ff', '#262026', '#ffffff'],
    ];
    for (final List<dynamic> b in blocks) {
      final double bx = (b[0] as double) - (b[2] as double) * 0.5;
      final double by = b[1] as double;
      final double bw = b[2] as double;
      final double bh = b[3] as double;
      final double lh = bh / 3.0;
      final List<String> layers = [
        b[4] as String,
        b[5] as String,
        b[6] as String,
      ];
      for (int l = 0; l < 3; l++) {
        ctx.fillStyle = layers[l].toJS;
        ctx.fillRect(bx, by + l * lh, bw, lh + 1);
      }
      ctx.strokeRect(bx, by, bw, bh);
    }
    ctx.restore();
  }

  /// Draws a trio of tri-color Candy Corn wedges!
  static void _drawCandyCornCluster(
      CanvasRenderingContext2D ctx, double x, double groundY) {
    ctx.save();
    ctx.translate(x, groundY);
    for (final List<double> c in const [
      [-18.0, 0.78, -0.18],
      [18.0, 0.82, 0.18],
      [0.0, 1.05, 0.0],
    ]) {
      ctx.save();
      ctx.translate(c[0], 0);
      ctx.rotate(c[2]);
      ctx.scale(c[1], c[1]);
      ctx.beginPath();
      ctx.moveTo(-18, 2);
      ctx.lineTo(-4, -46);
      ctx.quadraticCurveTo(0, -54, 4, -46);
      ctx.lineTo(18, 2);
      ctx.closePath();
      ctx.save();
      ctx.clip();
      ctx.fillStyle = '#ffe038'.toJS;
      ctx.fillRect(-22, -14, 44, 18);
      ctx.fillStyle = '#ff841f'.toJS;
      ctx.fillRect(-22, -34, 44, 20);
      ctx.fillStyle = '#ffffff'.toJS;
      ctx.fillRect(-22, -56, 44, 22);
      ctx.restore();
      ctx.strokeStyle = '#4a1f08'.toJS;
      ctx.lineWidth = 3.0;
      ctx.stroke();
      ctx.restore();
    }
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
  // 7. TOY LAND (Playroom Blocks & Giant Toys)
  // =========================================================================
  static void _drawToySkyBunting(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    bool compact,
    Random rng,
  ) {
    const List<String> flagColors = [
      'rgba(255, 82, 82, 0.72)',
      'rgba(255, 212, 59, 0.75)',
      'rgba(56, 178, 255, 0.72)',
      'rgba(76, 217, 100, 0.72)',
      'rgba(185, 108, 255, 0.72)',
    ];
    final int spans = compact ? 2 : 3;
    final double spanW = w / spans;
    final double sag = compact ? 12.0 : 34.0;
    final double flagW = compact ? 9.0 : 22.0;
    final double flagH = compact ? 11.0 : 26.0;
    final int colorOffset = rng.nextInt(flagColors.length);

    ctx.save();
    for (int s = 0; s < spans; s++) {
      final double x0 = s * spanW;
      final double x1 = (s + 1) * spanW;
      final double y0 = h * (0.04 + (s.isEven ? 0.0 : 0.03));
      final double y1 = h * (0.04 + (s.isOdd ? 0.0 : 0.03));

      ctx.strokeStyle = 'rgba(82, 56, 36, 0.45)'.toJS;
      ctx.lineWidth = compact ? 1.4 : 2.6;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.quadraticCurveTo((x0 + x1) * 0.5, (y0 + y1) * 0.5 + sag, x1, y1);
      ctx.stroke();

      final int count = max(4, (spanW ~/ (flagW * 1.35)));
      for (int i = 0; i < count; i++) {
        final double t = (i + 0.5) / count;
        final double px = x0 + (x1 - x0) * t;
        final double py = (1 - t) * (1 - t) * y0 +
            2 * (1 - t) * t * ((y0 + y1) * 0.5 + sag) +
            t * t * y1;
        ctx.fillStyle =
            flagColors[(i + s + colorOffset) % flagColors.length].toJS;
        ctx.beginPath();
        ctx.moveTo(px - flagW * 0.48, py);
        ctx.lineTo(px + flagW * 0.48, py);
        ctx.lineTo(px, py + flagH);
        ctx.closePath();
        ctx.fill();
      }
    }
    ctx.restore();
  }

  static void _drawToyHorizonCastle(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    bool compact,
    Random rng,
  ) {
    ctx.save();
    // Soft rolling pastel playroom hills in the background.
    _drawHorizonRidge(
        ctx, w, h, h * 0.78, compact ? 10 : 28, 'rgba(120, 214, 152, 0.30)', rng);

    // Distant pastel toy-block towers & conical roofs!
    const List<String> pastelTowers = [
      'rgba(255, 118, 118, 0.28)',
      'rgba(98, 182, 255, 0.28)',
      'rgba(255, 208, 86, 0.30)',
      'rgba(168, 128, 255, 0.26)',
    ];
    final int towerCount = compact ? 5 : 9;
    final double slotW = w / towerCount;
    for (int i = 0; i < towerCount; i++) {
      final double tw = slotW * (0.36 + rng.nextDouble() * 0.18);
      final double tx = i * slotW + (slotW - tw) * 0.5;
      final double th = h * (0.16 + rng.nextDouble() * 0.18);
      final double ty = h - th;
      ctx.fillStyle = pastelTowers[i % pastelTowers.length].toJS;
      ctx.fillRect(tx, ty, tw, th);
      // Conical toy castle turret cap!
      ctx.beginPath();
      ctx.moveTo(tx - tw * 0.12, ty);
      ctx.lineTo(tx + tw * 0.5, ty - tw * 0.65);
      ctx.lineTo(tx + tw * 1.12, ty);
      ctx.closePath();
      ctx.fill();
    }

    // Distant pastel Ferris wheel silhouette on one side!
    if (!compact) {
      final double wx = w * (0.74 + rng.nextDouble() * 0.12);
      final double wy = h * 0.64;
      final double wr = h * 0.16;
      ctx.strokeStyle = 'rgba(255, 126, 168, 0.32)'.toJS;
      ctx.lineWidth = 4.0;
      ctx.beginPath();
      ctx.arc(wx, wy, wr, 0, 2 * pi);
      ctx.stroke();
      for (int s = 0; s < 8; s++) {
        final double a = (s / 8.0) * 2 * pi;
        ctx.beginPath();
        ctx.moveTo(wx, wy);
        ctx.lineTo(wx + cos(a) * wr, wy + sin(a) * wr);
        ctx.stroke();
      }
      ctx.beginPath();
      ctx.moveTo(wx - wr * 0.55, h);
      ctx.lineTo(wx, wy);
      ctx.lineTo(wx + wr * 0.55, h);
      ctx.stroke();
    }
    ctx.restore();
  }

  static void _drawFloatingToyBalloons(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    double time,
    int seed, {
    double detailScale = 1.0,
  }) {
    const List<String> colors = [
      'rgba(255, 86, 94, 0.78)',
      'rgba(255, 208, 56, 0.80)',
      'rgba(66, 184, 255, 0.78)',
      'rgba(92, 224, 118, 0.78)',
      'rgba(196, 116, 255, 0.78)',
    ];
    final int s = seed.abs() % 500;
    final int balloonCount = max(2, (6 * detailScale).round());
    ctx.save();
    for (int i = 0; i < balloonCount; i++) {
      final double baseU = ((i * 173 + s * 11 + 40) % 920 + 40) / 1000.0;
      final double bob = sin(time * 1.3 + i * 1.9) * 14.0;
      final double sway = cos(time * 0.9 + i * 1.4) * 10.0;
      final double bx = baseU * w + sway;
      final double by = h * (0.20 + (i % 3) * 0.10) + bob;
      // Wavy string.
      ctx.strokeStyle = 'rgba(90, 72, 60, 0.42)'.toJS;
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.moveTo(bx, by + 16);
      ctx.quadraticCurveTo(bx + 5, by + 28, bx - 2, by + 40);
      ctx.stroke();
      // Balloon oval.
      ctx.fillStyle = colors[(i + s) % colors.length].toJS;
      ctx.beginPath();
      ctx.ellipse(bx, by, 13.0, 16.5, 0, 0, 2 * pi);
      ctx.fill();
      // Gloss highlight.
      ctx.fillStyle = 'rgba(255, 255, 255, 0.48)'.toJS;
      ctx.beginPath();
      ctx.ellipse(bx - 4.5, by - 5.5, 3.2, 5.2, -0.3, 0, 2 * pi);
      ctx.fill();
    }
    ctx.restore();
  }

  static void _generateToyland(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    // Rolling playroom hills keeping deep ground 100% solid down to bottom edge!
    final List<double> heights = _buildHeightfield(
      w,
      h * 0.69,
      86.0,
      rng,
      step: step,
      edgeDrop: 68.0,
      minY: 500.0,
      maxY: 752.0,
    );

    // Warm honey-maple wooden toybox floor with colorful rainbow playmat strata
    // and bright stitched green felt playmat turf on top!
    _drawCartoonGround(
      ctx,
      w,
      h,
      heights,
      step,
      rng,
      fillTop: '#e8b068',
      fillMid: '#c98842',
      fillBottom: '#965d24',
      outlineColor: '#361d0a',
      turfTop: '#56e36f',
      turfBottom: '#22a648',
      turfOutline: '#104a22',
      pebbleColor: 'rgba(130, 74, 24, 0.28)',
      turfThickness: 28.0,
      layerBands: const [
        'rgba(255, 92, 92, 0.24)',
        'rgba(56, 174, 255, 0.24)',
        'rgba(255, 214, 56, 0.24)',
      ],
    );

    // 1. Stacked Wooden ABC / 1-2-3 Alphabet Block Forts on left, center-left, and right!
    final List<String> blockLetters = ['A', 'B', 'C', '1', '2', '3'];
    final List<String> blockTrimColors = [
      '#ff4d4d',
      '#2e8cff',
      '#30c95b',
      '#ff9924',
      '#a864ff',
      '#ff5ca8',
    ];
    final double leftFortX = w * (0.14 + rng.nextDouble() * 0.03);
    final double leftBaseY = _sampleHeight(heights, leftFortX, step) + 10.0;
    _drawAlphabetBlock(ctx, leftFortX - 46, leftBaseY - 86, 88,
        blockLetters[0], blockTrimColors[0]);
    _drawAlphabetBlock(ctx, leftFortX + 46, leftBaseY - 86, 88,
        blockLetters[1], blockTrimColors[1]);
    _drawAlphabetBlock(ctx, leftFortX, leftBaseY - 174, 88,
        blockLetters[2], blockTrimColors[2]);

    final double rightFortX = w * (0.84 + rng.nextDouble() * 0.03);
    final double rightBaseY = _sampleHeight(heights, rightFortX, step) + 10.0;
    _drawAlphabetBlock(ctx, rightFortX - 46, rightBaseY - 86, 88,
        blockLetters[3], blockTrimColors[3]);
    _drawAlphabetBlock(ctx, rightFortX + 46, rightBaseY - 86, 88,
        blockLetters[4], blockTrimColors[4]);
    _drawAlphabetBlock(ctx, rightFortX, rightBaseY - 174, 88,
        blockLetters[5], blockTrimColors[5]);

    // 2. Interlocking Studded Plastic LEGO-style Brick Towers & Battlements!
    final List<double> towerXs = [
      w * (0.31 + rng.nextDouble() * 0.03),
      w * (0.67 + rng.nextDouble() * 0.03),
    ];
    for (int t = 0; t < towerXs.length; t++) {
      final double tx = towerXs[t];
      final double baseY = _sampleHeight(heights, tx, step) + 14.0;
      _drawPlasticBrickTower(ctx, tx, baseY, rows: 5 + (rng.nextInt(2)), seedOffset: t * 3);
    }

    // 3. Giant Bright Cartoon Wooden Toy Steam Train in the central playroom valley!
    final double trainX = w * (0.48 + rng.nextDouble() * 0.04);
    final double trainY = _sampleHeight(heights, trainX, step) + 6.0;
    _drawWoodenToyTrain(ctx, trainX, trainY);

    // 4. Giant Retro Tin Wind-Up Robot & Rainbow Ring-Stacker Props!
    final double robotX = w * 0.23;
    _drawTinWindUpRobot(ctx, robotX, _sampleHeight(heights, robotX, step) + 8.0);

    final double stackerX = w * 0.76;
    _drawRingStackerToy(
        ctx, stackerX, _sampleHeight(heights, stackerX, step) + 8.0);

    // 5. Floating Domino & Studded Plastic Brick Aerial Platforms linked by Xylophone Bridges!
    final List<List<dynamic>> skyPlatforms = [
      [w * 0.20, h * 0.27, 236.0, '#ff4d4d', '#c41e28'],
      [w * 0.50, h * 0.22, 260.0, '#2e8cff', '#1859b8'],
      [w * 0.80, h * 0.27, 236.0, '#ffd426', '#c99708'],
    ];
    for (int i = 0; i < skyPlatforms.length; i++) {
      final List<dynamic> p = skyPlatforms[i];
      _drawFloatingToyBrickPlatform(
        ctx,
        cx: p[0] as double,
        cy: p[1] as double,
        width: p[2] as double,
        height: 44.0,
        topColor: p[3] as String,
        bottomColor: p[4] as String,
      );
    }
    // Rainbow xylophone bridges connecting the upper floating brick platforms!
    _drawXylophoneBridge(ctx, w * 0.20 + 110, h * 0.27 + 8, w * 0.50 - 122,
        h * 0.22 + 8);
    _drawXylophoneBridge(ctx, w * 0.50 + 122, h * 0.22 + 8, w * 0.80 - 110,
        h * 0.27 + 8);

    // 6. THEMATIC INDESTRUCTIBLE BEDROCK: Heavy Studded Toy Baseplates & Bolted Beams
    // distributed cleanly across left, center, and right zones!
    _drawToyStuddedBedrockPlate(
      bCtx,
      x: leftFortX - 96,
      y: leftBaseY - 4,
      w: 192,
      h: 28,
      topColor: '#ff4d4d',
      bottomColor: '#b81822',
    );
    _drawToyStuddedBedrockPlate(
      bCtx,
      x: towerXs[0] - 88,
      y: _sampleHeight(heights, towerXs[0], step) - 96,
      w: 176,
      h: 26,
      topColor: '#2e8cff',
      bottomColor: '#1656b0',
    );
    _drawToyStuddedBedrockPlate(
      bCtx,
      x: trainX - 118,
      y: trainY + 12,
      w: 236,
      h: 28,
      topColor: '#ffd426',
      bottomColor: '#c7920a',
    );
    _drawToyStuddedBedrockPlate(
      bCtx,
      x: towerXs[1] - 88,
      y: _sampleHeight(heights, towerXs[1], step) - 96,
      w: 176,
      h: 26,
      topColor: '#30c95b',
      bottomColor: '#178737',
    );
    _drawToyStuddedBedrockPlate(
      bCtx,
      x: rightFortX - 96,
      y: rightBaseY - 4,
      w: 192,
      h: 28,
      topColor: '#ff4d4d',
      bottomColor: '#b81822',
    );
  }

  /// Draws an indestructible LEGO-style studded armored baseplate onto [bCtx].
  static void _drawToyStuddedBedrockPlate(
    CanvasRenderingContext2D bCtx, {
    required double x,
    required double y,
    required double w,
    required double h,
    required String topColor,
    required String bottomColor,
  }) {
    bCtx.save();
    // Raised plastic studs along the top edge!
    const double studW = 18.0;
    const double studH = 8.0;
    for (double sx = x + 10; sx <= x + w - studW - 8; sx += 28.0) {
      bCtx.fillStyle = topColor.toJS;
      bCtx.strokeStyle = '#12151f'.toJS;
      bCtx.lineWidth = 3.0;
      bCtx.beginPath();
      bCtx.roundRect(sx, y - studH + 2, studW, studH, 3.0.toJS);
      bCtx.fill();
      bCtx.stroke();
      bCtx.fillStyle = 'rgba(255, 255, 255, 0.40)'.toJS;
      bCtx.fillRect(sx + 3, y - studH + 4, studW - 6, 2.5);
    }

    // Main armored baseplate body with bold comic outline and rivets.
    _drawBedrockBlock(
      bCtx,
      x: x,
      y: y,
      w: w,
      h: h,
      style: _BedrockStyle.toyBrick,
    );

    // Tinted plastic overlay band so left/center/right baseplates showcase primary toy colors.
    bCtx.save();
    bCtx.beginPath();
    bCtx.roundRect(x + 5, y + 5, w - 10, h - 10, 4.0.toJS);
    bCtx.clip();
    final CanvasGradient g = bCtx.createLinearGradient(x, y, x, y + h);
    g.addColorStop(0.0, topColor);
    g.addColorStop(1.0, bottomColor);
    bCtx.fillStyle = g;
    bCtx.fillRect(x + 5, y + 5, w - 10, h - 10);
    bCtx.fillStyle = 'rgba(255, 255, 255, 0.30)'.toJS;
    bCtx.fillRect(x + 6, y + 6, w - 12, 5.0);
    // Silver Meccano bolts across the baseplate!
    bCtx.fillStyle = '#fff5bd'.toJS;
    bCtx.strokeStyle = '#12151f'.toJS;
    bCtx.lineWidth = 1.8;
    for (double bx = x + 22; bx < x + w - 16; bx += 36.0) {
      bCtx.beginPath();
      bCtx.arc(bx, y + h * 0.5, 4.0, 0, 2 * pi);
      bCtx.fill();
      bCtx.stroke();
    }
    bCtx.restore();
    bCtx.restore();
  }

  /// Draws a classic beveled wooden ABC / 123 toy block centered horizontally at [cx]
  /// with top edge at [topY].
  static void _drawAlphabetBlock(
    CanvasRenderingContext2D ctx,
    double cx,
    double topY,
    double size,
    String letter,
    String accentColor,
  ) {
    final double x = cx - size * 0.5;
    final double y = topY;
    ctx.save();
    // Colored painted outer frame.
    ctx.fillStyle = accentColor.toJS;
    ctx.strokeStyle = '#291507'.toJS;
    ctx.lineWidth = 4.0;
    ctx.beginPath();
    ctx.roundRect(x, y, size, size, 8.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Recessed warm cream maple wood face.
    final double inset = size * 0.14;
    final CanvasGradient wood =
        ctx.createLinearGradient(x, y + inset, x, y + size - inset);
    wood.addColorStop(0.0, '#fff3cf');
    wood.addColorStop(1.0, '#edd08a');
    ctx.fillStyle = wood;
    ctx.strokeStyle = '#6e3f19'.toJS;
    ctx.lineWidth = 2.6;
    ctx.beginPath();
    ctx.roundRect(
        x + inset, y + inset, size - inset * 2, size - inset * 2, 4.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Bold painted block letter in the center!
    ctx.fillStyle = accentColor.toJS;
    ctx.strokeStyle = '#291507'.toJS;
    ctx.lineWidth = 3.0;
    ctx.font = '900 ${(size * 0.50).round()}px "Comic Sans MS", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.strokeText(letter, cx, y + size * 0.53);
    ctx.fillText(letter, cx, y + size * 0.53);
    ctx.restore();
  }

  /// Draws a multi-course interlocking studded plastic LEGO-style brick tower!
  static void _drawPlasticBrickTower(
    CanvasRenderingContext2D ctx,
    double cx,
    double baseY, {
    int rows = 5,
    int seedOffset = 0,
  }) {
    const List<List<String>> brickPalettes = [
      ['#ff4d4d', '#c71e29'],
      ['#2e8cff', '#185ab8'],
      ['#ffd426', '#cfa00c'],
      ['#34c759', '#1c8c38'],
      ['#ff8c24', '#c95c0c'],
    ];
    const double rowH = 38.0;
    const double baseW = 168.0;

    ctx.save();
    for (int r = 0; r < rows; r++) {
      final double rw = baseW - (r >= rows - 1 ? 28.0 : 0.0);
      final double rx = cx - rw * 0.5 + (r.isOdd ? 6.0 : -6.0);
      final double ry = baseY - (r + 1) * rowH;
      final List<String> pal =
          brickPalettes[(r + seedOffset) % brickPalettes.length];

      // Top cylindrical plastic studs on the uppermost course (and exposed shoulders).
      for (double sx = rx + 10; sx <= rx + rw - 24; sx += 28.0) {
        ctx.fillStyle = pal[0].toJS;
        ctx.strokeStyle = '#1b202e'.toJS;
        ctx.lineWidth = 2.8;
        ctx.fillRect(sx, ry - 8, 16, 9);
        ctx.strokeRect(sx, ry - 8, 16, 9);
      }

      final CanvasGradient bg = ctx.createLinearGradient(rx, ry, rx, ry + rowH);
      bg.addColorStop(0.0, pal[0]);
      bg.addColorStop(1.0, pal[1]);
      ctx.fillStyle = bg;
      ctx.strokeStyle = '#1b202e'.toJS;
      ctx.lineWidth = 3.8;
      ctx.fillRect(rx, ry, rw, rowH);
      ctx.strokeRect(rx, ry, rw, rowH);

      // Vertical seam splitting each course into 2 interlocking bricks + specular shine!
      final double seamX = rx + rw * (r.isEven ? 0.5 : 0.38);
      ctx.beginPath();
      ctx.moveTo(seamX, ry);
      ctx.lineTo(seamX, ry + rowH);
      ctx.stroke();

      ctx.fillStyle = 'rgba(255, 255, 255, 0.30)'.toJS;
      ctx.fillRect(rx + 4, ry + 4, rw - 8, 6);
    }
    ctx.restore();
  }

  /// Draws a giant cheerful painted wooden toy steam locomotive!
  static void _drawWoodenToyTrain(
      CanvasRenderingContext2D ctx, double cx, double groundY) {
    ctx.save();
    ctx.translate(cx, groundY);

    // Solid red chassis beam.
    ctx.fillStyle = '#d92b38'.toJS;
    ctx.strokeStyle = '#24140e'.toJS;
    ctx.lineWidth = 4.0;
    ctx.beginPath();
    ctx.roundRect(-124, -46, 248, 28, 6.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Royal-blue engineer cab at the rear (-116..-22).
    final CanvasGradient cabG = ctx.createLinearGradient(-116, -142, -116, -46);
    cabG.addColorStop(0.0, '#3898ff');
    cabG.addColorStop(1.0, '#1d5ec4');
    ctx.fillStyle = cabG;
    ctx.fillRect(-114, -138, 94, 92);
    ctx.strokeRect(-114, -138, 94, 92);

    // Golden curved cab roof overhang.
    ctx.fillStyle = '#ffd426'.toJS;
    ctx.beginPath();
    ctx.roundRect(-124, -152, 114, 18, 7.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Bright sky-tinted cab window (solid painted glass so no tricky tiny holes).
    ctx.fillStyle = '#bff0ff'.toJS;
    ctx.beginPath();
    ctx.roundRect(-94, -120, 54, 44, 6.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Cherry-red cylindrical boiler (-20..96).
    final CanvasGradient boilerG = ctx.createLinearGradient(0, -118, 0, -46);
    boilerG.addColorStop(0.0, '#ff5454');
    boilerG.addColorStop(1.0, '#b81d28');
    ctx.fillStyle = boilerG;
    ctx.fillRect(-20, -114, 118, 68);
    ctx.strokeRect(-20, -114, 118, 68);
    // Golden brass boiler bands.
    ctx.fillStyle = '#ffd426'.toJS;
    ctx.fillRect(12, -114, 12, 68);
    ctx.strokeRect(12, -114, 12, 68);
    ctx.fillRect(56, -114, 12, 68);
    ctx.strokeRect(56, -114, 12, 68);

    // Flared smokestack & puffy solid cotton-ball steam clouds (climbable steps!).
    ctx.fillStyle = '#364054'.toJS;
    ctx.beginPath();
    ctx.moveTo(64, -114);
    ctx.lineTo(54, -158);
    ctx.lineTo(94, -158);
    ctx.lineTo(84, -114);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#fff9eb'.toJS;
    for (final List<double> puff in const [
      [74.0, -176.0, 18.0],
      [52.0, -196.0, 22.0],
      [22.0, -212.0, 25.0],
    ]) {
      ctx.beginPath();
      ctx.arc(puff[0], puff[1], puff[2], 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }

    // Yellow cowcatcher wedge at the front (+98..+138).
    ctx.fillStyle = '#ffd426'.toJS;
    ctx.beginPath();
    ctx.moveTo(98, -46);
    ctx.lineTo(138, -20);
    ctx.lineTo(98, -20);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Big painted wooden spoked wheels!
    for (final List<double> wh in const [
      [-72.0, -22.0, 28.0],
      [4.0, -20.0, 24.0],
      [68.0, -20.0, 24.0],
    ]) {
      ctx.fillStyle = '#ffd426'.toJS;
      ctx.beginPath();
      ctx.arc(wh[0], wh[1], wh[2], 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = '#ff4d4d'.toJS;
      ctx.beginPath();
      ctx.arc(wh[0], wh[1], wh[2] * 0.42, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  /// Draws a retro painted tin wind-up robot with a brass key on its side!
  static void _drawTinWindUpRobot(
      CanvasRenderingContext2D ctx, double cx, double groundY) {
    ctx.save();
    ctx.translate(cx, groundY);
    ctx.strokeStyle = '#182232'.toJS;
    ctx.lineWidth = 3.8;

    // Chunky red tin boots & legs.
    ctx.fillStyle = '#ff4d4d'.toJS;
    ctx.fillRect(-34, -44, 26, 44);
    ctx.strokeRect(-34, -44, 26, 44);
    ctx.fillRect(8, -44, 26, 44);
    ctx.strokeRect(8, -44, 26, 44);

    // Brass wind-up key sticking out the left side!
    ctx.fillStyle = '#ffd426'.toJS;
    ctx.fillRect(-68, -98, 24, 12);
    ctx.strokeRect(-68, -98, 24, 12);
    ctx.beginPath();
    ctx.arc(-76, -106, 12, 0, 2 * pi);
    ctx.arc(-76, -80, 12, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Teal tin torso.
    final CanvasGradient bodyG = ctx.createLinearGradient(-44, -128, 44, -44);
    bodyG.addColorStop(0.0, '#45d9d2');
    bodyG.addColorStop(1.0, '#1f9199');
    ctx.fillStyle = bodyG;
    ctx.beginPath();
    ctx.roundRect(-44, -128, 88, 86, 8.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Chest meter panel.
    ctx.fillStyle = '#fff5bd'.toJS;
    ctx.fillRect(-26, -110, 52, 34);
    ctx.strokeRect(-26, -110, 52, 34);
    ctx.strokeStyle = '#ff4d4d'.toJS;
    ctx.beginPath();
    ctx.moveTo(-18, -86);
    ctx.lineTo(-4, -102);
    ctx.lineTo(8, -90);
    ctx.lineTo(18, -104);
    ctx.stroke();

    // Robot head + glowing yellow eyes + red bulb antenna!
    ctx.strokeStyle = '#182232'.toJS;
    ctx.fillStyle = '#45d9d2'.toJS;
    ctx.beginPath();
    ctx.roundRect(-30, -176, 60, 48, 8.0.toJS);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#ffe047'.toJS;
    ctx.beginPath();
    ctx.arc(-12, -154, 7.5, 0, 2 * pi);
    ctx.arc(12, -154, 7.5, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    ctx.fillRect(-4, -194, 8, 18);
    ctx.strokeRect(-4, -194, 8, 18);
    ctx.fillStyle = '#ff4d4d'.toJS;
    ctx.beginPath();
    ctx.arc(0, -200, 9.0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /// Draws a giant rainbow toddler ring-stacker pyramid!
  static void _drawRingStackerToy(
      CanvasRenderingContext2D ctx, double cx, double groundY) {
    ctx.save();
    ctx.translate(cx, groundY);
    ctx.strokeStyle = '#26170b'.toJS;
    ctx.lineWidth = 3.8;

    // Wooden rocking base & center peg.
    ctx.fillStyle = '#e8b068'.toJS;
    ctx.beginPath();
    ctx.roundRect(-64, -20, 128, 22, 10.0.toJS);
    ctx.fill();
    ctx.stroke();
    ctx.fillRect(-10, -148, 20, 130);
    ctx.strokeRect(-10, -148, 20, 130);

    const List<List<dynamic>> rings = [
      [56.0, '#ff4d4d'],
      [48.0, '#ff9824'],
      [40.0, '#ffd426'],
      [32.0, '#34c759'],
      [24.0, '#2e8cff'],
    ];
    for (int i = 0; i < rings.length; i++) {
      final double hw = rings[i][0] as double;
      final double ry = -44.0 - i * 22.0;
      ctx.fillStyle = (rings[i][1] as String).toJS;
      ctx.beginPath();
      ctx.roundRect(-hw, ry, hw * 2, 22.0, 11.0.toJS);
      ctx.fill();
      ctx.stroke();
    }
    // Yellow topper ball.
    ctx.fillStyle = '#ffe047'.toJS;
    ctx.beginPath();
    ctx.arc(0, -158, 14.0, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /// Draws a floating oversized LEGO-style plastic building brick platform!
  static void _drawFloatingToyBrickPlatform(
    CanvasRenderingContext2D ctx, {
    required double cx,
    required double cy,
    required double width,
    required double height,
    required String topColor,
    required String bottomColor,
  }) {
    final double x = cx - width * 0.5;
    final double y = cy - height * 0.5;
    ctx.save();
    // Top studs!
    for (double sx = x + 12; sx <= x + width - 28; sx += 30.0) {
      ctx.fillStyle = topColor.toJS;
      ctx.strokeStyle = '#1b202e'.toJS;
      ctx.lineWidth = 3.0;
      ctx.fillRect(sx, y - 9, 18, 10);
      ctx.strokeRect(sx, y - 9, 18, 10);
    }

    final CanvasGradient g = ctx.createLinearGradient(x, y, x, y + height);
    g.addColorStop(0.0, topColor);
    g.addColorStop(1.0, bottomColor);
    ctx.fillStyle = g;
    ctx.strokeStyle = '#1b202e'.toJS;
    ctx.lineWidth = 4.0;
    ctx.beginPath();
    ctx.roundRect(x, y, width, height, 6.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Gloss highlight & domino-style white pips along the front!
    ctx.fillStyle = 'rgba(255, 255, 255, 0.34)'.toJS;
    ctx.fillRect(x + 6, y + 5, width - 12, 6);
    ctx.fillStyle = '#ffffff'.toJS;
    for (double px = x + 28; px < x + width - 20; px += 44.0) {
      ctx.beginPath();
      ctx.arc(px, y + height * 0.58, 4.5, 0, 2 * pi);
      ctx.fill();
    }
    ctx.restore();
  }

  /// Draws a colorful rainbow xylophone-bar suspension bridge between two ledges!
  static void _drawXylophoneBridge(
      CanvasRenderingContext2D ctx, double x0, double y0, double x1, double y1,
      {double sag = 24.0}) {
    const List<String> barColors = [
      '#ff4d4d',
      '#ff9824',
      '#ffd426',
      '#34c759',
      '#2e8cff',
      '#a864ff',
    ];
    ctx.save();
    final int bars = max(6, ((x1 - x0).abs() ~/ 24));
    ctx.strokeStyle = '#4a2e16'.toJS;
    ctx.lineWidth = 3.8;
    ctx.beginPath();
    ctx.moveTo(x0, y0 + 2);
    ctx.quadraticCurveTo((x0 + x1) * 0.5, (y0 + y1) * 0.5 + sag + 2, x1, y1 + 2);
    ctx.stroke();

    for (int i = 0; i <= bars; i++) {
      final double t = i / bars;
      final double px = x0 + (x1 - x0) * t;
      final double py = (1 - t) * (1 - t) * y0 +
          2 * (1 - t) * t * ((y0 + y1) * 0.5 + sag) +
          t * t * y1;
      ctx.fillStyle = barColors[i % barColors.length].toJS;
      ctx.strokeStyle = '#1b202e'.toJS;
      ctx.lineWidth = 2.4;
      ctx.beginPath();
      ctx.roundRect(px - 9, py - 5, 18, 11, 3.0.toJS);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  // =========================================================================
  // 8. JUNGLE TEMPLE (Vertikal Djungelravin & Mystiska Statyer)
  // =========================================================================
  static void _generateJungle(
    CanvasRenderingContext2D ctx,
    CanvasRenderingContext2D bCtx,
    int w,
    int h,
    Random rng,
  ) {
    const int step = 20;
    final List<double> heights = _buildHeightfield(
      w,
      h * 0.68,
      95.0,
      rng,
      step: step,
      edgeDrop: 65.0,
      minY: 360.0,
      maxY: 752.0,
    );

    // Sculpt steep vertical jungle mesas & deep canyon shafts so Jungle plays
    // noticeably more vertically than the other worlds while keeping bottom ground solid!
    for (int i = 0; i < heights.length; i++) {
      final double u = (i * step) / w;
      if ((u - 0.22).abs() < 0.085) {
        final double t = cos(((u - 0.22) / 0.085) * pi * 0.5);
        heights[i] -= t * t * 210.0;
      } else if ((u - 0.78).abs() < 0.085) {
        final double t = cos(((u - 0.78) / 0.085) * pi * 0.5);
        heights[i] -= t * t * 205.0;
      } else if ((u - 0.50).abs() < 0.10) {
        final double t = cos(((u - 0.50) / 0.10) * pi * 0.5);
        heights[i] += t * 72.0;
      }
      heights[i] = heights[i].clamp(370.0, 754.0);
    }

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

    // 1. Stepped Ancient Stone Temple in the deep central canyon + Towering Multi-Faced
    // Strange Totem Pillars rising vertically out of the side valleys!
    final double centerTempleX = w * (0.50 + (rng.nextDouble() - 0.5) * 0.03);
    _drawJunglePyramid(
      ctx,
      centerTempleX,
      _sampleHeight(heights, centerTempleX, step) + 18.0,
      230.0,
      195.0,
    );

    final double leftTotemX = w * 0.09;
    _drawStrangeTotemColumn(
        ctx, leftTotemX, _sampleHeight(heights, leftTotemX, step) + 10.0, 3);
    final double rightTotemX = w * 0.91;
    _drawStrangeTotemColumn(
        ctx, rightTotemX, _sampleHeight(heights, rightTotemX, step) + 10.0, 3);

    // 2. Strange Ancient Jungle Statues perched on the tall vertical cliff mesas!
    final double leftMesaX = w * 0.22;
    final double leftMesaY = _sampleHeight(heights, leftMesaX, step) + 8.0;
    _drawStrangeMoaiFrogIdol(ctx, leftMesaX, leftMesaY, 1.05, facingLeft: false);
    _drawSerpentHeadLedge(ctx, leftMesaX + 86, leftMesaY + 62, facingLeft: false);

    final double rightMesaX = w * 0.78;
    final double rightMesaY = _sampleHeight(heights, rightMesaX, step) + 8.0;
    _drawStrangeMoaiFrogIdol(ctx, rightMesaX, rightMesaY, 1.05, facingLeft: true);
    _drawSerpentHeadLedge(ctx, rightMesaX - 86, rightMesaY + 62, facingLeft: true);

    // 3. Multi-tiered Vertical Canopy Cliff Platforms (Mid-Canopy & High-Canopy Tiers!)
    // creating 3 distinct vertical combat elevations connected by bridges & hanging vines!
    final List<List<double>> midLedges = [
      [w * 0.36, h * 0.43, 195.0, 74.0],
      [w * 0.64, h * 0.42, 195.0, 74.0],
    ];
    final List<List<double>> highLedges = [
      [w * 0.18, h * 0.19, 215.0, 78.0],
      [w * 0.50, h * 0.14, 235.0, 82.0],
      [w * 0.82, h * 0.19, 215.0, 78.0],
    ];

    for (final List<double> l in [...midLedges, ...highLedges]) {
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
      // Hanging vertical jungle vines trailing below every canopy island!
      _drawHangingJungleVines(ctx, l[0] - l[2] * 0.34, l[1] + l[3] * 0.52, 3, 92.0);
      _drawHangingJungleVines(ctx, l[0] + l[2] * 0.24, l[1] + l[3] * 0.52, 2, 78.0);
    }

    // Four-armed mystery guardian idol crowning the highest central canopy altar!
    _drawFourArmedJungleDeity(
        ctx, highLedges[1][0], highLedges[1][1] - 10.0, 0.96);
    _drawPalmTree(ctx, highLedges[0][0] - 42, highLedges[0][1] - 10, 0.76, 18);
    _drawPalmTree(ctx, highLedges[2][0] + 42, highLedges[2][1] - 10, 0.76, -18);

    // Steep ascending vine-plank bridges linking mesas -> mid-canopy -> high-canopy!
    _drawRopeBridge(
      ctx,
      leftMesaX + 54,
      leftMesaY + 6,
      midLedges[0][0] - 84,
      midLedges[0][1] - 2,
      sag: 22.0,
      woodColor: '#8c6239',
    );
    _drawRopeBridge(
      ctx,
      midLedges[1][0] + 84,
      midLedges[1][1] - 2,
      rightMesaX - 54,
      rightMesaY + 6,
      sag: 22.0,
      woodColor: '#8c6239',
    );
    _drawRopeBridge(
      ctx,
      highLedges[0][0] + 96,
      highLedges[0][1] - 2,
      highLedges[1][0] - 106,
      highLedges[1][1] + 4,
      sag: 26.0,
      woodColor: '#8c6239',
    );
    _drawRopeBridge(
      ctx,
      highLedges[1][0] + 106,
      highLedges[1][1] + 4,
      highLedges[2][0] - 96,
      highLedges[2][1] - 2,
      sag: 26.0,
      woodColor: '#8c6239',
    );

    // Lush Bamboo Clusters & Giant Palms along canyon edges!
    for (final double frac in const [0.35, 0.64]) {
      final double px = w * frac;
      final double py = _sampleHeight(heights, px, step);
      _drawPalmTree(ctx, px, py, 1.02, frac < 0.5 ? 24 : -24);
      _drawBambooCluster(ctx, px + (frac < 0.5 ? -34 : 34), py + 4);
    }

    // THEMATIC INDESTRUCTIBLE BEDROCK (VERTICAL GOLDEN RUIN COLUMNS & SKY ALTARS):
    // 1-2. Tall vertical golden obelisk pillars inside the left & right cliff mesas!
    _drawBedrockPillar(
      bCtx,
      cx: leftMesaX,
      topY: leftMesaY + 26,
      height: 185,
      width: 46,
      style: _BedrockStyle.mayanGold,
    );
    _drawBedrockPillar(
      bCtx,
      cx: rightMesaX,
      topY: rightMesaY + 26,
      height: 185,
      width: 46,
      style: _BedrockStyle.mayanGold,
    );
    // 3-4. Elevated golden sky-altar girders at mid-canopy height on both sides!
    _drawBedrockGirder(
      bCtx,
      x: midLedges[0][0] - 78,
      y: midLedges[0][1] + 18,
      w: 156,
      h: 26,
      style: _BedrockStyle.mayanGold,
    );
    _drawBedrockGirder(
      bCtx,
      x: midLedges[1][0] - 78,
      y: midLedges[1][1] + 18,
      w: 156,
      h: 26,
      style: _BedrockStyle.mayanGold,
    );
    // 5. High-canopy sacred golden sun-altar slab beneath the top center deity!
    _drawBedrockBlock(
      bCtx,
      x: highLedges[1][0] - 84,
      y: highLedges[1][1] + 14,
      w: 168,
      h: 28,
      style: _BedrockStyle.mayanGold,
    );
    // 6. Ancient gold-trimmed temple vault arch shielding the deep central chamber!
    _drawBedrockArchVault(
      bCtx,
      cx: centerTempleX,
      y: h * 0.77,
      span: 188,
      thickness: 26,
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

  /// Towering multi-faced strange stone totem pillar (3 stacked bizarre masks)!
  static void _drawStrangeTotemColumn(
      CanvasRenderingContext2D ctx, double x, double baseY, int faces) {
    ctx.save();
    ctx.translate(x, baseY);
    const double faceH = 74.0;
    ctx.strokeStyle = '#241e14'.toJS;
    ctx.lineWidth = 3.8;

    for (int i = 0; i < faces; i++) {
      final double ty = -(i + 1) * faceH;
      final double w = 68.0 - i * 4.0;
      final CanvasGradient stone =
          ctx.createLinearGradient(-w * 0.5, ty, w * 0.5, ty);
      stone.addColorStop(0.0, i.isEven ? '#aba082' : '#968c6e');
      stone.addColorStop(1.0, '#695f47');
      ctx.fillStyle = stone;
      ctx.beginPath();
      ctx.roundRect(-w * 0.5, ty, w, faceH + 2, 8.0.toJS);
      ctx.fill();
      ctx.stroke();

      // Jutting stone ears / wings on middle & top masks!
      if (i > 0) {
        ctx.fillStyle = '#877c60'.toJS;
        for (final double side in const [-1.0, 1.0]) {
          ctx.beginPath();
          ctx.moveTo(side * w * 0.5, ty + 14);
          ctx.lineTo(side * (w * 0.5 + 24), ty + 4);
          ctx.lineTo(side * (w * 0.5 + 18), ty + 36);
          ctx.lineTo(side * w * 0.5, ty + 42);
          ctx.closePath();
          ctx.fill();
          ctx.stroke();
        }
      }

      if (i == 0) {
        // Bottom mask: Wide-mouthed fanged guardian!
        ctx.fillStyle = '#45ff82'.toJS;
        ctx.fillRect(-22, ty + 16, 14, 10);
        ctx.strokeRect(-22, ty + 16, 14, 10);
        ctx.fillRect(8, ty + 16, 14, 10);
        ctx.strokeRect(8, ty + 16, 14, 10);
        ctx.fillStyle = '#241e14'.toJS;
        ctx.fillRect(-20, ty + 42, 40, 18);
        ctx.fillStyle = '#efe6cf'.toJS;
        ctx.fillRect(-16, ty + 44, 8, 12);
        ctx.fillRect(8, ty + 44, 8, 12);
      } else if (i == 1) {
        // Middle mask: Upside-down spiral-eyed trickster face!
        ctx.fillStyle = '#5cf2ff'.toJS;
        ctx.beginPath();
        ctx.arc(-13, ty + 44, 8, 0, 2 * pi);
        ctx.arc(13, ty + 44, 8, 0, 2 * pi);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#ffd238'.toJS;
        ctx.beginPath();
        ctx.moveTo(-14, ty + 20);
        ctx.lineTo(14, ty + 20);
        ctx.lineTo(0, ty + 34);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
      } else {
        // Top mask: Strange 3-eyed horned sky-cyclops idol!
        ctx.fillStyle = '#ff52a8'.toJS;
        ctx.beginPath();
        ctx.arc(0, ty + 28, 12, 0, 2 * pi);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#241e14'.toJS;
        ctx.beginPath();
        ctx.ellipse(0, ty + 28, 3.5, 9.0, 0, 0, 2 * pi);
        ctx.fill();
        // Golden crescent horns!
        ctx.fillStyle = '#ffd638'.toJS;
        ctx.beginPath();
        ctx.moveTo(-26, ty + 2);
        ctx.lineTo(-34, ty - 24);
        ctx.lineTo(-10, ty + 2);
        ctx.moveTo(26, ty + 2);
        ctx.lineTo(34, ty - 24);
        ctx.lineTo(10, ty + 2);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  /// Enigmatic tilted Moai-meets-Aztec-frog monolith with glowing mystic third eye
  /// and a protruding carved stone tongue step!
  static void _drawStrangeMoaiFrogIdol(
    CanvasRenderingContext2D ctx,
    double x,
    double baseY,
    double s, {
    bool facingLeft = false,
  }) {
    ctx.save();
    ctx.translate(x, baseY);
    ctx.scale(facingLeft ? -s : s, s);
    ctx.rotate(-0.08);
    ctx.strokeStyle = '#241e14'.toJS;
    ctx.lineWidth = 4.0;

    final CanvasGradient body = ctx.createLinearGradient(-44, -148, 44, 0);
    body.addColorStop(0.0, '#b5aa8c');
    body.addColorStop(1.0, '#6e644b');
    ctx.fillStyle = body;
    ctx.beginPath();
    ctx.moveTo(-42, 6);
    ctx.lineTo(-34, -138);
    ctx.lineTo(28, -146);
    ctx.lineTo(44, -64);
    ctx.lineTo(36, 6);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Mossy stone headdress crown!
    ctx.fillStyle = '#38ba48'.toJS;
    ctx.beginPath();
    ctx.roundRect(-38, -154, 72, 16, 6.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Spiral stone ear-spool on the back!
    ctx.fillStyle = '#ffd238'.toJS;
    ctx.beginPath();
    ctx.arc(-34, -78, 14, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Heavy brow ridge, long angular Moai nose & glowing cyan mystic forehead gem!
    ctx.fillStyle = '#5cf7ff'.toJS;
    ctx.beginPath();
    ctx.moveTo(4, -132);
    ctx.lineTo(13, -120);
    ctx.lineTo(4, -108);
    ctx.lineTo(-5, -120);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#45ff82'.toJS;
    ctx.beginPath();
    ctx.ellipse(14, -94, 10, 7, -0.1, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#998e72'.toJS;
    ctx.beginPath();
    ctx.moveTo(18, -104);
    ctx.lineTo(50, -68);
    ctx.lineTo(22, -64);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Protruding carved stone tongue ledge!
    ctx.fillStyle = '#d96c75'.toJS;
    ctx.beginPath();
    ctx.roundRect(14, -42, 46, 16, 7.0.toJS);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /// Strange ancient four-armed stone deity statue crowning the highest canopy terrace!
  static void _drawFourArmedJungleDeity(
      CanvasRenderingContext2D ctx, double cx, double baseY, double s) {
    ctx.save();
    ctx.translate(cx, baseY);
    ctx.scale(s, s);
    ctx.strokeStyle = '#241e14'.toJS;
    ctx.lineWidth = 3.6;

    // 4 outstretched stone arms holding glowing emerald & gold orbs!
    for (final double side in const [-1.0, 1.0]) {
      for (final List<double> arm in const [
        [-48.0, -78.0],
        [-30.0, -44.0],
      ]) {
        ctx.strokeStyle = '#241e14'.toJS;
        ctx.lineWidth = 12.0;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(side * 18, arm[0]);
        ctx.lineTo(side * 52, arm[1]);
        ctx.stroke();
        ctx.strokeStyle = '#aba082'.toJS;
        ctx.lineWidth = 6.5;
        ctx.stroke();

        ctx.strokeStyle = '#241e14'.toJS;
        ctx.lineWidth = 2.8;
        ctx.fillStyle = (arm[1] < -60 ? '#45ff82' : '#ffd638').toJS;
        ctx.beginPath();
        ctx.arc(side * 54, arm[1] - 6, 8.0, 0, 2 * pi);
        ctx.fill();
        ctx.stroke();
      }
    }

    // Cross-legged stone pedestal & torso + tall stepped sun headdress!
    ctx.fillStyle = '#a39778'.toJS;
    ctx.lineWidth = 3.6;
    ctx.beginPath();
    ctx.roundRect(-38, -24, 76, 26, 10.0.toJS);
    ctx.fill();
    ctx.stroke();
    ctx.beginPath();
    ctx.roundRect(-24, -68, 48, 46, 8.0.toJS);
    ctx.fill();
    ctx.stroke();
    ctx.beginPath();
    ctx.roundRect(-22, -108, 44, 42, 8.0.toJS);
    ctx.fill();
    ctx.stroke();

    // Weird 3-eyed mask & golden fan crown!
    ctx.fillStyle = '#ffd638'.toJS;
    ctx.beginPath();
    ctx.arc(0, -108, 26, pi, 2 * pi);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#5cf7ff'.toJS;
    for (final double ex in const [-10.0, 0.0, 10.0]) {
      ctx.beginPath();
      ctx.arc(ex, -88 - (ex == 0.0 ? 7.0 : 0.0), 4.2, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  /// Carved stone feathered-serpent head jutting horizontally from a vertical cliff wall!
  static void _drawSerpentHeadLedge(
      CanvasRenderingContext2D ctx, double x, double y,
      {bool facingLeft = false}) {
    ctx.save();
    ctx.translate(x, y);
    if (facingLeft) ctx.scale(-1, 1);
    ctx.fillStyle = '#9e9274'.toJS;
    ctx.strokeStyle = '#241e14'.toJS;
    ctx.lineWidth = 3.6;
    ctx.beginPath();
    ctx.moveTo(-26, -22);
    ctx.lineTo(44, -22);
    ctx.lineTo(54, -4);
    ctx.lineTo(36, 14);
    ctx.lineTo(-26, 18);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Moss top cap & glowing eye + fang!
    ctx.fillStyle = '#3ecf5e'.toJS;
    ctx.fillRect(-24, -26, 66, 8);
    ctx.strokeRect(-24, -26, 66, 8);
    ctx.fillStyle = '#ffd638'.toJS;
    ctx.beginPath();
    ctx.arc(24, -8, 5.5, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /// Hanging vertical jungle vines with leaves dangling below canopy islands!
  static void _drawHangingJungleVines(CanvasRenderingContext2D ctx, double startX,
      double startY, int count, double maxLen) {
    ctx.save();
    for (int i = 0; i < count; i++) {
      final double vx = startX + i * 24.0;
      final double len = maxLen * (0.68 + (i % 3) * 0.16);
      ctx.strokeStyle = '#0d3b1c'.toJS;
      ctx.lineWidth = 7.0;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(vx, startY);
      ctx.quadraticCurveTo(vx + (i.isEven ? 8 : -8), startY + len * 0.5, vx, startY + len);
      ctx.stroke();
      ctx.strokeStyle = '#2eb84b'.toJS;
      ctx.lineWidth = 3.6;
      ctx.stroke();
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
    ctx.fillRect(w * 0.34, h * 0.42, w * 0.30, h * 0.45);
    ctx.strokeRect(w * 0.34, h * 0.42, w * 0.30, h * 0.45);
    ctx.fillStyle = '#2a1847'.toJS;
    ctx.beginPath();
    ctx.moveTo(w * 0.30, h * 0.42);
    ctx.lineTo(w * 0.50, h * 0.16);
    ctx.lineTo(w * 0.68, h * 0.42);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#ffd24d'.toJS;
    ctx.fillRect(w * 0.45, h * 0.52, w * 0.08, h * 0.13);
    _drawSolidSpookyGhost(ctx, w * 0.21, h * 0.44, 0.44, facingLeft: false);
    _drawCartoonSkeleton(ctx, w * 0.78, h * 0.84, 0.48, facingLeft: true);
    _drawPumpkin(ctx, w * 0.22, h * 0.82, 0.58);
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
    _drawTRexSkeleton(ctx, w * 0.54, h * 0.86, 0.34, facingLeft: false);
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
    _drawFrostedDonut(ctx, w * 0.50, h * 0.44, 32, 11, '#ff6eb8');
    _drawGummyBear(ctx, w * 0.21, h * 0.86, '#68f27c', '#1c9636', 0.48, 0.08);
    _drawWrappedBonbonCandy(
        ctx, w * 0.77, h * 0.72, '#4be6ff', '#fff9d2', 0.42, -0.15);
    _drawLollipop(ctx, w * 0.82, h * 0.52, '#ffe054', 0.44);
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

  static void _drawPreviewToyland(
      CanvasRenderingContext2D ctx, double w, double h) {
    // Playmat turf base.
    ctx.fillStyle = '#3ad65c'.toJS;
    ctx.strokeStyle = '#104a22'.toJS;
    ctx.lineWidth = 2.4;
    ctx.fillRect(0, h * 0.74, w, h * 0.26);
    ctx.strokeRect(-2, h * 0.74, w + 4, h * 0.28);

    // Mini studded LEGO-style brick stack on the left!
    const List<List<dynamic>> bricks = [
      [0.10, 0.56, 0.34, 0.18, '#2e8cff'],
      [0.14, 0.38, 0.28, 0.18, '#ffd426'],
      [0.17, 0.22, 0.22, 0.16, '#ff4d4d'],
    ];
    for (final List<dynamic> b in bricks) {
      final double bx = (b[0] as double) * w;
      final double by = (b[1] as double) * h;
      final double bw = (b[2] as double) * w;
      final double bh = (b[3] as double) * h;
      ctx.fillStyle = (b[4] as String).toJS;
      ctx.strokeStyle = '#1b202e'.toJS;
      ctx.lineWidth = 2.2;
      // Top studs.
      for (double sx = bx + 5; sx <= bx + bw - 12; sx += 13) {
        ctx.fillRect(sx, by - 4, 8, 5);
        ctx.strokeRect(sx, by - 4, 8, 5);
      }
      ctx.fillRect(bx, by, bw, bh);
      ctx.strokeRect(bx, by, bw, bh);
    }

    // Wooden 'A' alphabet block on the right!
    _drawAlphabetBlock(ctx, w * 0.68, h * 0.40, h * 0.35, 'A', '#ff4d4d');
  }

  static void _drawPreviewJungle(CanvasRenderingContext2D ctx, double w, double h) {
    _drawFloatingCartoonIsland(
      ctx,
      cx: w * 0.72,
      cy: h * 0.32,
      width: w * 0.42,
      height: h * 0.18,
      rockTop: '#806d52',
      rockBottom: '#473826',
      rockOutline: '#1f160c',
      turfTop: '#3ecf5e',
      turfBottom: '#1a7538',
      turfOutline: '#0d3b1c',
    );
    _drawStrangeTotemColumn(ctx, w * 0.28, h * 0.90, 3);
    _drawStrangeMoaiFrogIdol(ctx, w * 0.72, h * 0.88, 0.42, facingLeft: true);
  }
}
