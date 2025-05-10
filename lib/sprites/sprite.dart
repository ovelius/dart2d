import 'dart:js_interop';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
import 'package:web/web.dart';

import '../res/sounds.dart';


enum SpriteType {
  IMAGE,
  RECT,
  CIRCLE,
  CUSTOM
}

enum NetworkType {
  // Network should never touch this sprite.
  LOCAL_ONLY,
  // Local we sent to network.
  LOCAL,
  // A sprite controlled by remote entity.
  REMOTE,
  // A sprite controlled by remote party that we attempt to forward
  // to others we are connected to.
  REMOTE_FORWARD
}

class Sprite {
  static const int FLAG_FULL_FRAME = 1;
  static const int FLAG_COMMANDER_DATA = 2;
  static const int FLAG_NO_GRAVITY = 4;
  static const int FLAG_NO_MOVEMENTS = 8;

  static const int UNLIMITED_LIFETIME = -1;
  // Position, size, image and rendered angle.
  Vec2 position = new Vec2();
  // Access via getRadius()
  double? _radius;
  Vec2 size = new Vec2(1.0, 1.0);
  late int imageId;
  double angle = 0.0;
  SpriteType spriteType = SpriteType.RECT;
  Sound? spawn_sound = null;
  // Color
  String color = "rgba(255, 255, 255, 1.0)";
  //True if sprite doesn't have to be drawn when outside of canvas.
  //Default is true.
  bool invisibleOutsideCanvas = true;
  // Animation data computed in constructor.
  int frameIndex = 0;
  int frames = 1;
  num frameWidth = 0;
  bool lockFrame = false;

  int lifeTime = UNLIMITED_LIFETIME;

  // A globally unique ID within the game.
  int? networkId;
  NetworkType networkType = NetworkType.LOCAL;
  // The connection that originally created this sprite.
  // If the local world is owner, can be left null.
  String? ownerId;
  // Send a couple of frames of full data for newly added sprites.
  int fullFramesOverNetwork = 3;
  // Will be removed by the engine.
  bool remove = false;

  late ImageIndex _imageIndex;

  Sprite.empty(ImageIndex imageIndex) { this._imageIndex = imageIndex; }

  Sprite.imageBasedSprite(this.position, imageId, ImageIndex imageIndex) {
    this._imageIndex = imageIndex;
    this.setImage(imageId, 1);
    spriteType = SpriteType.IMAGE;
  }

  Sprite(this.position, Vec2 size, SpriteType spriteType) {
    this.spriteType = spriteType;
    this.size = size;
    assert(size.x > 0);
    assert(size.y > 0);
  }

  void setImage(int imageId, int frames) {
    this.imageId = imageId;
    HTMLImageElement image = _imageIndex.getImageById(imageId);
    if (image.width == 0) {
      throw "Invalid image width $imageId(src=${image.src}) - ${image.width}";
    }
    this.frames = frames;
    this.frameWidth = image.width / frames;
  }

  /**
   * Configure the sprite to show exactly one frame from the image.
   */
  void setImageWithLockedFrame(int imageId, int frames, int lockedFrame) {
    this.imageId = imageId;
    HTMLImageElement image = _imageIndex.getImageById(imageId);
    this.frameWidth = image.width / frames;
    // Only show a single frame.
    this.frames = 1;
    this.frameIndex = lockedFrame;
    if (frameIndex * frameWidth + frameWidth > image.width) {
      throw "Can't draw frame ${frameIndex} with frameWidth ${frameWidth}, image size only ${image.width}";
    }
    this.lockFrame = true;
  }
  
  void setCenter(Vec2 center) {
    position.x = center.x - size.x / 2;
    position.y = center.y - size.y / 2;
  }

  double getRadius() {
    if (_radius == null) {
      _radius = size.sum() / 2;
    }
    return _radius!;
  }
  
  void setRadius(double radius) {
    _radius = radius;
  }

