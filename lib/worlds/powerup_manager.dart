import 'package:di/di.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'byteworld.dart';
import 'dart:math';

@Injectable()
class PowerupManager {
  final Logger log = new Logger('PowerupManager');
  static int MAX_POWERUPS = 4;
  static double POWERUP_SPAWN_TIME = 10.0;

  SpriteIndex _spriteIndex;
  ImageIndex _imageIndex;
  ByteWorld _byteWorld;
  List<Powerup> activePowerups = [];

  double _nextPowerupIn = POWERUP_SPAWN_TIME / 2;

  PowerupManager(this._spriteIndex, this._imageIndex, this._byteWorld);

  void frame(double duration) {
    _nextPowerupIn -= duration;
    if (_nextPowerupIn < 0) {
      _nextPowerupIn = POWERUP_SPAWN_TIME;
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
    _nextPowerupIn = time;
  }
}
