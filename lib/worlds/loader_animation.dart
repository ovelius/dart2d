import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart';

/// ZooBlast Sky Island Diorama loading screen & continuous menu backdrop:
/// - Shared continuous world: sunny cartoon sky, drifting clouds, floating
///   mini-islands, playful distant artillery arcs & comic puffs, lush grassy
///   Worms-style foreground island, and a thin sparkling turquoise waterline.
/// - Phase 1 (no images yet): dotted artillery trajectories, spinning cartoon
///   target reticle, orbiting mini-projectiles, sizzling fuse bomb, and a
///   prowling shark fin in the waterline.
/// - Phase 2 (`shark.png` loaded): the sunglasses shark leaps out of the water
///   with a splash burst into comic sunburst rays, escorted by an aerial
///   3D-orbiting mini-shark squadron!
class LoaderAnimation {
  static const List<String> _LOADING_TIPS = [
    "Polishing the shark's sunglasses...",
    "Calibrating banana pancake physics...",
    "Brewing extra-strong espresso jets...",
    "Negotiating treaties with angry goats...",
    "Teaching jellybeans how to bounce...",
    "Packing extra craters into the island...",
    "Training WebRTC carrier pigeons...",
    "Counting shark teeth (still sharp)...",
    "Warming up the tiger-head zookas...",
    "Checking wind speed on the sky islands...",
  ];

  final Random _rng = Random();
  double _time = 0.0;
  double _sharkReveal = 0.0; // 0.0 = bomb/reticle mode, 1.0 = sky-shark spectacle
  bool _sharkBurstTriggered = false;

  // Periodic hero shark barrel-roll flourish.
  double _flourishTimer = 4.5;
  double _flourishProgress = 1.0;

  // Periodic background artillery shots between distant islands.
  double _nextArtilleryTimer = 0.9;

  // Periodic bomb fuse spark emitter.
  double _fuseSparkAccum = 0.0;

  final List<_Cloud> _clouds = [];
  final List<_SkyMote> _motes = [];
  final List<_OrbitProjectile> _orbitProjectiles = [];
  final List<_MiniShark> _miniSharks = [];
  final List<_Shockwave> _shockwaves = [];
  final List<_Sparkle> _sparkles = [];
  final List<_SplashDrop> _splashDrops = [];
  final List<_BgArtilleryShot> _artilleryShots = [];
  final List<_BgExplosionPuff> _explosionPuffs = [];

  LoaderAnimation() {
    for (int i = 0; i < 8; i++) {
      _clouds.add(_Cloud.random(_rng, i, 8));
    }
    for (int i = 0; i < 28; i++) {
      _motes.add(_SkyMote.random(_rng));
    }
    for (int i = 0; i < 6; i++) {
      _orbitProjectiles.add(_OrbitProjectile(i, 6));
    }
    for (int i = 0; i < 7; i++) {
      _miniSharks.add(_MiniShark(i, 7));
    }
  }

  void tick(double duration, {required bool sharkAvailable}) {
    final double dt = duration.clamp(0.0, 0.1);
    _time += dt;

    // Smoothly transition into the leaping shark spectacle when shark.png loads.
    if (sharkAvailable) {
      if (!_sharkBurstTriggered) {
        _sharkBurstTriggered = true;
        _triggerShockwave(color: "255, 255, 255", maxRadius: 235.0);
        _triggerShockwave(color: "255, 214, 72", maxRadius: 175.0);
        _spawnSparkleBurst(24);
        _spawnWaterSplash(22);
      }
      _sharkReveal = min(1.0, _sharkReveal + dt * 1.35);
    } else {
      _sharkReveal = max(0.0, _sharkReveal - dt * 2.0);
      _sharkBurstTriggered = false;
    }

    // Periodic hero shark hype barrel-roll + sparkle burst.
    if (_sharkReveal > 0.88) {
      _flourishTimer -= dt;
      if (_flourishTimer <= 0.0 && _flourishProgress >= 1.0) {
        _flourishProgress = 0.0;
        _flourishTimer = 6.0;
        _triggerShockwave(color: "255, 224, 88", maxRadius: 210.0);
        _spawnSparkleBurst(18);
      }
    }
    if (_flourishProgress < 1.0) {
      _flourishProgress = min(1.0, _flourishProgress + dt * 1.25);
    }

    // Periodic anticipation pulse + crackling fuse sparks in Phase 1.
    if (_sharkReveal < 0.5) {
      if (((_time - dt) / 2.8).floor() != (_time / 2.8).floor()) {
        _triggerShockwave(color: "255, 214, 72", maxRadius: 195.0);
      }
      _fuseSparkAccum += dt;
      while (_fuseSparkAccum > 0.055) {
        _fuseSparkAccum -= 0.055;
        final double a = _rng.nextDouble() * 2 * pi;
        final double spd = 38.0 + _rng.nextDouble() * 78.0;
        _sparkles.add(_Sparkle(
          x: 24.0 + cos(_time * 9.0) * 3.0,
          y: -46.0 + sin(_time * 11.0) * 2.0,
          vx: cos(a) * spd,
          vy: sin(a) * spd - 28.0,
          size: 3.5 + _rng.nextDouble() * 4.5,
          life: 0.35 + _rng.nextDouble() * 0.3,
          maxLife: 0.65,
          gold: _rng.nextBool(),
        ));
      }
    }

    // Advance drifting cartoon clouds.
    for (final _Cloud c in _clouds) {
      c.x += c.speed * dt;
      if (c.x > 1.22) {
        c.x = -0.22;
        c.y = 0.08 + _rng.nextDouble() * 0.34;
      }
    }

    // Advance sunlit sky motes / dandelion puffs.
    for (final _SkyMote m in _motes) {
      m.x += m.vx * dt;
      m.y += m.vy * dt;
      m.phase += m.twinkleSpeed * dt;
      if (m.x > 1.06) m.x = -0.06;
      if (m.x < -0.06) m.x = 1.06;
      if (m.y < -0.06) m.y = 0.85;
      if (m.y > 0.90) m.y = -0.04;
    }

    // Advance orbiting mini projectiles (Phase 1).
    for (final _OrbitProjectile p in _orbitProjectiles) {
      p.angle += dt * p.speed;
      if (p.angle > 2 * pi) p.angle -= 2 * pi;
    }

    // Advance aerial mini shark squadron (Phase 2).
    for (final _MiniShark s in _miniSharks) {
      s.angle += dt * s.speed;
      if (s.angle > 2 * pi) s.angle -= 2 * pi;
    }

    // Spawn playful distant artillery arcs across the background sky.
    _nextArtilleryTimer -= dt;
    if (_nextArtilleryTimer <= 0.0) {
      _nextArtilleryTimer = 2.0 + _rng.nextDouble() * 1.9;
      if (_artilleryShots.length < 3) {
        _spawnBackgroundArtillery();
      }
    }

    // Advance distant artillery shots.
    for (int i = _artilleryShots.length - 1; i >= 0; i--) {
      final _BgArtilleryShot shot = _artilleryShots[i];
      shot.t += dt / shot.duration;
      if (shot.t >= 1.0) {
        _spawnBackgroundExplosion(shot.endX, shot.endY, shot.accentColor);
        _artilleryShots.removeAt(i);
      }
    }

    // Advance distant comic explosion puffs.
    for (int i = _explosionPuffs.length - 1; i >= 0; i--) {
      final _BgExplosionPuff puff = _explosionPuffs[i];
      puff.age += dt;
      if (puff.age >= puff.maxAge) {
        _explosionPuffs.removeAt(i);
      }
    }

    // Advance shockwaves.
    for (int i = _shockwaves.length - 1; i >= 0; i--) {
      final _Shockwave sw = _shockwaves[i];
      sw.progress += dt * 1.1;
      if (sw.progress >= 1.0) {
        _shockwaves.removeAt(i);
      }
    }

    // Advance sparkles.
    for (int i = _sparkles.length - 1; i >= 0; i--) {
      final _Sparkle sp = _sparkles[i];
      sp.x += sp.vx * dt;
      sp.y += sp.vy * dt;
      sp.vy += 65.0 * dt;
      sp.vx *= 0.97;
      sp.life -= dt;
      if (sp.life <= 0) {
        _sparkles.removeAt(i);
      }
    }

    // Advance water splash droplets.
    for (int i = _splashDrops.length - 1; i >= 0; i--) {
      final _SplashDrop d = _splashDrops[i];
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.vy += 420.0 * dt;
      d.life -= dt;
      if (d.life <= 0) {
        _splashDrops.removeAt(i);
      }
    }
  }

