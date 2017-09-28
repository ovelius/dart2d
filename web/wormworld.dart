library spaceworld;

import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'dart:math';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'dart:js';
import 'package:di/di.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:html';
import 'dart:convert';
import 'dart:async';

const bool USE_LOCAL_HOST_PEER = false;
const Duration TIMEOUT = const Duration(milliseconds: 21);
final Logger log = new Logger('Connection');

DateTime lastStep;
WormWorld world;
List iceServers = [{'url': 'stun:stun.l.google.com:19302'}];

void main() {
  String url = "url";
  HttpRequest request = new HttpRequest();
  request.open("POST", url, async: true);
  request.onReadyStateChange.listen((_) {
    if (request.readyState == HttpRequest.DONE) {
      if (request.status == 200 || request.status == 0) {
        iceServers = JSON.decode(request.responseText)["iceServers"];
        print("Fetched ICE config from HTTP");
        init();
      } else {
        print("Failure loading ICE config HTTP ${request.status} ${request
            .responseText}");
        init();
      }
    }
  });
  request.send("{}");
}

void init() {
  CanvasElement canvasElement = (querySelector("#canvas") as CanvasElement);
  //TODO should we really to this?
  canvasElement.width = min(canvasElement.width, max(window.screen.width, window.screen.height));
  canvasElement.height = min(canvasElement.height, min(window.screen.width, window.screen.height));

  var injector = new ModuleInjector([
    new Module()
      ..bind(int,
          withAnnotation: const WorldWidth(), toValue: canvasElement.width)
      ..bind(int,
          withAnnotation: const WorldHeight(), toValue: canvasElement.height)
      ..bind(bool,
          withAnnotation: const TouchControls(), toValue: TouchEvent.supported)
      ..bind(Map,
          withAnnotation: const LocalStorage(), toValue: window.localStorage)
      ..bind(Map,
          withAnnotation: const UriParameters(), toValue: Uri.base.queryParametersAll)
      ..bind(Object,
          withAnnotation: const WorldCanvas(), toValue: canvasElement)
      ..bind(Object, withAnnotation: const HtmlScreen(), toValue: window.screen)
      ..install(new HtmlDomBindingsModule())
      ..install(new UtilModule())
      ..install(new NetModule())
      ..install(new WorldModule())
      ..bind(KeyState,
          withAnnotation: const LocalKeyState(), toValue: new KeyState())
      ..bind(FpsCounter,
          withAnnotation: const ServerFrameCounter(), toInstanceOf: FpsCounter)
      ..bind(ImageIndex)
      ..bind(SpriteIndex)
  ]);
  world = injector.get(WormWorld);

  setKeyListeners(world, canvasElement);

  Logger.root.onRecord.listen((LogRecord rec) {
    String msg = '${rec.loggerName}: ${rec.level.name}: ${rec
        .time}: ${rec
        .message}';
    print(msg);
  });

  querySelector("#sendMsg").onClick.listen((e) {
    var message = (querySelector("#chatMsg") as InputElement).value;
    world.displayHudMessageAndSendToNetwork(
        "${window.localStorage['playerName']}: ${message}");
  });

  // TODO register using named keys instead.
  MobileControls controls = injector.get(MobileControls);
  canvasElement.onTouchStart.listen((TouchEvent e) {
    e.preventDefault();
    e.changedTouches.forEach((Touch t) {
      controls.touchDown(t.identifier, t.page.x, t.page.y);
    });
  });
  canvasElement.onTouchEnd.listen((TouchEvent e) {
    e.preventDefault();
    e.changedTouches.forEach((Touch t) {
      controls.touchUp(t.identifier);
    });
  });
  canvasElement.onTouchMove.listen((TouchEvent e) {
    e.preventDefault();
    e.changedTouches.forEach((Touch t) {
      controls.touchMove(t.identifier, t.page.x, t.page.y);
    });
  });

  startTimer();
}

void startTimer() {
  lastStep = new DateTime.now();
  new Timer(TIMEOUT, step);
}

void step() {
  DateTime startStep = new DateTime.now();

  DateTime now = new DateTime.now();
  int millis = now.millisecondsSinceEpoch - lastStep.millisecondsSinceEpoch;
  assert(millis >= 0);
  double secs = millis / 1000.0;
  world.frameDraw(secs);
  lastStep = now;

  int frameTimeMillis = new DateTime.now().millisecondsSinceEpoch -
      startStep.millisecondsSinceEpoch;
  new Timer(TIMEOUT - new Duration(milliseconds: frameTimeMillis), step);
}

