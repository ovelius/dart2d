import 'dart:js_interop';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/res/sounds.dart';
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
  PowerUpType get type => _type;

  final ImageIndex _powerupImageIndex;
  StickySprite? _swiwel;
  double _animTime = 0.0;

  Powerup(Vec2 position, PowerUpType type, ImageIndex imageIndex) :
        _powerupImageIndex = imageIndex,
        super.imageBasedSprite(position, imageIndex.getImageIdByName(_IMAGES[type]!), imageIndex) {
    this._type = type;
    lifeTime = LIFETIME;
    Random r = new Random();
    _animTime = r.nextDouble() * 10.0;
    velocity = new Vec2(r.nextInt(300), -100);
    if (r.nextBool()) {
      velocity = velocity.multiply(-1.0);
    }
    if (_type == PowerUpType.POWERUP) {
      _swiwel = _createSwivel(imageIndex);
    }
    size = new Vec2.copy(SIZE_OFFSET);
  }

  StickySprite _createSwivel(ImageIndex index) {
    StickySprite swivel = new StickySprite(this, index.getImageIdByName("powerup_swiwel.png"),
        index, Sprite.UNLIMITED_LIFETIME);
    swivel.size = SIZE_OFFSET.multiply(1.35);
    swivel.rotationVelocity = 1.8;
    return swivel;
  }

  Powerup.createEmpty(ImageIndex index)
      : _powerupImageIndex = index,
        super.empty(index) {
    _type = PowerUpType.HEALTH;
    lifeTime = LIFETIME;
    size = new Vec2.copy(SIZE_OFFSET);
  }

  double get fadeAlpha =>
      (this.lifeTime != Sprite.UNLIMITED_LIFETIME && this.lifeTime < ALPHA_LOWER)
          ? (lifeTime / ALPHA_LOWER).clamp(0.0, 1.0)
          : 1.0;

  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    final double currentFadeAlpha = fadeAlpha;

    if (_type == PowerUpType.POWERUP) {
      _drawMysteryQuestionCloud(context, currentFadeAlpha, debug);
      return;
    }

    context.save();
    context.globalAlpha = currentFadeAlpha;
    super.draw(context, debug);
    context.restore();
    _swiwel?.draw(context, debug);
  }

  void _drawMysteryQuestionCloud(
      CanvasRenderingContext2D context, double fadeAlpha, bool debug) {
    final Vec2 c = centerPoint();
    final double bobY = sin(_animTime * 4.0) * 3.2;
    final double pulse = 1.0 + sin(_animTime * 5.2) * 0.065;
    final double cy = c.y + bobY;

    // 1. Tempting golden-magenta-cyan radiant aura + rotating comic sunburst rays.
    context.save();
    context.translate(c.x, cy);
    context.globalAlpha = fadeAlpha;

    final double auraR = 40.0 + sin(_animTime * 3.5) * 4.5;
    final CanvasGradient aura = context.createRadialGradient(0, 0, 5.0, 0, 0, auraR);
    aura.addColorStop(0.0, "rgba(255, 232, 102, 0.56)");
    aura.addColorStop(0.48, "rgba(218, 122, 255, 0.26)");
    aura.addColorStop(0.78, "rgba(86, 236, 255, 0.14)");
    aura.addColorStop(1.0, "rgba(86, 236, 255, 0.0)");
    context.fillStyle = aura;
    context.beginPath();
    context.arc(0, 0, auraR, 0, 2 * pi);
    context.fill();

    // Gently spinning golden starburst rays behind the cloud.
    context.save();
    context.rotate(_animTime * 0.85);
    const int rays = 8;
    for (int i = 0; i < rays; i++) {
      final double a0 = (i / rays) * 2 * pi;
      final double a1 = a0 + 0.22;
      final double rayLen = 28.0 + (i.isEven ? 7.0 : 3.0) + sin(_animTime * 4.0 + i) * 2.5;
      context.fillStyle = (i.isEven
              ? "rgba(255, 236, 120, 0.34)"
              : "rgba(180, 245, 255, 0.26)")
          .toJS;
      context.beginPath();
      context.moveTo(0, 0);
      context.arc(0, 0, rayLen, a0, a1);
      context.closePath();
      context.fill();
    }
    context.restore();

    // 2. Fluffy billowing cartoon mystery cloud ring cradling the orb!
    const int puffCount = 8;
    for (int i = 0; i < puffCount; i++) {
      final double angle = (i / puffCount) * 2 * pi + _animTime * 0.72;
      final double dist = 17.5 + sin(_animTime * 3.1 + i * 1.4) * 2.6;
      final double px = cos(angle) * dist;
      final double py = sin(angle) * dist * 0.86;
      final double pr = 8.2 + sin(_animTime * 4.2 + i * 1.9) * 2.0;

      // Soft pastel lavender-gold cloud puff tint.
      context.fillStyle = (i.isEven
              ? "rgba(255, 248, 255, 0.54)"
              : "rgba(235, 246, 255, 0.48)")
          .toJS;
      context.beginPath();
      context.arc(px, py, pr, 0, 2 * pi);
      context.fill();

      // Subtle glossy highlight inside puff.
      context.fillStyle = "rgba(255, 255, 255, 0.36)".toJS;
      context.beginPath();
      context.arc(px - pr * 0.25, py - pr * 0.25, pr * 0.48, 0, 2 * pi);
      context.fill();
    }
    context.restore();

    // 3. Swirling iridescent halo sprite (if present).
    if (_swiwel != null) {
      context.save();
      context.globalAlpha = fadeAlpha * 0.72;
      context.translate(0, bobY);
      _swiwel!.draw(context, debug);
      context.restore();
    }

    // 4. The tempting golden `?` orb with bob + enticing heartbeat scale pulse!
    context.save();
    context.globalAlpha = fadeAlpha;
    context.translate(c.x, cy);
    context.scale(pulse, pulse);
    context.translate(-c.x, -c.y);
    super.draw(context, debug);
    context.restore();

    // 5. Rising cartoon mini `?` glyphs + twinkling golden stars floating out of the cloud!
    context.save();
    context.translate(c.x, cy);
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.lineJoin = "round";

    const List<String> qColors = ["#ffe44d", "#ff6eb4", "#5ef2ff", "#ffae42", "#c88cff"];
    for (int i = 0; i < 5; i++) {
      final double cycle = (_animTime * 0.55 + i * 0.2) % 1.0;
      final double qAlpha = sin(cycle * pi) * fadeAlpha;
      final double baseAngle = i * 1.35 - 0.5;
      final double qx = sin(baseAngle) * (15.0 + cycle * 14.0) +
          sin(_animTime * 4.5 + i * 2.1) * 4.0;
      final double qy = 8.0 - cycle * 38.0;
      final double qSize = 11.0 + sin(cycle * pi) * 4.5;

      context.save();
      context.globalAlpha = qAlpha.clamp(0.0, 1.0);
      context.translate(qx, qy);
      context.rotate(sin(_animTime * 3.8 + i) * 0.25);
      context.font =
          "900 ${qSize.round()}px 'Comic Sans MS', 'Trebuchet MS', Arial, sans-serif";
      context.strokeStyle = "#2b1236".toJS;
      context.lineWidth = 2.8;
      context.strokeText("?", 0, 0);
      context.fillStyle = qColors[i % qColors.length].toJS;
      context.fillText("?", 0, 0);
      context.restore();
    }

    // Twinkling 4-point comic sparkle stars around the mystery cloud rim.
    for (int i = 0; i < 6; i++) {
      final double twinkle = (sin(_animTime * 6.5 + i * 1.8) * 0.5 + 0.5);
      if (twinkle < 0.25) continue;
      final double a = (i / 6.0) * 2 * pi - _animTime * 0.9;
      final double r = 24.0 + (i % 2) * 7.0;
      final double sx = cos(a) * r;
      final double sy = sin(a) * r;
      final double starR = (3.0 + twinkle * 4.2);

      context.save();
      context.globalAlpha = (twinkle * fadeAlpha).clamp(0.0, 1.0);
      context.translate(sx, sy);
      context.rotate(_animTime * 2.5 + i);
      context.fillStyle = (i.isEven ? "#fff394" : "#ffffff").toJS;
      context.beginPath();
      for (int p = 0; p < 8; p++) {
        final double pa = (p * pi) / 4.0;
        final double pr = p.isEven ? starR : starR * 0.28;
        if (p == 0) {
          context.moveTo(cos(pa) * pr, sin(pa) * pr);
        } else {
          context.lineTo(cos(pa) * pr, sin(pa) * pr);
        }
      }
      context.closePath();
      context.fill();
      context.restore();
    }

    context.restore();
  }


  Vec2 baseSize = SIZE_OFFSET;

  @override
  frame(double duration, int frames, [Vec2? gravity]) {
    _animTime += duration;
    if (remoteControlled()) {
      final int savedLifeTime = lifeTime;
      super.frame(duration, frames, gravity);
      if (savedLifeTime != Sprite.UNLIMITED_LIFETIME) {
        lifeTime = max(1, savedLifeTime - frames);
        remove = false;
      }
    } else {
      super.frame(duration, frames, gravity);
    }

    if (_swiwel != null) {
      _swiwel?.frame(duration, frames, gravity);
    }
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (other is LocalPlayerSprite) {
      dynamic action = _ACTIONS[_type];
      action(this, other);
      if (remove) {
        other.world.playSoundAtSprite(this, Sound.POWERUP);
      }
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
    data.extraInt.add(lifeTime);
    return data;
  }

  void parseExtraNetworkData(ExtraSpriteData data) {
    _type = PowerUpType.values[data.extraInt[0]];
    if (data.extraInt.length > 1) {
      lifeTime = data.extraInt[1];
    }
    if (spriteType != SpriteType.IMAGE) {
      setImage(_powerupImageIndex.getImageIdByName(_IMAGES[_type]!), 1);
      spriteType = SpriteType.IMAGE;
    }
    if (size.x <= 1.0 && size.y <= 1.0) {
      size = new Vec2.copy(SIZE_OFFSET);
    }
    if (_type == PowerUpType.POWERUP && _swiwel == null) {
      _swiwel = _createSwivel(_powerupImageIndex);
    } else if (_type != PowerUpType.POWERUP) {
      _swiwel = null;
    }
  }
}