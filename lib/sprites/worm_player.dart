import 'dart:js_interop';

import 'package:dart2d/net/state_updates.pb.dart';
import 'dart:math';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/config_params.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/util/mobile_controls.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:web/web.dart';

import '../res/sounds.dart';
import '../weapons/abstractweapon.dart';

/**
 * How a server represents itself.
 */
class LocalPlayerSprite extends MovingSprite {
  final Logger log = new Logger('LocalPlayerSprite');
  static const BOUCHYNESS = 0.2;
  static const WALKABLE_HILL_PIXEL_HEIGHT = 4;
  static const MAX_WALK_SPEED = 150.0;
  static const WALK_ACCELERATION_SPEED = 100.0;
  static const JUMP_VELOCITY = -300;
  static final Vec2 DEFAULT_PLAYER_SIZE = new Vec2(42.0, 42.0);
  static int MAX_HEALTH = 100;
  static int MAX_SHIELD = 200;
  static const double RESPAWN_TIME = 5.0;
  static const double SPAWN_EFFECT_DURATION = 0.65;
  static const double AIM_SPEED = 2.8;
  static const MAX_SPEED = 500.0;

  static Map<String, int> _default_controls = {
    "Left": KeyCodeDart.A,
    "Right": KeyCodeDart.D,
    "Aim up": KeyCodeDart.UP,
    "Aim down": KeyCodeDart.DOWN,
    "Jump": KeyCodeDart.W,
    "Fire": KeyCodeDart.F,
    "Rope": KeyCodeDart.S,
    "Next weapon": KeyCodeDart.Q,
    "Prev weapon": KeyCodeDart.E,
  };

  static Set<int> _mappedControls = new Set.from(_default_controls.values);

  Map<String, int> getControls() => _default_controls;

  bool isMappedKey(int code) {
    return _mappedControls.contains(code);
  }

  late WormWorld world;
  int health = MAX_HEALTH;
  int _shieldPoints = 0;
  double _jetPackSec = 0.0;
  Particles? _jetParticles = null;

  late PlayerInfoProto info;
  PlayerInfoProto? _killer = null;
  Mod? _killedByMod = null;
  String? _killedByMessage = null;
  Rope? rope = null;
  MobileControls? _mobileControls;
  double? _gunAngleTouchLock = null;
  WeaponState? weaponState = null;

  bool onGround = false;

  // Don't spawn player when created.
  double spawnIn = 10000000000.0;

  late MovingSprite gun;

  double _shieldSec = -1.0;
  double _nextDamageAnimation = 0.0;
  double _spawnEffectRemaining = 0.0;
  double _bingoEffectRemaining = 0.0;
  double _bingoEffectDuration = 1.6;
  int _bingoEffectTier = 0;
  bool _wasInGame = false;
  late StickySprite _shield;

  PlayerInfoProto? get killer => _killer;
  Mod? get killedByMod => _killedByMod;
  String? get killedByMessage => _killedByMessage;
  double get spawnEffectRemaining => _spawnEffectRemaining;
  double get bingoEffectRemaining => _bingoEffectRemaining;
  int get bingoEffectTier => _bingoEffectTier;

  void applyExtraBingoBonus() {
    if (inGame() && health < MAX_HEALTH) {
      health = MAX_HEALTH;
    }
    _bingoEffectTier = 1;
    _bingoEffectDuration = 1.6;
    _bingoEffectRemaining = 1.6;
  }

  void applySuperBingoBonus() {
    if (inGame()) {
      health = MAX_HEALTH;
      _shieldPoints = MAX_SHIELD;
      _shieldSec = max(_shieldSec, 2.6);
    }
    _bingoEffectTier = 2;
    _bingoEffectDuration = 2.4;
    _bingoEffectRemaining = 2.4;
  }

  /**
   * Server constructor.
   */
  LocalPlayerSprite(
      WormWorld world,
      ImageIndex imageIndex,
      MobileControls? mobileControls,
      PlayerInfoProto info,
      Vec2 position,
      int imageId)
      : super.imageBasedSprite(position, imageId, imageIndex) {
    this.world = world;
    this.info = info;
    this._wasInGame = info.inGame == true;
    this.collision = this._wasInGame;
    this._mobileControls = mobileControls;
    this.size = DEFAULT_PLAYER_SIZE;
    this.gun = _createGun(imageIndex);
    this._shield = _createShield(imageIndex);
    this.weaponState =
        new WeaponState(world, this, this.gun, this._mobileControls);
    this.listenFor("Next weapon", () {
      weaponState?.nextWeapon();
    });
    this.listenFor("Prev weapon", () {
      weaponState?.prevWeapon();
    });
  }

  StickySprite _createGun(ImageIndex index) {
    PlayerGunSprite sprite = new PlayerGunSprite(
        this, index.getImageIdByName("gun.png"), index);
    // Keep width at 60.0 so muzzleOffset (gun.size.x * 0.5 == 30.0) stays exact.
    sprite.size = new Vec2(60.0, 19.0);
    return sprite;
  }

  StickySprite _createShield(ImageIndex index) {
    StickySprite shield = new StickySprite(this, index.getImageIdByName("shield.png"),
        index, Sprite.UNLIMITED_LIFETIME);
    shield.size = LocalPlayerSprite.DEFAULT_PLAYER_SIZE.multiply(1.5);
    shield.rotationVelocity = 200.0;
    shield.setImage(index.getImageIdByName("shield.png"), 2);
    return shield;
  }

  bool drawWeaponHelpers() => _ownedByThisWorld();

  hasCommanderToOwnerData() =>
      world.network().isCommander() && !_ownedByThisWorld();

