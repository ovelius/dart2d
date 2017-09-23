import 'dart:async';

class WorldWidth {
  const WorldWidth();
}

class WorldHeight {
  const WorldHeight();
}

class WorldCanvas {
  const WorldCanvas();
}

class LocalStorage {
  const LocalStorage();
}

class UriParameters {
  const UriParameters();
}

class HtmlScreen {
  const HtmlScreen();
}

class TouchControls {
  const TouchControls();
}

class ServerFrameCounter {
  const ServerFrameCounter();
}

class LocalKeyState {
  const LocalKeyState();
}

class CanvasFactory {
  const CanvasFactory();
}

class ReloadFactory {
  const ReloadFactory();
}

class RtcPeerConnectionFactory {
  const RtcPeerConnectionFactory();
}

class ImageDataFactory {
  const ImageDataFactory();
}

class ImageFactory {
  const ImageFactory();
}

class ByteWorldCanvas {
  const ByteWorldCanvas();
}

abstract class GaReporter {
  reportEvent(String action, [String category, int count, String label]);
}

abstract class ServerChannel {
  sendData(Map<dynamic, dynamic> data);
  Stream<dynamic> dataStream();

  void disconnect();
  void reconnect(String id);
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
      String ourPeerId,
      String connectionId);
  /**
   * Create and answer for our inbound connection.
   */
  handleCreateAnswer(dynamic connection, String src, String dst, String connectionId);
  /**
   * Handle receiving that answer.
   */
  handleGotAnswer(dynamic connection, dynamic sdp);

  /**
   * Handle receiving ICE candidates.
   */
  handleIceCandidateReceived(dynamic connection, dynamic iceCandidate);
}

/**
 * A generic factory object.
 * We use this to create fake HTML elements in testing.
 */
class DynamicFactory {
  DynamicFactory(this._factory);
  dynamic _factory;
  create(var args) {
    return _factory(args);
  }
}
