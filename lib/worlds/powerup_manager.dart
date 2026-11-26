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

  SpriteIndex _spriteIndex;
  ImageIndex _imageIndex;
  ByteWorld _byteWorld;
  List<Powerup> activePowerups = [];

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

  void addNewRandomPowerup() {
    PowerUpType type = PowerUpType.values[new Random().nextInt(PowerUpType.values.length)];
    Powerup p = new Powerup(_byteWorld.randomNotSolidPoint(
        Powerup.SIZE_OFFSET), type, _imageIndex);
    _spriteIndex.addSprite(p);
    log.info("Added new powerup ${type} to world at ${p.position}");
    activePowerups.add(p);
  }

  setNextPowerForTest(double time) {
    _nextPowerupin = time;
  }
}
