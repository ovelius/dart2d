library matchers;

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:matcher/matcher.dart';
import 'dart:convert';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/net/net.dart';
import 'fake_canvas.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/sprites/sprites.dart';

playerId(int count) {
  return GameState.ID_OFFSET_FOR_NEW_CLIENT + count * GameState.ID_OFFSET_FOR_NEW_CLIENT;
}

WorldSpriteMatcher hasSpriteWithNetworkId(int? id) {
  return new WorldSpriteMatcher(id);
}

WorldPlayerMatcher hasPlayerSpriteWithNetworkId(int? id) {
  return new WorldPlayerMatcher(id);
}

WorldSpriteStateMatcher hasExactSprites(List<WorldSpriteMatcher> matchers) {
  return new WorldSpriteStateMatcher(matchers);
}

GameStateMatcher isGameStateOf(Map<int, String>  data) {
  return new GameStateMatcher(data);
}

WorldConnectionMatcher hasSpecifiedConnections(List connections) {
  return new WorldConnectionMatcher(new Set.from(connections));
}

TypeMatcher hasType(String type) {
  return new TypeMatcher(type);
}

class GameStateMatcher extends Matcher {
  Map<int, String> _playersWithName;
  String _commanderId = "";
  
  GameStateMatcher(this._playersWithName);

  GameStateMatcher withCommanderId(String id) {
    this._commanderId = id;
    return this;
  }

  bool matches(item, Map matchState) {
    GameState? gameState = null;
    if (item is World) {
      gameState = (item as WormWorld).network().gameState;
    }
    if (item is GameState) {
      gameState = item;
    }
    if (gameState!.gameStateProto.actingCommanderId != _commanderId) {
      matchState["ActualGameState"] = "Expected commander id of ${_commanderId} was ${gameState.gameStateProto.actingCommanderId  }";
      return false;
    }
      matchState["ActualGameState"] = gameState;
    if (gameState.playerInfoList().length == _playersWithName.length) {
      for (int id in _playersWithName.keys) {
        bool hasMatch = false;
        for (PlayerInfoProto info in gameState.playerInfoList()) {
          if (info.spriteId == id && info.name == _playersWithName[id]) {
            hasMatch = true;
          }
        }
        if (!hasMatch) {
          return false;
        }
      }
    }
    return gameState.playerInfoList().length == _playersWithName.length;
  }
  
  Description describe(Description description) {
    return description.add("GameState of ${_playersWithName}");
  }
  
  /// This builds a textual description of a specific mismatch.
  Description describeMismatch(item, Description mismatchDescription,
      Map matchState, bool verbose) {
    return mismatchDescription.add("Actual gameState: ${matchState['ActualGameState']}");
  }
}

PeerStateMatcher isConnectedToServer(bool connected) {
  return new PeerStateMatcher(connected);
}

class PeerStateMatcher extends Matcher {
  bool _connected;
  PeerStateMatcher(this._connected);

  bool matches(item, Map matchState) {
    if (item is WormWorld) {
      return item.network().getPeer().connectedToServer() == _connected;
    }
    return false;
  }

  Description describe(Description description) {
    return description.add("World connected to server ${_connected}");
  }

  toString() => "PeerStateMatcher connected ${this._connected}";
}

class WorldPlayerMatcher extends WorldSpriteMatcher {
  bool _remoteKeyState = false;
  WorldPlayerMatcher(int? networkId) : super(networkId);

  WorldPlayerMatcher andRemoteKeyState() {
    _remoteKeyState = true;
    return this;
  }

  WorldPlayerMatcher andSpriteId(int id) {
    super.andSpriteId(id);
    return this;
  }

  WorldPlayerMatcher andImageIndex(int index) {
    super.andImageIndex(index);
    return this;
  }

  WorldPlayerMatcher andNetworkType(NetworkType networkType) {
    super.andNetworkType(networkType);
    return this;
  }

  WorldPlayerMatcher andOwnerId(String ownerId) {
    super.andOwnerId(ownerId);
    return this;
  }

  bool _keyStateMatches(LocalPlayerSprite sprite) {
    return sprite.getKeyState().remoteState == _remoteKeyState;
  }

