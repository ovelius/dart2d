library world;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/fps_counter.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/worlds/sprite_index.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:di/di.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/keystate.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

int serverFrame = 0;
// 25 server frames per second.
const FRAME_SPEED = 1.0/15;
double untilNextFrame = FRAME_SPEED;

abstract class World {
  final Logger log = new Logger('World');
  
  String playerName = "Unkown";
  int invalidKeysPressed = 0;

  PeerWrapper peer; 
  // Representing the player in the world.
  LocalPlayerSprite playerSprite;
  // The next id we use for new sprites.
  int spriteNetworkId = 0;


  HudMessages hudMessages;
  KeyState localKeyState; 
  // For debuggging.
  FpsCounter drawFps = new FpsCounter();
  FpsCounter serverFps = new FpsCounter();
  
  bool restart = false;
  bool freeze = false;
  bool connectOnOpenConnection = false;

  Network network;

  double controlHelperTime = 0.0;

  World() {
    localKeyState = new KeyState(this);
    localKeyState.registerGenericListener((e) {
      if (!playerSprite.isMappedKey(e)) {
        invalidKeysPressed++;
        if (invalidKeysPressed > 2) {
          controlHelperTime = 4.0;
        }
      } else {
        invalidKeysPressed = 0;
      }
    });
    hudMessages = new HudMessages(this);
  }

  /**
   * Connect to the given id.
   * The ID is an id of the rtc subsystem.
   */
  void connectTo(var id, [String name = null]);

  /**
   * Advances the world this amount of time.
   * Update objects.
   * Draw objects.
   * Possibly send updates to network.
   */
  void frameDraw([double duration = 0.01]);

  /**
   * Execute a collision check on this sprite.
   * A collision may occur with other sprite or the world itself.
   */
  void collisionCheck(int networkId, duration);


  /**
   * Create a local representation of this player in a remote world.
   */
  void createLocalClient(int spriteId, int spriteIndex);

  toString() => "World[${peer.id}]";
}


