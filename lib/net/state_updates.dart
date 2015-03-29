library state_updates;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/sprites/playersprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';

String REMOVE_KEY = "_r";
String KEY_FRAME_KEY = "_";
String IS_KEY_FRAME_KEY = "_k";
String MESSAGE_KEY = "_s";
String KEY_STATE_KEY = "-k";
String CLIENT_PLAYER_SPEC = "_c";
String SERVER_PLAYER_REPLY = "-c";
String SERVER_PLAYER_REJECT = "-r";
String GAME_STATE = "-g";

/**
 * Method remaps short keynames to more readable ones during testing.
 */
void remapKeyNamesForTest() {
  REMOVE_KEY = "remove_sprite";
  KEY_FRAME_KEY = "last_key_frame";
  IS_KEY_FRAME_KEY = "is_key_frame";
  MESSAGE_KEY = "player_message";
  KEY_STATE_KEY = "key_state";
  CLIENT_PLAYER_SPEC = "client_spec";
  SERVER_PLAYER_REPLY = "server_client_reply";
  SERVER_PLAYER_REJECT = "server_client_reject";
  GAME_STATE = "game_state";
}

// We lazily convert doubles to int by multiplying them with this factor.
const double DOUBLE_INT_CONVERSION = 10000.0;

const int LOCAL_PLAYER_SPRITE_FLAG = 1;

// Keys that should be delivered reliable.
Map RELIABLE_KEYS = {
    REMOVE_KEY: mergeUniqueList,
    MESSAGE_KEY: mergeUniqueList,
    CLIENT_PLAYER_SPEC: singleTonStoredValue,
    SERVER_PLAYER_REPLY: singleTonStoredValue,
    };
// Keys that should not be handled as sprite state updates.
Set<String> SPECIAL_KEYS = new Set.from(
    [CLIENT_PLAYER_SPEC,
     SERVER_PLAYER_REPLY,
     REMOVE_KEY,
     GAME_STATE,
     KEY_STATE_KEY,
     KEY_FRAME_KEY,
     IS_KEY_FRAME_KEY,
     MESSAGE_KEY]);

List mergeUniqueList(List list1, List list2) {
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

// Store all the properties of the sprite as a list of ints.
List<int> propertiesToIntList(MovingSprite sprite, bool keyFrame) {
  List<int> data = [];
  // Special flag a LocalPlayerSprite because, reasons.
  if (sprite is LocalPlayerSprite) {
    data.add(LOCAL_PLAYER_SPRITE_FLAG);
  } else {
    data.add(0);
  }
  data.add(sprite.position.x.toInt());
  data.add(sprite.position.y.toInt());
  int deg = (sprite.angle/(2 * PI) * 360).toInt();
  data.add(deg);

  if (keyFrame || sprite.fullFramesOverNetwork > 0) {
    data.add(sprite.imageIndex);
    Vec2 velocityScaled = sprite.velocity.multiply(DOUBLE_INT_CONVERSION);
    data.add(velocityScaled.x.toInt());
    data.add(velocityScaled.y.toInt());
    data.add(sprite.spriteType.value);
    
    data.add(sprite.size.x.toInt());
    data.add(sprite.size.y.toInt());
    data.add(sprite.frames);
    data.add((sprite.rotationVelocity * DOUBLE_INT_CONVERSION).toInt());
    sprite.fullFramesOverNetwork --;
  }
  return data;
}

// Set all the properties to the sprite availble in the list.
void intListToSpriteProperties(
    List<int> data, MovingSprite sprite) {
  sprite.position.x = data[1].toDouble();
  sprite.position.y = data[2].toDouble();
  double rad = (data[3] / 360.0) * (2*PI);
  sprite.angle = rad;
  
  if (data.length > 4) {
    sprite.setImage(data[4]);
  
    sprite.velocity.x = data[5] / DOUBLE_INT_CONVERSION;
    sprite.velocity.y = data[6] / DOUBLE_INT_CONVERSION;
      
    SpriteType type = new SpriteType.fromInt(data[7]);
    sprite.spriteType = type;
    
    sprite.size.x = data[8].toDouble();
    sprite.size.y = data[9].toDouble();
    sprite.frames = data[10];
    sprite.rotationVelocity = data[11] / DOUBLE_INT_CONVERSION;
  }
}
