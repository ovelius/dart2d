library sprite;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';


class SpriteType {
  final value;
  const SpriteType._internal(this.value);
  toString() => 'Enum.$value';

  static const IMAGE = const SpriteType._internal(0);
  static const RECT = const SpriteType._internal(1);
  static const CIRCLE = const SpriteType._internal(2);
  static const CUSTOM = const SpriteType._internal(3);
  
  SpriteType.fromInt(this.value);
  operator ==(SpriteType other) {
    return value == other.value; 
  }
}

class NetworkType {
  final _value;
  const NetworkType._internal(this._value);
  toString() => 'Enum.$_value';

  // Network should never touch this sprite.
  static const LOCAL_ONLY = const NetworkType._internal('LOCAL_ONLY');
  // Controlled locally - should be sent to peers.
  static const LOCAL = const NetworkType._internal('LOCAL');
  // Sprite is controlled remotely.
  static const REMOTE = const NetworkType._internal('REMOTE');
  // Sprite is controlled remotely AND should be forwarded to other peers.
  static const REMOTE_FORWARD = const NetworkType._internal('REMOTE_FORWARD');
  
  bool remoteControlled() {
    return _value == 'REMOTE' || _value == 'REMOTE_FORWARD';
  }
  operator ==(NetworkType other) {
    return _value == other._value; 
  }
}

class Sprite {
  static const int UNLIMITED_LIFETIME = -1;
  // Position, size, image and rendered angle.
  Vec2 position;
  // Access via getRadius()
  double _radius;
  Vec2 size;
  int imageId;
  double angle = 0.0;
  SpriteType spriteType = SpriteType.IMAGE;
  // Color
  String color = "rgba(255, 255, 255, 1.0)";
  //True if sprite doesn't have to be drawn when outside of canvas.
  //Default is true.
  bool invisibleOutsideCanvas = true;
  // Animation data computed in constructor.
  int frameIndex = 0;
  int frames = 1;

  // Frame when sprite is remoted from world.
  int lifeTime = UNLIMITED_LIFETIME;

  int networkId;
  NetworkType networkType = NetworkType.LOCAL;
  var ownerId;
  // Send a coulple of frames of full data for newly added sprites.
  int fullFramesOverNetwork = 3;
  // Will be removed by the engine.
  bool remove = false;

  ImageIndex _imageIndex;

  Sprite.empty() { }

  Sprite(this.position, imageId, [Vec2 size, ImageIndex imageIndex]) {
    this._imageIndex = imageIndex;
    var image = images[imageId];
    if (size == null) {
      size = new Vec2();
      size.x = (image.width).toDouble();
      size.y = (image.height).toDouble();
    } else {
      this.size = size;
    }
    setImage(imageId, size.x.toInt());
      
    assert(size.x > 0);
    assert(size.y > 0);
  }

  void setImage(int imageId, [int frameWidth]) {
    this.imageId = imageId;
    var image = _imageIndex.getImageById(imageId);
    if (frameWidth != null) {
      frames = image.width ~/ frameWidth;
      if (frames == 0) {
        print("Sprite frames is zero! ${image.width} ~/ ${frameWidth}");
        assert(frames !=0);
      }
    } else {
      frames = 1;
    }
  }
  
  void setCenter(Vec2 center) {
    position.x = center.x - size.x / 2;
    position.y = center.y - size.y / 2;
  }

  double getRadius() {
    if (_radius == null) {
      _radius = size.sum() / 2;
    }
    return _radius;
  }
  
  void setRadius(double radius) {
    _radius = radius;
  }

  Vec2 centerPoint() {
    return new Vec2(
        position.x + size.x / 2,
        position.y + size.y / 2);
  }

  frame(double duration, int frameStep, [Vec2 gravity]) {
    if (frameStep > 0) {
      frameIndex += frameStep;
      frameIndex = frameIndex % frames;
    }
    if (lifeTime != UNLIMITED_LIFETIME) {
      lifeTime -= frameStep;
      if (lifeTime <= 0) {
        remove = true;
      }
    }
  }

  draw(var context, bool debug) {
    context.translate(position.x + size.x / 2, position.y + size.y / 2);
    if (debug) {
      context.fillStyle = "#ffffff";
      context.beginPath();
      context.arc(0, 0, getRadius(), 0, 2 * PI, false);
      context.rect(-size.x / 2, -size.y / 2, size.x, size.y);
      context.lineWidth = 1;
      context.strokeStyle = '#ffffff';
      context.stroke();
    }
    if (spriteType == SpriteType.CIRCLE) {
      drawCircle(context); 
    } else if (spriteType == SpriteType.IMAGE) {
      var image = _imageIndex.getImageById(imageId);
      num frameWidth = (image.width / frames); 
      if (this.angle > PI * 2) {
        context.scale(-1, 1);
      }
      context.rotate(angle);
      context.drawImageScaledFromSource(
          image,
          frameWidth * frameIndex, 0,
          frameWidth, image.height,
          -size.x / 2,  -size.y / 2,
          size.x, size.y);
    } else if (spriteType == SpriteType.RECT) {
      drawRect(context);
    } else {
      print("Warning: Can't handle sprite type $spriteType");
    }

  }
  
  setColor(var context) {
    context.fillStyle = color;
  }

  drawRect(var context) {
    context.rotate(angle);
    setColor(context);
    int x2 = size.x ~/ 2;
    int y2 = size.y ~/ 2;
    context.fillRect(-x2, -y2, size.x, size.y);
  }

  drawCircle(var context) {
    setColor(context);
    context.beginPath();
    context.arc(
        position.x - size.x / 2,
        position.y - size.y / 2,
        size.sum(),
        0, PI*2);
    context.closePath();
    context.fill();
  }
  
  double distanceTo(Sprite other) {
    Vec2 center = centerPoint();
    Vec2 otherCenter = other.centerPoint();
    return (center - otherCenter).sum();
  }
  
  bool takesDamage() {
    return false;
  }

  // TODO: Make methods below abstract?
  void takeDamage(int damage) {

  }
  
  void addExtraNetworkData(List<int> data) {
    
  }
  
  void parseExtraNetworkData(List<int> data, int startAt) {
    
  }
  
  toString() => "Sprite[${this.networkType}] p:$position";
}