  void _spawnBackgroundArtillery() {
    final bool leftToRight = _rng.nextBool();
    final double startX = leftToRight
        ? 0.08 + _rng.nextDouble() * 0.16
        : 0.76 + _rng.nextDouble() * 0.16;
    final double endX = leftToRight
        ? 0.72 + _rng.nextDouble() * 0.20
        : 0.08 + _rng.nextDouble() * 0.20;
    final double startY = 0.56 + _rng.nextDouble() * 0.14;
    final double endY = 0.54 + _rng.nextDouble() * 0.16;
    final double peakHeight = 0.22 + _rng.nextDouble() * 0.18;
    const List<String> colors = ["#ff6b4a", "#ffd447", "#ff6eb4", "#5ce68a"];
    _artilleryShots.add(_BgArtilleryShot(
      startX: startX,
      startY: startY,
      endX: endX,
      endY: endY,
      peakHeight: peakHeight,
      duration: 1.45 + _rng.nextDouble() * 0.65,
      accentColor: colors[_rng.nextInt(colors.length)],
    ));
  }

  void _spawnBackgroundExplosion(double x, double y, String color) {
    if (_explosionPuffs.length > 6) return;
    _explosionPuffs.add(_BgExplosionPuff(
      x: x,
      y: y,
      color: color,
      maxAge: 1.15,
      seed: _rng.nextInt(1000),
    ));
  }

  void _triggerShockwave({required String color, required double maxRadius}) {
    if (_shockwaves.length > 6) return;
    _shockwaves.add(_Shockwave(color: color, maxRadius: maxRadius));
  }

  void _spawnSparkleBurst(int count) {
    for (int i = 0; i < count; i++) {
      final double angle = (i / count) * 2 * pi + _rng.nextDouble() * 0.35;
      final double speed = 80.0 + _rng.nextDouble() * 145.0;
      _sparkles.add(_Sparkle(
        x: cos(angle) * 20.0,
        y: sin(angle) * 16.0,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 25.0,
        size: 5.5 + _rng.nextDouble() * 7.5,
        life: 0.65 + _rng.nextDouble() * 0.5,
        maxLife: 1.15,
        gold: i.isEven,
      ));
    }
  }

  void _spawnWaterSplash(int count) {
    for (int i = 0; i < count; i++) {
      final double spread = (_rng.nextDouble() - 0.5) * 2.2;
      _splashDrops.add(_SplashDrop(
        x: spread * 26.0,
        y: 0.0,
        vx: spread * 145.0,
        vy: -(160.0 + _rng.nextDouble() * 210.0),
        radius: 3.5 + _rng.nextDouble() * 5.5,
        life: 0.75 + _rng.nextDouble() * 0.45,
        maxLife: 1.2,
      ));
    }
  }

  /// Draws the continuous sunny ZooBlast Sky Island diorama backdrop (used
  /// behind Name Entry, Player Select, and World Select), with optional
  /// fading-out centerpiece during smooth loading -> selector crossfades.
  void drawBackdrop(
    CanvasRenderingContext2D ctx,
    int width,
    int height, {
    HTMLImageElement? sharkImage,
    double centerpieceAlpha = 0.0,
    bool showProwlingFin = false,
  }) {
    if (width <= 0 || height <= 0) return;

    final double w = width.toDouble();
    final double h = height.toDouble();
    final double cx = w * 0.5;
    final double cy = h * 0.40;
    final double scale = min(w / 960.0, h / 640.0).clamp(0.55, 1.35);

    ctx.save();
    ctx.globalAlpha = 1.0;
    ctx.globalCompositeOperation = "source-over";

    _drawSkyAndSun(ctx, w, h, scale, isError: false);
    _drawClouds(ctx, w, h, scale, backLayer: true);
    _drawFloatingIslands(ctx, w, h, scale);
    _drawBackgroundArtillery(ctx, w, h, scale);
    _drawClouds(ctx, w, h, scale, backLayer: false);
    _drawSkyMotes(ctx, w, h, scale);

    if (centerpieceAlpha > 0.01) {
      ctx.save();
      ctx.globalAlpha = centerpieceAlpha.clamp(0.0, 1.0);
      _drawCenterpiece(ctx, cx, cy, h, scale, sharkImage);
      _drawShockwavesAndSparkles(ctx, cx, cy, scale);
      ctx.restore();
    }

    _drawForegroundIslandAndWater(
      ctx,
      w,
      h,
      scale,
      showProwlingFin: showProwlingFin,
    );
    _drawSplashDrops(ctx, cx, h * 0.93, scale);

    ctx.restore();
  }

  void draw(
    CanvasRenderingContext2D ctx,
    int width,
    int height, {
    required String message,
    HTMLImageElement? sharkImage,
    double? progress,
    bool isError = false,
  }) {
    if (width <= 0 || height <= 0) return;

    final double w = width.toDouble();
    final double h = height.toDouble();
    final double cx = w * 0.5;
    final double cy = h * 0.40;
    final double scale = min(w / 960.0, h / 640.0).clamp(0.55, 1.35);

    ctx.save();
    ctx.globalAlpha = 1.0;
    ctx.globalCompositeOperation = "source-over";

    // 1. Bright sunny cartoon sky & cheerful spinning sun.
    _drawSkyAndSun(ctx, w, h, scale, isError: isError);

    // 2. Back cloud layer + bobbing distant sky islands.
    _drawClouds(ctx, w, h, scale, backLayer: true);
    _drawFloatingIslands(ctx, w, h, scale);

    // 3. Miniature playful artillery arcs & cartoon POOF explosions!
    _drawBackgroundArtillery(ctx, w, h, scale);

    // 4. Foreground clouds & sunlit floating motes.
    _drawClouds(ctx, w, h, scale, backLayer: false);
    _drawSkyMotes(ctx, w, h, scale);

    // 5. Centerpiece: smooth transition from Bomb/Reticle to Leaping Sky Shark!
    _drawCenterpiece(ctx, cx, cy, h, scale, sharkImage);

    // 6. Expanding comic shockwaves & flying star sparkles.
    _drawShockwavesAndSparkles(ctx, cx, cy, scale);

    // 7. Foreground Worms grassy island + thin turquoise waterline + prowling fin.
    final bool hasDrawableShark =
        sharkImage != null && sharkImage.width > 0 && sharkImage.height > 0;
    _drawForegroundIslandAndWater(
      ctx,
      w,
      h,
      scale,
      showProwlingFin: !hasDrawableShark || _sharkReveal < 0.65,
    );

    // 8. Water splash droplets from shark's leap!
    _drawSplashDrops(ctx, cx, h * 0.93, scale);

    // 9. Cartoon status banner, progress bar, and rotating witty tip.
    _drawStatusBanner(ctx, w, h, scale, message, progress, isError);

    ctx.restore();
  }

  void _drawCenterpiece(
    CanvasRenderingContext2D ctx,
    double cx,
    double cy,
    double h,
    double scale,
    HTMLImageElement? sharkImage,
  ) {
    final bool hasDrawableShark =
        sharkImage != null && sharkImage.width > 0 && sharkImage.height > 0;
    final double bombAlpha =
        hasDrawableShark ? (1.0 - _sharkReveal * 1.15).clamp(0.0, 1.0) : 1.0;

    if (bombAlpha > 0.01) {
      ctx.save();
      ctx.globalAlpha = ctx.globalAlpha * bombAlpha;
      _drawArtilleryBombCenterpiece(ctx, cx, cy, scale);
      ctx.restore();
    }

    if (hasDrawableShark && _sharkReveal > 0.01) {
      _drawSkySharkSpectacle(ctx, cx, cy, h, scale, sharkImage);
    }
  }

  void _drawSkyAndSun(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    double scale, {
    required bool isError,
  }) {
    final CanvasGradient sky = ctx.createLinearGradient(0, 0, 0, h * 0.92);
    if (isError) {
      sky.addColorStop(0.0, "#d94b5a");
      sky.addColorStop(0.55, "#f07c64");
      sky.addColorStop(1.0, "#ffd099");
    } else {
      sky.addColorStop(0.0, "#38aef8");
      sky.addColorStop(0.45, "#74d5ff");
      sky.addColorStop(0.82, "#cef2ff");
      sky.addColorStop(1.0, "#fff8d6");
    }
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);

    if (isError) return;

    // Cheerful cartoon sun in the upper-right sky with rotating warm rays.
    final double sunX = w * 0.84;
    final double sunY = h * 0.16;
    final double sunR = 44.0 * scale;

    ctx.save();
    ctx.translate(sunX, sunY);

    // Wide warm sunlit glow.
    final CanvasGradient halo =
        ctx.createRadialGradient(0, 0, sunR * 0.5, 0, 0, sunR * 4.4);
    halo.addColorStop(0.0, "rgba(255, 248, 165, 0.52)");
    halo.addColorStop(0.45, "rgba(255, 242, 160, 0.18)");
    halo.addColorStop(1.0, "rgba(255, 242, 160, 0.0)");
    ctx.fillStyle = halo;
    ctx.beginPath();
    ctx.arc(0, 0, sunR * 4.4, 0, 2 * pi);
    ctx.fill();

