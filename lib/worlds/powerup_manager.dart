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

  SpriteIndex _spriteIndex;
  ImageIndex _imageIndex;
  ByteWorld _byteWorld;
  List<Powerup> activePowerups = [];

  double _nextPowerupin = POWERUP_SPAWN_TIME / 2;

  PowerupManager(this._spriteIndex, this._imageIndex, this._byteWorld) {
    log.info("Created PowerupManager spawning every ${POWERUP_SPAWN_TIME} seconds");
  }

  void frame(double duration) {
    _nextPowerupin -= duration;
    if (_nextPowerupin < 0) {
      _nextPowerupin = POWERUP_SPAWN_TIME;
      List<Powerup> filtered = [];
      for (Powerup p in activePowerups) {
        if (!p.remove) {
          filtered.add(p);
        }
      }
      activePowerups = filtered;

      if (activePowerups.length < MAX_POWERUPS) {
        addNewRandomPowerup();
      }
    }
  }

  void addNewRandomPowerup() {
    PowerUpType type =
        PowerUpType.values[new Random().nextInt(PowerUpType.values.length)];
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
