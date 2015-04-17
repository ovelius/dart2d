library spriteindex;

import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/worlds/world.dart';

/**
 * Maps constructors to numbers.
 */
class SpriteIndex {
  static const int MOVING_SPRITE = 0;
  static const int REMOTE_PLAYER_CLIENT_SPRITE = 1;
    
  static final Map<int, dynamic> _spriteConstructors = {
    MOVING_SPRITE: (World world) => new MovingSprite(0.0, 0.0, 0),
    REMOTE_PLAYER_CLIENT_SPRITE: (World world) => new RemotePlayerClientSprite(world),
  };
  
  static MovingSprite fromWorldByIndex(World world, int number) {
    print("Get request to create ${world} for ${number}");
    return _spriteConstructors[number](world);
  }
}