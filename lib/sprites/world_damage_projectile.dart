
import 'dart:js_interop';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:web/web.dart';

import '../res/sounds.dart';
import 'movingsprite.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('DamageProjectile');

class BananaCake extends WorldDamageProjectile {
  BananaCake.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
       : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
      this.world = world;
      this.owner = owner;
      this.damage = damage;
      Vec2 ownerCenter = owner.centerPoint();
      this.size = new Vec2(15.0, 17.0);
      this.position.x = ownerCenter.x - size.x / 2;
      this.position.y = ownerCenter.y - size.y / 2;
      this.spriteType = SpriteType.IMAGE;
      this.velocity.x = cos(positionBase.angle);
      this.velocity.y = sin(positionBase.angle);
      this.velocity = this.velocity.multiply(200.0);
      this.velocity = owner.velocity + this.velocity;
    }
  
  explode() {
    world.explosionAtSprite(
        sprite: this, velocity: velocity.multiply(0.2),
        addParticles: particlesOnExplode,
        damage: damage, radius: radius, damageDoer: owner!, mod:Mod.BANANA);
    for (int i = 0; i < 9; i++) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(world,
          this.owner!, 30, positionBase: this);
      sprite.mod = Mod.BANANA;
      sprite.setImage(world.imageIndex().getImageIdByName("banana.png"), 1);
      sprite.position = Vec2.copy(this.position);
      sprite.velocity.x = -pi * 2; 
      sprite.velocity.y = -pi * 2; 
      sprite.velocity.x += WorldDamageProjectile.random.nextDouble() * pi * 4;
      sprite.velocity.y += WorldDamageProjectile.random.nextDouble() * pi * 4;
      sprite.velocity = sprite.velocity.normalize().multiply(500.0);
      sprite.velocity = velocity + sprite.velocity;
      sprite.rotationVelocity = WorldDamageProjectile.random.nextDouble() * 200.1;
      sprite.radius = 40.0;
      world.addSprite(sprite);
    }
    this.remove = true;
  }
}

class Hyper extends WorldDamageProjectile {
  static const int EFFECTIVE_DISTANCE = 300;
  static const int DPS_BEAM = 30;
  static const double SOUND_LOOP = 1.0;
  int _quality = 40;

  List<LocalPlayerSprite> _spritesInDamageArea = [];
  double _time = 0.0;

  double _nextSound = 0.0;

  Hyper(WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super(world, x, y, imageId, imageIndex);

  Hyper.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.color = "#A400AF";
    double ownerSize = positionBase.size.sum() / 2;
    Vec2 positionCenter = positionBase.centerPoint();
    this.size = new Vec2(25.0, 25.0);
    this.position.x = positionCenter.x + cos(positionBase.angle) * ownerSize;
    this.position.y = positionCenter.y + sin(positionBase.angle) * ownerSize;
    this.velocity.x = cos(positionBase.angle);
    this.angle = positionBase.angle;
    this.velocity.y = sin(positionBase.angle);
    this.velocity = this.velocity.multiply(150.0);
    this.velocity = owner.velocity + this.velocity;
    this.spriteType = SpriteType.CUSTOM;
  }

  void _collectDamageSprites() {
    List<LocalPlayerSprite> spritesInDamageArea = [];
    for (PlayerInfoProto inf in world.network().gameState.playerInfoList()) {
      if (inf.spriteId != owner?.networkId) {
        LocalPlayerSprite? sprite = world.spriteIndex[inf.spriteId] as LocalPlayerSprite?;
        if (sprite != null && sprite.inGame() && sprite.takesDamage(Mod.HYPER)) {
          double dst = distanceTo(sprite);
          if (dst < EFFECTIVE_DISTANCE) {
            spritesInDamageArea.add(sprite);
          }
        }
      }
    }
    _spritesInDamageArea = spritesInDamageArea;
  }

