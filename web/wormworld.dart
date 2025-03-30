library spaceworld;

import 'package:dart2d/net/connection.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'dart:math';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'dart:js_interop';
import 'package:web/web.dart';
import 'injector.dart';
import 'injector.config.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:async';

const bool RELOAD_ON_ERROR = false;
const int TIMEOUT_MILLIS = 21;
const Duration TIMEOUT = const Duration(milliseconds: TIMEOUT_MILLIS);
final Logger log = new Logger('WormWorldMain');

late DateTime lastStep;
late WormWorld world;
late GaReporter gaReporter;
late ServerChannel _serverChannel;

List iceServers = [
  {'url': 'stun:turn.goog'}
];

JSArray<RTCIceServer> getIceServers() {
  JSArray<RTCIceServer> servers = JSArray<RTCIceServer>();
  iceServers.forEach((string) {
    servers.add(RTCIceServer(urls: string));
  });
  return servers;
}

RTCConfiguration getRtcConfiguration() {
  return RTCConfiguration(iceServers:  getIceServers());
}

void main() {
  configureDependencies();
  String url = "";
  if (url.isEmpty) {
    init();
    return;
  }
  /*
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
  request.send("{}"); */
}

void init() {
  HTMLCanvasElement canvasElement = (document.querySelector("#canvas") as HTMLCanvasElement);
  canvasElement.width =
      min(canvasElement.width, max(window.screen.width, window.screen.height));
  canvasElement.height =
      min(canvasElement.height, min(window.screen.width, window.screen.height));

  getIt.initWorldScope();
  world = getIt<WormWorld>();
  gaReporter = getIt<GaReporter>();
  _serverChannel = getIt<ServerChannel>();

  setKeyListeners(world, canvasElement);

  Logger.root.onRecord.listen((LogRecord rec) {
    String msg = '${rec.loggerName}: ${rec.level.name}: ${rec
        .time}: ${rec
        .message}';
    print(msg);
  });
  document.querySelector("#sendMsg")!.onClick.listen((e) {
    var message = (document.querySelector("#chatMsg") as HTMLInputElement).value;
    world.displayHudMessageAndSendToNetwork(
        "${window.localStorage.getItem('playerName')}: ${message}");
  });

  // TODO register using named keys instead.
  MobileControls controls = getIt<MobileControls>();
  canvasElement.onTouchStart.listen((TouchEvent e) {
    e.preventDefault();
    e.changedTouches.toList().forEach((Touch t) {
      controls.touchDown(t.identifier, t.pageX.toInt(), t.pageY.toInt());
    });
  });
  canvasElement.onTouchEnd.listen((TouchEvent e) {
    e.preventDefault();
    e.changedTouches.toList().forEach((Touch t) {
      controls.touchUp(t.identifier);
    });
  });
  canvasElement.onTouchMove.listen((TouchEvent e) {
    e.preventDefault();
    e.changedTouches.toList().forEach((Touch t) {
      controls.touchMove(t.identifier, t.pageX.toInt(), t.pageY.toInt());
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
  int millis = startStep.millisecondsSinceEpoch - lastStep.millisecondsSinceEpoch;
  assert(millis >= 0);
  double secs = millis / 1000.0;

  //try {
    world.frameDraw(secs);
  /*
  } catch (e, s) {
    log.severe("Main loop crash, reloading", e, s);
    gaReporter.reportEvent("crash", sanitizeStack(s));
    if (RELOAD_ON_ERROR) {
      new Timer(new Duration(seconds: 6), () { window.location.reload(); });
    }
    return;
  }*/

  lastStep = startStep;
  int frameTimeMillis = new DateTime.now().millisecondsSinceEpoch -
      startStep.millisecondsSinceEpoch;
  new Timer(new Duration(milliseconds: TIMEOUT_MILLIS - frameTimeMillis), step);
}

String sanitizeStack(StackTrace s) {
  String trace = s.toString();
  return trace.replaceAll(new RegExp(":"), "_");
}

void setKeyListeners(WormWorld world, var canvasElement) {
  window.onkeydown = (KeyboardEvent e) {
    world.localKeyState.onKeyDown(e.keyCode);
  }.toJS;
  window.onkeyup = (KeyboardEvent e) {
    world.localKeyState.onKeyUp(e.keyCode);
  }.toJS;
}


/**
 * This is where the WebRTC magic happens.
 */
@Injectable(as: ConnectionFactory)
class RtcConnectionFactory extends ConnectionFactory {
  /**
   * Try to connect to a remote peer.
   */
  connectTo(dynamic wrapper, String ourPeerId, String otherPeerId) {
    RTCPeerConnection connection = new RTCPeerConnection(getRtcConfiguration());
    _listenForAndSendIceCandidatesToPeer(connection, ourPeerId, otherPeerId);
    _addConnectionListeners(wrapper, connection);
    RTCDataChannelInit init = RTCDataChannelInit(ordered: false, maxRetransmits: 0);
    RTCDataChannel channel = connection.createDataChannel('dart2d', init);
    log.info(
        "Created DataChannel ${ourPeerId} <-> ${otherPeerId} maxRetransmits: ${channel.maxRetransmits} Ordered: ${channel.ordered}");
    channel.onopen = (Event event) {
      wrapper.readyDataChannel(channel);
      log.info("Outbound datachannel to ${otherPeerId} ready.");
    }.toJS;
    channel.onmessage = (MessageEvent e) {
      if (!wrapper.hasReadyDataChannel()) {
        log.warning(
            "Receiving data on channel not marked as open, forcing open!");
        wrapper.readyDataChannel(channel);
      }
      wrapper.receiveData(e.data);
    }.toJS;
    connection.createOffer().toDart.then((dynamic desc) {
      connection.setLocalDescription(desc).toDart.then((_) {
        _serverChannel.sendData({
          'type': 'OFFER',
          'payload': {
            'sdp': {'sdp': desc.sdp, 'type': desc.type},
            'type': 'data',
          },
          'dst': otherPeerId
        });
      });
    });
    return connection;
  }

  /**
   * Someone sent us an offer and wants to connect.
   */
  createInboundConnection(dynamic wrapper, dynamic sdp,
      String otherPeerId, String ourPeerId) {

    // Create a local peer object.
    RTCPeerConnection connection = new RTCPeerConnection(getRtcConfiguration());
    // Make sure ICE candidates are sent to our remote peer.
    _listenForAndSendIceCandidatesToPeer(connection, ourPeerId, otherPeerId);
    _addConnectionListeners(wrapper, connection);
    // We expect there to be a datachannel available here eventually.
    connection.ondatachannel = (RTCDataChannelEvent e) {
      e.channel.onopen = (Event openEvent) {
        wrapper.readyDataChannel(e.channel);
        log.info("Inbound datachannel to ${otherPeerId} ready.");
      }.toJS;
      e.channel.onmessage = (MessageEvent messageEvent) {
        if (!wrapper.hasReadyDataChannel()) {
          log.warning(
              "Receiving data on channel not marked as open, forcing open!");
          wrapper.readyDataChannel(e.channel);
        }
        wrapper.receiveData(messageEvent.data);
      }.toJS;
    }.toJS;
    // Set our local peers remote description, what type of data thus the other
    // peer want us to receive?
    RTCSessionDescriptionInit init = RTCSessionDescriptionInit(type: sdp['type'], sdp: sdp['sdp']);
    connection.setRemoteDescription(init);
    return connection;
  }

  _addConnectionListeners(
      ConnectionWrapper wrapper, RTCPeerConnection connection) {
    wrapper.setRtcConnection(connection);

    connection.oniceconnectionstatechange = (Event _) {
      if (connection.iceConnectionState == "checking") {
        // Do nothing...
      } else if (connection.iceConnectionState == "connected") {
        wrapper.open();
      } else if (connection.iceConnectionState == 'closed') {
        wrapper.close("ICE closed");
      } else if (connection.iceConnectionState == 'failed') {
        wrapper.error(e.toString());
      } else if (connection.iceConnectionState == 'disconnected') {
        wrapper.close("ICE disconnected");
      } else {
        log.warning(
            "Unhandled ICE connection state ${connection.iceConnectionState}");
      }
      log.info(
          "ICE connection to ${wrapper.id} state ${connection.iceConnectionState}");
    }.toJS;
  }

  _listenForAndSendIceCandidatesToPeer(
      RTCPeerConnection connection, String ourPeerId, String otherPeerId) {

    connection.onicecandidate = (RTCPeerConnectionIceEvent e) {
      if (e.candidate == null) {
        log.warning("Received null ICE candidate - END OF CANDIDATES");
        return;
      }
      _serverChannel.sendData({
        'type': 'CANDIDATE',
        'payload': {
          'candidate': {
            'candidate': e.candidate!.candidate,
          },
          'type': 'data',
        },
        'src': ourPeerId,
        'dst': otherPeerId
      });
    }.toJS;
  }

  handleIceCandidateReceived(
      dynamic connection, dynamic iceCandidate) {
    RTCPeerConnection rtcPeerConnection = connection as RTCPeerConnection;
    RTCIceCandidateInit init = new RTCIceCandidateInit(candidate:iceCandidate['candidate'], sdpMLineIndex:0);
    rtcPeerConnection.addIceCandidate(init);
  }

  handleCreateAnswer(dynamic connection, String src, String dst) {
    RTCPeerConnection rtcPeerConnection = connection as RTCPeerConnection;
    rtcPeerConnection.createAnswer().toDart.then((dynamic desc) {
      rtcPeerConnection.setLocalDescription(desc).toDart.then((_) {
        _serverChannel.sendData({
          'type': 'ANSWER',
          'payload': {
            'sdp': {'sdp': desc.sdp, 'type': desc.type},
            'type': 'data',
            'browser': 'fixme',
          },
          'src': dst,
          'dst': src
        });
      });
    });
  }

  handleGotAnswer(dynamic connection, dynamic sdp) {
    RTCPeerConnection rtcPeerConnection = connection as RTCPeerConnection;
    RTCSessionDescriptionInit init = RTCSessionDescriptionInit(type: sdp['type'], sdp:sdp['sdp']);
    rtcPeerConnection.setRemoteDescription(init).toDart;
  }
}


