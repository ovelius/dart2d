library sprite_index;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/sprites/rope.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:di/di.dart';

import 'package:logging/logging.dart' show Logger, Level, LogRecord;

enum SpriteConstructor {
  MOVING_SPRITE,
  REMOTE_PLAYER_CLIENT_SPRITE,
  ROPE_SPRITE
}
/**
 * Contains the world sprite data, indexed by id.
 */
@Injectable()
class SpriteIndex {
  final Logger log = new Logger('SpriteIndex');

  static final Map<SpriteConstructor, dynamic> _spriteConstructors = {
    SpriteConstructor.MOVING_SPRITE: (WormWorld world) => new MovingSprite.imageBasedSprite(
        new Vec2(), 0, world.imageIndex),
    SpriteConstructor.REMOTE_PLAYER_CLIENT_SPRITE: (WormWorld world) => new RemotePlayerClientSprite(world),
    SpriteConstructor.ROPE_SPRITE: (WormWorld world) => new Rope.createEmpty(world),
  };
    
  static MovingSprite fromWorldByIndex(WormWorld world, SpriteConstructor constructor) {
    return _spriteConstructors[constructor](world);
  }

  // Current sprites in our world.
  Map<int, Sprite> _sprites = {};
  // Sprites that will be added to the world next frame.
  List<Sprite> _waitingSprites = [];
  // Removals that needs to sent to the network.
  List<int> _networkRemovals = [];
  // Sprites that will be removed from the world next frame;
  List<int> _removeSprites = [];
  // Sprites that will replace the current world sprites next frame.
  Map<int, Sprite> _replaceSprite = {};
  
  // When adding local world sprite we start from this number.
  int spriteNetworkId = 0;
  
  /**
   * Put the sprite in queue to be added.
   * The networkId of the sprite might be left empty, which means the sprite
   * will get a networkId when added.
   */
  void addSprite(Sprite sprite) {
    assert(sprite.position != null);
    assert(sprite.size != null);
    if (sprite.networkId != null) {
      if (_sprites.containsKey(sprite.networkId)) {
        throw new StateError(
            "Network controlled sprite ${sprite}[${sprite.networkId}] would overwrite existing sprite ${_sprites[sprite.networkId]}");
      }
    }
    _waitingSprites.add(sprite);
  }

  List<Sprite> putPendingSpritesInWorld() {
    List<Sprite> added = [];
    while (_waitingSprites.length > 0) {
      Sprite newSprite = _waitingSprites.removeAt(0);
      if (newSprite.networkId == null) {
        newSprite.networkId = spriteNetworkId++;
        while (_sprites.containsKey(newSprite.networkId)) {
          log.warning("${this}: Warning: World contains sprite ${newSprite.networkId} adding 1");
          newSprite.networkId = spriteNetworkId++;
        }
      }
      if (_sprites.containsKey(newSprite.networkId)) {
        log.severe("Network controlled sprite ${newSprite}[${newSprite.networkId}]"
            + "would overwrite existing sprite ${_sprites[newSprite.networkId]} not adding it!");
        continue;
      }
      _sprites[newSprite.networkId] = newSprite;
      print("added ${newSprite.networkId} as ${newSprite}");
      added.add(newSprite);
    }
    _replacePending();
    return added;
  }
  
  /**
   * Replace this sprite at next frame. 
   */
  void replaceSprite(int id, Sprite sprite) {
    _replaceSprite[id] = sprite;
  }
  
  /**
   * Replace the sprites in index with pending replacements.
   */
  void _replacePending() {
    for (int id in new List.from(_replaceSprite.keys)) {
      _sprites[id] = _replaceSprite.remove(id);
    }
  }
  
  /**
   * Add the sprite to the pending removals queue.
   */
  void removeSprite(int id) {
    _removeSprites.add(id);
  }
  
  /**
   * Mutate the world by running the pending removals.
   * Populates the pending network removals queue.
   */
  void removePending() {
    while (_removeSprites.length > 0) {
      int id = _removeSprites.removeAt(0);
      Sprite sprite = _sprites[id];
      _sprites.remove(id);
      log.fine("${this}: Removing sprite ${id} from world");
      if (sprite != null) {
        sprite.remove = true;
        if (sprite.networkType != NetworkType.REMOTE) {
          log.fine("${this}: Removing sprite ${id} from network");
          _networkRemovals.add(id);
        }
      }
    }
  }
  
  /**
   * Return an iterable of the sprites keys. 
   * We do not return a defense copy.
   */
  Iterable<int> spriteIds() {
    return _sprites.keys;
  }
  
  /**
   * Grab the current nework removals and clear the state.
   */
  List<int> getAndClearNetworkRemovals() {
    List<int> copy = new List.from(_networkRemovals);
    _networkRemovals.clear();
    return copy;
  }
   
  /**
   * Clear away all sprites and reset state.
   */
  void clear() {
    _sprites.clear();
    _networkRemovals.clear();
    _removeSprites.clear();
    _replaceSprite.clear();
  }
  
  int count() => _sprites.length;
  operator [](index) => _sprites[index];
  operator []=(int i, Sprite value) => _sprites[i] = value;
  bool hasSprite(int id) => _sprites.containsKey(id);

  toString() => "SpriteIndex ${_sprites}";
}