  bool matches(item, Map matchState) {
    Sprite? sprite = _spriteFromItem(item);
    if (sprite == null) {
      return false;
    }
    if (!(sprite is LocalPlayerSprite)) {
      return false;
    }
    return super.matches(item, matchState) && _keyStateMatches(sprite);
  }

  Description describeMismatch(item, Description mismatchDescription,
      var matchState, bool verbose) {
    super.describeMismatch(item, mismatchDescription, matchState, verbose);
    Sprite? sprite = _spriteFromItem(item);
    if (sprite == null) {
      mismatchDescription.add("Sprite ${_networkId} not found!");
    } else if (sprite is LocalPlayerSprite) {
      if (!_keyStateMatches(sprite)) {
        mismatchDescription.add(
            "Wanted keystate remote of ${_remoteKeyState} was ${sprite.getKeyState()
                .remoteState} for ${_networkId} info ${sprite
                .info} of type ${sprite.runtimeType}\n");
      }
    } else {
      mismatchDescription.add("Sprite of wrong type, expected LocalPlayerSprite was ${sprite.runtimeType}");
    }
    return mismatchDescription;
  }

  Description describe(Description description) {
    return description.add("PlayerSpriteMatcher not matching");
  }
}

class WorldSpriteMatcher extends Matcher {
  int? _networkId;
  int? _imageIndex = null;
  NetworkType? _networkType = null;
  String? _ownerId = null;
  WorldSpriteMatcher(this._networkId);

  WorldSpriteMatcher andSpriteId(int id) {
    _networkId = id;
    return this;
  }

  WorldSpriteMatcher andOwnerId(String ownerId) {
    _ownerId = ownerId;
    return this;
  }

  WorldSpriteMatcher andImageIndex(int index) {
    _imageIndex = index;
    return this;
  }

  WorldSpriteMatcher andNetworkType(NetworkType networkType) {
     _networkType = networkType;
     return this;
  }

  bool matchesNetworkType(Sprite sprite) {
    return _networkType != null ? sprite.networkType == _networkType : true;
  }

  bool matchesOwnerId(Sprite sprite) {
    return _ownerId != null ? sprite.ownerId == _ownerId : true;
  }

  bool matchesImageIndex(Sprite sprite) {
    return _imageIndex != null ? sprite.imageId == _imageIndex : true;
  }

  Sprite? _spriteFromItem(item) {
    if (item is WormWorld) {
      return item.spriteIndex[_networkId];
    }
    if (item is Sprite) {
      return item;
    }
    throw new ArgumentError("Unkown item type ${item.runtimeType}!");
  }

  bool matches(item, Map matchState) {
    Sprite? sprite = _spriteFromItem(item);
    if (sprite == null) {
      return false;
    }
    if (sprite.networkId == _networkId) {
      return matchesNetworkType(sprite) && matchesImageIndex(sprite) && matchesOwnerId(sprite);
    }
      return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is WormWorld) {
      Sprite? sprite = item.spriteIndex[_networkId];
      if (sprite == null) {
        mismatchDescription.add("No sprite with networkId ${_networkId} among world sprites ${item.spriteIndex.spriteIds()}");
      } else if (sprite.networkType != _networkType) {
        mismatchDescription.add("Sprite.networktype = ${sprite.networkType} != ${_networkType}\n");
      } else if (sprite.ownerId != _ownerId) {
        mismatchDescription.add("Sprite.ownerId = ${sprite.ownerId} != ${_ownerId}\n");
      }
    } else {
      mismatchDescription.add("Matched item must be World");
    }
    return mismatchDescription;
  }
  Description describe(Description description) {
    return description.add("World does not contain sprite with networkId ${_networkId}");    
  }
  
  toString() => "SpriteMatcher for networkId ${_networkId}";
}

class WorldSpriteStateMatcher extends Matcher {
  List<WorldSpriteMatcher> _spriteMatchers;
  WorldSpriteStateMatcher(this._spriteMatchers);

  List<WorldSpriteMatcher> _reduceToMisMatches(item, Map matchState) {
    List<WorldSpriteMatcher> spriteMatchers = new List.from(_spriteMatchers);
    for (int i = spriteMatchers.length - 1; i >=0; i--) {
      if (spriteMatchers[i].matches(item, matchState)) {
        spriteMatchers.removeAt(i);
      }
    }
    return spriteMatchers;
  }

