import 'package:dart2d/sprites/sprites.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

// 15 server frames per second.
const TARGET_SERVER_FRAMES_PER_SECOND = 15;
const FRAME_SPEED = 1.0/TARGET_SERVER_FRAMES_PER_SECOND;
double untilNextFrame = FRAME_SPEED;

abstract class World {
  final Logger log = new Logger('World');

  int invalidKeysPressed = 0;

  // Representing the player in the world.
  LocalPlayerSprite? playerSprite;
  // The next id we use for new sprites.
  int spriteNetworkId = 0;

  bool restart = false;
  bool freeze = false;

  double controlHelperTime = 0.0;

  /**
   * Connect to the given id.
   * The ID is an id of the rtc subsystem.
   */
  void connectTo(var id, [String? name = null]);

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

  toString() => "World";
}


