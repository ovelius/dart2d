import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:web/web.dart';
import 'package:dart2d/net/state_updates.pb.dart';

/**
 * Represents the destructable world.
 */
@Singleton(scope: 'world')
class ByteWorld {
  final Logger log = new Logger('ByteWorld');
  // Needs to create canvas.
  late CanvasFactory _canvasFactory;
  // Needs to create imageData.
  late ImageDataFactory _imageDataFactory;
  // Needs to create images.
  late ImageFactory _imageFactory;
  late int _width;
  late int _height;
  late Point<int> viewSize;
  // The main canvas object.
  late HTMLCanvasElement? canvas;
  // The part of the world the player can't destroy... if any.
  late HTMLImageElement _bedrockImage;
  // Temporary canvas storage.
  late HTMLCanvasElement _bedrocksCanvas;
  // x line for current bedrock computation.
  int _bedrockLine = -1;
  late Uint8List _collisionBuffer;

  ByteWorld(
      ImageFactory imageFactory,
      @Named(WORLD_WIDTH) int width, @Named(WORLD_HEIGHT) int height,
      ImageDataFactory imageDataFactory,
      CanvasFactory canvasFactory) {
    this.viewSize = new Point(width, height);
    this._canvasFactory = canvasFactory;
    this._imageDataFactory = imageDataFactory;
    this._imageFactory = imageFactory;
  }

  /**
   * Initialize the world image. If [bedrockCanvas] is supplied (e.g. from the
   * procedural world generator), uses it directly as the indestructible bedrock
   * layer instead of scanning for legacy RGB sentinel pixels.
   */
  void setWorldImage(HTMLImageElement image, {HTMLCanvasElement? bedrockCanvas}) {
    canvas = _canvasFactory.createCanvas(image.width, image.height);
    _width = canvas!.width;
    _height = canvas!.height;
    canvas!.context2D.drawImage(image, 0, 0, _width, _height);
    _bedrocksCanvas = _canvasFactory.createCanvas(_width, _height);
    _bedrockLine = 0;
    _collisionBuffer = new Uint8List(_width * _height);
    // Initialize buffer with current canvas alpha.
    Uint8ClampedList data = canvas!.context2D.getImageData(0, 0, _width, _height).data.toDart;
    for (int i = 0; i < _width * _height; i++) {
      _collisionBuffer[i] = data[i * 4 + 3] > 0 ? 1 : 0;
    }
    if (bedrockCanvas != null && _width > 0 && _height > 0) {
      _bedrocksCanvas.context2D.drawImage(bedrockCanvas, 0, 0, _width, _height);
      _bedrockLine = _width + 1;
      _finalizeBedrock();
    }
  }

  bool isSolid(int x, int y) {
    if (x < 0 || x >= _width || y < 0 || y >= _height) return false;
    return _collisionBuffer[y * _width + x] > 0;
  }
  bool worldImageSet() {
    return _bedrockLine >= 0;
  }
  void reset() {
    _bedrockLine = -1;
  }
  bool bedrockComputed() {
    return (_bedrockLine > _width);
  }

  bool byteWorldReady() {
    return worldImageSet() && bedrockComputed();
  }
  /**
   * calculate a single bedrock segment, or finish bedrock computation.
   */
  void bedrockStep() {
    assert(!bedrockComputed());
    int startX = min(_bedrockLine, _width);
    int computeWidth = min(startX + 1, _width) - startX;
    if (computeWidth > 0) {
      _computeBedrockSegment(startX, computeWidth, _bedrocksCanvas);
    }
    _bedrockLine++;
    if (_bedrockLine > _width) {
      _finalizeBedrock();
    }
  }

  /**
   * create the final bedrock image.
   */
  void _finalizeBedrock() {
    _bedrockImage = _imageFactory.createWithSize(_width, _height);
    _bedrockImage.src = _bedrocksCanvas.toDataUrl("png");
  }

  double percentComplete() => _bedrockLine / _width;