  frame(double duration, int frameStep, [Vec2? gravity]) {
    _time += duration;
    _nextSound -= duration;
    int damage = (_time * DPS_BEAM).toInt();
    _time -= (damage / DPS_BEAM);
    _collectDamageSprites();
    if (_nextSound < 0) {
      _nextSound += SOUND_LOOP;
      world.playSoundAtSprite(this, Sound.BUZZ, playSpriteId: true);
    }
    if (owner != null) {
      for (LocalPlayerSprite damageSprite in _spritesInDamageArea) {
        if (damageSprite.takesDamage(Mod.HYPER)) {
          damageSprite.takeDamage(damage, owner!, Mod.HYPER);
        }
      }
    }
    super.frame(duration, frameStep, gravity);
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    Vec2 center = centerPoint();
    for (LocalPlayerSprite sprite in _spritesInDamageArea) {
      if (sprite.inGame() && sprite.takesDamage(Mod.HYPER)) {
        Vec2 targetCenter = sprite.centerPoint();
        context.lineWidth = 4;
        context.strokeStyle = color.toJS;
        context.globalCompositeOperation = "lighter";
        context.beginPath();
        context.moveTo(center.x, center.y);
        context.lineTo(targetCenter.x, targetCenter.y);
        context.stroke();
      }
    }

    super.draw(context, debug);
    double r = getRadius() * 6;
    context.translate(-r, -r);
    context.strokeStyle = this.color.toJS;
    context.globalCompositeOperation = "lighter";
    context.lineWidth = 2;
    for (var i = 0; i < _quality; i++) {
      var theta = 2 * pi * WorldDamageProjectile.random.nextDouble();
      var x = r + (r * cos(theta) / 2);
      var y = r + (r * sin(theta) / 2);
      drawSeed(context, x, y, r);
    }
  }

  drawSeed(CanvasRenderingContext2D ctx, num x,y,r) {
    num fractions = 3;
    num xM = r;
    num yM = r;
    num xStep = (xM - x) / fractions;
    num yStep = (yM - y) / fractions;
    for (int i = 0; i < fractions; i++) {
      num nextX = xStep * WorldDamageProjectile.random.nextDouble();
      num nextY = yStep * WorldDamageProjectile.random.nextDouble();
      ctx.globalAlpha = 1.0 - (i / fractions);
      drawPath(ctx, xM, yM, xM + nextX, yM + nextY);
      xM += nextX;
      yM += nextY;
    }
  }

  drawPath(CanvasRenderingContext2D ctx, num startX, startY, num destX, destY) {
    ctx.beginPath();
    ctx.moveTo(startX, startY);
    ctx.lineTo(destX, destY);
    ctx.stroke();
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (networkType == NetworkType.REMOTE) {
      return;
    }
    if (owner != null && other != null && other.networkId != owner!.networkId && other.takesDamage(Mod.HYPER)) {
      other.takeDamage(damage, owner!, Mod.HYPER);
      remove = true;
    }
    if (world != null && other == null) {
      remove = true;
    }
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.HYPER;
  }
}

