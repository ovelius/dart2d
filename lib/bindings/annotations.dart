import 'dart:async';

import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:web/web.dart';
import 'package:dart2d/res/sounds.dart';


const WORLD_WIDTH = "world_width";
const WORLD_HEIGHT= "world_height";
const SERVER_FPS_COUNTER = "server_fps_counter";
const RELOAD_FUNCTION = "reload_function";
const URI_PARAMS_MAP = 'uri_params_map';
const TOUCH_SUPPORTED = 'touch_supported';

abstract class WorldCanvas {
  dynamic get context2D;
  int get width;
  int get height;
}

abstract class LocalStorage {
  void setItem(String key, String value);
  String? getItem(String key);
  void remove(String key);
  bool containsKey(String key) {
    return getItem(key) != null;
  }
  operator [](String key) => getItem(key);
  operator []=(String key, String value) => setItem(key, value);
}

abstract class ByteWorldCanvas implements WorldCanvas {
}

abstract class HtmlScreen {
  dynamic get orientation;
}

abstract class CanvasFactory {
  dynamic createCanvas(int width, height);
}

class RtcPeerConnectionFactory {
  const RtcPeerConnectionFactory();
}

abstract class ImageDataFactory {
  dynamic createWithSize(int x,y);
}

abstract class ImageFactory {
  dynamic create();
  dynamic createWithSrc(String src);
  dynamic createWithSize(int x,y);
}

abstract class SoundFactory {
  HTMLAudioElement clone(HTMLAudioElement other, Sound s);
  HTMLAudioElement createWithSrc(String src, Sound s);
}

abstract class GaReporter {
  reportEvent(String action, [String category, int count, String label]);
}

abstract class ServerChannel {
  /*
   The first item returned is expected to be our own PeerId.
   */
  Future<List<String>> openAndReadExistingPeers();
  sendData(String dst, String type, String payload);
  Stream<Map<String, String>> dataStream();

  void disconnect();
  void reconnect(String id);
  bool isConnected();
}

abstract class ConnectionFactory {
  /**
   * Us trying to connect to someone.
   */
  connectTo(ConnectionWrapper wrapper, Negotiator negotiator);
  /**
   * Callback for someone trying to connection to us.
   */
  createInboundConnection(ConnectionWrapper wrapper, Negotiator negotiator, WebRtcDanceProto proto);
  /**
   * Handle receiving that answer.
   */
  handleGotAnswer(dynamic connection, WebRtcDanceProto proto);

  Future<String> getStats(dynamic connection);
}

