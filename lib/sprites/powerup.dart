import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
import 'package:web/web.dart';
import 'package:dart2d/worlds/byteworld.dart';

enum PowerUpType {
  SHIELD,
  HEALTH,
  JETPACK,
  POWERUP,
  // DFG,
  // BLACK_SHEEP_WALL
}

class Powerup extends MovingSprite {
  static final double BLINK_TIME = 0.3;
  static final Vec2 SIZE_OFFSET = new Vec2(37, 37);

  static final double BOUNCHE = 0.7;
  static final int LIFETIME = 20 * 24;
  static final int ALPHA_LOWER = (LIFETIME / 4).toInt();

  static Map<PowerUpType, String> _IMAGES = {
    PowerUpType.HEALTH: "health02.png",
    PowerUpType.SHIELD: "shieldi02.png",
    PowerUpType.JETPACK: "soda.png",
    PowerUpType.POWERUP: "powerup.png",
  };
  static Map<PowerUpType, String> _NAMES = {
    PowerUpType.HEALTH: "Health restoration",
    PowerUpType.SHIELD: "Personal border wall",
    PowerUpType.JETPACK:"Fizzy Bubbletech",
    PowerUpType.POWERUP:"Random",
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
    PowerUpType.POWERUP:  (Powerup self, LocalPlayerSprite s) {
      print("You took it, congrats!");
      self.remove = true;
    },
  };

  late PowerUpType _type;

  StickySprite? _swiwel;

  Powerup(Vec2 position, PowerUpType type, ImageIndex imageIndex) :
        super.imageBasedSprite(position, imageIndex.getImageIdByName(_IMAGES[type]!), imageIndex) {
    this._type = type;
    lifeTime = LIFETIME;
    Random r = new Random();
    velocity = new Vec2(r.nextInt(300), -100);
    if (r.nextBool()) {
      velocity = velocity.multiply(-1.0);
    }
    if (_type == PowerUpType.POWERUP) {
      _swiwel = _createSwivel(imageIndex);
      size = SIZE_OFFSET;
    }
  }

  StickySprite _createSwivel(ImageIndex index) {
    StickySprite swivel = new StickySprite(this, index.getImageIdByName("powerup_swiwel.png"),
        index, Sprite.UNLIMITED_LIFETIME);
    swivel.size = SIZE_OFFSET;
    return swivel;
  }

  Powerup.createEmpty(ImageIndex index)
      : super.empty(index) {
  }

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    context.save();
    if (this.lifeTime < ALPHA_LOWER) {
      context.globalAlpha = lifeTime / ALPHA_LOWER;
    }
    super.draw(context, debug);
    context.restore();
    _swiwel?.draw(context, debug);
  }


  Vec2 baseSize = SIZE_OFFSET;

  @override
  frame(double duration, int frames, [Vec2? gravity]) {
    super.frame(duration, frames, gravity);

    if (_swiwel != null) {
      _swiwel?.frame(duration, frames, gravity);
    }
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
          if (_type != PowerUpType.POWERUP) {
            if (velocity.x < -2.0) {
              rotationVelocity = velocity.x / 2;
            } else {
              rotationVelocity = 0.0;
            }
          }
          velocity.x = -velocity.x * BOUNCHE;
        }
      }
      if (direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          if (_type != PowerUpType.POWERUP) {
            if (velocity.x > 2.0) {
              rotationVelocity = velocity.x / 2;
            } else {
              rotationVelocity = 0.0;
            }
          }
          velocity.x = -velocity.x * BOUNCHE;
        }
      }
    }
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.POWERUP;
  }

  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = ExtraSpriteData();
    data.extraInt.add(_type.index);
    return data;
  }

  void parseExtraNetworkData(ExtraSpriteData data) {
    _type = PowerUpType.values[data.extraInt[0]];
  }
}