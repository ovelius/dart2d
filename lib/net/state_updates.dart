import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'dart:math';

String REMOVE_KEY = "_r";
// Sent with each datagram to tell the latest keyframe we received.
String KEY_FRAME_KEY = "_";
// Sent to indicate the recipient should increment the KEY_FRAME_KEY sent to us.
String IS_KEY_FRAME_KEY = "_k";
String MESSAGE_KEY = "_s";
String KEY_STATE_KEY = "-k";
String CLIENT_PLAYER_SPEC = "_c";
String CLIENT_PLAYER_ENTER = "_e";
String SERVER_PLAYER_REPLY = "-c";
String SERVER_PLAYER_REJECT = "-r";
String FPS = "-f";
String CONNECTIONS_LIST = "_f";
String GAME_STATE = "-g";
String WORLD_DESTRUCTION = "_w";
String WORLD_DRAW = "+w";
String WORLD_PARTICLE = "_p";
String IMAGE_DATA_REQUEST = "_i";
String IMAGE_DATA_RESPONSE = "-i";
String PING = "-p";
String PONG = "-o";
String KEY_FRAME_DELAY = ".k";
String TRANSFER_COMMAND = "tt";
String DATA_RECEIPTS = ".";
String CONTAINED_DATA_RECEIPTS = ";";
String OTHER_PLAYER_WORLD_SELECT = "se";

/**
 * Method remaps short keynames to more readable ones during testing.
 */
void remapKeyNamesForTest() {
  REMOVE_KEY = "remove_sprite";
  FPS = "fps";
  CONNECTIONS_LIST = "connection_list";
  KEY_FRAME_KEY = "last_key_frame";
  IS_KEY_FRAME_KEY = "is_key_frame";
  MESSAGE_KEY = "player_message";
  KEY_STATE_KEY = "key_state";
  CLIENT_PLAYER_SPEC = "client_spec";
  CLIENT_PLAYER_ENTER = "client_enter";
  SERVER_PLAYER_REPLY = "server_client_reply";
  SERVER_PLAYER_REJECT = "server_client_reject";
  GAME_STATE = "game_state";
  // World.
  WORLD_DESTRUCTION = "world_destruction";
  WORLD_DRAW = "world_draw";
  WORLD_PARTICLE = "world_particles";
  IMAGE_DATA_REQUEST = "image_request";
  IMAGE_DATA_RESPONSE = "image_response";
  //
  PING = "ping";
  KEY_FRAME_DELAY = "key_frame_delay";
  PONG = "pong";

  TRANSFER_COMMAND = "transfer_command";

  DATA_RECEIPTS = "data_receipts";
  CONTAINED_DATA_RECEIPTS = "contained_data_receipts";
  OTHER_PLAYER_WORLD_SELECT = "world_select";
}

// We lazily convert doubles to int by multiplying them with this factor.
const double DOUBLE_INT_CONVERSION = 10000.0;

// Keys that should be delivered reliable.
// Mapped to the function how old and new data should be merged.
Map RELIABLE_KEYS = {
  REMOVE_KEY: mergeUniqueList,
  MESSAGE_KEY: mergeUniqueList,
  WORLD_DESTRUCTION: mergeUniqueList,
  WORLD_DRAW: mergeUniqueList,
  CLIENT_PLAYER_SPEC: singleTonStoredValue,
  CLIENT_PLAYER_ENTER: singleTonStoredValue,
  SERVER_PLAYER_REPLY: singleTonStoredValue,
  PING: singleTonStoredValue,
  PONG: singleTonStoredValue,
};

// Keys that should not be handled as sprite state updates.
Set<String> SPECIAL_KEYS = new Set.from([
  CLIENT_PLAYER_SPEC,
  CLIENT_PLAYER_ENTER,
  WORLD_DRAW,
  FPS,
  CONNECTIONS_LIST,
  SERVER_PLAYER_REPLY,
  SERVER_PLAYER_REJECT,
  REMOVE_KEY,
  GAME_STATE,
  PING,
  PONG,
  KEY_FRAME_DELAY,
  KEY_STATE_KEY,
  KEY_FRAME_KEY,
  IS_KEY_FRAME_KEY,
  MESSAGE_KEY,
  WORLD_DESTRUCTION,
  WORLD_PARTICLE,
  OTHER_PLAYER_WORLD_SELECT,
  IMAGE_DATA_REQUEST,
  DATA_RECEIPTS,
  CONTAINED_DATA_RECEIPTS,
  TRANSFER_COMMAND,
  IMAGE_DATA_RESPONSE
]);

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

// Store all the properties of the sprite as a list of ints.
List<dynamic> propertiesToIntList(MovingSprite sprite, bool keyFrame) {
  keyFrame = keyFrame || sprite.fullFramesOverNetwork-- > 0;
  List<dynamic> data = [
    sprite.extraSendFlags() | (keyFrame ? Sprite.FLAG_FULL_FRAME : 0),
    sprite.position.x.toInt(),
    sprite.position.y.toInt(),
    (sprite.angle * DOUBLE_INT_CONVERSION).toInt(),
    (sprite.velocity.x * DOUBLE_INT_CONVERSION).toInt(),
    (sprite.velocity.y * DOUBLE_INT_CONVERSION).toInt(),
  ];
  if (keyFrame) {
    data.add(sprite.remoteRepresentation().index);
    data.add(sprite.spriteType.index);
    if (sprite.spriteType == SpriteType.IMAGE) {
      data.add(sprite.imageId);
    } else if (_colorSpriteTypes.contains(sprite.spriteType)) {
      data.add(sprite.color);
    }
    data.add(sprite.size.x.toInt());
    data.add(sprite.size.y.toInt());
    data.add(sprite.frames);
    data.add((sprite.rotationVelocity * DOUBLE_INT_CONVERSION).toInt());
  }
  sprite.addExtraNetworkData(data);
  return data;
}

// Set all the properties to the sprite availble in the list.
void intListToSpriteProperties(List<dynamic> data, MovingSprite sprite) {
  sprite.flags = data[0];
  sprite.position.x = data[1].toDouble();
  sprite.position.y = data[2].toDouble();
  sprite.angle = data[3] / DOUBLE_INT_CONVERSION;
  sprite.velocity.x = data[4] / DOUBLE_INT_CONVERSION;
  sprite.velocity.y = data[5] / DOUBLE_INT_CONVERSION;

  if (sprite.flags & Sprite.FLAG_FULL_FRAME == Sprite.FLAG_FULL_FRAME) {
    sprite.parseExtraNetworkData(data, _addFullFrameData(sprite, data, 7));
  } else {
    sprite.parseExtraNetworkData(data, 6);
  }
}

int _addFullFrameData(MovingSprite sprite, List data, int startAt) {
  SpriteType type = SpriteType.values[data[7]];
  sprite.spriteType = type;
  if (type == SpriteType.IMAGE) {
    sprite.setImage(data[8]);
  } else if (_colorSpriteTypes.contains(type)) {
    sprite.color = data[8];
  }
  sprite.size.x = data[9].toDouble();
  sprite.size.y = data[10].toDouble();
  sprite.frames = data[11];
  sprite.rotationVelocity = data[12] / DOUBLE_INT_CONVERSION;
  return startAt + 6;
}
