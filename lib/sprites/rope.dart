
import 'movingsprite.dart';
import 'sprite.dart';
import 'dart:math';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';

class Rope extends MovingSprite {
  WormWorld world;
  bool locked = false;
  bool invisibleOutsideCanvas = false;
  MovingSprite owner;
  MovingSprite lockedOnOther = null;

  Rope.createEmpty(WormWorld world)
        : super.empty(world.imageIndex()) {
    this.world = world;
    this.invisibleOutsideCanvas = false;
    owner = null;
  }
  
  Rope.createWithOwner(WormWorld world, this.owner, double angle, double velocity)
       : super(new Vec2(), new Vec2(5.0, 5.0), SpriteType.RECT) {
      this.owner = owner;
      Vec2 ownerCenter = owner.centerPoint();
      this.position.x = ownerCenter.x - size.x / 2;
      this.position.y = ownerCenter.y - size.y / 2;
      this.angle = owner.angle;
      this.velocity.x = cos(angle);
      this.velocity.y = sin(angle);
      this.invisibleOutsideCanvas = false;
      this.velocity = this.velocity.multiply(velocity);
      this.velocity = owner.velocity + this.velocity;
  }
    
  collide(MovingSprite other, ByteWorld world, int direction) {
    if (other != null) {
      if (other.networkId == owner.networkId || other is Rope) {
        return;
      }
      if (networkType != NetworkType.LOCAL) {
        return;
      }
    }
    locked = true;
    this.velocity = new Vec2();
    if (other != null) {
      lockedOnOther = other;
    }
  }
  
  dragOwner(double duration) {
    Vec2 delta = position - owner.position;
    delta = delta.multiply(duration * 5.0);
    owner.velocity += delta;
  }
  
  frame(double duration, int frames, [Vec2 gravity]) {
    if (owner != null && owner.remove) {
      this.remove = true;
    }
    if (locked && owner != null) {
      // When locked we have no gravity.
      if (lockedOnOther != null) {
        this.setCenter(lockedOnOther.centerPoint());
        if (lockedOnOther.remove) {
          locked = false;
          lockedOnOther = null;
        }
      }
      dragOwner(duration);
      super.frame(duration, frames);
      if (this.velocity.sum() > 0.01) {
        locked = false;
        lockedOnOther = null;
      }
    } else {
      super.frame(duration, frames, gravity);
    }
  }
  
  draw(var context, bool debug) {
    if (owner == null) {
      return;
    }
    Vec2 ownerCenter = owner.centerPoint();
    context.lineWidth = 2;
    var grad= context.createLinearGradient(ownerCenter.x, ownerCenter.y, position.x, position.y);
    grad.addColorStop(0, "red");
    grad.addColorStop(1, "green");

    context.strokeStyle = grad;

    context.beginPath();
    context.moveTo(ownerCenter.x, ownerCenter.y);
    context.lineTo(position.x, position.y);
    context.stroke();
    super.draw(context, debug);
  }
  
  void addExtraNetworkData(List<int> data) {
    if (owner != null) {
      data.add(owner.networkId);
    }
  }
   
  void parseExtraNetworkData(List<int> data, int startAt) {
    this.owner = world.spriteIndex[data[startAt]];
  }
  
  int extraSendFlags() {
    if (locked) {
      return Sprite.FLAG_NO_GRAVITY;
    }
    return 0;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.ROPE_SPRITE;
  }
}