import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'byteworld.dart';
import 'dart:math';

@Singleton(scope: 'world')
class PowerupManager {
  final Logger log = new Logger('PowerupManager');
  static int MAX_POWERUPS = 4;
  static double POWERUP_SPAWN_TIME = 10.0;
  static double MIN_POWERUP_SPAWN_TIME = 2.5;
  static const double MYSTERY_POWERUP_PROBABILITY = 0.55;

  SpriteIndex _spriteIndex;
  ImageIndex _imageIndex;
  ByteWorld _byteWorld;
  List<Powerup> activePowerups = [];
  bool mysteryPowerupEnabled = true;
  final Random _random = new Random();

  double _nextPowerupin = MIN_POWERUP_SPAWN_TIME;

  PowerupManager(this._spriteIndex, this._imageIndex, this._byteWorld) {
    log.info("Created PowerupManager spawning every ${MIN_POWERUP_SPAWN_TIME}-${POWERUP_SPAWN_TIME} seconds");
  }

  void reset() {
    for (Powerup p in activePowerups) {
      p.remove = true;
    }
    activePowerups.clear();
    _nextPowerupin = MIN_POWERUP_SPAWN_TIME;
  }

  /// Returns a shorter spawn interval when fewer powerups are active in the world.
  double nextSpawnInterval() {
    if (MAX_POWERUPS <= 0) {
      return POWERUP_SPAWN_TIME;
    }
    final double fillRatio =
        (activePowerups.length / MAX_POWERUPS).clamp(0.0, 1.0);
    return MIN_POWERUP_SPAWN_TIME +
        (POWERUP_SPAWN_TIME - MIN_POWERUP_SPAWN_TIME) * fillRatio;
  }

  void _pruneRemovedPowerups() {
    final int prevCount = activePowerups.length;
    activePowerups.removeWhere((p) => p.remove);
    if (activePowerups.length < prevCount) {
      _nextPowerupin = min(_nextPowerupin, nextSpawnInterval());
    }
  }

  void pruneRemoved() {
    _pruneRemovedPowerups();
  }

  void trackPowerup(Powerup powerup) {
    if (powerup.remove) {
      return;
    }
    final bool alreadyTracked = activePowerups.any((p) =>
        identical(p, powerup) ||
        (p.networkId != null && p.networkId == powerup.networkId));
    if (!alreadyTracked) {
      activePowerups.add(powerup);
    }
  }

  void syncWithSpriteIndex() {
    final int prevCount = activePowerups.length;
    activePowerups.removeWhere((p) {
      if (p.remove) {
        return true;
      }
      final int? id = p.networkId;
      if (id == null) {
        return false;
      }
      if (_spriteIndex.isPendingRemoval(id) == true) {
        return true;
      }
      return !_spriteIndex.hasSprite(id) &&
          _spriteIndex.getPendingSprite(id) == null;
    });
    for (int id in _spriteIndex.spriteIds()) {
      if (_spriteIndex.isPendingRemoval(id) == true) {
        continue;
      }
      Sprite? s = _spriteIndex[id];
      if (s is Powerup && !s.remove) {
        trackPowerup(s);
      }
    }
    for (Sprite s in (_spriteIndex.pendingSprites() ?? const <Sprite>[])) {
      final int? id = s.networkId;
      if (id != null && _spriteIndex.isPendingRemoval(id) == true) {
        continue;
      }
      if (s is Powerup && !s.remove) {
        trackPowerup(s);
      }
    }
    if (activePowerups.length < prevCount) {
      _nextPowerupin = min(_nextPowerupin, nextSpawnInterval());
    } else if (activePowerups.length > prevCount &&
        _nextPowerupin < nextSpawnInterval()) {
      _nextPowerupin = nextSpawnInterval();
    }
  }

  void frame(double duration) {
    _pruneRemovedPowerups();
    _nextPowerupin -= duration;
    if (_nextPowerupin < 0) {
      if (activePowerups.length < MAX_POWERUPS) {
        addNewRandomPowerup();
      }
      _nextPowerupin = nextSpawnInterval();
    }
  }

  double get nextPowerupIn => _nextPowerupin;

  List<PowerUpType> get spawnableTypes => mysteryPowerupEnabled
      ? PowerUpType.values
      : PowerUpType.values
          .where((PowerUpType t) => t != PowerUpType.POWERUP)
          .toList(growable: false);

  PowerUpType _chooseNextPowerupType() {
    final List<PowerUpType> nonMystery = PowerUpType.values
        .where((PowerUpType t) => t != PowerUpType.POWERUP)
        .toList(growable: false);
    if (!mysteryPowerupEnabled) {
      return nonMystery[_random.nextInt(nonMystery.length)];
    }

    // Guarantee at least half of active powerups are mystery powerups whenever
    // >= 2 powerups are active, AND roll >= 55% mystery probability otherwise.
    final int activeMysteryCount = activePowerups
        .where((Powerup p) => !p.remove && p.type == PowerUpType.POWERUP)
        .length;
    final int nextTotal = activePowerups.length + 1;
    final int minMysteryRequired = nextTotal ~/ 2;
    if (activeMysteryCount < minMysteryRequired) {
      return PowerUpType.POWERUP;
    }
    if (_random.nextDouble() < MYSTERY_POWERUP_PROBABILITY) {
      return PowerUpType.POWERUP;
    }
    return nonMystery[_random.nextInt(nonMystery.length)];
  }

  void addNewRandomPowerup() {
    if (activePowerups.length >= MAX_POWERUPS) {
      return;
    }
    final PowerUpType type = _chooseNextPowerupType();
    Powerup p = new Powerup(_byteWorld.randomNotSolidPoint(
        Powerup.SIZE_OFFSET), type, _imageIndex);
    _spriteIndex.addSprite(p);
    log.info("Added new powerup ${type} to world at ${p.position}");
    trackPowerup(p);
  }

  setNextPowerForTest(double time) {
    _nextPowerupin = time;
  }
}