class BrickBuilder extends WorldDamageProjectile {
  static const String COLOR = "#aa3311";
  static const int COLOR_R = 170;
  static const int COLOR_G = 51;
  static const int COLOR_B = 17;
  BrickBuilder.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, MovingSprite positionBase)
      : super(world, 0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(5.0, 5.0);
    this.position.x = ownerCenter.x - size.x / 2;
    this.position.y = ownerCenter.y - size.y / 2;
    this.spriteType = SpriteType.CIRCLE;
    this.color = COLOR;
    this.velocity.x = cos(positionBase.angle);
    this.velocity.y = sin(positionBase.angle);
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = owner.velocity + this.velocity;
  }

  explode() {
    Vec2 brickSize = new Vec2(80, 28);
    Vec2 center = centerPoint();
    center.x -= brickSize.x / 2;
    Vec2 outerPosition = new Vec2.copy(center);
    Vec2 brickPosition = new Vec2.copy(center);
    outerPosition.x -= 1;
    outerPosition.y -= 1;

    bool aligned = false;
    // Try and align brick with other bricks.
    int alignBelow = 0;
    List<int> existingBrick = world.byteWorld.getImageData(center, new Vec2(1, brickSize.y));
    for (int i = 0; i < existingBrick.length ~/ 4; i++) {
      if (existingBrick[i * 4] == COLOR_R && existingBrick[i * 4 + 1] == COLOR_G && existingBrick[i * 4 + 2] == COLOR_B) {
        break;
      } else {
        alignBelow++;
      }
    }
    if (alignBelow > 0) {
      brickPosition.y -= brickSize.y.toInt();
      outerPosition.y -= brickSize.y.toInt();
      brickPosition.y += alignBelow;
      outerPosition.y += alignBelow;
      aligned = true;
    }

    if (!aligned) {
      // Try and align brick with other bricks.
      int alignAbove = 0;
      List<int> existingBrick = world.byteWorld.getImageData(
          center, new Vec2(1, brickSize.y));
      for (int i = (existingBrick.length ~/ 4) -1; i >= 0; i--) {
        if (existingBrick[i * 4] == COLOR_R &&
            existingBrick[i * 4 + 1] == COLOR_G &&
            existingBrick[i * 4 + 2] == COLOR_B) {
          break;
        } else {
          alignAbove--;
        }
      }
      if (alignAbove < 0) {
        brickPosition.y += brickSize.y.toInt();
        outerPosition.y += brickSize.y.toInt();
        brickPosition.y += alignAbove;
        outerPosition.y += alignAbove;
      }
    }

    world.fillRectAt(outerPosition, new Vec2(brickSize.x + 2, brickSize.y + 2), "#ffffff");
    world.fillRectAt(brickPosition, brickSize, COLOR);
    this.remove = true;
  }
}

class WorldDamageProjectile extends MovingSprite {
  // Visible for testing.
  static Random random = new Random();

  late WormWorld world;
  int damage = 1;

  double bounche = 0.5;
  
  double radius = 15.0;

  // Counter until explode.
  double? explodeAfter = null;

  // Draw the counter?
  bool showCounter = true;

  // Create particles when exploding.
  bool particlesOnExplode = true;

  // Remove when colliding with something.
  bool removeOnCollision = true;

  // Can collide with world ?
  bool worldCollide = true;

  // If this can be take damage/be destroyed.
  int health = -1;

  Vec2? maxSpeed = null;

  Mod mod = Mod.UNKNOWN;
  
  WorldDamageProjectile(WormWorld world, double x, double y, int imageId, ImageIndex imageIndex)
      : super.imageBasedSprite(new Vec2(x, y), imageId, imageIndex) {
    this.world = world;
  }

  bool takesDamage(Mod mod) {
    return health > 0 && mod != Mod.TV;
  }

  void takeDamage(int damage, LocalPlayerSprite inflictor, Mod mod) {
    health -= damage;
    if (health < 0) {
      remove = true;
    }
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (networkType == NetworkType.REMOTE) {
      return;
    }
    if (other != null && owner != null && other.networkId != owner!.networkId && other.takesDamage(mod)) {
      other.takeDamage(damage, owner!, mod);
      if (removeOnCollision) {
        explode();
      }
    }
    if (world != null && direction != null) {
      handleWorldCollide(world, direction);
    }
  }