  ExtraSpriteData getCommanderToOwnerData() {
    ExtraSpriteData data = ExtraSpriteData()
        ..extraInt.add(health)
        ..extraInt.add(_shieldPoints)
        ..extraFloat.add(_shieldSec)
        ..extraFloat.add(spawnIn);
    if (_killer != null) {
      data.extraString.add(_killer!.connectionId);
      data.extraString.add(_killedByMessage ?? "");
      data.extraString.add((_killedByMod ?? Mod.UNKNOWN).name);
    }
    if (weaponState != null) {
      Weapon w = weaponState!.getSelectedWeapon();
      data.extraFloat.add(w.untilReload);
      data.extraFloat.add(w.untilNextFire);
      data.extraInt.add(w.shotsLeft);
    }
    data.extraFloat.add(_jetPackSec);
    if (weaponState != null) {
      data.extraInt
        ..add(weaponState!.unlockedWeaponsBitmask)
        ..add(weaponState!.rouletteNonce)
        ..add(weaponState!.rouletteTargetWeaponIndex)
        ..add(weaponState!.selectedWeaponIndex)
        ..add(weaponState!.rouletteBingoTier.index);
      data.extraFloat.add(weaponState!.rouletteSpinRemaining);
    }
    return data;
  }

  bool commanderToOwnerData(ExtraSpriteData data) {
    health = data.extraInt[0];
    _shieldPoints = data.extraInt[1];
    _shieldSec = data.extraFloat[0];
    spawnIn = data.extraFloat[1];
    if (data.extraString.isNotEmpty) {
      String killerId = data.extraString[0];
      _killer = world
          .network()
          .gameState
          .playerInfoByConnectionId(killerId);
      if (data.extraString.length > 1 && data.extraString[1].isNotEmpty) {
        _killedByMessage = data.extraString[1];
      }
      if (data.extraString.length > 2) {
        final String modName = data.extraString[2];
        _killedByMod = Mod.values.firstWhere(
          (m) => m.name == modName,
          orElse: () => Mod.UNKNOWN,
        );
      }
    }
    if (weaponState != null &&
        data.extraInt.length >= 6 &&
        data.extraFloat.length >= 6) {
      final int bingoIdx = data.extraInt.length >= 8 ? data.extraInt[7] : 0;
      weaponState!.applyCommanderSync(
        unlockedMask: data.extraInt[3],
        rouletteNonce: data.extraInt[4],
        rouletteTarget: data.extraInt[5],
        rouletteSpinRem: data.extraFloat[5],
        rouletteBingoIndex: bingoIdx,
      );
    }
    if (data.extraFloat.length > 3 && weaponState != null) {
      final bool weaponMatches = data.extraInt.length < 7 ||
          data.extraInt[6] == weaponState!.selectedWeaponIndex;
      if (weaponMatches) {
        Weapon w = weaponState!.getSelectedWeapon();
        w.untilReload = data.extraFloat[2];
        w.untilNextFire = data.extraFloat[3];
        w.shotsLeft = data.extraInt[2];
      }
    }
    final int jetPackIdx = weaponState != null ? 4 : 2;
    if (data.extraFloat.length > jetPackIdx) {
      final double remoteJetPackSec = data.extraFloat[jetPackIdx];
      if (remoteJetPackSec > _jetPackSec) {
        _jetPackSec = remoteJetPackSec;
      }
    }
    return true;
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (world != null && direction != null) {
      if (direction & MovingSprite.DIR_BELOW == MovingSprite.DIR_BELOW) {
        onGround = true;
        if (velocity.y.abs() > 1.0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        } else {
          velocity.y = 0.0;
        }
        if (direction != MovingSprite.DIR_BELOW) {
          // Go back right a bit.
          if (direction & MovingSprite.DIR_LEFT == MovingSprite.DIR_LEFT) {
            while (world.isCanvasCollide(
                position.x.toInt(), position.y.toInt(),
                // Allow a few pixels of incline...
                1, size.y.toInt() - WALKABLE_HILL_PIXEL_HEIGHT)) {
              position.x++;
            }
            direction -= MovingSprite.DIR_LEFT;
          }
          // Go back left a bit.
          if (direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
            while (world.isCanvasCollide(
                position.x.toInt() + size.x
                .toInt(), position.y.toInt(),
                // Allow a few pixels of incline...
                1, size.y.toInt() - WALKABLE_HILL_PIXEL_HEIGHT)) {
              position.x--;
            }
            direction -= MovingSprite.DIR_RIGHT;
          }
        }
        // Check one more time, but y -1.
        while (world.isCanvasCollide(
            (position.x + 1).toInt(), (position.y + size.y - 1.0).toInt(), (size.x - 1).toInt(), 1)) {
          position.y--;
        }
      }
      if (direction & MovingSprite.DIR_ABOVE == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        }
        // Check one more time, but more above..
        while (world.isCanvasCollide(
            (position.x + 2).toInt(),
            (position.y - 1).toInt(),
               (size.x - 4).toInt(), 1)) {
          position.y++;
        }
      }

      if (direction & MovingSprite.DIR_LEFT == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          velocity.x = -velocity.x * BOUCHYNESS;
          position.x++;
        }
      }
      if (direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          velocity.x = -velocity.x * BOUCHYNESS;
          position.x--;
        }
      }
    }
  }

  bool inGame() {
    return info.inGame == true;
  }

  void triggerSpawnEffect() {
    _spawnEffectRemaining = SPAWN_EFFECT_DURATION;
    if (_ownedByThisWorld()) {
      world.playSound(Sound.SPAWN, volume: 0.90, multiPlay: true);
    } else {
      world.playSoundAtSprite(this, Sound.SPAWN, multiPlay: true);
    }
  }

  void _drawSpawnEffectBackdrop(CanvasRenderingContext2D context) {
    final double elapsed =
        (SPAWN_EFFECT_DURATION - _spawnEffectRemaining).clamp(0.0, SPAWN_EFFECT_DURATION);
    final double t = (elapsed / SPAWN_EFFECT_DURATION).clamp(0.0, 1.0);
    final Vec2 c = centerPoint();
    final double footY = position.y + size.y;

    context.save();

    // 1. Narrowing golden-cyan sky drop beam during the first 0.38s!
    if (t < 0.58) {
      final double bt = (t / 0.58).clamp(0.0, 1.0);
      final double beamAlpha = (1.0 - bt) * 0.72;
      final double halfW = (size.x * 0.62) * (1.0 - bt * 0.72);
      final CanvasGradient beamGrad =
          context.createLinearGradient(c.x, footY, c.x, footY - 125.0);
      beamGrad.addColorStop(0.0, "rgba(255, 244, 158, ${beamAlpha.toStringAsFixed(2)})");
      beamGrad.addColorStop(0.45, "rgba(110, 244, 255, ${(beamAlpha * 0.65).toStringAsFixed(2)})");
      beamGrad.addColorStop(1.0, "rgba(110, 244, 255, 0.0)");
      context.fillStyle = beamGrad;
      context.fillRect(c.x - halfW, footY - 125.0, halfW * 2.0, 125.0);
    }

    // 2. Expanding ground arrival shockwave ring at the player's feet.
    final double ringR = 10.0 + t * 42.0;
    final double ringAlpha = (1.0 - t) * 0.85;
    context.strokeStyle =
        "rgba(255, 238, 128, ${ringAlpha.toStringAsFixed(2)})".toJS;
    context.lineWidth = 3.0 * (1.0 - t * 0.6) + 0.8;
    context.beginPath();
    context.ellipse(c.x, footY - 2.0, ringR, ringR * 0.36, 0.0, 0.0, pi * 2.0);
    context.stroke();

    // Soft warm glow behind the arriving player.
    if (t < 0.65) {
      final double ga = (1.0 - t / 0.65) * 0.45;
      final CanvasGradient halo = context.createRadialGradient(
          c.x, c.y, 2.0, c.x, c.y, size.x * 0.9);
      halo.addColorStop(0.0, "rgba(255, 252, 200, ${ga.toStringAsFixed(2)})");
      halo.addColorStop(1.0, "rgba(255, 230, 110, 0.0)");
      context.fillStyle = halo;
      context.beginPath();
      context.arc(c.x, c.y, size.x * 0.9, 0.0, pi * 2.0);
      context.fill();
    }

    context.restore();
  }

  void _applySpawnPopTransform(CanvasRenderingContext2D context) {
    final double elapsed =
        (SPAWN_EFFECT_DURATION - _spawnEffectRemaining).clamp(0.0, SPAWN_EFFECT_DURATION);
    if (elapsed >= 0.44) return;
    final double p = (elapsed / 0.44).clamp(0.0, 1.0);
    // Elastic cartoon drop-squash-bounce curve!
    double sx = 1.0;
    double sy = 1.0;
    if (p < 0.32) {
      final double u = p / 0.32;
      sx = 0.56 + (1.20 - 0.56) * u;
      sy = 1.42 + (0.82 - 1.42) * u;
    } else if (p < 0.68) {
      final double u = (p - 0.32) / 0.36;
      sx = 1.20 + (0.94 - 1.20) * u;
      sy = 0.82 + (1.06 - 0.82) * u;
    } else {
      final double u = (p - 0.68) / 0.32;
      sx = 0.94 + (1.0 - 0.94) * u;
      sy = 1.06 + (1.0 - 1.06) * u;
    }
    final double pivotX = position.x + size.x * 0.5;
    final double pivotY = position.y + size.y;
    context.translate(pivotX, pivotY);
    context.scale(sx, sy);
    context.translate(-pivotX, -pivotY);
  }

  void _drawSpawnEffectForeground(CanvasRenderingContext2D context) {
    final double elapsed =
        (SPAWN_EFFECT_DURATION - _spawnEffectRemaining).clamp(0.0, SPAWN_EFFECT_DURATION);
    final double t = (elapsed / SPAWN_EFFECT_DURATION).clamp(0.0, 1.0);
    final double ease = 1.0 - pow(1.0 - t, 2.4).toDouble();
    final double alpha = (1.0 - t).clamp(0.0, 1.0);
    final Vec2 c = centerPoint();
    final double footY = position.y + size.y - 3.0;

    context.save();
    context.globalAlpha = alpha;

    // 1. Six cartoon arrival poof clouds billow outward around the feet!
    for (int i = 0; i < 6; i++) {
      final double side = i < 3 ? -1.0 : 1.0;
      final int idx = i % 3;
      final double px = c.x + side * (8.0 + idx * 7.5 + ease * (16.0 + idx * 8.0));
      final double py = footY - idx * 3.5 - ease * (6.0 + idx * 5.0);
      final double pr = (6.8 - idx * 1.1) * (1.0 - t * 0.45);
      context.fillStyle = "#fffdf2".toJS;
      context.strokeStyle = "#1a2230".toJS;
      context.lineWidth = 1.4;
      context.beginPath();
      context.arc(px, py, max(1.2, pr), 0.0, pi * 2.0);
      context.fill();
      context.stroke();
    }

    // 2. Seven twinkling 4-point cartoon stars popping outward & upward!
    for (int i = 0; i < 7; i++) {
      final double a = -pi * 0.92 + (pi * 0.84) * (i / 6.0);
      final double dist = 12.0 + ease * (28.0 + (i.isEven ? 10.0 : 0.0));
      final double sx = c.x + cos(a) * dist;
      final double sy = c.y + sin(a) * dist - ease * 10.0;
      final double sr = (4.8 - (i % 2) * 1.0) * (1.0 - t * 0.35);
      context.save();
      context.translate(sx, sy);
      context.rotate(t * 2.6 * (i.isEven ? 1.0 : -1.0));
      context.fillStyle = (i.isEven ? "#ffe44d" : "#7df9ff").toJS;
      context.strokeStyle = "#18202c".toJS;
      context.lineWidth = 1.2;
      context.beginPath();
      context.moveTo(0.0, -sr);
      context.lineTo(sr * 0.30, -sr * 0.30);
      context.lineTo(sr, 0.0);
      context.lineTo(sr * 0.30, sr * 0.30);
      context.lineTo(0.0, sr);
      context.lineTo(-sr * 0.30, sr * 0.30);
      context.lineTo(-sr, 0.0);
      context.lineTo(-sr * 0.30, -sr * 0.30);
      context.closePath();
      context.fill();
      context.stroke();
      context.restore();
    }

    context.restore();
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    context.save();
    if (!inGame()) {
      this.velocity.x = 0.0;
      this.velocity.y = 0.0;
      if (rope != null) {
        rope!.remove = true;
        rope = null;
      }
      context.restore();
      return;
    }
    if (_spawnEffectRemaining > 0.0) {
      _drawSpawnEffectBackdrop(context);
    }
    weaponState?.draw(context);
    context.save();
    if (_spawnEffectRemaining > 0.0) {
      _applySpawnPopTransform(context);
    }
    context.save();
    gun.draw(context, debug);
    context.restore();
    if (_shieldSec > 0) {
      context.save();
      super.draw(context, debug);
      context.restore();
      context.save();
      _shield.draw(context, debug);
      context.restore();
    } else {
      super.draw(context, debug);
    }
    context.restore();
    if (_spawnEffectRemaining > 0.0) {
      _drawSpawnEffectForeground(context);
    }
    if (_bingoEffectRemaining > 0.0) {
      _drawBingoAuraEffect(context);
    }
    context.save();
    drawHealthBar(context);
    context.restore();
    context.restore();
  }

  void _drawBingoAuraEffect(CanvasRenderingContext2D context) {
    final bool isSuper = _bingoEffectTier >= 2;
    final double total = max(0.2, _bingoEffectDuration);
    final double elapsed = (total - _bingoEffectRemaining).clamp(0.0, total);
    final double t = (elapsed / total).clamp(0.0, 1.0);
    final double alpha = (1.0 - t * 0.85).clamp(0.0, 1.0);
    final Vec2 c = centerPoint();

    context.save();
    context.globalAlpha = alpha;

    // 1. Expanding jackpot shockwave ring(s) around the player!
    final double ringR = size.x * 0.55 + t * (isSuper ? 78.0 : 44.0);
    context.strokeStyle =
        (isSuper ? "rgba(255, 238, 96, 0.90)" : "rgba(104, 255, 156, 0.85)")
            .toJS;
    context.lineWidth = (isSuper ? 4.2 : 3.0) * (1.0 - t * 0.65) + 0.8;
    context.beginPath();
    context.arc(c.x, c.y, ringR, 0.0, pi * 2.0);
    context.stroke();

    if (isSuper) {
      final double innerR = size.x * 0.42 + t * 52.0;
      context.strokeStyle = "rgba(96, 245, 255, 0.85)".toJS;
      context.lineWidth = 3.0 * (1.0 - t * 0.5) + 0.8;
      context.beginPath();
      context.arc(c.x, c.y, innerR, 0.0, pi * 2.0);
      context.stroke();

      final CanvasGradient halo =
          context.createRadialGradient(c.x, c.y, 4.0, c.x, c.y, size.x * 1.15);
      halo.addColorStop(0.0, "rgba(255, 244, 130, 0.42)");
      halo.addColorStop(0.55, "rgba(110, 245, 255, 0.24)");
      halo.addColorStop(1.0, "rgba(255, 110, 236, 0.0)");
      context.fillStyle = halo;
      context.beginPath();
      context.arc(c.x, c.y, size.x * 1.15, 0.0, pi * 2.0);
      context.fill();
    }

    // 2. Orbiting / rising stars around the player.
    final int count = isSuper ? 8 : 5;
    for (int i = 0; i < count; i++) {
      final double a = (i / count) * pi * 2.0 + elapsed * (isSuper ? 5.2 : 3.4);
      final double orbitR = size.x * 0.72 + (isSuper ? 10.0 * sin(elapsed * 8.0 + i) : 4.0);
      final double sx = c.x + cos(a) * orbitR;
      final double sy = c.y + sin(a) * orbitR * 0.75 - t * 14.0;
      final double sr = isSuper ? 5.2 : 4.0;
      context.fillStyle = (isSuper
              ? (i.isEven ? "#ffe96b" : "#7df9ff")
              : "#7dff9e")
          .toJS;
      context.beginPath();
      for (int p = 0; p < 8; p++) {
        final double pa = p * pi / 4.0;
        final double pr = p.isEven ? sr : sr * 0.34;
        if (p == 0) {
          context.moveTo(sx + cos(pa) * pr, sy + sin(pa) * pr);
        } else {
          context.lineTo(sx + cos(pa) * pr, sy + sin(pa) * pr);
        }
      }
      context.closePath();
      context.fill();
    }

    // 3. Floating world-space comic callout above remote players so opponents see it too!
    if (!_ownedByThisWorld()) {
      final String badge = isSuper ? "⚡ SUPERBINGO! ⚡" : "★ EXTRA BINGO! ★";
      context.font = '900 12px "Trebuchet MS", Arial, sans-serif';
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.strokeStyle = "#101824".toJS;
      context.lineWidth = 3.2;
      final double labelY = position.y - 18.0 - t * 16.0;
      context.strokeText(badge, c.x, labelY);
      context.fillStyle = (isSuper ? "#fff066" : "#7dff9e").toJS;
      context.fillText(badge, c.x, labelY);
    }

    context.restore();
  }

  bool drawHealthBar(CanvasRenderingContext2D context) {
    if (!_ownedByThisWorld()) {
      return false;
    }
    if (shieldPoints <= 0 && health == MAX_HEALTH) {
      // Don't draw if max health.
      return true;
    }
    final double barWidth = size.x + 18.0;
    final double barX = position.x + (size.x - barWidth) * 0.5;
    final double barY = position.y + size.y + 8.0;
    final double healthHeight = 9.5;
    final double healthFrac = (health / MAX_HEALTH).clamp(0.0, 1.0);

    // Pick juicy cartoon health fill colors based on remaining HP.
    final String topColor;
    final String bottomColor;
    if (healthFrac > 0.55) {
      topColor = "#7dff74";
      bottomColor = "#20bd42";
    } else if (healthFrac > 0.25) {
      topColor = "#ffe252";
      bottomColor = "#eb8614";
    } else {
      topColor = "#ff6b6b";
      bottomColor = "#d41e32";
    }

    context.save();
    context.globalAlpha = 0.94;
    _drawCartoonStatusBar(
      context,
      x: barX,
      y: barY,
      width: barWidth,
      height: healthHeight,
      fraction: healthFrac,
      fillTop: topColor,
      fillBottom: bottomColor,
    );

    if (_shieldPoints > 0) {
      final double shieldHeight = 8.0;
      final double shieldY = barY + healthHeight + 3.5;
      final double shieldFrac = (_shieldPoints / MAX_SHIELD).clamp(0.0, 1.0);

      // Subtle electric-cyan outer glow behind the shield bar.
      context.fillStyle = "rgba(86, 232, 255, 0.30)".toJS;
      context.beginPath();
      context.roundRect(
        barX - 2.0,
        shieldY - 2.0,
        barWidth + 4.0,
        shieldHeight + 4.0,
        ((shieldHeight + 4.0) * 0.5).toJS,
      );
      context.fill();

      _drawCartoonStatusBar(
        context,
        x: barX,
        y: shieldY,
        width: barWidth,
        height: shieldHeight,
        fraction: shieldFrac,
        fillTop: "#8ef6ff",
        fillBottom: "#1e90ff",
      );
    }

    context.restore();
    return true;
  }

  void _drawCartoonStatusBar(
    CanvasRenderingContext2D context, {
    required double x,
    required double y,
    required double width,
    required double height,
    required double fraction,
    required String fillTop,
    required String fillBottom,
  }) {
    final double radius = height * 0.5;

    // Cartoon drop shadow.
    context.fillStyle = "rgba(10, 16, 26, 0.45)".toJS;
    context.beginPath();
    context.roundRect(x + 1.4, y + 1.8, width, height, radius.toJS);
    context.fill();

    // Recessed dark trough.
    context.fillStyle = "rgba(18, 24, 36, 0.88)".toJS;
    context.beginPath();
    context.roundRect(x, y, width, height, radius.toJS);
    context.fill();

    // Clipped glossy fill gradient.
    if (fraction > 0.0) {
      context.save();
      context.beginPath();
      context.roundRect(x, y, width, height, radius.toJS);
      context.clip();

      final double fillW = width * fraction;
      final CanvasGradient grad = context.createLinearGradient(0, y, 0, y + height);
      grad.addColorStop(0.0, fillTop);
      grad.addColorStop(1.0, fillBottom);
      context.fillStyle = grad;
      context.fillRect(x, y, fillW, height);

      // Glossy top cartoon highlight strip.
      context.fillStyle = "rgba(255, 255, 255, 0.36)".toJS;
      context.fillRect(x, y + 0.8, fillW, height * 0.38);
      context.restore();
    }

    // Subtle quarter-segment divider ticks for quick readability.
    context.strokeStyle = "rgba(12, 18, 28, 0.35)".toJS;
    context.lineWidth = 1.0;
    for (int i = 1; i < 4; i++) {
      final double tx = x + width * (i * 0.25);
      context.beginPath();
      context.moveTo(tx, y + 1.5);
      context.lineTo(tx, y + height - 1.5);
      context.stroke();
    }

    // Crisp cartoon dark ink border.
    context.strokeStyle = "#121b28".toJS;
    context.lineWidth = 2.0;
    context.beginPath();
    context.roundRect(x, y, width, height, radius.toJS);
    context.stroke();
  }

  bool _ownedByThisWorld() {
    return info.connectionId == world.network().peer.getId();
  }

  bool _updatePosition = false;

  bool maybeRespawn(double duration) {
    if (_ownedByThisWorld()) {
      if (!inGame() && spawnIn < RESPAWN_TIME / 2) {
        if (_updatePosition) {
          position = world.byteWorld.randomNotSolidPoint(size);
          _updatePosition = false;
        }
      } else {
        _updatePosition = true;
      }
    }
    if (!world.network().isCommander()) {
      return false;
    }
    if (!inGame() && !world.network().getGameState().hasWinner()) {
      spawnIn -= duration;
      if (spawnIn < 0) {
        velocity = new Vec2();
        world.displayHudMessageAndSendToNetwork("${info.name} is back!");
        world.network().gameState.markAsUrgent();
        info.inGame = true;
        collision = true;
        health = MAX_HEALTH;
      }
    }
    return true;
  }

  frame(double duration, int frames, [Vec2? gravity]) {
    maybeRespawn(duration);
    final bool nowInGame =
        inGame() && !world.network().getGameState().hasWinner();
    if (nowInGame && !_wasInGame) {
      collision = true;
      if (health <= 0) {
        health = MAX_HEALTH;
      }
      triggerSpawnEffect();
    }
    _wasInGame = nowInGame;
    if (_spawnEffectRemaining > 0.0) {
      _spawnEffectRemaining = max(0.0, _spawnEffectRemaining - duration);
    }
    if (_bingoEffectRemaining > 0.0) {
      _bingoEffectRemaining = max(0.0, _bingoEffectRemaining - duration);
    }
    checkControlKeys(duration);
    checkShouldFire();
    super.frame(duration, frames, gravity);
    gun.frame(duration, frames, gravity);
    _shield.frame(duration, frames, gravity);
    _shieldSec -= duration;
    _jetPackSec -= duration;
    _nextDamageAnimation -= duration;
    weaponState?.think(duration);
    if (velocity.x.abs() < 10.0) {
      this.frameIndex = 0;
    }
  }

  /**
   * return true
   */
  bool checkControlKeys(double duration) {
    if (!_ownedByThisWorld()) {
      return false;
    }
    if (!inGame()) {
      return true;
    }
    double? left = keyIsDownStrength("Left");
    double? right = keyIsDownStrength("Right");
    double? aimUp = keyIsDownStrength("Aim up");
    double? aimDown = keyIsDownStrength("Aim down");

    _applyVel(right, left);

    if (keyIsDown("Jump") && rope != null) {
      world.removeSprite(rope!.networkId!);
      rope = null;
    }

    if (_jetPackSec <= 0 || !keyIsDown("Jump")) {
      if (_jetParticles != null) {
        _jetParticles!.remove = true;
        _jetParticles = null;
      }
    }

    if (keyIsDown("Jump")) {
      if (_jetPackSec > 0) {
        velocity.y -= 700 * duration;
        if (_jetParticles != null && _jetParticles!.remove) {
          _jetParticles = null;
        }
        if (_jetParticles == null) {
          _jetParticles = new Particles(weaponState!.world,
              this, new Vec2.copy(this.position), new Vec2(0, velocity.y + 50),
              followOffset: new Vec2(0, size.y / 2), radius: 10.0, count: 10, lifeTime: 10,
              shrinkPerStep: 0.8, particleType:  ParticleEffects_ParticleType.SODA);
          _jetParticles!.sendToNetwork = true;
          _jetParticles!.spawn_sound = Sound.FIZZ;
          world.addSprite(_jetParticles!);
        }
      } else if (onGround) {
        velocity.y += JUMP_VELOCITY;
        world.playSound(Sound.JUMP);
        onGround = false;
      }
    }

    if (aimUp != null) {
      _gunUp(duration * aimUp);
    } else if (aimDown != null) {
      _gunDown(duration * aimDown);
    }

    if (keyIsDown("Rope")) {
      _fireRope();
    }

    if (_mobileControls != null) {
      Point<int>? delta = _mobileControls!.getTouchDeltaForButton();
      if (_mobileControls!.buttonIsDown()) {
        if (_gunAngleTouchLock == null) {
          _gunAngleTouchLock = gun.angle;
        }
        if (delta != null) {
          checkMobileControls(delta.x, delta.y);
        }
      } else {
        _gunAngleTouchLock = null;
      }
      if (_mobileControls!.buttonIsDown(MobileControls.WEAPON_SELECT_BUTTON)) {
        Point<int>? delta = _mobileControls!
            .getTouchDeltaForButton(MobileControls.WEAPON_SELECT_BUTTON);
        if (delta != null &&
            (delta.x * delta.x + delta.y * delta.y) >= 18 * 18) {
          final Point<int> btnCenter = _mobileControls!
              .buttonLocation(MobileControls.WEAPON_SELECT_BUTTON);
          weaponState?.selectWeaponAtScreenPoint(
            Point<int>(btnCenter.x - delta.x, btnCenter.y - delta.y),
            btnCenter,
          );
        }
      }
    }
    return true;
  }

  int extraSendFlags() {
   return 0;
  }

  void _applyVel(double? right, double? left) {
    if (left != null) {
      if (velocity.x > -WALK_ACCELERATION_SPEED) {
        velocity.x -= WALK_ACCELERATION_SPEED * left;
      }
      if (velocity.x < -MAX_WALK_SPEED * left) {
        velocity.x = -MAX_WALK_SPEED * left;
      }
      if (velocity.x < -MAX_WALK_SPEED) {
        velocity.x = -MAX_WALK_SPEED;
      }
      if (angle < pi * 2) {
        gun.angle -= (gun.angle + pi / 2) * 2;
        if (_gunAngleTouchLock != null) {
          _gunAngleTouchLock = _gunAngleTouchLock! - (_gunAngleTouchLock! + pi / 2) * 2;
          ;
        }
        angle = pi * 2 + 0.01;
      }
    } else if (right != null) {
      if (velocity.x < MAX_WALK_SPEED * right) {
        velocity.x += WALK_ACCELERATION_SPEED * right;
      }
      if (velocity.x > MAX_WALK_SPEED * right) {
        velocity.x = MAX_WALK_SPEED * right;
      }
      if (velocity.x > MAX_WALK_SPEED) {
        velocity.x = MAX_WALK_SPEED;
      }
      if (angle != 0.0) {
        angle = 0.0;
        gun.angle -= (gun.angle + pi / 2) * 2;
        ;
        if (_gunAngleTouchLock != null) {
          _gunAngleTouchLock = _gunAngleTouchLock! - (_gunAngleTouchLock! + pi / 2) * 2;
          ;
        }
      }
    } else {
      velocity.x = velocity.x * 0.94;
    }
  }

  bool checkMobileControls(int xD, yD) {
    if (angle != 0.0) {
      gun.angle = _gunAngleTouchLock! + (yD * 0.02);
      if (gun.angle > -pi / 2) {
        gun.angle = -pi / 2;
      }
      if (gun.angle < -(pi + pi / 3)) {
        gun.angle = -(pi + pi / 3);
      }
    } else {
      gun.angle = _gunAngleTouchLock! - (yD * 0.02);
      if (gun.angle > pi / 3) {
        gun.angle = pi / 3;
      }
      if (gun.angle < -pi / 2) {
        gun.angle = -pi / 2;
      }
    }

    const int moveDeadzonePx = 12;
    if (xD > moveDeadzonePx) {
      _applyVel(null, ((xD.abs() - moveDeadzonePx) / 36.0).clamp(0.0, 1.0));
    } else if (xD < -moveDeadzonePx) {
      _applyVel(((xD.abs() - moveDeadzonePx) / 36.0).clamp(0.0, 1.0), null);
    } else {
      _applyVel(null, null);
    }
    return true;
  }

  bool checkShouldFire() {
    if (!world.network().isCommander()) {
      return false;
    }
    if (keyIsDown("Fire") && inGame()) {
      weaponState?.fire();
    }
    return true;
  }

  void _gunDown(double duration) {
    if (angle != 0.0) {
      gun.angle -= duration * AIM_SPEED;
      if (gun.angle < -(pi + pi / 3)) {
        gun.angle = -(pi + pi / 3);
      }
    } else {
      gun.angle += duration * AIM_SPEED;
      if (gun.angle > pi / 3) {
        gun.angle = pi / 3;
      }
    }
  }

  void _gunUp(double duration) {
    // Diffent if facing left or right.
    if (angle != 0.0) {
      gun.angle += duration * AIM_SPEED;
      if (gun.angle > -pi / 2) {
        gun.angle = -pi / 2;
      }
    } else {
      gun.angle -= duration * AIM_SPEED;
      if (gun.angle < -pi / 2) {
        gun.angle = -pi / 2;
      }
    }
  }

  void _fireRope() {
    world.playSoundAtSprite(this, Sound.WHIP);
    if (rope != null) {
      world.removeSprite(rope!.networkId!);
    }
    rope = new Rope.createWithOwner(this.world, this, this.gun.angle, 600.0);
    world.addSprite(rope!);
  }

  bool takesDamage(Mod mod) {
    return collision;
  }

  void takeDamage(int damage, LocalPlayerSprite inflictor, Mod mod) {
    if (world.network().isCommander()) {
      if (_shieldPoints > 0) {
        _shieldSec = 0.8;
        _shieldPoints -= damage;
        if (_shieldPoints < 0) {
          health += _shieldPoints;
          _shieldPoints = 0;
          _shieldSec = 0.0;
        }
      } else {
        health -= damage;
      }
      if (health <= 0) {
        world.gaReporter().reportEvent("player_killed", "Frags");
        world
            .network()
            .gameState
            .markAsUrgent();
        info.deaths++;
        info.inGame = false;
        collision = false;
        _killer = world
            .network()
            .gameState
            .playerInfoBySpriteId(inflictor.networkId!);
        if (_killer != null && _killer != info) {
          _killer!.score++;
          world.gaReporter().reportEvent("player_frags", "Frags");
          world.checkWinner(killer!);
        }
        spawnIn = RESPAWN_TIME;
        _killedByMod = mod;
        _deathMessage(mod);
        _addDeathParticles();
      } else if (_shieldPoints <= 0) {
        _addDamageParticles();
      }
    }
  }

  void _addDeathParticles() {
    int blood = world.config().getInt(ConfigParam.BLOOD);
    bool bloodEnabled = blood > 0;
    String killerId =
        (_killer != null && _killer != info) ? _killer!.connectionId : "";
    PlayerDeathEffect effect = PlayerDeathEffect.create(
      world,
      this,
      bloodEnabled: bloodEnabled,
      bloodCount: bloodEnabled ? blood : 0,
      killerConnectionId: killerId,
    );
    world.addSprite(effect);
  }

  void _addDamageParticles() {
    if (_nextDamageAnimation < 0) {
      int blood = world.config().getInt(ConfigParam.BLOOD);
      int countLifeTime = blood > 0 ? blood : 120;
      final double lod = world.effectiveDetailScale;
      final int scaledCount = max(3, ((countLifeTime / 10) * lod).round());
      Particles p = Particles(
          world,
          null,
          centerPoint(),
          Vec2(200, 300),
          radius: 8.0,
          count: scaledCount,
          lifeTime: (countLifeTime / 2).toInt(),
          shrinkPerStep: 0.3,
          particleType: blood > 0 ?
              ParticleEffects_ParticleType.BLOOD :
              ParticleEffects_ParticleType.CONFETTI);
      p.sendToNetwork = true;
      world.addSprite(p);
      world.playSoundAtSprite(this, Sound.OW);
      _nextDamageAnimation = 0.3;
    }
  }

  void _deathMessage(Mod mod) {
    if (_killer != null) {
      if (_killer == info) {
        final String message = selfKillMessage(info.name, mod);
        _killedByMessage = message;
        world.displayHudMessageAndSendToNetwork(message);
        world.gaReporter().reportEvent("self_kill", "Frags");
      } else {
        final String message = killedMessage(info.name, killer!.name, mod);
        _killedByMessage = message;
        world.displayHudMessageAndSendToNetwork(message);
      }
    } else {
      final String message = "${info.name} went poof!";
      _killedByMessage = message;
      world.displayHudMessageAndSendToNetwork(message);
    }
  }

  KeyState getKeyState() {
    KeyState? keyState = world.network().getGameState().getKeyStateFor(info.connectionId);
    if (keyState == null) {
      throw "No keystate for ${info.connectionId} in world ${world}";
    }
    return keyState;
  }

  bool listenFor(String key, dynamic f) {
    assert(getControls().containsKey(key));
    getKeyState().registerListener(getControls()[key]!, f);
    return true;
  }

  bool keyIsDown(String key) {
    assert(getControls().containsKey(key));
    return getKeyState().keyIsDown(getControls()[key]!);
  }

  double? keyIsDownStrength(String key) {
    assert(getControls().containsKey(key));
    return getKeyState().keyIsDownStrength(getControls()[key]!);
  }

  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = ExtraSpriteData()
      ..extraFloat.add(gun.angle)
      ..extraInt.add(weaponState!.selectedWeaponIndex);
    if (world.network().isCommander()) {
      data.extraInt
        ..add(health)
        ..add(_shieldPoints);
      data.extraFloat
        ..add(_shieldSec)
        ..add(_jetPackSec);
      if (weaponState != null) {
        data.extraInt
          ..add(weaponState!.unlockedWeaponsBitmask)
          ..add(weaponState!.rouletteNonce)
          ..add(weaponState!.rouletteTargetWeaponIndex)
          ..add(weaponState!.rouletteBingoTier.index);
        data.extraFloat.add(weaponState!.rouletteSpinRemaining);
      }
    } else if (weaponState != null) {
      data.extraInt.add(weaponState!.completedRouletteNonce);
    }
    return data;
  }

  void parseExtraNetworkData(ExtraSpriteData data) {
    gun.angle = data.extraFloat[0];
    if (weaponState != null &&
        data.extraInt.length >= 6 &&
        data.extraFloat.length >= 4 &&
        !world.network().isCommander()) {
      final int bingoIdx = data.extraInt.length >= 7 ? data.extraInt[6] : 0;
      weaponState!.applyCommanderSync(
        unlockedMask: data.extraInt[3],
        rouletteNonce: data.extraInt[4],
        rouletteTarget: data.extraInt[5],
        rouletteSpinRem: data.extraFloat[3],
        rouletteBingoIndex: bingoIdx,
      );
    }
    if (weaponState != null) {
      if (!_ownedByThisWorld()) {
        final int requestedIdx = data.extraInt[0];
        if (!world.network().isCommander()) {
          weaponState!.selectedWeaponIndex = requestedIdx;
        } else {
          final int clientCompletedNonce =
              data.extraInt.length >= 2 ? data.extraInt[1] : 0;
          final bool clientCaughtUpWithRoulette =
              !weaponState!.isRouletteSpinning &&
              clientCompletedNonce >= weaponState!.completedRouletteNonce;
          if (clientCaughtUpWithRoulette &&
              weaponState!.isWeaponAvailable(requestedIdx)) {
            weaponState!.selectedWeaponIndex = requestedIdx;
          }
        }
      }
    }
    if (!world.network().isCommander() &&
        data.extraInt.length >= 3 &&
        data.extraFloat.length >= 2) {
      health = data.extraInt[1];
      _shieldPoints = data.extraInt[2];
      _shieldSec = data.extraFloat[1];
      if (data.extraFloat.length > 2 && !_ownedByThisWorld()) {
        _jetPackSec = data.extraFloat[2];
      }
    }
  }

  int get shieldPoints => _shieldPoints;

  void set shieldPoints(int shieldPoints) {
    this._shieldPoints = shieldPoints;
  }

  double get jetPackSec => _jetPackSec;

  void set jetPackSec(double secs) {
    this._jetPackSec = secs;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.REMOTE_PLAYER_CLIENT_SPRITE;
  }

  String toString() => "PlayerSprite for ${info.name}";
}

