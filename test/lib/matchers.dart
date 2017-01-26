library matchers;

import 'package:matcher/matcher.dart';
import 'dart:convert';
import 'dart:mirrors';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/connection.dart';
import 'test_peer.dart';
import 'fake_canvas.dart';
import 'package:dart2d/util/gamestate.dart';
import 'package:dart2d/sprites/sprites.dart';

playerId(int count) {
  return GameState.ID_OFFSET_FOR_NEW_CLIENT + count * GameState.ID_OFFSET_FOR_NEW_CLIENT;
}

WorldSpriteMatcher hasSpriteWithNetworkId(int id) {
  return new WorldSpriteMatcher(id);
}

WorldPlayerMatcher hasPlayerSpriteWithNetworkId(int id) {
  return new WorldPlayerMatcher(id);
}

WorldSpriteStateMatcher hasExactSprites(List<WorldSpriteMatcher> matchers) {
  return new WorldSpriteStateMatcher(matchers);
}

GameStateMatcher isGameStateOf(data) {
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
  String _commanderId;
  
  GameStateMatcher(this._playersWithName);

  GameStateMatcher withCommanderId(String id) {
    this._commanderId = id;
    return this;
  }

  bool matches(item, Map matchState) {
    GameState gameState = null;
    if (item is World) {
      gameState = (item as WormWorld).network().gameState;
    }
    if (item is GameState) {
      gameState = item;
    }
    if (_commanderId != null) {
      if (gameState.actingCommanderId != _commanderId) {
        matchState["ActualGameState"] = "Expected commander id of ${_commanderId} was ${gameState.actingCommanderId }";
        return false;
      }
    }
    matchState["ActualGameState"] = gameState;
    if (gameState.playerInfoList().length == _playersWithName.length) {
      for (int id in _playersWithName.keys) {
        bool hasMatch = false;
        for (PlayerInfo info in gameState.playerInfoList()) {
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
    if (item is World) {
      TestPeer peer = item.network().peer.peer;
      return peer.connectedToServer == _connected;
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
  WorldPlayerMatcher(int networkId) : super(networkId);

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

  bool _keyStateMatches(LocalPlayerSprite sprite) {
    return sprite.info.remoteKeyState().remoteState == _remoteKeyState;
  }

  bool matches(item, Map matchState) {
    Sprite sprite = _spriteFromItem(item);
    if (!(sprite is LocalPlayerSprite)) {
      throw new ArgumentError("Type of sprite ${_networkId} is ${sprite.runtimeType} expected LocalPlayerSprite");
    }
    return super.matches(item, matchState) && _keyStateMatches(sprite);
  }

  Description describeMismatch(item, Description mismatchDescription,
      var matchState, bool verbose) {
    super.describeMismatch(item, mismatchDescription, matchState, verbose);
    LocalPlayerSprite sprite = _spriteFromItem(item);
    if (!_keyStateMatches(sprite)) {
      mismatchDescription.add("Wanted keystate remote of ${_remoteKeyState} was ${sprite.info.remoteKeyState().remoteState} for ${_networkId} info ${sprite.info} of type ${sprite.runtimeType}\n");
    }
    return mismatchDescription;
  }

  Description describe(Description description) {
    return description.add("PlayerSpriteMatcher not matching");
  }
}

class WorldSpriteMatcher extends Matcher {
  int _networkId;
  int _imageIndex = null;
  NetworkType _networkType = null;
  WorldSpriteMatcher(this._networkId);

  WorldSpriteMatcher andSpriteId(int id) {
    _networkId = id;
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

  bool matchesImageIndex(Sprite sprite) {
    return _imageIndex != null ? sprite.imageId == _imageIndex : true;
  }

  Sprite _spriteFromItem(item) {
    if (item is World) {
      return item.spriteIndex[_networkId];
    }
    if (item is Sprite) {
      return item;
    }
    throw new ArgumentError("Unkown item type ${item.runtimeType}!");
  }

  bool matches(item, Map matchState) {
    Sprite sprite = _spriteFromItem(item);
    if (sprite != null) {
      if (sprite.networkId == _networkId) {
        return matchesNetworkType(sprite) && matchesImageIndex(sprite);
      }
    }
    return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is World) {
      Sprite sprite = item.spriteIndex[_networkId];
      if (sprite == null) {
        mismatchDescription.add("World sprites ${item.spriteIndex} does not contain key ${_networkId}\n");
      } else if (sprite.networkType != _networkType) {
        mismatchDescription.add("Sprite.networktype = ${sprite.networkType} != ${_networkType}\n");
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
    if (item is World) {
      List<WorldSpriteMatcher> spriteMatchers = _reduceToMisMatches(item, matchState);
      return spriteMatchers.isEmpty && _spriteMatchers.length == item.spriteIndex.count();
    }
    return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is World) {
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
    PlayerControlMethods.CONTROL_KEYS: (LocalPlayerSprite s) => s.checkControlKeys(0.01),
    PlayerControlMethods.RESPAWN: (LocalPlayerSprite s) => s.maybeRespawn(0.01),
    PlayerControlMethods.FIRE_KEY: (LocalPlayerSprite s) => s.checkShouldFire(),
    PlayerControlMethods.SERVER_TO_OWNER_DATA: (LocalPlayerSprite s) => s.hasServerToOwnerData(),
    PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH: (LocalPlayerSprite s) => s.listenFor("Jump", () {}),
  };

  int _spriteId;
  Set<PlayerControlMethods> _activeControlMethods = new Set();

  WorldPlayerControlMatcher(this._spriteId);

  WorldPlayerControlMatcher withActiveMethod(PlayerControlMethods method) {
    _activeControlMethods.add(method);
    return this;
  }

  bool matches(item, Map matchState) {
    LocalPlayerSprite sprite;
    if (item is LocalPlayerSprite) {
      sprite = item;
    }
    if (item is WormWorld) {
      sprite = item.spriteIndex[_spriteId];
    }
    if (item is SpriteIndex) {
      sprite = item[_spriteId];
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
          "Expected active methods ${matchState['missing']}");
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
    Map data = null;
    if (item is String) {
      data = JSON.decode(item);
    } else if (item is Map) {
      data = item;
    }
    for (String key in _keys) {
      if (!data.containsKey(key)) {
        return false;
      }
    }
    return true;
  }

  Description describe(Description description) {
    return description.add("Map/Json string not containing all keys ${_keys}");    
  }
}

class TypeMatcher extends Matcher {
  String _type;
  TypeMatcher(this._type);
  
  bool matches(item, Map matchState) {
    InstanceMirror mirror = reflect(item);
    return MirrorSystem.getName(mirror.type.simpleName) == _type;
  }

  Description describe(Description description) {
    return description.add("ClassType is ${_type}");    
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
    Map data = null;
    if (item is String) {
      data = JSON.decode(item);
    } else if (item is Map) {
      data = item;
    }

    bool containsKey = data != null && data.containsKey(_key);
    
    if (_invert) {
      return !containsKey;
    }
    
    if (containsKey) {
      // If _value is null always match.
      return _value == null ? true : data[_key] == _value;
    }
    return false;
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
  
  WorldConnectionMatcher(this._expectedConnections);

  bool matches(item, Map matchState) {
    if (item is World) {
      WormWorld world = item;
      Map connections = world.network().peer.connections;
      for (String id in _expectedConnections) {
        if (!connections.containsKey(id)) {
          matchState[id] = "Expected but missing! No such key ${id} in ${connections}";
        }
      }
      for (String id in connections.keys) {
        if (!_expectedConnections.contains(id)) {
          matchState[id] = "wasn't expected";
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

