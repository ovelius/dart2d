import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/util/util.dart';
import 'package:injectable/injectable.dart';

import 'package:logging/logging.dart' show Logger, Level, LogRecord;

import '../res/sounds.dart';

enum SpriteConstructor {
  DO_NOT_CREATE,
  MOVING_SPRITE,
  DAMAGE_PROJECTILE,
  HYPER,
  REMOTE_PLAYER_CLIENT_SPRITE,
  POWERUP,
  ROPE_SPRITE
}

/**
 * Contains the world sprite data, indexed by id.
 */
@Singleton(scope: 'world')
class SpriteIndex {
  static final Logger log = new Logger('SpriteIndex');

  static final Map<SpriteConstructor, dynamic> _spriteConstructors = {
    SpriteConstructor.MOVING_SPRITE: (WormWorld world, int spriteId,
            String connectionId) =>
        new MovingSprite.imageBasedSprite(new Vec2(), 0, world.imageIndex()),
    SpriteConstructor.REMOTE_PLAYER_CLIENT_SPRITE:
        (WormWorld world, int spriteId, String connectionId) {
      PlayerInfoProto? info =
          world.network().getGameState().playerInfoByConnectionId(connectionId);
      if (info == null) {
        log.warning(
            "Recieved player sprite not in Gamestate ${world.network().getGameState()}");
        return null;
      }
      return new LocalPlayerSprite(
          world, world.imageIndex(), null, info, new Vec2(), 0);
    },
    SpriteConstructor.ROPE_SPRITE:
        (WormWorld world, int spriteId, String connectionId) =>
            new Rope.createEmpty(world),
    SpriteConstructor.POWERUP:
        (WormWorld world, int spriteId, String connectionId) =>
            new Powerup.createEmpty(world.imageIndex()),
    SpriteConstructor.DAMAGE_PROJECTILE:
        (WormWorld world, int spriteId, String connectionId) =>
            new WorldDamageProjectile(world, 0.0, 0.0, 0, world.imageIndex()),
    SpriteConstructor.HYPER:
        (WormWorld world, int spriteId, String connectionId) =>
            new Hyper(world, 0.0, 0.0, 0, world.imageIndex()),
  };

  static MovingSprite? fromWorldByIndex(WormWorld world, int spriteId,
      String connectionId, SpriteConstructor constructor) {
    if (!_spriteConstructors.containsKey(constructor)) {
      throw new ArgumentError("No such Spriteconstructor mapped $constructor");
    }
    return _spriteConstructors[constructor](world, spriteId, connectionId);
  }

  /**
   * Creates a sprite we got to know over the network.
   */
  MovingSprite? CreateSpriteFromNetwork(WormWorld world, int networkId,
      SpriteConstructor constructor, ConnectionWrapper wrapper, SpriteUpdate data) {
    MovingSprite? sprite =
        SpriteIndex.fromWorldByIndex(world, networkId, wrapper.id, constructor);
    if (sprite == null) {
      return null;
    }
    if (constructor == SpriteConstructor.REMOTE_PLAYER_CLIENT_SPRITE) {
      world.adjustPlayerSprite(sprite as LocalPlayerSprite, data.imageId);
    }
    int spawnSound = data.spawnSound;
    if (spawnSound > 0 && spawnSound < Sound.values.length) {
      sprite.spawn_sound = Sound.values[spawnSound];
    }
    sprite.networkType = NetworkType.REMOTE;
    sprite.networkId = networkId;
    // This might not be 100% accurate, since onwer might be:
    // Client -> Server -> Client.
    // But if that is the case it will be updated when we parse the GameState.
    sprite.ownerId = wrapper.id;
    world.addSprite(sprite);
    return sprite;
  }

  // Current sprites in our world.
  Map<int, Sprite> _sprites = {};
  // Sprites that will be added to the world next frame.
  List<Sprite> _waitingSprites = [];
  // Removals that needs to sent to the network.
  List<int> _networkRemovals = [];
  // Sprites that will be removed from the world next frame;
  List<int> _removeSprites = [];
  // Store away player sprites in case the need to be ressurected.
  Map<int, LocalPlayerSprite> _removedPlayerSprites = {};
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
    if (sprite.networkId != null) {
      if (_sprites.containsKey(sprite.networkId)) {
        throw new StateError(
            "Network controlled sprite ${sprite}[${sprite.networkId}] ${sprite.networkType} would overwrite existing sprite ${_sprites[sprite.networkId]} ${sprite.networkType}");
      }
    }
    _waitingSprites.add(sprite);
  }

  LocalPlayerSprite? maybeResurrectPlayerSprite(int id) {
    LocalPlayerSprite? deletedPlayerSprite = _removedPlayerSprites[id];
    if (deletedPlayerSprite != null) {
      log.info("Resurrected player sprite ${deletedPlayerSprite}");
      deletedPlayerSprite.remove = false;
      addSprite(deletedPlayerSprite);
    }
    return deletedPlayerSprite;
  }

  List<Sprite> putPendingSpritesInWorld() {
    List<Sprite> added = [];
    while (_waitingSprites.length > 0) {
      Sprite newSprite = _waitingSprites.removeAt(0);
      if (newSprite.networkId == null) {
        newSprite.networkId = spriteNetworkId++;
        while (_sprites.containsKey(newSprite.networkId)) {
          log.warning(
              "${this}: World contains sprite ${newSprite.networkId} adding 1");
          newSprite.networkId = spriteNetworkId++;
        }
      }
      if (_sprites.containsKey(newSprite.networkId)) {
        log.severe(
            "Network controlled sprite ${newSprite}[${newSprite.networkId}] ${newSprite.networkType} " +
                "would overwrite existing sprite ${_sprites[newSprite.networkId]} ${_sprites[newSprite.networkId]?.networkType} not adding it!");
        continue;
      }
      _sprites[newSprite.networkId!] = newSprite;
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
      _sprites[id] = _replaceSprite.remove(id)!;
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
      Sprite? sprite = _sprites[id];
      _sprites.remove(id);
      // Store away player sprites.
      if (sprite is LocalPlayerSprite) {
        _removedPlayerSprites[id] = sprite;
      }
      log.fine("Removing sprite ${id} from world");
      if (sprite != null) {
        sprite.remove = true;
        if (sprite.networkType != NetworkType.REMOTE) {
          log.fine("Removing sprite ${id} from network");
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
  Sprite? operator [](index) => _sprites[index];
  operator []=(int i, Sprite value) => _sprites[i] = value;
  bool hasSprite(int id) => _sprites.containsKey(id);

  toString() => "SpriteIndex ${_sprites}";
}
