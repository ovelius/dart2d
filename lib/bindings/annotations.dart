import 'dart:async';


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

abstract class GaReporter {
  reportEvent(String action, [String category, int count, String label]);
}

abstract class ServerChannel {
  sendData(Map<dynamic, dynamic> data);
  Stream<dynamic> dataStream();

  void disconnect();
  Stream<dynamic> reconnect(String id);
}

abstract class ConnectionFactory {
  /**
   * Us trying to connect to someone.
   */
  connectTo(dynamic wrapper, String ourPeerId, String otherPeerId);
  /**
   * Callback for someone trying to connection to us.
   */
  createInboundConnection(dynamic wrapper, dynamic sdp,  String otherPeerId,
      String ourPeerId);
  /**
   * Create and answer for our inbound connection.
   */
  handleCreateAnswer(dynamic connection, String src, String dst);
  /**
   * Handle receiving that answer.
   */
  handleGotAnswer(dynamic connection, dynamic sdp);

  /**
   * Handle receiving ICE candidates.
   */
  handleIceCandidateReceived(dynamic connection, dynamic iceCandidate);
}

