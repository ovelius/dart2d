library matchers;

import 'package:matcher/matcher.dart';
import 'dart:convert';
import 'dart:mirrors';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/sprites/sprite.dart';

playerId(int count) {
  return GameState.ID_OFFSET_FOR_NEW_CLIENT + count * GameState.ID_OFFSET_FOR_NEW_CLIENT;
}

WorldSpriteMatcher hasSpriteWithNetworkId(int id) {
  return new WorldSpriteMatcher(id);
}

WorldSpriteStateMatcher hasExactSprites(List<WorldSpriteMatcher> matchers) {
  return new WorldSpriteStateMatcher(matchers);
}

GameStateMatcher isGameStateOf(data) {
  return new GameStateMatcher(data);
}

WorldConnectionMatcher hasSpecifiedConnections(Map connections) {
  return new WorldConnectionMatcher(connections);
}

TypeMatcher hasType(String type) {
  return new TypeMatcher(type);
}

class GameStateMatcher extends Matcher {
  Map<int, String> _playersWithName;
  
  GameStateMatcher(this._playersWithName);

  bool matches(item, Map matchState) {
    GameState gameState = null;
    if (item is World) {
      gameState = (item as World).network.gameState;
    }
    if (item is GameState) {
      gameState = item;
    }
    matchState["ActualGameState"] = gameState;
    if (gameState.playerInfo.length == _playersWithName.length) {
      for (int id in _playersWithName.keys) {
        bool hasMatch = false;
        for (PlayerInfo info in gameState.playerInfo) {
          if (info.spriteId == id && info.name == _playersWithName[id]) {
            hasMatch = true;
          }
        }
        if (!hasMatch) {
          return false;
        }
      }
    }
    return gameState.playerInfo.length == _playersWithName.length;
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

  bool matches(item, Map matchState) {
    if (item is World) {
      Sprite sprite = item.spriteIndex[_networkId];
      if (sprite != null) {
        if (sprite.networkId == _networkId) {
          return matchesNetworkType(sprite) && matchesImageIndex(sprite);
        }
      }
    }
    return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is World) {
      Sprite sprite = item.spriteIndex[_networkId];
      if (sprite == null) {
        mismatchDescription.add("World sprites ${item.spriteIndex} does not contain key ${_networkId}");
      } else if (sprite.networkType != _networkType) {
        mismatchDescription.add("Sprite.networktype = ${sprite.networkType} != ${_networkType}");
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

  bool matches(item, Map matchState) {
    List<WorldSpriteMatcher> spriteMatchers = new List.from(_spriteMatchers);
    if (item is World) {
      for (int i = spriteMatchers.length - 1; i >=0; i--) {
        if (spriteMatchers[i].matches(item, matchState)) {
          spriteMatchers.removeAt(i);
        }
      }
      return spriteMatchers.isEmpty && _spriteMatchers.length == item.spriteIndex.count();
    }
    return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is World) {
      mismatchDescription.add("${_spriteMatchers} didn't match all in ${item.spriteIndex}");
    } else {
      mismatchDescription.add("Matched item must be World");
    }
    return mismatchDescription;
  }
  Description describe(Description description) {
    return description.add("World with exactly ${_spriteMatchers}");    
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
  Map<String, ConnectionType> _expectedConnections;
  
  WorldConnectionMatcher(this._expectedConnections);

  bool matches(item, Map matchState) {
    if (item is World) {
      World world = item;
      Map connections = world.network.peer.connections;
      for (String id in _expectedConnections.keys) {
        if (!connections.containsKey(id)) {
          matchState[id] = "Expected but missing! No such key ${id} in ${connections}";
        }
        ConnectionWrapper connection = connections[id];
        if (connection.connectionType != _expectedConnections[id]) {
          matchState[id] = "${connection.connectionType} != ${_expectedConnections[id]}";
        }
      }
      for (String id in connections.keys) {
        if (!_expectedConnections.containsKey(id)) {
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

