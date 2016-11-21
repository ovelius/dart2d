library connection;

import 'dart:js';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/net/state_updates.dart';
import 'dart:convert';
import 'dart:core';

class RtcConnectionWrapper {
  // How long until connection attempt times out.
  static const Duration DEFAULT_TIMEOUT = const Duration(seconds:5);
  // Remote id.
  var _id;
  var connection;
  // True if connection was successfully opened.
  bool opened = false;
  // True if closed.
  bool closed = false;
  // Storage of our reliable key data.
  Map keyFrameData = {};
  // Keep track of how long connection has been open.
  Stopwatch _connectionTimer;
  // When we time out.
  Duration _timeout;

  RtcConnectionWrapper(this._id, this.connection, [_timeout = DEFAULT_TIMEOUT]) {
    assert(_id != null);
    
    // Hookup js callbacks.
    connection.callMethod('on',
        new JsObject.jsify(
            ['data', new JsFunction.withThis(this.receiveData)]));
    connection.callMethod('on',
        new JsObject.jsify(
            ['close', new JsFunction.withThis(this.close)]));
    connection.callMethod('on',
        new JsObject.jsify(
            ['open', new JsFunction.withThis(this.open)]));
    connection.callMethod('on',
        new JsObject.jsify(
            ['error', new JsFunction.withThis(this.error)]));
    
    // Start the connection timer.
    _connectionTimer = new Stopwatch();
    _connectionTimer.start();
  }
  
  void close(unusedThis) {
    opened = false;
    closed = true;
  }
  
  void open(unusedThis) {
    opened = true;
  }

  void error(unusedThis, error) {
    print("error ${error}");
    opened = false;
    closed = true;
  }

  void receiveData(unusedThis, data) {
    Map dataMap = JSON.decode(data);
    assert(dataMap.containsKey(KEY_FRAME_KEY));
  }
 
  void alsoSendWithStoredData(var data) {
    for (String key in RELIABLE_KEYS.keys) {
      // Use the merge function specified to merge any previosly stored data
      // with the data being sent in this frame.
      var mergedData = RELIABLE_KEYS[key](data[key], keyFrameData[key]);
      if (mergedData != null) {
        data[key] = mergedData;
        keyFrameData[key] = mergedData;
      }
    }
  }
  
  void storeAwayReliableData(var data) {
    RELIABLE_KEYS.keys.forEach((String reliableKey) {
      if (data.containsKey(reliableKey)) {
        var mergedData = RELIABLE_KEYS[reliableKey](data[reliableKey], keyFrameData[reliableKey]);
        if (mergedData != null) {
          keyFrameData[reliableKey] = mergedData;
        }
      }
    }); 
  }
  
  void sendData(Map data) {
    data[KEY_FRAME_KEY] = lastKeyFrameFromPeer;
    if (data.containsKey(IS_KEY_FRAME_KEY)) {
      // Check how many keyframes the remote peer is currenlty behind.
      // We might decide to close the connection because of this.
      if (keyFramesBehind(data[IS_KEY_FRAME_KEY]) > ALLOWED_KEYFRAMES_BEHIND) {
        opened = false;
        closed = true;
        return;
      }
      // Make a defensive copy in case of keyframe.
      // Then add previous data to it.
      data = new Map.from(data);
      alsoSendWithStoredData(data);
    } else {
      // Store away any reliable data sent.
      storeAwayReliableData(data);
    }
    var jsonData = JSON.encode(data);
    connection.callMethod('send', [jsonData]);
  }

  Duration sinceCreated() {
    return new Duration(milliseconds:_connectionTimer.elapsedMilliseconds);
  }

  bool timedOut() {
    return sinceCreated().compareTo(_timeout) > 0;
  }

  /**
   * Checks if the connection has timed out and closes it if that is the case.
   */
  void checkForTimeout() {
    if (timedOut()) {
      close(null);
    }
  }
  
  toString() => "${connectionType} to ${id}";
}