  handleWorldCollide(ByteWorld world, int direction) {
    if (explodeAfter == null) {
      explode();
    } else if (worldCollide) {
      if (direction & MovingSprite.DIR_BELOW == MovingSprite.DIR_BELOW) {
        if (velocity.y > 0) {
          velocity.y = -velocity.y * bounche;
        }
        // Make the "above" check exclusive, as a hacky way of preferring objects to
        // go upwards.
      } else if(direction & MovingSprite.DIR_ABOVE == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * bounche;
        }
      }
      if(direction & MovingSprite.DIR_LEFT == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          velocity.x = -velocity.x * bounche;
        }
      }
      if(direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          velocity.x = -velocity.x * bounche;
        }
      }
    }
  }
  explode() {
    if (radius > 0.0) {
      world.explosionAtSprite(
        sprite: this, velocity: velocity.multiply(0.2),
        addParticles: particlesOnExplode,
        damage: damage, radius: radius, damageDoer: owner!, mod:mod);
    }
    if (removeOnCollision) {
      this.remove = true;
    }
  }
  
  frame(double duration, int frameStep, [Vec2? gravity]) {
    if (networkType != NetworkType.REMOTE) {
      if (explodeAfter != null) {
        explodeAfter = explodeAfter! - duration;
        if (explodeAfter! < 0) {
          explode();
        }
      }
    }
    Vec2? maxSpeed = this.maxSpeed;
    if (maxSpeed != null) {
      if (maxSpeed.x > 0 && velocity.x > maxSpeed.x) {
        this.velocity.x = maxSpeed.x;
        this.acceleration.x = 0;
      }
      if (maxSpeed.x < 0 && velocity.x < maxSpeed.x) {
        this.velocity.x = maxSpeed.x;
        this.acceleration.x = 0;
      }
      if (maxSpeed.y > 0 && velocity.y > maxSpeed.y) {
        this.velocity.y = maxSpeed.y;
        this.acceleration.y = 0;
      }
      if (maxSpeed.y < 0 && velocity.y < maxSpeed.y) {
        this.velocity.y = maxSpeed.y;
        this.acceleration.y = 0;
      }
    }
    super.frame(duration, frameStep, gravity);
  }
  
  draw(var context, bool debug) {
    if (explodeAfter != null && showCounter) {
      context.fillStyle = "#ffffff".toJS;
      context.fillText(
        explodeAfter!.toInt().toString(), position.x, position.y - size.y);
    }
    super.draw(context, debug);
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.DAMAGE_PROJECTILE;
  }

  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = ExtraSpriteData()
     ..extraFloat.add(radius)
     ..extraInt.add(damage)
     ..extraInt.add(owner == null ? -1 : owner!.networkId!)
     ..extraInt.add(health)
     ..extraBool.add(showCounter)
     ..extraBool.add(removeOnCollision);
    if (explodeAfter != null) {
      data.extraFloat.add(explodeAfter!);
    }
    return data;
  }

  void parseExtraNetworkData(ExtraSpriteData data) {
    radius = data.extraFloat[0];
    damage = data.extraInt[0];
    showCounter = data.extraBool[0];
    removeOnCollision = data.extraBool[1];
    int ownerId = data.extraInt[1];
    health = data.extraInt[2];
    this.owner = world.spriteIndex[ownerId] as LocalPlayerSprite?;
    if (data.extraFloat.length > 1) {
      this.explodeAfter = data.extraFloat[1];
    }
  }

  WorldDamageProjectile.createWithOwner(WormWorld world, LocalPlayerSprite owner, int damage, {MovingSprite? positionBase = null, Vec2? size = null})
     : super.imageBasedSprite(new Vec2(), world.imageIndex().getImageIdByName("zooka.png"), world.imageIndex()) {
    if (positionBase == null) {
      positionBase = owner;
    }
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    this.size = size == null? new Vec2(15.0, 7.0) : size;
    double ownerSize = owner.size.sum() / 2;
    Vec2 positionCenter = owner.centerPoint();
    this.setCenter(Vec2(positionCenter.x + cos(positionBase.angle) * ownerSize,
        positionCenter.y + sin(positionBase.angle) * ownerSize));
    this.velocity.x = cos(positionBase.angle);
    this.angle = positionBase.angle;
    this.velocity.y = sin(positionBase.angle);
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = positionBase.velocity + this.velocity;
  }
}