  /**
   * Some colors in the level image can't be destroyed, we find them and put them
   * in it's own image.
   */
  void _computeBedrockSegment(int startX, int computeWidth,
      HTMLCanvasElement bedrockCanvas) {
    Uint8ClampedList data = canvas!.context2D.getImageData(startX, 0, computeWidth, _height).data.toDart;
    ImageData newData = _imageDataFactory.createWithSize(computeWidth, _height);
    Uint8ClampedList newDataArr = newData.data.toDart;
    for (int i = 0; i < (data.length ~/ 4); i++) {
      int p = i * 4;
      // Brownish color.
      // #3b2e01
      if (data[p] == 59 && data[p + 1] == 46 && data[p + 2] == 1) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 255 && data[p + 1] == 145 && data[p + 2] == 34) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 231 && data[p + 1] == 3 && data[p + 2] == 30) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 254 && data[p + 1] == 201 && data[p + 2] == 89) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 254 && data[p + 1] == 201 && data[p + 2] == 89) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
      if (data[p] == 171 && data[p + 1] == 206 && data[p + 2] == 150) {
        newDataArr[p] = data[p];
        newDataArr[p + 1] = data[p + 1];
        newDataArr[p + 2] = data[p + 2];
        newDataArr[p + 3] = data[p + 3];
      }
    }
    bedrockCanvas.context2D.putImageData(newData, startX, 0);
  }

  Uint8ClampedList getImageData(Vec2 pos, Vec2 size) {
    return canvas!.context2D.getImageData(pos.x.toInt(), pos.y.toInt(), size.x.toInt(), size.y.toInt()).data.toDart;
  }

  Uint8ClampedList getImageDataFor(int x,y, w,h) {
    return canvas!.context2D.getImageData(x, y, w, h).data.toDart;
  }

  void drawAt(CanvasRenderingContext2D canvas, x, y) {
    canvas.drawImage(
       this.canvas!,
       x, y, // Source
       viewSize.x, viewSize.y, // width.
       0, 0, viewSize.x , viewSize.y);
  }
  
  void drawAsMiniMap(var canvas, x, y, [double wScale= 0.1, double hScale = 0.1]) {
    canvas.drawImage(
       this.canvas,
       0, 0, // Source
       _width, _height, // width.
       x, y, _width * wScale, _height * hScale);
  }

  /**
   * Check if any pixel inside area is solid.
   */
  bool isCanvasCollide(int x, int y, [int width = 1, int height = 1]) {
    Uint8ClampedList data = canvas!.context2D.getImageData(x, y, width, height).data.toDart;
    for (int i = 0; i < data.length / 4; i++) {
      // If transparency data is present, we are solid.
      if (data[i*4 + 3] > 0) {
        return true;
      }
    }
    return  false;
  }
  
  clearAtRect(int x, int y, int width, int height) {
    canvas!.context2D.clearRect(x, y, width, height);
  }
  
  String asDataUrl() {
    return canvas!.toDataUrl("image/png");
  }

  drawFromNetworkUpdate(ByteWorldDraw data) {
    Vec2 pos = Vec2.fromProto(data.position);
    Vec2 size = Vec2.fromProto(data.size);
    String colorString = data.color;
    fillRectAt(pos, size, colorString);
  }

  fillRectAt(Vec2 pos, Vec2 size, String colorString) {
    final CanvasRenderingContext2D ctx = canvas!.context2D;
    ctx.save();
    ctx.fillStyle = colorString.toJS;
    ctx.fillRect(pos.x, pos.y, size.x, size.y);

    // For BrickBuilder bricks (`#aa3311`, 54x18), enrich the interior center with
    // realistic kiln-baked terracotta shading, inner bevels, and subtle mineral
    // grain while leaving the outer 2px `#aa3311` perimeter completely untouched
    // for pixel-exact brick alignment & pattern matching.
    if (colorString.toLowerCase() == "#aa3311" &&
        size.x >= 20.0 &&
        size.y >= 10.0) {
      _drawRealisticBrickCenter(ctx, pos.x, pos.y, size.x, size.y);
    }
    ctx.restore();
    
    // Update collision buffer.
    int x1 = max(0, pos.x.toInt());
    int y1 = max(0, pos.y.toInt());
    int x2 = min(_width, (pos.x + size.x).toInt());
    int y2 = min(_height, (pos.y + size.y).toInt());
    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        _collisionBuffer[y * _width + x] = 1;
      }
    }
  }

  /// Renders realistic baked-clay depth, subtle kiln-fired shade variation,
  /// inner chamfer highlights/shadows, and fine mineral grain strictly inside
  /// a 2px margin of a brick so the outer `#aa3311` edges remain exact.
  void _drawRealisticBrickCenter(CanvasRenderingContext2D ctx, double x, double y,
      double w, double h) {
    const double edgeMargin = 2.0;
    final double ix = x + edgeMargin;
    final double iy = y + edgeMargin;
    final double iw = w - edgeMargin * 2.0;
    final double ih = h - edgeMargin * 2.0;
    if (iw <= 4.0 || ih <= 4.0) return;

    // Deterministic seed from brick coordinates so commander & remote clients
    // draw identical clay grain while adjacent bricks look naturally varied.
    final int seed = ((x.round() * 73856093) ^ (y.round() * 19349663)) & 0x7FFFFFFF;
    final Random rng = Random(seed);
    final int shadeJitter = rng.nextInt(15) - 7;

    ctx.save();
    ctx.beginPath();
    ctx.rect(ix, iy, iw, ih);
    ctx.clip();

    // 1. Soft radial terracotta glow toward the brick center fading back to #aa3311.
    final double cx = ix + iw * (0.46 + (rng.nextDouble() - 0.5) * 0.14);
    final double cy = iy + ih * 0.42;
    final CanvasGradient clayGrad =
        ctx.createRadialGradient(cx, cy, 1.5, cx, cy, max(iw, ih) * 0.62);
    final int hiR = (204 + shadeJitter).clamp(180, 224);
    final int hiG = (78 + (shadeJitter ~/ 2)).clamp(60, 96);
    final int hiB = (36 + (shadeJitter ~/ 3)).clamp(24, 50);
    final int midR = (176 + shadeJitter).clamp(156, 194);
    final int midG = (56 + (shadeJitter ~/ 2)).clamp(44, 72);
    final int midB = (21 + (shadeJitter ~/ 3)).clamp(14, 32);
    clayGrad.addColorStop(0.0, "rgb($hiR, $hiG, $hiB)");
    clayGrad.addColorStop(0.62, "rgb($midR, $midG, $midB)");
    clayGrad.addColorStop(1.0, "#992a0c");
    ctx.fillStyle = clayGrad;
    ctx.fillRect(ix, iy, iw, ih);

    // 2. Subtle top-left sunlit clay bevel and bottom-right recessed bevel.
    ctx.fillStyle = "rgba(255, 206, 162, 0.28)".toJS;
    ctx.fillRect(ix + 1.0, iy, iw - 2.0, 2.0);
    ctx.fillRect(ix, iy, 1.5, ih - 2.0);

    ctx.fillStyle = "rgba(56, 12, 2, 0.36)".toJS;
    ctx.fillRect(ix + 1.0, iy + ih - 2.0, iw - 1.0, 2.0);
    ctx.fillRect(ix + iw - 1.5, iy + 1.0, 1.5, ih - 1.0);

    // 3. Subtle horizontal pressed-clay striations across the face.
    for (int s = 0; s < 3; s++) {
      final double sy = iy + 2.5 + rng.nextDouble() * (ih - 5.0);
      final double sx = ix + 2.0 + rng.nextDouble() * (iw * 0.35);
      final double sw = 8.0 + rng.nextDouble() * (iw * 0.45);
      ctx.fillStyle = (s.isEven
              ? "rgba(82, 18, 4, 0.20)"
              : "rgba(245, 162, 112, 0.16)")
          .toJS;
      ctx.fillRect(sx, sy, sw, 1.0);
    }

    // 4. Fine kiln-fired clay pores & sand/mineral flecks concentrated toward center.
    for (int i = 0; i < 18; i++) {
      final double fx = ix + 2.0 + rng.nextDouble() * (iw - 4.0);
      final double fy = iy + 1.5 + rng.nextDouble() * (ih - 3.0);
      final double fr = (i % 4 == 0) ? 1.4 : 0.9;
      ctx.fillStyle = (i % 3 == 0
              ? "rgba(62, 14, 3, 0.42)"
              : (i % 3 == 1
                  ? "rgba(255, 198, 152, 0.28)"
                  : "rgba(128, 30, 8, 0.34)"))
          .toJS;
      ctx.fillRect(fx, fy, fr, fr);
    }

    // 5. Occasional tiny hairline clay micro-crack near the middle.
    if (rng.nextInt(3) == 0) {
      final double kx = ix + iw * (0.28 + rng.nextDouble() * 0.44);
      final double ky = iy + 3.0 + rng.nextDouble() * max(1.0, ih - 8.0);
      ctx.strokeStyle = "rgba(64, 14, 4, 0.36)".toJS;
      ctx.lineWidth = 0.9;
      ctx.beginPath();
      ctx.moveTo(kx, ky);
      ctx.lineTo(kx + (rng.nextDouble() - 0.5) * 6.0, ky + 3.5);
      ctx.stroke();
    }

    ctx.restore();
  }

  void _traceCraterPolygon(CanvasRenderingContext2D ctx, double cx, double cy,
      List<double> radii, double scale) {
    ctx.beginPath();
    int count = radii.length;
    for (int i = 0; i < count; i++) {
      double theta = (2.0 * pi * i) / count;
      double r = radii[i] * scale;
      double px = cx + cos(theta) * r;
      double py = cy + sin(theta) * r;
      if (i == 0) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.closePath();
  }

  /**
   * Destroy part of the world. From an explosion perhaps?
   * Carves a deterministic jagged crater with a charred scorch rim (via
   * `source-atop` so only solid terrain is tinted) and returns up to
   * [maxColorSamples] sampled RGB colors from the destroyed terrain pixels
   * for spawning debris chunks (pass 0 to skip color sampling when FPS-limited).
   */
  clearAt(Vec2 pos, double radius, {int maxColorSamples = 18}) {
    if (radius <= 0) {
      return <String>[];
    }
    bool useJaggedCrater = radius >= 6.0;
    double maxCraterR = useJaggedCrater ? radius * 1.14 : radius;
    double scorchPad = useJaggedCrater ? (radius * 0.24).clamp(4.0, 12.0) : 0.0;
    double samplePad = maxCraterR + 2.0;

    int x1 = max(0, (pos.x - samplePad).floor());
    int y1 = max(0, (pos.y - samplePad).floor());
    int x2 = min(_width, (pos.x + samplePad).ceil());
    int y2 = min(_height, (pos.y + samplePad).ceil());
    if (x2 <= x1 || y2 <= y1) {
      return <String>[];
    }

    int boxW = x2 - x1;
    int boxH = y2 - y1;
    CanvasRenderingContext2D ctx = canvas!.context2D;

    // Deterministic seed from impact coordinates & radius so every peer carves
    // the exact same crater shape and scorch marks with zero extra network data.
    int seed = ((pos.x.round() * 73856093) ^
            (pos.y.round() * 19349663) ^
            (radius.round() * 83492791)) &
        0x7fffffff;
    Random rng = Random(seed);

    // 1. Sample actual terrain pixel colors inside the blast before erasing
    // (skipped when maxColorSamples <= 0 to save GPU->CPU readback at low FPS).
    List<String> sampledColors = <String>[];
    bool hadSolidTerrain = false;
    if (radius >= 5.0 && maxColorSamples > 0) {
      Uint8ClampedList beforeData = ctx.getImageData(x1, y1, boxW, boxH).data.toDart;
      int targetSamples = min(maxColorSamples, (6 + (radius / 5.0).round()).clamp(6, 18));
      int attempts = targetSamples * 6;
      for (int i = 0; i < attempts && sampledColors.length < targetSamples; i++) {
        double a = rng.nextDouble() * 2.0 * pi;
        double d = sqrt(rng.nextDouble()) * radius * 0.92;
        int sx = (pos.x + cos(a) * d).round() - x1;
        int sy = (pos.y + sin(a) * d).round() - y1;
        if (sx < 0 || sy < 0 || sx >= boxW || sy >= boxH) continue;
        int idx = (sy * boxW + sx) * 4;
        if (beforeData[idx + 3] > 140) {
          hadSolidTerrain = true;
          int r = beforeData[idx];
          int g = beforeData[idx + 1];
          int b = beforeData[idx + 2];
          // Prefer non-charred colors when available so repeated blasts still
          // show recognizable dirt/rock/brick hues.
          if (r + g + b > 55 || sampledColors.isEmpty && i > attempts ~/ 2) {
            sampledColors.add("rgb($r, $g, $b)");
          }
        }
      }
      if (!hadSolidTerrain) {
        // Fallback quick grid scan so thin ledges still register as solid terrain.
        int step = max(1, (radius / 4).round());
        for (int ly = 0; ly < boxH && !hadSolidTerrain; ly += step) {
          for (int lx = 0; lx < boxW; lx += step) {
            int idx = (ly * boxW + lx) * 4;
            if (beforeData[idx + 3] > 140) {
              hadSolidTerrain = true;
              sampledColors.add(
                  "rgb(${beforeData[idx]}, ${beforeData[idx + 1]}, ${beforeData[idx + 2]})");
              break;
            }
          }
        }
      }
    }

    // Build deterministic organic rocky crater radii.
    List<double>? craterRadii;
    if (useJaggedCrater) {
      int segments = (18 + (radius * 0.45).round()).clamp(18, 44);
      double p1 = rng.nextDouble() * 2.0 * pi;
      double p2 = rng.nextDouble() * 2.0 * pi;
      double p3 = rng.nextDouble() * 2.0 * pi;
      craterRadii = List<double>.generate(segments, (int i) {
        double theta = (2.0 * pi * i) / segments;
        double wave = 0.065 * sin(3.0 * theta + p1) +
            0.045 * sin(7.0 * theta + p2) +
            0.030 * sin(13.0 * theta + p3) +
            (rng.nextDouble() - 0.5) * 0.07;
        return radius * (0.96 + wave).clamp(0.84, 1.12);
      });
    }

    // 2. Paint charred soot halo & scorched inner rim onto existing terrain only.
    // (`source-atop` is a no-op on transparent sky pixels, so it stays safe even
    // when color sampling was skipped at low FPS.)
    if (useJaggedCrater && (hadSolidTerrain || maxColorSamples <= 0) && craterRadii != null) {
      ctx.save();
      ctx.globalCompositeOperation = "source-atop";

      double outerScorchR = radius + scorchPad;
      CanvasGradient sootGrad = ctx.createRadialGradient(
          pos.x, pos.y, radius * 0.78, pos.x, pos.y, outerScorchR);
      sootGrad.addColorStop(0.0, "rgba(18, 12, 8, 0.62)");
      sootGrad.addColorStop(0.55, "rgba(28, 19, 13, 0.36)");
      sootGrad.addColorStop(1.0, "rgba(32, 22, 16, 0)");
      ctx.fillStyle = sootGrad;
      ctx.beginPath();
      ctx.arc(pos.x, pos.y, outerScorchR, 0, 2.0 * pi);
      ctx.fill();

      // Crisp dark charred rim hugging the carved rock fracture edge.
      ctx.lineJoin = "round";
      _traceCraterPolygon(ctx, pos.x, pos.y, craterRadii, 1.0);
      ctx.strokeStyle = "rgba(16, 11, 8, 0.72)".toJS;
      ctx.lineWidth = (radius * 0.14).clamp(3.0, 8.0);
      ctx.stroke();

      ctx.strokeStyle = "rgba(72, 54, 42, 0.42)".toJS;
      ctx.lineWidth = 2.0;
      ctx.stroke();

      ctx.restore();
    }

    // 3. Carve the jagged (or smooth tiny) crater hole.
    ctx.save();
    if (craterRadii != null) {
      _traceCraterPolygon(ctx, pos.x, pos.y, craterRadii, 1.0);
    } else {
      ctx.beginPath();
      ctx.arc(pos.x, pos.y, radius, 0, 2 * pi, false);
    }
    ctx.clip();
    ctx.clearRect(x1, y1, boxW, boxH);
    ctx.restore();

    // 4. Re-apply any destroyed or scorched bedrock inside the blast+scorch rect.
    int bx1 = max(0, (pos.x - (radius + scorchPad + 2.0)).floor());
    int by1 = max(0, (pos.y - (radius + scorchPad + 2.0)).floor());
    int bx2 = min(_width, (pos.x + (radius + scorchPad + 2.0)).ceil());
    int by2 = min(_height, (pos.y + (radius + scorchPad + 2.0)).ceil());
    int bW = bx2 - bx1;
    int bH = by2 - by1;
    if (bW > 0 && bH > 0 && _bedrockImage.width >= bx2 && _bedrockImage.height >= by2) {
      ctx.drawImage(_bedrockImage, bx1, by1, bW, bH, bx1, by1, bW, bH);
    } else {
      ctx.drawImage(_bedrockImage, 0, 0);
    }

    // 5. Sync collision buffer pixel-for-pixel with the carved canvas & bedrock.
    Uint8ClampedList afterData = ctx.getImageData(x1, y1, boxW, boxH).data.toDart;
    for (int y = 0; y < boxH; y++) {
      int rowOffset = (y1 + y) * _width + x1;
      int dataRowOffset = y * boxW * 4;
      for (int x = 0; x < boxW; x++) {
        _collisionBuffer[rowOffset + x] =
            afterData[dataRowOffset + x * 4 + 3] > 0 ? 1 : 0;
      }
    }

    return sampledColors;
  }

  Vec2 randomNotSolidPoint(Vec2 sizeOffset) {
    assert(byteWorldReady());
    Vec2? point = null;
    Random r = Random();
    for (int i = 0; i < 50; i++) {
      point = new Vec2(
          r.nextInt(_width).toDouble(),
          r.nextInt(_height).toDouble());
      if (!isCanvasCollide(point.x.toInt(), point.y.toInt())) {
        return point;
      }
    }
    throw "Unable to find random not solid location!";
  }

  int get width => _width;
  int get height => _height;
}