    // Gently spinning cartoon sun rays.
    ctx.save();
    ctx.rotate(_time * 0.18);
    const int rays = 12;
    for (int i = 0; i < rays; i++) {
      final double a0 = (i / rays) * 2 * pi;
      final double a1 = a0 + 0.14;
      final double rayLen = sunR * (i.isEven ? 1.85 : 1.52);
      ctx.fillStyle = "rgba(255, 240, 128, 0.45)".toJS;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, rayLen, a0, a1);
      ctx.closePath();
      ctx.fill();
    }
    ctx.restore();

    // Crisp sun disc.
    final CanvasGradient sunDisc =
        ctx.createRadialGradient(-sunR * 0.25, -sunR * 0.25, 4, 0, 0, sunR);
    sunDisc.addColorStop(0.0, "#fffef0");
    sunDisc.addColorStop(0.65, "#ffe869");
    sunDisc.addColorStop(1.0, "#ffc233");
    ctx.fillStyle = sunDisc;
    ctx.beginPath();
    ctx.arc(0, 0, sunR, 0, 2 * pi);
    ctx.fill();

    ctx.restore();
  }

  void _drawClouds(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    double scale, {
    required bool backLayer,
  }) {
    ctx.save();
    for (final _Cloud c in _clouds) {
      if (c.isBack != backLayer) continue;
      final double cx = c.x * w;
      final double cy = c.y * h + sin(_time * 0.6 + c.seed) * 4.0 * scale;
      final double s = c.scale * scale;

      ctx.save();
      ctx.translate(cx, cy);
      ctx.globalAlpha = backLayer ? 0.65 : 0.90;

      // Soft sky-blue cloud underside shadow.
      ctx.fillStyle = "#cdeeff".toJS;
      _traceCloudPath(ctx, s, offsetY: 5.0 * s);
      ctx.fill();

      // Fluffy white cartoon cloud body.
      ctx.fillStyle = "#ffffff".toJS;
      _traceCloudPath(ctx, s, offsetY: 0.0);
      ctx.fill();

      ctx.restore();
    }
    ctx.restore();
  }

  void _traceCloudPath(CanvasRenderingContext2D ctx, double s,
      {required double offsetY}) {
    ctx.beginPath();
    ctx.arc(-34 * s, 6 * s + offsetY, 18 * s, 0, 2 * pi);
    ctx.arc(-14 * s, -6 * s + offsetY, 24 * s, 0, 2 * pi);
    ctx.arc(14 * s, -4 * s + offsetY, 22 * s, 0, 2 * pi);
    ctx.arc(34 * s, 7 * s + offsetY, 17 * s, 0, 2 * pi);
    ctx.rect(-34 * s, 4 * s + offsetY, 68 * s, 19 * s);
  }

  void _drawFloatingIslands(
      CanvasRenderingContext2D ctx, double w, double h, double scale) {
    // Left distant bobbing floating rock island.
    _drawMiniFloatingIsland(
      ctx,
      x: w * 0.15,
      y: h * 0.59 + sin(_time * 1.1) * 7.0 * scale,
      width: 118.0 * scale,
      height: 54.0 * scale,
      scale: scale,
      hasPalm: true,
    );
    // Right distant bobbing floating rock island.
    _drawMiniFloatingIsland(
      ctx,
      x: w * 0.85,
      y: h * 0.56 + cos(_time * 0.95 + 1.2) * 8.0 * scale,
      width: 128.0 * scale,
      height: 58.0 * scale,
      scale: scale,
      hasPalm: false,
    );
  }

  void _drawMiniFloatingIsland(
    CanvasRenderingContext2D ctx, {
    required double x,
    required double y,
    required double width,
    required double height,
    required double scale,
    required bool hasPalm,
  }) {
    ctx.save();
    ctx.translate(x, y);

    final double hw = width * 0.5;

    // Tapered floating rock underside.
    final CanvasGradient rockGrad =
        ctx.createLinearGradient(0, 0, 0, height);
    rockGrad.addColorStop(0.0, "#a87752");
    rockGrad.addColorStop(1.0, "#6c4830");
    ctx.fillStyle = rockGrad;
    ctx.strokeStyle = "#3a2518".toJS;
    ctx.lineWidth = 2.4 * scale;
    ctx.beginPath();
    ctx.moveTo(-hw * 0.92, 0);
    ctx.quadraticCurveTo(-hw * 0.65, height * 0.65, -hw * 0.12, height);
    ctx.quadraticCurveTo(hw * 0.16, height * 0.88, hw * 0.35, height * 0.62);
    ctx.quadraticCurveTo(hw * 0.78, height * 0.42, hw * 0.92, 0);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Lush green cartoon grass cap.
    final CanvasGradient grassGrad =
        ctx.createLinearGradient(0, -14 * scale, 0, 12 * scale);
    grassGrad.addColorStop(0.0, "#7ee85a");
    grassGrad.addColorStop(1.0, "#3db53a");
    ctx.fillStyle = grassGrad;
    ctx.strokeStyle = "#1f5920".toJS;
    ctx.lineWidth = 2.2 * scale;
    ctx.beginPath();
    ctx.moveTo(-hw, 2 * scale);
    ctx.quadraticCurveTo(-hw * 0.5, -14 * scale, 0, -11 * scale);
    ctx.quadraticCurveTo(hw * 0.55, -14 * scale, hw, 2 * scale);
    ctx.quadraticCurveTo(hw * 0.65, 11 * scale, hw * 0.35, 4 * scale);
    ctx.quadraticCurveTo(0, 13 * scale, -hw * 0.35, 5 * scale);
    ctx.quadraticCurveTo(-hw * 0.72, 12 * scale, -hw, 2 * scale);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Tiny cute tree / palm silhouette on the floating island.
    if (hasPalm) {
      _drawCartoonPalm(ctx, -hw * 0.2, -10 * scale, 0.58 * scale);
    } else {
      _drawCartoonPine(ctx, hw * 0.18, -10 * scale, 0.65 * scale);
      _drawCartoonPine(ctx, -hw * 0.25, -9 * scale, 0.48 * scale);
    }

    ctx.restore();
  }

  void _drawBackgroundArtillery(
      CanvasRenderingContext2D ctx, double w, double h, double scale) {
    // Active parabolic artillery arcs + cute little rockets.
    for (final _BgArtilleryShot shot in _artilleryShots) {
      // Dotted smoke trail behind projectile.
      const int trailDots = 10;
      for (int i = 1; i <= trailDots; i++) {
        final double pt = shot.t - i * 0.032;
        if (pt < 0.0) continue;
        final double px = shot.xAt(pt) * w;
        final double py = shot.yAt(pt) * h;
        final double fade = 1.0 - (i / (trailDots + 1));
        ctx.fillStyle = "rgba(255, 255, 255, ${fade * 0.72})".toJS;
        ctx.beginPath();
        ctx.arc(px, py, (2.2 + fade * 3.0) * scale, 0, 2 * pi);
        ctx.fill();
      }

      // Projectile head oriented along velocity tangent.
      final double x = shot.xAt(shot.t) * w;
      final double y = shot.yAt(shot.t) * h;
      final double prevX = shot.xAt(max(0.0, shot.t - 0.015)) * w;
      final double prevY = shot.yAt(max(0.0, shot.t - 0.015)) * h;
      final double angle = atan2(y - prevY, x - prevX);

      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(angle);
      ctx.fillStyle = shot.accentColor.toJS;
      ctx.strokeStyle = "#1c2838".toJS;
      ctx.lineWidth = 1.8 * scale;
      ctx.beginPath();
      ctx.ellipse(0, 0, 6.5 * scale, 3.6 * scale, 0, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();

      // Tiny glowing flame tail.
      ctx.fillStyle = "#fff176".toJS;
      ctx.beginPath();
      ctx.arc(-6.5 * scale, 0, 2.6 * scale, 0, 2 * pi);
      ctx.fill();
      ctx.restore();
    }

    // Cartoon "POOF" comic explosion puffs!
    for (final _BgExplosionPuff puff in _explosionPuffs) {
      final double p = (puff.age / puff.maxAge).clamp(0.0, 1.0);
      final double px = puff.x * w;
      final double py = puff.y * h - p * 18.0 * scale;
      final double ease = _easeOutCubic(p);

      ctx.save();
      ctx.translate(px, py);

      // Flash starburst during the first 35% of the pop.
      if (p < 0.42) {
        final double starAlpha = (1.0 - p / 0.42);
        final double starR = (10.0 + ease * 26.0) * scale;
        _drawMultiStar(ctx, 0, 0, starR, 8,
            color: puff.color, alpha: starAlpha * 0.9, rotation: p * 1.4);
        _drawMultiStar(ctx, 0, 0, starR * 0.62, 8,
            color: "#fff8a6", alpha: starAlpha, rotation: -p * 1.8);
      }

      // Fluffy expanding white cartoon smoke puffs.
      final double smokeAlpha = (1.0 - p) * 0.85;
      ctx.fillStyle = "rgba(255, 255, 255, $smokeAlpha)".toJS;
      for (int k = 0; k < 5; k++) {
        final double a = (k / 5.0) * 2 * pi + puff.seed;
        final double dist = ease * (10.0 + (k % 2) * 8.0) * scale;
        final double r = (5.0 + (1.0 - p * 0.3) * 8.0) * scale;
        ctx.beginPath();
        ctx.arc(cos(a) * dist, sin(a) * dist, r, 0, 2 * pi);
        ctx.fill();
      }
      ctx.restore();
    }
  }

  void _drawSkyMotes(
      CanvasRenderingContext2D ctx, double w, double h, double scale) {
    ctx.save();
    for (final _SkyMote m in _motes) {
      final double pulse = sin(m.phase) * 0.5 + 0.5;
      final double alpha = 0.25 + pulse * 0.45;
      final double r = m.radius * scale * (0.8 + pulse * 0.4);
      ctx.fillStyle = "rgba(${m.rgb}, $alpha)".toJS;
      ctx.beginPath();
      ctx.arc(m.x * w, m.y * h, r, 0, 2 * pi);
      ctx.fill();
    }
    ctx.restore();
  }

  /// Phase 1 (No images yet): Worms-style dotted trajectory arcs, spinning
  /// cartoon target reticle, orbiting colorful projectiles, and a sizzling bomb!
  void _drawArtilleryBombCenterpiece(
      CanvasRenderingContext2D ctx, double cx, double cy, double scale) {
    ctx.save();
    ctx.translate(cx, cy);

    final double baseR = 104.0 * scale;

    // Animated dotted artillery sightline arcs curving left & right.
    for (int side in const [-1, 1]) {
      for (int i = 1; i <= 7; i++) {
        final double frac = ((i / 7.0) + (_time * 0.35)) % 1.0;
        final double ax = side * (36.0 + frac * 145.0) * scale;
        final double ay = (-sin(frac * pi) * 78.0 + frac * 35.0) * scale;
        final double alpha = sin(frac * pi) * 0.65;
        ctx.fillStyle = "rgba(255, 255, 255, $alpha)".toJS;
        ctx.strokeStyle = "rgba(20, 60, 110, ${alpha * 0.45})".toJS;
        ctx.lineWidth = 1.4 * scale;
        ctx.beginPath();
        ctx.arc(ax, ay, (3.2 + sin(frac * pi) * 2.2) * scale, 0, 2 * pi);
        ctx.fill();
        ctx.stroke();
      }
    }

    // Rotating comic sunburst halo behind the target reticle.
    ctx.save();
    ctx.rotate(_time * 0.32);
    for (int i = 0; i < 12; i++) {
      final double a0 = (i / 12.0) * 2 * pi;
      final double a1 = a0 + 0.16;
      ctx.fillStyle = i.isEven
          ? "rgba(255, 245, 165, 0.28)".toJS
          : "rgba(255, 255, 255, 0.22)".toJS;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, baseR * 1.32, a0, a1);
      ctx.closePath();
      ctx.fill();
    }
    ctx.restore();

    // Spinning cartoon target crosshair ring!
    ctx.save();
    ctx.rotate(-_time * 0.55);
    final double ringPulse = 1.0 + sin(_time * 3.0) * 0.04;
    final double ringR = baseR * 0.94 * ringPulse;
    ctx.strokeStyle = "rgba(255, 76, 68, 0.85)".toJS;
    ctx.lineWidth = 5.0 * scale;
    ctx.lineCap = "round";
    for (int q = 0; q < 4; q++) {
      final double start = q * pi * 0.5 + 0.22;
      final double end = (q + 1) * pi * 0.5 - 0.22;
      ctx.beginPath();
      ctx.arc(0, 0, ringR, start, end);
      ctx.stroke();
    }
    // Crisp white inner target ticks at 4 cardinal points.
    for (int q = 0; q < 4; q++) {
      ctx.save();
      ctx.rotate(q * pi * 0.5);
      ctx.fillStyle = "#ffffff".toJS;
      ctx.strokeStyle = "#162436".toJS;
      ctx.lineWidth = 2.0 * scale;
      ctx.beginPath();
      ctx.roundRect(ringR - 14 * scale, -4 * scale, 28 * scale, 8 * scale, (4 * scale).toJS);
      ctx.fill();
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();

    // Back-half of orbiting colorful cartoon projectiles.
    _drawOrbitProjectiles(ctx, baseR, scale, frontHalf: false);

    // Centerpiece: Sizzling Cartoon Bomb!
    final double beat = sin(_time * 4.4);
    final double squashX = 1.0 + beat * 0.055;
    final double squashY = 1.0 - beat * 0.055;
    final double bombR = 36.0 * scale;

    ctx.save();
    ctx.translate(0, sin(_time * 2.2) * 5.0 * scale);
    ctx.scale(squashX, squashY);

    // Metallic fuse collar.
    ctx.fillStyle = "#8a99ad".toJS;
    ctx.strokeStyle = "#121c29".toJS;
    ctx.lineWidth = 3.0 * scale;
    ctx.beginPath();
    ctx.roundRect(-10 * scale, -bombR - 7 * scale, 20 * scale, 12 * scale, (3 * scale).toJS);
    ctx.fill();
    ctx.stroke();

    // Curling cartoon fuse rope.
    ctx.strokeStyle = "#d9b477".toJS;
    ctx.lineWidth = 4.6 * scale;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(0, -bombR - 6 * scale);
    ctx.quadraticCurveTo(
      14 * scale,
      -bombR - 26 * scale,
      (24.0 + cos(_time * 9.0) * 3.0) * scale,
      (-46.0 + sin(_time * 11.0) * 2.0) * scale,
    );
    ctx.stroke();

    // Glossy cartoon round bomb body.
    final CanvasGradient bombGrad = ctx.createRadialGradient(
      -bombR * 0.34,
      -bombR * 0.34,
      3 * scale,
      0,
      0,
      bombR,
    );
    bombGrad.addColorStop(0.0, "#5c6f8a");
    bombGrad.addColorStop(0.45, "#283548");
    bombGrad.addColorStop(1.0, "#121a26");
    ctx.fillStyle = bombGrad;
    ctx.strokeStyle = "#0a101a".toJS;
    ctx.lineWidth = 3.8 * scale;
    ctx.beginPath();
    ctx.arc(0, 0, bombR, 0, 2 * pi);
    ctx.fill();
    ctx.stroke();

    // Big glossy cartoon highlight crescent.
    ctx.fillStyle = "rgba(255, 255, 255, 0.38)".toJS;
    ctx.beginPath();
    ctx.ellipse(-bombR * 0.34, -bombR * 0.30, bombR * 0.24, bombR * 0.13, -0.65, 0, 2 * pi);
    ctx.fill();

    // Playful painted yellow cartoon skull/star emblem on bomb belly.
    _drawMultiStar(ctx, 2 * scale, 4 * scale, 14 * scale, 5,
        color: "#ffe054", alpha: 0.95, rotation: -pi * 0.1);

    // Crackling fuse tip spark star!
    final double sx = (24.0 + cos(_time * 9.0) * 3.0) * scale;
    final double sy = (-46.0 + sin(_time * 11.0) * 2.0) * scale;
    final double sparkScale = 1.0 + sin(_time * 28.0) * 0.28;
    _drawMultiStar(ctx, sx, sy, 15.0 * scale * sparkScale, 8,
        color: "#ff7e29", alpha: 0.95, rotation: _time * 6.0);
    _drawMultiStar(ctx, sx, sy, 9.0 * scale * sparkScale, 8,
        color: "#fff8a6", alpha: 1.0, rotation: -_time * 9.0);

    ctx.restore();

    // Front-half of orbiting colorful cartoon projectiles.
    _drawOrbitProjectiles(ctx, baseR, scale, frontHalf: true);

    ctx.restore();
  }

  void _drawOrbitProjectiles(
    CanvasRenderingContext2D ctx,
    double baseR,
    double scale, {
    required bool frontHalf,
  }) {
    for (final _OrbitProjectile p in _orbitProjectiles) {
      final double depth = sin(p.angle);
      if (frontHalf ? depth < 0 : depth >= 0) continue;

      final double tilt = p.tilt + sin(_time * 0.45 + p.index) * 0.12;
      final double rx = baseR * p.radiusFactor;
      final double ry = rx * 0.38;

      ctx.save();
      ctx.rotate(tilt);

      // Puffy white/tinted comic trail.
      const int tailSteps = 6;
      for (int t = tailSteps; t >= 1; t--) {
        final double ta = p.angle - t * 0.12 * (p.speed > 0 ? 1 : -1);
        final double tx = cos(ta) * rx;
        final double ty = sin(ta) * ry;
        final double frac = 1.0 - (t / (tailSteps + 1));
        ctx.fillStyle = "rgba(255, 255, 255, ${frac * 0.68})".toJS;
        ctx.beginPath();
        ctx.arc(tx, ty, (2.6 + 3.2 * frac) * scale, 0, 2 * pi);
        ctx.fill();
      }

      // Glossy jellybean / rocket orb head with cartoon ink outline.
      final double hx = cos(p.angle) * rx;
      final double hy = sin(p.angle) * ry;
      final double headR = (6.8 + 2.6 * ((depth + 1) * 0.5)) * scale;
      ctx.fillStyle = p.color.toJS;
      ctx.strokeStyle = "#142030".toJS;
      ctx.lineWidth = 2.0 * scale;
      ctx.beginPath();
      ctx.arc(hx, hy, headR, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();

      // Glossy specular dot.
      ctx.fillStyle = "rgba(255, 255, 255, 0.85)".toJS;
      ctx.beginPath();
      ctx.arc(hx - headR * 0.3, hy - headR * 0.3, headR * 0.3, 0, 2 * pi);
      ctx.fill();

      ctx.restore();
    }
  }

  /// Phase 2 (`shark.png` loaded!): The Sunglasses Shark leaps out of the
  /// bottom waterline into the sunny sky with comic sunburst rays & an aerial
  /// mini-shark squadron!
  void _drawSkySharkSpectacle(
    CanvasRenderingContext2D ctx,
    double cx,
    double cy,
    double h,
    double scale,
    HTMLImageElement sharkImage,
  ) {
    final double frameW = _sharkFrameWidth(sharkImage);
    final double aspect = sharkImage.height / frameW;
    final double revealEase = _easeOutBack(_sharkReveal);
    // Leap arc: rises smoothly from the bottom waterline up to sky center!
    final double leapOffsetY = (1.0 - _easeOutCubic(_sharkReveal)) * (h * 0.52);
    final double orbitRx = 188.0 * scale * revealEase.clamp(0.2, 1.15);
    final double orbitRy = 74.0 * scale * revealEase.clamp(0.2, 1.15);

    ctx.save();
    ctx.translate(cx, cy + leapOffsetY);

    // 1. Punchy golden-white comic-book sunburst rays behind the sky-shark!
    _drawSharkSunburst(ctx, scale * revealEase);

    // 2. Back half of the 3D orbital mini-shark aerial squadron.
    _drawMiniSharkSquadron(
      ctx,
      sharkImage,
      aspect,
      orbitRx,
      orbitRy,
      scale,
      frontHalf: false,
    );

    // 3. Hero Boss Sunglasses Shark cruising the sunny sky!
    _drawHeroShark(ctx, sharkImage, aspect, scale, revealEase);

    // 4. Front half of the 3D orbital mini-shark aerial squadron.
    _drawMiniSharkSquadron(
      ctx,
      sharkImage,
      aspect,
      orbitRx,
      orbitRy,
      scale,
      frontHalf: true,
    );

    ctx.restore();
  }

  void _drawSharkSunburst(CanvasRenderingContext2D ctx, double scale) {
    ctx.save();
    final double outerR = 178.0 * scale;
    const int rayCount = 14;
    ctx.rotate(_time * 0.28);

    for (int i = 0; i < rayCount; i++) {
      final double a0 = (i / rayCount) * 2 * pi;
      final double a1 = a0 + (pi / rayCount) * 0.72;
      final double pulse = sin(_time * 2.4 + i * 0.9) * 0.5 + 0.5;
      final CanvasGradient rayGrad =
          ctx.createRadialGradient(0, 0, 18 * scale, 0, 0, outerR);
      if (i.isEven) {
        rayGrad.addColorStop(0.0, "rgba(255, 224, 72, ${0.55 + pulse * 0.16})");
        rayGrad.addColorStop(0.65, "rgba(255, 240, 145, 0.20)");
        rayGrad.addColorStop(1.0, "rgba(255, 240, 145, 0.0)");
      } else {
        rayGrad.addColorStop(0.0, "rgba(255, 255, 255, ${0.46 + pulse * 0.14})");
        rayGrad.addColorStop(0.65, "rgba(255, 255, 255, 0.14)");
        rayGrad.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
      }
      ctx.fillStyle = rayGrad;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, outerR * (0.9 + pulse * 0.14), a0, a1);
      ctx.closePath();
      ctx.fill();
    }

    ctx.restore();
  }

  void _drawHeroShark(
    CanvasRenderingContext2D ctx,
    HTMLImageElement sharkImage,
    double aspect,
    double scale,
    double revealScale,
  ) {
    final double bobX = sin(_time * 1.45) * 14.0 * scale;
    final double bobY = sin(_time * 2.9) * 11.0 * scale;
    final double pitch = cos(_time * 2.9) * 0.09;
    final double swaggerPulse = 1.0 + sin(_time * 5.8) * 0.028;

    // Celebratory 360-degree barrel-roll flourish every ~6s.
    double spinAngle = 0.0;
    double flourishScale = 1.0;
    if (_flourishProgress < 1.0) {
      final double eased = _easeInOutCubic(_flourishProgress);
      spinAngle = eased * 2 * pi;
      flourishScale = 1.0 + sin(_flourishProgress * pi) * 0.18;
    }

    final double heroW = 196.0 * scale * revealScale * flourishScale;
    final double heroH = heroW * aspect;

    ctx.save();
    ctx.translate(bobX, bobY);

    // Fluffy cartoon sky-contrail puffs trailing behind the hero shark's tail!
    for (int i = 0; i < 6; i++) {
      final double phase = (_time * 2.1 + i * 0.42) % 1.0;
      final double bx = -heroW * 0.46 - phase * 72.0 * scale;
      final double by = heroH * 0.05 +
          sin(_time * 5.0 + i * 1.7) * 8.0 * scale -
          phase * 14.0 * scale;
      final double br = (4.0 + (1.0 - phase) * 8.0) * scale;
      ctx.fillStyle = "rgba(255, 255, 255, ${(1.0 - phase) * 0.72})".toJS;
      ctx.beginPath();
      ctx.arc(bx, by, br, 0, 2 * pi);
      ctx.fill();
    }

    ctx.rotate(pitch + spinAngle);
    ctx.scale(-swaggerPulse, 2.0 - swaggerPulse); // Face right + squash/stretch

    // Warm sunny glow behind shark so he pops dramatically off the sky.
    final CanvasGradient underGlow =
        ctx.createRadialGradient(0, 4 * scale, 10, 0, 4 * scale, heroW * 0.58);
    underGlow.addColorStop(0.0, "rgba(255, 245, 150, 0.58)");
    underGlow.addColorStop(0.55, "rgba(255, 255, 255, 0.25)");
    underGlow.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
    ctx.fillStyle = underGlow;
    ctx.beginPath();
    ctx.ellipse(0, 6 * scale, heroW * 0.58, heroH * 0.56, 0, 0, 2 * pi);
    ctx.fill();

    // Draw the sunglasses shark (frame 0 of spritesheet)!
    final double srcW = _sharkFrameWidth(sharkImage);
    ctx.drawImage(sharkImage, 0, 0, srcW, sharkImage.height,
        -heroW * 0.5, -heroH * 0.5, heroW, heroH);

    // Periodic comic star glint sweeping across his sunglasses!
    final double glintCycle = _time % 2.8;
    if (glintCycle < 0.75) {
      final double t = glintCycle / 0.75;
      final double glintAlpha = sin(t * pi);
      final double gx = -heroW * (0.31 - t * 0.17);
      final double gy = -heroH * 0.19;
      _drawFourPointStar(
        ctx,
        gx,
        gy,
        (13.0 + 7.5 * glintAlpha) * scale,
        rotation: t * pi * 0.7,
        alpha: glintAlpha,
        color: "#ffffff",
      );
    }

    ctx.restore();
  }

  void _drawMiniSharkSquadron(
    CanvasRenderingContext2D ctx,
    HTMLImageElement sharkImage,
    double aspect,
    double orbitRx,
    double orbitRy,
    double scale, {
    required bool frontHalf,
  }) {
    final List<_MiniShark> visible = [];
    for (final _MiniShark s in _miniSharks) {
      final double depth = sin(s.angle);
      if (frontHalf ? depth >= 0 : depth < 0) {
        visible.add(s);
      }
    }
    visible.sort((a, b) => sin(a.angle).compareTo(sin(b.angle)));

    for (final _MiniShark s in visible) {
      final double depth = sin(s.angle);
      final double depthNorm = (depth + 1.0) * 0.5;
      final double waveY =
          sin(s.angle * 2.0 + _time * 2.2 + s.index) * 14.0 * scale;
      final double x = cos(s.angle) * orbitRx * s.orbitScale;
      final double y = depth * orbitRy * s.orbitScale + waveY;

      final double vx = -sin(s.angle) * s.speed;
      final double vy = cos(s.angle) * orbitRy / max(1.0, orbitRx) * s.speed;
      final bool facingRight = vx >= 0;

      final double miniW = (44.0 + depthNorm * 30.0) * scale;
      final double miniH = miniW * aspect;
      final double alpha = (0.64 + depthNorm * 0.36) * _sharkReveal;

      ctx.save();
      ctx.globalAlpha = ctx.globalAlpha * alpha.clamp(0.0, 1.0);
      ctx.translate(x, y);

      // Cute white cloud-puff contrails behind each flying mini shark.
      final double trailDir = facingRight ? -1.0 : 1.0;
      for (int b = 1; b <= 2; b++) {
        ctx.fillStyle = "rgba(255, 255, 255, ${0.72 / b})".toJS;
        ctx.beginPath();
        ctx.arc(
          trailDir * (miniW * 0.48 + b * 10.0 * scale),
          sin(_time * 8.0 + s.index + b) * 3.0 * scale,
          (4.0 - b * 0.9) * scale * (0.65 + depthNorm * 0.4),
          0,
          2 * pi,
        );
        ctx.fill();
      }

      final double tilt = (vy / (vx.abs() + 0.35)).clamp(-0.32, 0.32);
      ctx.rotate(tilt);
      if (facingRight) {
        ctx.scale(-1, 1);
      }
      final double srcW = _sharkFrameWidth(sharkImage);
      ctx.drawImage(sharkImage, 0, 0, srcW, sharkImage.height,
          -miniW * 0.5, -miniH * 0.5, miniW, miniH);
      ctx.restore();
    }
  }

  static double _sharkFrameWidth(HTMLImageElement img) {
    if (img.width >= img.height * 4) {
      return img.width / 5.0;
    }
    if (img.width >= img.height * 3) {
      return img.width / 4.0;
    }
    return img.width.toDouble();
  }

  /// Foreground Worms-style grassy island + thin turquoise rising-water strip
  /// at the very bottom!
  void _drawForegroundIslandAndWater(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    double scale, {
    required bool showProwlingFin,
  }) {
    final double waterTopY = h * 0.925;
    final double islandLeft = w * 0.06;
    final double islandRight = w * 0.94;
    final double islandWidth = islandRight - islandLeft;
    final double ridgeY = h * 0.855;

    // 1. Back turquoise water strip behind island edges.
    _drawWaveLayer(
      ctx,
      w,
      h,
      baseY: waterTopY - 6.0 * scale,
      amp: 5.0 * scale,
      freq: 0.015 / scale,
      speed: 1.5,
      fill: "rgba(32, 186, 232, 0.72)",
      crest: "rgba(255, 255, 255, 0.55)",
    );

    // 2. Chunky Worms-style cartoon earth & grass island!
    ctx.save();
    final CanvasGradient dirtGrad =
        ctx.createLinearGradient(0, ridgeY, 0, h);
    dirtGrad.addColorStop(0.0, "#b57c4b");
    dirtGrad.addColorStop(0.55, "#8f5b34");
    dirtGrad.addColorStop(1.0, "#663e22");
    ctx.fillStyle = dirtGrad;
    ctx.strokeStyle = "#3a2212".toJS;
    ctx.lineWidth = 3.2 * scale;

    ctx.beginPath();
    ctx.moveTo(islandLeft, h);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.03, ridgeY + 6 * scale, islandLeft + islandWidth * 0.12, ridgeY - 4 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.28, ridgeY - 22 * scale, islandLeft + islandWidth * 0.44, ridgeY - 6 * scale);
    // Cute little cartoon crater dip in the center-left ridge!
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.50, ridgeY + 6 * scale, islandLeft + islandWidth * 0.56, ridgeY - 6 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.74, ridgeY - 24 * scale, islandLeft + islandWidth * 0.89, ridgeY - 4 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.97, ridgeY + 6 * scale, islandRight, h);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Decorative cartoon pebbles / bedrock chunks inside the island earth.
    ctx.fillStyle = "rgba(74, 42, 22, 0.35)".toJS;
    for (int i = 0; i < 9; i++) {
      final double rx = islandLeft + islandWidth * (0.12 + i * 0.095);
      final double ry = ridgeY + (18.0 + (i % 3) * 11.0) * scale;
      ctx.beginPath();
      ctx.ellipse(rx, ry, (11.0 + (i % 2) * 6.0) * scale, (6.0 + (i % 3) * 2.5) * scale, 0.1 * i, 0, 2 * pi);
      ctx.fill();
    }

    // Lush bright green cartoon grass cap hugging the island ridge.
    final CanvasGradient grassGrad =
        ctx.createLinearGradient(0, ridgeY - 24 * scale, 0, ridgeY + 18 * scale);
    grassGrad.addColorStop(0.0, "#8cf25c");
    grassGrad.addColorStop(0.6, "#4ec940");
    grassGrad.addColorStop(1.0, "#2f992c");
    ctx.fillStyle = grassGrad;
    ctx.strokeStyle = "#1d571e".toJS;
    ctx.lineWidth = 2.8 * scale;

    ctx.beginPath();
    ctx.moveTo(islandLeft + islandWidth * 0.04, ridgeY + 14 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.05, ridgeY - 2 * scale, islandLeft + islandWidth * 0.12, ridgeY - 6 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.28, ridgeY - 24 * scale, islandLeft + islandWidth * 0.44, ridgeY - 8 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.50, ridgeY + 4 * scale, islandLeft + islandWidth * 0.56, ridgeY - 8 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.74, ridgeY - 26 * scale, islandLeft + islandWidth * 0.89, ridgeY - 6 * scale);
    ctx.quadraticCurveTo(
        islandLeft + islandWidth * 0.95, ridgeY - 2 * scale, islandLeft + islandWidth * 0.96, ridgeY + 14 * scale);
    // Scalloped grass bottom lip hanging over the dirt.
    for (int i = 10; i >= 0; i--) {
      final double gx = islandLeft + islandWidth * (0.04 + (i / 10.0) * 0.92);
      final double gy = ridgeY + (i.isEven ? 16.0 : 8.0) * scale;
      ctx.lineTo(gx, gy);
    }
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Cute cartoon props perched on the left & right hills (out of center banner's way).
    _drawCartoonPalm(ctx, islandLeft + islandWidth * 0.11, ridgeY - 7 * scale, 0.92 * scale);
    _drawCartoonPine(ctx, islandLeft + islandWidth * 0.86, ridgeY - 9 * scale, 0.95 * scale);
    _drawCartoonPine(ctx, islandLeft + islandWidth * 0.91, ridgeY - 4 * scale, 0.68 * scale);
    _drawWavingFlag(ctx, islandLeft + islandWidth * 0.22, ridgeY - 14 * scale, scale);

    ctx.restore();

    // 3. Prowling cartoon shark fin cruising the bottom waterline before shark leaps!
    if (showProwlingFin) {
      final double finFade = (1.0 - _sharkReveal * 1.4).clamp(0.0, 1.0);
      if (finFade > 0.02) {
        _drawProwlingSharkFin(ctx, w, waterTopY + 5 * scale, scale, finFade);
      }
    }

    // 4. Foreground sparkling Worms turquoise waterline!
    _drawWaveLayer(
      ctx,
      w,
      h,
      baseY: waterTopY + 4.0 * scale,
      amp: 5.5 * scale,
      freq: 0.018 / scale,
      speed: -2.4,
      fill: "rgba(18, 162, 224, 0.88)",
      crest: "rgba(255, 255, 255, 0.82)",
    );
  }

  void _drawCartoonPalm(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    final double sway = sin(_time * 1.8 + x * 0.02) * 5.0 * s;
    ctx.save();
    ctx.translate(x, y);

    // Curved cartoon palm trunk.
    ctx.strokeStyle = "#8a5a30".toJS;
    ctx.lineWidth = 7.0 * s;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.quadraticCurveTo(-8 * s + sway * 0.4, -22 * s, 4 * s + sway, -44 * s);
    ctx.stroke();

    // Palm fronds.
    final double topX = 4 * s + sway;
    final double topY = -44 * s;
    ctx.translate(topX, topY);
    const List<double> angles = [-2.5, -1.7, -0.7, 0.1, 0.8];
    for (final double a in angles) {
      ctx.save();
      ctx.rotate(a + sway * 0.01);
      ctx.fillStyle = "#48cc44".toJS;
      ctx.strokeStyle = "#1d571e".toJS;
      ctx.lineWidth = 1.8 * s;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.quadraticCurveTo(14 * s, -9 * s, 26 * s, 3 * s);
      ctx.quadraticCurveTo(13 * s, 3 * s, 0, 0);
      ctx.fill();
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();
  }

  void _drawCartoonPine(
      CanvasRenderingContext2D ctx, double x, double y, double s) {
    final double sway = sin(_time * 1.5 + x * 0.03) * 2.5 * s;
    ctx.save();
    ctx.translate(x, y);

    // Trunk.
    ctx.fillStyle = "#7a4d28".toJS;
    ctx.fillRect(-3.5 * s, -12 * s, 7 * s, 14 * s);

    // 3 stacked cartoon triangles.
    for (int tier = 0; tier < 3; tier++) {
      final double ty = (-12 - tier * 11) * s;
      final double tw = (18 - tier * 3.5) * s;
      final double th = (17 - tier * 1.5) * s;
      ctx.fillStyle = (tier.isEven ? "#3bbf47" : "#56db59").toJS;
      ctx.strokeStyle = "#1b5420".toJS;
      ctx.lineWidth = 2.0 * s;
      ctx.beginPath();
      ctx.moveTo(sway * (tier + 1) * 0.35, ty - th);
      ctx.lineTo(-tw, ty);
      ctx.lineTo(tw, ty);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  void _drawWavingFlag(
      CanvasRenderingContext2D ctx, double x, double y, double scale) {
    ctx.save();
    ctx.translate(x, y);

    // Pole.
    ctx.strokeStyle = "#2b3848".toJS;
    ctx.lineWidth = 3.0 * scale;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(0, -34 * scale);
    ctx.stroke();

    // Fluttering coral-red cartoon pennant!
    final double flutter = sin(_time * 6.5) * 4.0 * scale;
    ctx.fillStyle = "#ff5252".toJS;
    ctx.strokeStyle = "#1c2430".toJS;
    ctx.lineWidth = 2.0 * scale;
    ctx.beginPath();
    ctx.moveTo(0, -33 * scale);
    ctx.quadraticCurveTo(12 * scale, -35 * scale + flutter, 24 * scale, -27 * scale - flutter * 0.6);
    ctx.quadraticCurveTo(12 * scale, -21 * scale + flutter, 0, -21 * scale);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  void _drawProwlingSharkFin(CanvasRenderingContext2D ctx, double w,
      double waterY, double scale, double alpha) {
    final double cycle = (_time * 0.14) % 1.0;
    final double finX = -70.0 * scale + cycle * (w + 140.0 * scale);
    final double waveY =
        waterY + sin(finX * (0.018 / scale) - _time * 2.4) * 4.5 * scale;
    final double finH = 30.0 * scale;
    final double finW = 34.0 * scale;

    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.translate(finX, waveY);
    ctx.rotate(cos(finX * (0.018 / scale) - _time * 2.4) * 0.10);

    // Shark dorsal fin matching shark.png's blue-grey coat.
    ctx.fillStyle = "#5c8fc2".toJS;
    ctx.strokeStyle = "#102840".toJS;
    ctx.lineWidth = 2.4 * scale;
    ctx.beginPath();
    ctx.moveTo(-finW * 0.55, 8.0 * scale);
    ctx.quadraticCurveTo(-finW * 0.12, -finH * 0.92, finW * 0.42, -finH * 0.88);
    ctx.quadraticCurveTo(finW * 0.08, -finH * 0.2, finW * 0.35, 8.0 * scale);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Foamy white wake ripples behind fin.
    for (int i = 0; i < 3; i++) {
      final double wakeX = -finW * 0.65 - i * 14.0 * scale;
      final double wakeW = (9.0 - i * 2.0) * scale;
      ctx.strokeStyle = "rgba(255, 255, 255, ${0.88 - i * 0.22})".toJS;
      ctx.lineWidth = 2.2 * scale;
      ctx.beginPath();
      ctx.moveTo(wakeX - wakeW, 4.0 * scale);
      ctx.lineTo(wakeX + wakeW, 4.0 * scale);
      ctx.stroke();
    }
    ctx.restore();
  }

  void _drawWaveLayer(
    CanvasRenderingContext2D ctx,
    double w,
    double h, {
    required double baseY,
    required double amp,
    required double freq,
    required double speed,
    required String fill,
    required String crest,
  }) {
    const int steps = 48;
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(0, h);
    for (int i = 0; i <= steps; i++) {
      final double x = (i / steps) * w;
      final double y = baseY +
          sin(x * freq + _time * speed) * amp +
          cos(x * freq * 1.8 - _time * speed * 0.7) * amp * 0.32;
      ctx.lineTo(x, y);
    }
    ctx.lineTo(w, h);
    ctx.closePath();
    ctx.fillStyle = fill.toJS;
    ctx.fill();

    // Crisp cartoon foam crest line.
    ctx.beginPath();
    for (int i = 0; i <= steps; i++) {
      final double x = (i / steps) * w;
      final double y = baseY +
          sin(x * freq + _time * speed) * amp +
          cos(x * freq * 1.8 - _time * speed * 0.7) * amp * 0.32;
      if (i == 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.strokeStyle = crest.toJS;
    ctx.lineWidth = 2.6;
    ctx.stroke();
    ctx.restore();
  }

  void _drawSplashDrops(
      CanvasRenderingContext2D ctx, double cx, double baseY, double scale) {
    if (_splashDrops.isEmpty) return;
    ctx.save();
    ctx.translate(cx, baseY);
    for (final _SplashDrop d in _splashDrops) {
      final double alpha = (d.life / d.maxLife).clamp(0.0, 1.0);
      ctx.fillStyle = "rgba(225, 252, 255, ${alpha * 0.92})".toJS;
      ctx.strokeStyle = "rgba(32, 168, 224, ${alpha * 0.75})".toJS;
      ctx.lineWidth = 1.5 * scale;
      ctx.beginPath();
      ctx.arc(d.x * scale, d.y * scale, d.radius * scale, 0, 2 * pi);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }

  void _drawShockwavesAndSparkles(
      CanvasRenderingContext2D ctx, double cx, double cy, double scale) {
    ctx.save();
    ctx.translate(cx, cy);

    for (final _Shockwave sw in _shockwaves) {
      final double p = _easeOutCubic(sw.progress);
      final double r = (24.0 + p * sw.maxRadius) * scale;
      final double alpha = (1.0 - sw.progress) * 0.72;
      ctx.strokeStyle = "rgba(${sw.color}, $alpha)".toJS;
      ctx.lineWidth = (4.8 * (1.0 - sw.progress) + 1.2) * scale;
      ctx.beginPath();
      ctx.arc(0, 0, r, 0, 2 * pi);
      ctx.stroke();
    }

    for (final _Sparkle sp in _sparkles) {
      final double alpha = (sp.life / sp.maxLife).clamp(0.0, 1.0);
      _drawFourPointStar(
        ctx,
        sp.x * scale,
        sp.y * scale,
        sp.size * scale * (0.5 + alpha * 0.7),
        rotation: _time * 3.5,
        alpha: alpha,
        color: sp.gold ? "#ffe44d" : "#ffffff",
      );
    }

    ctx.restore();
  }

  void _drawFourPointStar(
    CanvasRenderingContext2D ctx,
    double x,
    double y,
    double size, {
    required double rotation,
    required double alpha,
    required String color,
  }) {
    _drawMultiStar(ctx, x, y, size, 4,
        color: color, alpha: alpha, rotation: rotation);
  }

  void _drawMultiStar(
    CanvasRenderingContext2D ctx,
    double x,
    double y,
    double outerR,
    int points, {
    required String color,
    required double alpha,
    required double rotation,
  }) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(rotation);
    ctx.globalAlpha = ctx.globalAlpha * alpha.clamp(0.0, 1.0);
    ctx.fillStyle = color.toJS;
    ctx.beginPath();
    final double innerR = outerR * 0.32;
    final int total = points * 2;
    for (int i = 0; i < total; i++) {
      final double a = (i * pi) / points;
      final double r = i.isEven ? outerR : innerR;
      final double px = cos(a) * r;
      final double py = sin(a) * r;
      if (i == 0) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  void _drawStatusBanner(
    CanvasRenderingContext2D ctx,
    double w,
    double h,
    double scale,
    String message,
    double? progress,
    bool isError,
  ) {
    final double fontSize = (20.0 * scale).clamp(14.0, 24.0);
    final double tipFontSize = (14.0 * scale).clamp(11.5, 16.5);
    final double centerX = w * 0.5;
    final double bannerY = h * 0.70;

    ctx.save();
    ctx.font =
        "800 ${fontSize.round()}px 'Comic Sans MS', 'Trebuchet MS', Arial, sans-serif";
    final double textW = ctx.measureText(message).width.toDouble();
    final double barW = max(260.0 * scale, min(w * 0.76, textW + 76.0 * scale));
    final double pillW =
        max(barW, textW + 64.0 * scale).clamp(240.0 * scale, w * 0.88);
    final double pillH = (progress != null ? 72.0 : 66.0) * scale;
    final double pillX = centerX - pillW * 0.5;
    final double pillY = bannerY - pillH * 0.5;
    final double radius = 20.0 * scale;

    // Soft cartoon drop shadow.
    ctx.fillStyle = "rgba(18, 42, 72, 0.34)".toJS;
    ctx.beginPath();
    ctx.roundRect(
        pillX + 4 * scale, pillY + 6 * scale, pillW, pillH, radius.toJS);
    ctx.fill();

    // Cheerful vibrant cobalt cartoon pill body.
    final CanvasGradient pillGrad =
        ctx.createLinearGradient(0, pillY, 0, pillY + pillH);
    if (isError) {
      pillGrad.addColorStop(0.0, "rgba(218, 52, 72, 0.96)");
      pillGrad.addColorStop(1.0, "rgba(154, 24, 44, 0.98)");
    } else {
      pillGrad.addColorStop(0.0, "rgba(32, 118, 206, 0.94)");
      pillGrad.addColorStop(1.0, "rgba(18, 76, 152, 0.96)");
    }
    ctx.fillStyle = pillGrad;
    ctx.beginPath();
    ctx.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    ctx.fill();

    // Glossy top cartoon shine strip.
    ctx.fillStyle = "rgba(255, 255, 255, 0.20)".toJS;
    ctx.beginPath();
    ctx.roundRect(pillX + 7 * scale, pillY + 4 * scale, pillW - 14 * scale,
        pillH * 0.36, (radius * 0.6).toJS);
    ctx.fill();

    // Bold cartoon ink outline + sunny golden-yellow inner trim!
    ctx.strokeStyle = "#102845".toJS;
    ctx.lineWidth = 4.4 * scale;
    ctx.beginPath();
    ctx.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    ctx.stroke();

    ctx.strokeStyle = (isError ? "#ffd4a8" : "#ffe054").toJS;
    ctx.lineWidth = 2.4 * scale;
    ctx.beginPath();
    ctx.roundRect(pillX + 2.0 * scale, pillY + 2.0 * scale, pillW - 4 * scale,
        pillH - 4 * scale, (radius - 2.0 * scale).toJS);
    ctx.stroke();

    // Status message text (crisp white with dark comic outline).
    final double textY = pillY + 29.0 * scale;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineJoin = "round";
    ctx.lineWidth = 4.2 * scale;
    ctx.strokeStyle = "#102845".toJS;
    ctx.strokeText(message, centerX, textY);
    ctx.fillStyle = "#ffffff".toJS;
    ctx.fillText(message, centerX, textY);

    // Candy-bright progress bar track.
    final double trackW = pillW - 44.0 * scale;
    final double trackH = 12.5 * scale;
    final double trackX = centerX - trackW * 0.5;
    final double trackY = pillY + pillH - 22.0 * scale;
    final double trackR = trackH * 0.5;

    ctx.fillStyle = "rgba(10, 34, 68, 0.72)".toJS;
    ctx.beginPath();
    ctx.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
    ctx.fill();

    ctx.save();
    ctx.beginPath();
    ctx.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
    ctx.clip();

    if (progress != null) {
      final double clamped = progress.clamp(0.0, 1.0);
      final double fillW = max(trackH, trackW * clamped);
      final CanvasGradient fillGrad =
          ctx.createLinearGradient(trackX, 0, trackX + trackW, 0);
      fillGrad.addColorStop(0.0, "#47f0ff");
      fillGrad.addColorStop(0.5, "#6dff8f");
      fillGrad.addColorStop(1.0, "#ffe44d");
      ctx.fillStyle = fillGrad;
      ctx.fillRect(trackX, trackY, fillW, trackH);

      // Moving glossy comic sheen across the progress bar.
      final double sheenX = trackX +
          ((_time * 160.0 * scale) % (trackW + 80.0 * scale)) -
          40.0 * scale;
      final CanvasGradient sheen = ctx.createLinearGradient(
          sheenX - 24 * scale, 0, sheenX + 24 * scale, 0);
      sheen.addColorStop(0.0, "rgba(255, 255, 255, 0.0)");
      sheen.addColorStop(0.5, "rgba(255, 255, 255, 0.65)");
      sheen.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
      ctx.fillStyle = sheen;
      ctx.fillRect(trackX, trackY, fillW, trackH);
    } else if (!isError) {
      // Indeterminate gliding sunny pulse.
      final double pulseW = trackW * 0.36;
      final double travel = trackW + pulseW;
      final double px = trackX + ((_time * 0.65 * travel) % travel) - pulseW;
      final CanvasGradient indGrad =
          ctx.createLinearGradient(px, 0, px + pulseW, 0);
      indGrad.addColorStop(0.0, "rgba(109, 255, 143, 0.0)");
      indGrad.addColorStop(0.35, "#6dff9e");
      indGrad.addColorStop(0.65, "#ffe44d");
      indGrad.addColorStop(1.0, "rgba(255, 228, 77, 0.0)");
      ctx.fillStyle = indGrad;
      ctx.fillRect(px, trackY, pulseW, trackH);
    }
    ctx.restore();

    // Track rim.
    ctx.strokeStyle = "rgba(255, 255, 255, 0.45)".toJS;
    ctx.lineWidth = 1.5 * scale;
    ctx.beginPath();
    ctx.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
    ctx.stroke();

    // Rotating witty sub-tip underneath the banner.
    if (!isError) {
      const double tipPeriod = 4.6;
      final int tipIdx = (_time / tipPeriod).floor() % _LOADING_TIPS.length;
      final double localT = (_time % tipPeriod) / tipPeriod;
      double tipAlpha = 1.0;
      if (localT < 0.12) {
        tipAlpha = localT / 0.12;
      } else if (localT > 0.88) {
        tipAlpha = (1.0 - localT) / 0.12;
      }
      ctx.globalAlpha = tipAlpha * 0.96;
      ctx.font =
          "700 ${tipFontSize.round()}px 'Trebuchet MS', Arial, sans-serif";
      ctx.fillStyle = "#ffffff".toJS;
      ctx.strokeStyle = "#16355a".toJS;
      ctx.lineWidth = 3.8 * scale;
      final double tipY = pillY + pillH + 19.0 * scale;
      ctx.strokeText(_LOADING_TIPS[tipIdx], centerX, tipY);
      ctx.fillText(_LOADING_TIPS[tipIdx], centerX, tipY);
    }

    ctx.restore();
  }

  double _easeOutCubic(double t) {
    final double u = 1.0 - t.clamp(0.0, 1.0);
    return 1.0 - u * u * u;
  }

  double _easeInOutCubic(double t) {
    final double x = t.clamp(0.0, 1.0);
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2;
  }

  double _easeOutBack(double t) {
    final double x = t.clamp(0.0, 1.0);
    const double c1 = 1.70158;
    const double c3 = c1 + 1.0;
    return 1.0 + c3 * pow(x - 1.0, 3) + c1 * pow(x - 1.0, 2);
  }
}

class _Cloud {
  double x;
  double y;
  final double scale;
  final double speed;
  final bool isBack;
  final double seed;

  _Cloud.random(Random r, int index, int total)
      : x = (index / total) * 1.3 - 0.15 + r.nextDouble() * 0.12,
        y = 0.08 + r.nextDouble() * 0.34,
        scale = 0.65 + r.nextDouble() * 0.85,
        speed = 0.012 + r.nextDouble() * 0.022,
        isBack = index.isEven,
        seed = r.nextDouble() * 2 * pi;
}

class _SkyMote {
  double x;
  double y;
  final double vx;
  final double vy;
  final double radius;
  double phase;
  final double twinkleSpeed;
  final String rgb;

  _SkyMote.random(Random r)
      : x = r.nextDouble(),
        y = r.nextDouble() * 0.82,
        vx = 0.008 + r.nextDouble() * 0.02,
        vy = (r.nextDouble() - 0.5) * 0.012,
        radius = 1.6 + r.nextDouble() * 2.8,
        phase = r.nextDouble() * 2 * pi,
        twinkleSpeed = 1.5 + r.nextDouble() * 2.6,
        rgb = const [
          "255, 255, 255",
          "255, 244, 150",
          "210, 255, 224",
        ][r.nextInt(3)];
}

class _OrbitProjectile {
  final int index;
  double angle;
  final double speed;
  final double tilt;
  final double radiusFactor;
  final String color;

  _OrbitProjectile(this.index, int total)
      : angle = (index / total) * 2 * pi,
        speed = (index.isEven ? 1.0 : -1.0) * (1.35 + (index % 3) * 0.32),
        tilt = (index / total) * pi,
        radiusFactor = 0.96 + (index % 3) * 0.18,
        color = const [
          "#ff595e",
          "#ffca3a",
          "#8ac926",
          "#ff70a6",
          "#1982c4",
          "#ff924c",
        ][index % 6];
}

class _MiniShark {
  final int index;
  double angle;
  final double speed;
  final double orbitScale;

  _MiniShark(this.index, int total)
      : angle = (index / total) * 2 * pi,
        speed = 1.15 + (index % 2) * 0.28,
        orbitScale = 0.88 + (index % 3) * 0.14;
}

class _BgArtilleryShot {
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final double peakHeight;
  final double duration;
  final String accentColor;
  double t = 0.0;

  _BgArtilleryShot({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.peakHeight,
    required this.duration,
    required this.accentColor,
  });

  double xAt(double u) => startX + (endX - startX) * u;
  double yAt(double u) =>
      startY + (endY - startY) * u - sin(u * pi) * peakHeight;
}

class _BgExplosionPuff {
  final double x;
  final double y;
  final String color;
  final double maxAge;
  final int seed;
  double age = 0.0;

  _BgExplosionPuff({
    required this.x,
    required this.y,
    required this.color,
    required this.maxAge,
    required this.seed,
  });
}

class _Shockwave {
  final String color;
  final double maxRadius;
  double progress = 0.0;

  _Shockwave({required this.color, required this.maxRadius});
}

class _Sparkle {
  double x;
  double y;
  double vx;
  double vy;
  final double size;
  double life;
  final double maxLife;
  final bool gold;

  _Sparkle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.maxLife,
    required this.gold,
  });
}

class _SplashDrop {
  double x;
  double y;
  double vx;
  double vy;
  final double radius;
  double life;
  final double maxLife;

  _SplashDrop({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.life,
    required this.maxLife,
  });
}
