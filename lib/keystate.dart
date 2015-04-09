library keystate;

import 'dart:html';
import 'package:dart2d/worlds/world.dart';

class KeyState {
  World world;
  bool debug = false;
  
  Map<int, bool> keysDown = new Map<int, bool>();
  Map<int, List<dynamic>> _listeners = new Map<int, List<dynamic>>();
  
  KeyState(this.world);
  
  void onKeyDown(KeyboardEvent e) {
    if (e.keyCode == KeyCode.F2) {
      debug = !debug;
    }
    if (e.keyCode == KeyCode.F4) {
      world.freeze = !world.freeze;
    }
    if (!keysDown.containsKey(e.keyCode)) {
      // If this a newly pushed key, send it to the network right away.
      if (world != null) {
        world.network.maybeSendLocalKeyStateUpdate();
      }
      if (_listeners.containsKey(e.keyCode)) {
        _listeners[e.keyCode].forEach((f) { f(); });
      }
    }
    keysDown[e.keyCode] = true;
  }
  
  void onKeyUp(KeyboardEvent e) {
    keysDown.remove(e.keyCode);
  }
  
  bool keyIsDown(num key) {
    return keysDown.containsKey(key);
  }

  void setEnabledKeys(Map<String, bool> keysDown) {
    this.keysDown = {};
    for (String key in keysDown.keys) {
      this.keysDown[int.parse(key)] = true;
    }
  }

  Map<String, bool> getEnabledState() {
    Map<String, bool> keys = {};
    for (int key in keysDown.keys) {
      if (keysDown[key]) {
        keys[key.toString()] = true;
      }
    }
    return keys;
  }
  
  registerListener(int key, dynamic f) {
    if (!_listeners.containsKey(key)) {
      _listeners[key] = new List<dynamic>();
    }
    List<dynamic> listeners = _listeners[key];
    listeners.add(f);
  }
}