void setKeyListeners(WormWorld world, var canvasElement) {
  document.window.addEventListener("keydown", world.localKeyState.onKeyDown);
  document.window.addEventListener("keyup", world.localKeyState.onKeyUp);

  canvasElement.addEventListener("keydown", world.localKeyState.onKeyDown);
  canvasElement.addEventListener("keyup", world.localKeyState.onKeyUp);
}

class WebSocketServerChannel extends ServerChannel {
  WebSocket _socket;
  bool _ready;

  WebSocketServerChannel() {
    _socket = new WebSocket(_socketUrl());
    _socket.onOpen.listen((_) => _ready = true);
    _socket.onClose.listen((_) => _ready = false);
  }

  sendData(Map<dynamic, dynamic> data) {
    if (!_ready) {
      throw new StateError("Socket not read! State is ${_socket.readyState}");
    }
    _socket.send(JSON.encoder.convert(data));
  }

  Stream<dynamic> dataStream() {
    return _socket.onMessage.map((MessageEvent e) => JSON.decode(e.data));
  }

  void disconnect() {
    _socket.close();
  }

  Stream<dynamic> reconnect(String id) {
    if (_socket.readyState == 1) {
     throw new StateError("Socket still open!");
    }
    _socket = new WebSocket(_socketUrl(id));
    _socket.onOpen.listen((_) => _ready = true);
    _socket.onClose.listen((_) => _ready = false);
    return dataStream();
  }

  String _socketUrl([String id = null]) {
    if (id != null) {
      return USE_LOCAL_HOST_PEER ? 'ws://127.0.0.1:8089/peerjs?id=$id' : 'ws://anka.locutus.se:8089/peerjs?id=$id';
    } else {
      return USE_LOCAL_HOST_PEER ? 'ws://127.0.0.1:8089/peerjs' : 'ws://anka.locutus.se:8089/peerjs';
    }
  }

  bool ready() => _ready;
}

/**
 * This is where the WebRTC magic happens.
 */
@Injectable()
class RtcConnectionFactory extends ConnectionFactory {

  /**
   * Try to connect to a remote peer.
   */
  connectTo(ConnectionWrapper wrapper, String ourPeerId, String otherPeerId) {
    Map config =  {'iceServers': iceServers};
    RtcPeerConnection connection = new RtcPeerConnection(config);
    _listenForAndSendIceCandidatesToPeer(connection, ourPeerId, otherPeerId);
    _addConnectionListeners(wrapper, connection);
    RtcDataChannel channel = connection.createDataChannel('dart2d');
    log.info("Created DataChannel ${ourPeerId} <-> ${otherPeerId} Reliable: ${channel.reliable} Ordered: ${channel.ordered}");
    channel.onOpen.listen((_) {
      wrapper.readyDataChannel(channel);
    });
    channel.onMessage.listen((MessageEvent e) {
      wrapper.receiveData(e.data);
    });
    connection.createOffer().then((RtcSessionDescription desc) {
      connection.setLocalDescription(desc).then((_) {
        _serverChannel.sendData({
          'type': 'OFFER',
          'payload': {
            'sdp': { 'sdp': desc.sdp, 'type': desc.type },
            'type': 'data',
          },
          'dst': otherPeerId});
      });
    });
    return connection;
  }

  /**
   * Someone sent us an offer and wants to connect.
   */
  createInboundConnection(ConnectionWrapper wrapper, dynamic sdp,
      String otherPeerId,  String ourPeerId) {
    Map config =  {'iceServers': iceServers};
    // Create a local peer object.
    RtcPeerConnection connection = new RtcPeerConnection(config);

    // Make sure ICE candidates are sent to our remote peer.
    _listenForAndSendIceCandidatesToPeer(connection, ourPeerId, otherPeerId);
    _addConnectionListeners(wrapper, connection);
    // We expect there to be a datachannel available here eventually.
    connection.onDataChannel.listen((RtcDataChannelEvent e) {
      e.channel.onOpen.listen((_){
        wrapper.readyDataChannel(e.channel);
      });
      e.channel.onMessage.listen((MessageEvent e) {
        wrapper.receiveData(e.data);
      });
    });
    // Set our local peers remote description, what type of data thus the other
    // peer want us to receive?
    connection.setRemoteDescription(new RtcSessionDescription(sdp));
    return connection;
  }