  Vec2 centerPoint() {
    return new Vec2(
        position.x + size.x / 2,
        position.y + size.y / 2);
  }

  frame(double duration, int frameStep, [Vec2? gravity]) {
    if (frameStep > 0 && frames > 1) {
      frameIndex = (frameIndex +  frameStep) % frames;
    }
    if (lifeTime != UNLIMITED_LIFETIME) {
      lifeTime -= frameStep;
      if (lifeTime <= 0) {
        remove = true;
      }
    }
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    context.translate(position.x + size.x / 2, position.y + size.y / 2);
    if (debug) {
      context.fillStyle = "#ffffff".toJS;
      context.beginPath();
      context.arc(0, 0, getRadius(), 0, 2 * pi, false);
      context.rect(-size.x / 2, -size.y / 2, size.x, size.y);
      context.lineWidth = 1;
      context.strokeStyle = '#ffffff'.toJS;
      context.stroke();
      context.fillStyle = "rgb(255, 255, 255, 0.7)".toJS;
      context.font = "9px Arial";
      String positionText = "x: ${position.x}, y: ${position.y}";
      var metrics = context.measureText(positionText);
      context.fillText(positionText, - metrics.width / 2 , -(size.y));
      if (this is MovingSprite) {
        MovingSprite m = this as MovingSprite;
        String velText = "dx: ${m.velocity.x}, dy: ${m.velocity.y}";
        var metrics = context.measureText(velText);
        context.fillText(velText, - metrics.width / 2 , -(size.y) / 2);
      }
    }
    if (spriteType == SpriteType.CIRCLE) {
      drawCircle(context); 
    } else if (spriteType == SpriteType.IMAGE) {
      HTMLImageElement image = _imageIndex.getImageById(imageId);
      if (this.angle > pi * 2) {
        context.scale(-1, 1);
      }
      context.rotate(angle);
      context.drawImage(
          image,
          frameWidth * frameIndex, 0,
          frameWidth, image.height,
          -size.x / 2,  -size.y / 2,
          size.x, size.y);
    } else if (spriteType == SpriteType.RECT) {
      drawRect(context);
    }
  }
  
  setColor(CanvasRenderingContext2D context) {
    context.fillStyle = color.toJS;
  }

  /**
   * Is sprite controlled by remote world?
   */
  bool remoteControlled() {
    return networkType == NetworkType.REMOTE
        || networkType == NetworkType.REMOTE_FORWARD;
  }

  drawRect(CanvasRenderingContext2D context) {
    context.rotate(angle);
    setColor(context);
    int x2 = size.x ~/ 2;
    int y2 = size.y ~/ 2;
    context.fillRect(-x2, -y2, size.x, size.y);
  }

  drawCircle(CanvasRenderingContext2D context) {
    setColor(context);
    context.beginPath();
    context.arc(
        size.x / 2,
        size.y / 2,
        size.sum(),
        0, pi*2);
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
  void takeDamage(int damage, LocalPlayerSprite inflictor, Mod mod) {

  }

  /**
   * Extra data to be sent to clients.
   */
  ExtraSpriteData addExtraNetworkData() {
    return ExtraSpriteData();
  }

  /**
   * Parsing of above extra data.
   */
  void parseExtraNetworkData(ExtraSpriteData data) {
  }

  /**
   * If the below methods should be inspected for data.
   */

  bool hasCommanderToOwnerData() => false;
  /**
   * Data flowing the other way, from Server to the sprite owner.
   */
  ExtraSpriteData getCommanderToOwnerData() {
    throw new StateError("Needs implementation!");
  }

  /**
   * Parse the above data.
   */
  bool commanderToOwnerData(ExtraSpriteData data) {
    throw new StateError("${runtimeType} needs implementation of commanderToOwnerData!");
  }

  int extraSendFlags() {
    return 0;
  }

  toString() => "Sprite[${networkId} = ${this.networkType}] p:$position";
}