  bool matches(item, Map matchState) {
    if (item is WormWorld) {
      List<WorldSpriteMatcher> spriteMatchers = _reduceToMisMatches(item, matchState);
      return spriteMatchers.isEmpty && _spriteMatchers.length == item.spriteIndex.count();
    }
    return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is WormWorld) {
      mismatchDescription.add("${_spriteMatchers} didn't match all in ${item.spriteIndex}\n");
      List<WorldSpriteMatcher> spriteMatchers = _reduceToMisMatches(item, matchState);
      for(WorldSpriteMatcher m in spriteMatchers) {
        m.describeMismatch(item, mismatchDescription, matchState, verbose);
      }
    } else {
      mismatchDescription.add("Matched item must be World");
    }
    return mismatchDescription;
  }
  Description describe(Description description) {
    return description.add("World with exactly ${_spriteMatchers}");    
  }
}

WorldPlayerControlMatcher controlsMatching(int spriteId) {
  return new WorldPlayerControlMatcher(spriteId);
}

enum PlayerControlMethods {
  DRAW_HEALTH_BAR,
  DRAW_WEAPON_HELPER,
  CONTROL_KEYS,
  FIRE_KEY,
  LISTEN_FOR_WEAPON_SWITCH,
  RESPAWN,
  SERVER_TO_OWNER_DATA,
}

class WorldPlayerControlMatcher extends Matcher {

  Map<PlayerControlMethods, dynamic> _methodCheck = {
    PlayerControlMethods.DRAW_HEALTH_BAR: (LocalPlayerSprite s) => s.drawHealthBar(new FakeCanvas().context2D),
    PlayerControlMethods.DRAW_WEAPON_HELPER: (LocalPlayerSprite s) => s.drawWeaponHelpers(),
    PlayerControlMethods.CONTROL_KEYS: (LocalPlayerSprite s) {
      if (!s.checkControlKeys(0.01)) {
        return false;
      }
      // A locally controlled player sprite.
      return !s.getKeyState().remoteState;
    },
    PlayerControlMethods.RESPAWN: (LocalPlayerSprite s) => s.maybeRespawn(0.01),
    PlayerControlMethods.FIRE_KEY: (LocalPlayerSprite s) => s.checkShouldFire(),
    PlayerControlMethods.SERVER_TO_OWNER_DATA: (LocalPlayerSprite s) => s.hasCommanderToOwnerData(),
    PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH: (LocalPlayerSprite s) => s.listenFor("Jump", () {}),
  };

  int _spriteId;
  Set<PlayerControlMethods> _activeControlMethods = new Set();

  WorldPlayerControlMatcher(this._spriteId);

  WorldPlayerControlMatcher withActiveControlMethods(Iterable<PlayerControlMethods> methods) {
    _activeControlMethods.addAll(methods);
    return this;
  }

  WorldPlayerControlMatcher withActiveMethod(PlayerControlMethods method) {
    _activeControlMethods.add(method);
    return this;
  }

  bool matches(item, Map matchState) {
    LocalPlayerSprite? sprite = null;
    if (item is LocalPlayerSprite) {
      sprite = item;
    }
    if (item is WormWorld) {
      sprite = item.spriteIndex[_spriteId]! as LocalPlayerSprite;
    }
    if (item is SpriteIndex) {
      sprite = item[_spriteId]! as LocalPlayerSprite;
    }
    bool matches = true;
    for (PlayerControlMethods method in PlayerControlMethods.values) {
      dynamic func = _methodCheck[method];
      if (_activeControlMethods.contains(method)) {
        if (!func(sprite)) {
          if (!matchState.containsKey('missing')) {
            matchState['missing'] = [];
          }
          matchState['missing'].add(method);
          matches = false;
        }
      } else {
        if (func(sprite)) {
          if (!matchState.containsKey('extra')) {
            matchState['extra'] = [];
          }
          matchState['extra'].add(method);
          matches = false;
        }
      }
    }
    return matches;
  }

  Description describeMismatch(item, Description mismatchDescription,
      Map matchState, bool verbose) {
    if (matchState.containsKey('missing')) {
      mismatchDescription.add(
          "Active methods missing: ${matchState['missing']}");
    }
    if (matchState.containsKey('extra')) {
      mismatchDescription.add(
          "Expected inactive methods ${matchState['extra']}");
    }
    return mismatchDescription;
  }
  Description describe(Description description) {
    return description.add("WorldPlayerControlMatcher with active control methods of ${_activeControlMethods}");
  }
}