/// Renders the player's equipped cartoon blaster (`gun.png`), keeping the sight
/// rail upright when aiming left (`cos(angle) < 0`) and adding a snappy barrel
/// recoil kick whenever a shot is fired.
class PlayerGunSprite extends StickySprite {
  final LocalPlayerSprite player;
  final ImageIndex _gunImageIndex;
  double _recoil = 0.0;
  int _lastShotsLeft = -1;
  int _lastWeaponIdx = -1;

  PlayerGunSprite(this.player, int imageId, this._gunImageIndex)
      : super(player, imageId, _gunImageIndex, Sprite.UNLIMITED_LIFETIME);

  @override
  frame(double duration, int frames, [Vec2? gravity]) {
    super.frame(duration, frames, gravity);
    final WeaponState? ws = player.weaponState;
    if (ws != null) {
      final int idx = ws.selectedWeaponIndex;
      final int shots = ws.getSelectedWeapon().shotsLeft;
      if (idx == _lastWeaponIdx && _lastShotsLeft >= 0 && shots < _lastShotsLeft) {
        _recoil = 1.0;
      }
      _lastWeaponIdx = idx;
      _lastShotsLeft = shots;
    }
    if (_recoil > 0.0) {
      _recoil = max(0.0, _recoil - duration * 9.0);
    }
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final Vec2 c = centerPoint();
    context.save();
    context.translate(c.x, c.y);
    context.rotate(angle);
    // Flip vertically when aiming left so the orange top sight & grip stay upright!
    if (cos(angle) < 0.0) {
      context.scale(1.0, -1.0);
    }

    final double kick = sin(_recoil * pi * 0.5) * 4.5;
    const double forwardVisualShift = 4.0;
    try {
      final HTMLImageElement image = _gunImageIndex.getImageById(imageId);
      final num srcW = frameWidth > 0 ? frameWidth : image.width;
      final num srcH = image.height;
      if (srcW > 0 && srcH > 0) {
        context.drawImage(
          image,
          frameWidth * frameIndex,
          0,
          srcW,
          srcH,
          -size.x * 0.5 + forwardVisualShift - kick,
          -size.y * 0.5,
          size.x,
          size.y,
        );
      }
    } catch (_) {}

    context.restore();
    if (debug) {
      super.draw(context, true);
    }
  }
}
