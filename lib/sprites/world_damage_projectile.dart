
import 'movingsprite.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';

class BananaCake extends WorldDamageProjectile {
  BananaCake.createWithOwner(WormWorld world, MovingSprite owner, int damage, [double homingFactor])
       : super(0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
      this.world = world;
      this.owner = owner;
      this.damage = damage;
      Vec2 ownerCenter = owner.centerPoint();
      this.size = new Vec2(15.0, 17.0);
      this.position.x = ownerCenter.x - size.x / 2;
      this.position.y = ownerCenter.y - size.y / 2;
      this.spriteType = SpriteType.IMAGE;
      this.velocity.x = cos(owner.angle);
     // this.angle = owner.angle;
      this.velocity.y = sin(owner.angle);
      this.outOfBoundsMovesRemaining = 2;
      this.velocity = this.velocity.multiply(200.0);
      this.velocity = owner.velocity + this.velocity;
    }
  
  explode() {
    world.explosionAtSprite(this, this.velocity.multiply(0.2), damage, radius);
    Random r = new Random();
    for (int i = 0; i < 9; i++) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(world, this, 30);
      sprite.setImage(world.imageIndex().getImageIdByName("banana.png"));
      sprite.velocity.x = -PI * 2; 
      sprite.velocity.y = -PI * 2; 
      sprite.velocity.x += r.nextDouble() * PI * 4;
      sprite.velocity.y += r.nextDouble() * PI * 4;
      sprite.velocity = sprite.velocity.normalize().multiply(500.0);
      sprite.velocity = velocity + sprite.velocity;
      sprite.rotationVelocity = r.nextDouble() * 200.1;
      sprite.radius = 40.0;
      world.addSprite(sprite);
    }
    this.remove = true;
  }
}

class BrickBuilder extends WorldDamageProjectile {
  static const String COLOR = "#aa3311";
  static const int COLOR_R = 170;
  static const int COLOR_G = 51;
  static const int COLOR_B = 17;
  BrickBuilder.createWithOwner(WormWorld world, MovingSprite owner, int damage, [double homingFactor])
      : super(0.0, 0.0, world.imageIndex().getImageIdByName("cake.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(5.0, 5.0);
    this.position.x = ownerCenter.x - size.x / 2;
    this.position.y = ownerCenter.y - size.y / 2;
    this.spriteType = SpriteType.CIRCLE;
    this.color = COLOR;
    this.velocity.x = cos(owner.angle);
    this.velocity.y = sin(owner.angle);
    this.outOfBoundsMovesRemaining = 2;
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = owner.velocity + this.velocity;
  }

  explode() {
    Vec2 brickSize = new Vec2(40, 14);
    Vec2 center = centerPoint();
    center.x -= brickSize.x / 2;
    Vec2 outerPosition = new Vec2.copy(center);
    Vec2 brickPosition = new Vec2.copy(center);
    outerPosition.x -= 1;
    outerPosition.y -= 1;
    // TODO Make this work better.
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
    }
    // TODO merge into one call.
    world.fillRectAt(outerPosition, new Vec2(brickSize.x + 2, brickSize.y + 2), "#ffffff");
    world.fillRectAt(brickPosition, brickSize, COLOR);
    this.remove = true;
  }
}

class WorldDamageProjectile extends MovingSprite {

  WormWorld world;
  MovingSprite owner;
  int damage = 1;

  double bounche = 0.5;
  
  double radius = 15.0;

  double explodeAfter = null;

  bool showCounter = true;
  
  WorldDamageProjectile(double x, double y, int imageId, ImageIndex imageIndex)
      : super.imageBasedSprite(new Vec2(x, y), imageId, imageIndex);

  collide(MovingSprite other, ByteWorld world, int direction) {
    if (networkType == NetworkType.REMOTE) {
      return;
    }
    assert(owner != null);
    if (other != null && other.networkId != owner.networkId && other.takesDamage()) {
      other.takeDamage(/*this.owner,*/ damage);
      explode();
    }
     
    if (world != null && other == null) {
      handleWorldCollide(world, direction);
    }
  }
  
  handleWorldCollide(ByteWorld world, int direction) {
    if (explodeAfter == null) {
      explode();
    } else {
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
          this, this.velocity.multiply(0.2), damage, radius);
    }
    this.remove = true;
  }
  
  frame(double duration, int frameStep, [Vec2 gravity]) {
    if (networkType != NetworkType.REMOTE) {
      if (explodeAfter != null) {
        explodeAfter -= duration;
        if (explodeAfter < 0) {
          explode();
        }
      }
    }
    super.frame(duration, frames, gravity);
  }
  
  draw(var context, bool debug) {
    if (explodeAfter != null && showCounter) {
      context.fillStyle = "#ffffff";
      context.fillText(
        explodeAfter.toInt().toString(), position.x, position.y - size.y);
    }
    super.draw(context, debug);
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.DAMAGE_PROJECTILE;
  }

  void addExtraNetworkData(List data) {
    data.add(showCounter);
    if (explodeAfter != null) {
      data.add(explodeAfter.toInt());
    }
  }

  void parseExtraNetworkData(List data, int startAt) {
    showCounter = data[startAt];
    if (data.length > startAt + 1) {
      this.explodeAfter = data[startAt + 1].toDouble();
    }
  }

  WorldDamageProjectile.createWithOwner(WormWorld world, MovingSprite owner, int damage)
     : super.imageBasedSprite(new Vec2(), world.imageIndex().getImageIdByName("fire.png"), world.imageIndex()) {
    this.world = world;
    this.owner = owner;
    this.damage = damage;
    Vec2 ownerCenter = owner.centerPoint();
    this.size = new Vec2(15.0, 7.0);
    double ownerSize = owner.size.sum() / 2;
    this.position.x = ownerCenter.x + cos(owner.angle) * ownerSize;
    this.position.y = ownerCenter.y + sin(owner.angle) * ownerSize;
    this.velocity.x = cos(owner.angle);
    this.angle = owner.angle;
    this.velocity.y = sin(owner.angle);
    this.outOfBoundsMovesRemaining = 2;
    this.velocity = this.velocity.multiply(500.0);
    this.velocity = owner.velocity + this.velocity;
  }
}