class MapKeysMatcher extends Matcher {
  List<String> _keys;
  MapKeysMatcher.containsKeys(this._keys);

  bool matches(item, Map matchState) {
    if (item == null) {
      throw new ArgumentError("Item can not be null");
    }
    Map? data = null;
    if (item is String) {
      data = jsonDecode(item);
    } else if (item is Map) {
      data = item;
    }
    if (data == null) {
      return false;
    }
    for (String key in _keys) {
      if (!data!.containsKey(key)) {
        return false;
      }
    }
    return true;
  }

  Description describe(Description description) {
    return description.add("Map/Json string not containing all keys ${_keys}");    
  }
}

class MapKeyMatcher extends Matcher {
  MapKeyMatcher.doesNotContain(this._key) {
    this._value = null;
    this._invert = true;
  }
  MapKeyMatcher.containsKey(this._key) {
    this._value = null;
  }
  MapKeyMatcher.containsKeyWithValue(this._key, this._value);
  final String _key;
  var _value;
  bool _invert = false;
  
  bool matches(item, Map matchState) {
    Map? data = null;
    if (item is String) {
      data = jsonDecode(item);
    } else if (item is Map) {
      data = item;
    }

    bool containsKey = data!.containsKey(_key);
    
    if (_invert) {
      return !containsKey;
    }
    
    if (containsKey) {
      // If _value is null always match.
      if (_value == null) {
        return true;
      }
      var otherValue = data[_key];
      if (_value is Matcher) {
        return _value.matches(otherValue, matchState);
      }
      return _value == otherValue;
    }
    return false;
  }

  Description describeMismatch(item, Description mismatchDescription,
      Map matchState, bool verbose) {
    Map? data = null;
    if (item is String) {
      data = jsonDecode(item);
    } else if (item is Map) {
      data = item;
    }
    if (data == null) {
      mismatchDescription.add("Can't create a Map from ${item.runtimeType}");
    } else {
      bool containsKey = data.containsKey(_key);
      if (containsKey) {
        var otherValue = data[_key];
        if (_value != otherValue) {
          mismatchDescription.add("Values don't match! Expected ${_value
              .runtimeType} of ${_value}, was ${otherValue
              .runtimeType} of ${otherValue}");
        }
      } else {
        mismatchDescription.add("Not such key $_key in ${data}");
      }
    }
    return mismatchDescription;
  }

  Description describe(Description description) {
    if (_invert) {
      description.add("Map/Json that DOES NOT contain key ${_key}");
      return description;
    }
    if (_value == null) {
      description.add("Map/Json string not containing key ${_key}");
    } else {
      description.add(
          "Map/Json string not containing key ${_key} with value ${_value}");
    }
    return description;
  }
  toString() => "MapKeyMatcher for key '$_key' and value '$_value'";
}

class WorldConnectionMatcher extends Matcher {
  Set<String> _expectedConnections;
  bool _gameConnections = false;
  
  WorldConnectionMatcher(this._expectedConnections);

  WorldConnectionMatcher isValidGameConnections() {
    _gameConnections = true;
    return this;
  }

  bool matches(item, Map matchState) {
    if (item is WormWorld) {
      WormWorld world = item;
      Map connections = world.network().peer.connections;
      for (String id in _expectedConnections) {
        if (!connections.containsKey(id)) {
          matchState[id] = "Expected but missing! No such key ${id} in ${connections}";
        }
        ConnectionWrapper c = connections[id];
        if (_gameConnections != c.isValidGameConnection()) {
          matchState[id] = "Expected game connection of ${_gameConnections} was ${c.isValidGameConnection()}";
        }
      }
      for (String id in connections.keys) {
        if (!_expectedConnections.contains(id)) {
          matchState[id] = " ${connections[id]} wasn't among ${connections}";
        }
      }
    }
    return matchState.length == 0;
  }
  
  Description describe(Description description) {
    return description.add("World connections of ${_expectedConnections}");
  }
  
  /// This builds a textual description of a specific mismatch.
  Description describeMismatch(item, Description mismatchDescription,
      Map matchState, bool verbose) {
    return mismatchDescription.add("$matchState");
  }
}

