import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
import 'package:dart2d/worlds/byteworld.dart';

enum PowerUpType {
  SHIELD,
  HEALTH,
  JETPACK,
  // DFG,
  // BLACK_SHEEP_WALL
}

class Powerup extends MovingSprite {
  static final double BLINK_TIME = 0.3;
  static final Vec2 SIZE_OFFSET = new Vec2(37, 37);

  static final double BOUNCHE = 0.7;
  static final int LIFETIME = 20 * 24;

  static Map<PowerUpType, String> _IMAGES = {
    PowerUpType.HEALTH: "health02.png",
    PowerUpType.SHIELD: "shieldi02.png",
    PowerUpType.JETPACK: "soda.png",
  };
  static Map<PowerUpType, String> _NAMES = {
    PowerUpType.HEALTH: "Health restoration",
    PowerUpType.SHIELD: "Border wall",
    PowerUpType.JETPACK:"Fizzy Bubblech",
  };
  static Map<PowerUpType, dynamic> _ACTIONS =  {
    PowerUpType.HEALTH: (Powerup self, LocalPlayerSprite s) {
      if (s.health < LocalPlayerSprite.MAX_HEALTH) {
        s.health = LocalPlayerSprite.MAX_HEALTH;
        self.remove = true;
      }
    },
    PowerUpType.SHIELD: (Powerup self, LocalPlayerSprite s) {
      if (s.shieldPoints < LocalPlayerSprite.MAX_SHIELD) {
        s.shieldPoints = LocalPlayerSprite.MAX_SHIELD;
        self.remove = true;
      }
    },
    PowerUpType.JETPACK: (Powerup self, LocalPlayerSprite s) {
      s.jetPackSec = 60.0;
      self.remove = true;
    },
  };

  late PowerUpType _type;
  double _blink = BLINK_TIME;

  Powerup(Vec2 position, PowerUpType type, ImageIndex imageIndex) :
        super.imageBasedSprite(position, imageIndex.getImageIdByName(_IMAGES[type]!), imageIndex) {
    this._type = type;
    lifeTime = LIFETIME;
    Random r = new Random();
    velocity = new Vec2(r.nextInt(300), -100);
    if (r.nextBool()) {
      velocity = velocity.multiply(-1.0);
    }
  }

  Powerup.createEmpty(ImageIndex index)
      : super.empty(index) {
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (other is LocalPlayerSprite) {
      dynamic action = _ACTIONS[_type];
      action(this, other);
    }
    if (direction != null) {
      if (direction & MovingSprite.DIR_BELOW == MovingSprite.DIR_BELOW) {
        if (velocity.y > 0) {
          velocity.y = -velocity.y * BOUNCHE;
        }
        // Make the "above" check exclusive, as a hacky way of preferring objects to
        // go upwards.
      } else if (direction & MovingSprite.DIR_ABOVE == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * BOUNCHE;
        }
      }
      if (direction & MovingSprite.DIR_LEFT == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          if (velocity.x < -2.0) {
            rotationVelocity = velocity.x / 2;
          } else {
            rotationVelocity = 0.0;
          }
          velocity.x = -velocity.x * BOUNCHE;
        }
      }
      if (direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          if (velocity.x > 2.0) {
            rotationVelocity = velocity.x / 2;
          } else {
            rotationVelocity = 0.0;
          }
          velocity.x = -velocity.x * BOUNCHE;
        }
      }
    }
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.POWERUP;
  }

  void addExtraNetworkData(List<dynamic> data) {
    data.add(_type.index);
  }

  void parseExtraNetworkData(List<dynamic> data, int startAt) {
    _type = PowerUpType.values[data[startAt]];
  }
}