import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/phys/vec2.dart';

extension FindUpdate on GameStateUpdates {
  hasStateUpdate(StateUpdate_Update type) {
    return getStateUpdate(type) != null;
  }
  StateUpdate? getStateUpdate(StateUpdate_Update type) {
    for (StateUpdate u in this.stateUpdate) {
      if (u.whichUpdate() == type) {
        return u;
      }
    }
    return null;
  }
}

extension PlayerInfoExtensions on PlayerInfoProto {
  bool isConnectedTo(String other) => this.connectionInfo.any((c) => c.id == other);
}

extension AttachCaseUniqueDataReceipt on StateUpdate {
  void attachSingleTonUniqueDataReceipt() {
    dataReceipt = "${this.whichUpdate()}_single".hashCode;
  }
  void attachUniqueDataReceipt(ConnectionWrapper c) {
    dataReceipt = "${this.whichUpdate()}_${c.id}".hashCode;
  }
  void attachDataReceipt(String id) {
    dataReceipt = "${this.whichUpdate()}_${id}".hashCode;
  }
}

List? mergeUniqueList(List? list1, List? list2) {
  Set merged = new Set();
  if (list1 != null) {
    merged.addAll(list1);
  }
  if (list2 != null) {
    merged.addAll(list2);
  }
  List data = new List.from(merged, growable: false);
  return data.length == 0 ? null : data;
}

singleTonStoredValue(var a, var b) {
  return a == null ? b : a;
}

Set<SpriteType> _colorSpriteTypes =
    new Set.from([SpriteType.RECT, SpriteType.CIRCLE, SpriteType.CUSTOM]);


SpriteUpdate toSpriteUpdate(MovingSprite sprite, bool keyFrame) {
  keyFrame = keyFrame || sprite.fullFramesOverNetwork-- > 0;
  SpriteUpdate update = SpriteUpdate();
  update.spriteId = sprite.networkId!;
  update.flags = sprite.extraSendFlags() | (keyFrame ? Sprite.FLAG_FULL_FRAME : 0);
  update.position = sprite.position.toProto();
  update.angle = sprite.angle;
  update.velocity = sprite.velocity.toProto();
  if (keyFrame) {
    update.remoteRepresentation = sprite.remoteRepresentation().index;
    if (sprite.spawn_sound != null) {
      update.spawnSound = sprite.spawn_sound!.index;
    }
    update.spriteType = sprite.spriteType.index;
    if (sprite.spriteType == SpriteType.IMAGE) {
      update.imageId = sprite.imageId;
    } else if (_colorSpriteTypes.contains(sprite.spriteType)) {
      update.color = sprite.color;
    }
    update.size = sprite.size.toProto();
    update.frames = sprite.frames;
    if (sprite.lockFrame) {
      update.lockedFrame = sprite.frameIndex;
    }
    update.rotationVelocity = sprite.rotationVelocity;
  }
  update.extraSpriteData = sprite.addExtraNetworkData();
  return update;
}

// Set all the properties to the sprite availble in the list.
void intListToSpriteProperties(SpriteUpdate update, MovingSprite sprite) {
  sprite.flags = update.flags;
  sprite.position = Vec2.fromProto(update.position);
  sprite.angle = update.angle;
  sprite.velocity = Vec2.fromProto(update.velocity);

  if (sprite.flags & Sprite.FLAG_FULL_FRAME == Sprite.FLAG_FULL_FRAME) {
    _addFullFrameData(sprite, update);
  }
  sprite.parseExtraNetworkData(update.extraSpriteData);
}

void _addFullFrameData(MovingSprite sprite, SpriteUpdate data) {
  SpriteType type = SpriteType.values[data.spriteType];
  sprite.spriteType = type;
  sprite.size = Vec2.fromProto(data.size);
  sprite.frames = data.frames;
  if (type == SpriteType.IMAGE) {
    if (data.hasLockedFrame()) {
      sprite.setImageWithLockedFrame(data.imageId, data.frames, data.lockedFrame);
    } else {
      sprite.setImage(data.imageId, data.frames);
    }
  } else if (_colorSpriteTypes.contains(type)) {
    sprite.color = data.color;
  }
  sprite.rotationVelocity = data.rotationVelocity;
}