  _addConnectionListeners(ConnectionWrapper wrapper, RtcPeerConnection connection) {
    wrapper.setRtcConnection(connection);
    connection.onIceConnectionStateChange.listen((Event e) {
      if (connection.iceConnectionState == "checking") {
        // Do nothing...
      } else if (connection.iceConnectionState == "connected") {
        wrapper.open();
      } else if (connection.iceConnectionState == 'closed') {
        wrapper.close();
      } else  if (connection.iceConnectionState == 'failed'){
        wrapper.error(e.toString());
      } else if (connection.iceConnectionState == 'disconnected'){
        wrapper.close();
      } else {
        log.warning("Unhandled ICE connection state ${connection.iceConnectionState}");
      }
    });
  }

  _listenForAndSendIceCandidatesToPeer(
      RtcPeerConnection connection, String ourPeerId, String otherPeerId) {
    connection.onIceCandidate.listen((RtcIceCandidateEvent e) {
      if (e.candidate == null) {
        log.warning("Received null ICE candidate :/");
        return;
      }
      _serverChannel.sendData({
        'type': 'CANDIDATE',
        'payload': {
          'candidate': {
            'candidate': e.candidate.candidate,
            'sdpMLineIndex':  e.candidate.sdpMLineIndex,
            'sdpMid': e.candidate.sdpMid,
          },
          'type': 'data',
        },
        'src': ourPeerId,
        'dst': otherPeerId
      });
    });
  }

  handleIceCandidateReceived(RtcPeerConnection connection, dynamic iceCandidate) {
    assert(connection != null, "Connection is null!");
    RtcIceCandidate candidate = new RtcIceCandidate(iceCandidate);
    connection.addIceCandidate(candidate);
  }

  handleCreateAnswer(RtcPeerConnection connection, String src, String dst) {
    connection.createAnswer().then((RtcSessionDescription desc) {
      connection.setLocalDescription(desc).then((_) {
        _serverChannel.sendData({
          'type': 'ANSWER',
          'payload': {
            'sdp': { 'sdp': desc.sdp, 'type': desc.type },
            'type': 'data',
            'browser': 'fixme',
          },
          'src': dst,
          'dst': src});
      });
    });
  }

  handleGotAnswer(RtcPeerConnection connection, dynamic sdp) {
    connection.setRemoteDescription(new RtcSessionDescription(sdp));
  }
}

WebSocketServerChannel _serverChannel;

class HtmlDomBindingsModule extends Module {
  HtmlDomBindingsModule() {
    bind(GaReporter, toImplementation:  RealGaReporter);
    // Initialize server signalling channel.
    _serverChannel = new WebSocketServerChannel();
    bind(ServerChannel, toValue: _serverChannel);
    bind(ConnectionFactory, toImplementation: RtcConnectionFactory);
    bind(DynamicFactory,
        withAnnotation: const ReloadFactory(),
        toValue: new DynamicFactory(
        (args) => window.location.reload()));
    bind(DynamicFactory,
        withAnnotation: const CanvasFactory(),
        toValue: new DynamicFactory(
            (args) => new CanvasElement(width: args[0], height: args[1])));
    bind(DynamicFactory,
        withAnnotation: const ImageDataFactory(),
        toValue: new DynamicFactory(
            (args) => new ImageData(args[0], args[1])));
    bind(DynamicFactory, withAnnotation: const ImageFactory(),
        toValue: new DynamicFactory((args) {
      if (args.length == 0) {
        return new ImageElement();
      } else if (args.length == 1) {
        return new ImageElement(src: args[0]);
      } else {
        return new ImageElement(width: args[0], height: args[1]);
      }
    }));
  }
}

@Injectable()
class RealGaReporter extends GaReporter {
  reportEvent(String action, [String category, int count, String label]) {
    Map data = {'eventAction': action, 'hitType': 'event'};
    if (category != null) {
      data['eventCategory'] = category;
    }
    if (count != null) {
      data['eventValue'] = count;
    }
    if (label != null) {
      data['eventLabel'] = label;
    }
    context.callMethod('ga',  ['send', new JsObject.jsify(data)]);
  }
}
