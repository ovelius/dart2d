library matchers;

import 'package:unittest/unittest.dart';
import 'dart:convert';
import '../world.dart';
import '../gamestate.dart';
import '../sprite.dart';

WorldSpriteMatcher hasSpriteWithNetworkId(int id) {
  return new WorldSpriteMatcher(id);
}

GameStateMatcher isGameStateOf(data) {
  return new GameStateMatcher(data);
}

class GameStateMatcher extends Matcher {
  Map<int, String> _playersWithName;
  
  GameStateMatcher(this._playersWithName);

  bool matches(item, Map matchState) {
    if (item is GameState) {
      if (item.playerInfo.length == _playersWithName.length) {
        for (int id in _playersWithName.keys) {
          bool hasMatch = false;
          for (PlayerInfo info in item.playerInfo) {
            if (info.spriteId == id && info.name == _playersWithName[id]) {
              hasMatch = true;
            }
          }
          if (!hasMatch) {
            return false;
          }
        }
      }
    }
    return item.playerInfo.length == _playersWithName.length;
  }
  
  Description describe(Description description) {
    description.add("GameState of ${_playersWithName}");
  }
}

class WorldSpriteMatcher extends Matcher {
  int _networkId;
  int _imageIndex = null;
  WorldSpriteMatcher(this._networkId);

  WorldSpriteMatcher andSpriteId(int id) {
    _networkId = id;
    return this;
  }
  
  WorldSpriteMatcher andImageIndex(int index) {
    _imageIndex = index;
    return this;
  }

  bool matches(item, Map matchState) {
    if (item is World) {
      Sprite sprite = item.sprites[_networkId];
      if (sprite != null) {
        if (sprite.networkId == _networkId) {
          if (_imageIndex == null) {
            return true;
          } else {
            return sprite.imageIndex == _imageIndex;
          }
        }
      }
    }
    return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is World) {
      if (!item.sprites.containsKey(_networkId)) {
        mismatchDescription.add("World sprites ${item.sprites} does not contain key ${_networkId}");
      }
    } else {
      mismatchDescription.add("Matched item must be World");
    }
  }
  Description describe(Description description) {
    description.add("World does not contain sprite with networkId ${_networkId}");    
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
    description.add("Map/Json string not containing all keys ${_keys}");    
  }
}

class MapKeyMatcher extends Matcher {
  MapKeyMatcher.containsKey(this._key) {
    this._value = null;
  }
  MapKeyMatcher.containsKeyWithValue(this._key, this._value);
  final String _key;
  var _value;
  bool matches(item, Map matchState) {
    Map data = null;
    if (item is String) {
      data = JSON.decode(item);
    } else if (item is Map) {
      data = item;
    }
    bool containsKey = data != null && data.containsKey(_key);
    if (containsKey) {
      return _value == null ? true : data[_key] == _value;
    }
    return false;
  }
  Description describe(Description description) {
    if (_value == null) {
      description.add("Map/Json string not containing key ${_key}");
    } else {
      description.add("Map/Json string not containing key ${_key} with value ${_value}");
    }
  }
}