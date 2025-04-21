library spaceworld;

//import 'package:firebase_dart/core.dart';
//import 'package:firebase_dart/database.dart';

import 'dart:js_interop_unsafe';

import 'web_bindings.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/state_updates.pb.dart';
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
final Logger log = new Logger('WormWorldMain');

late DateTime lastStep;
late WormWorld world;
late GaReporter gaReporter;

List<RTCIceServer> getIceServers() => [RTCIceServer(urls:'stun:turn.goog'.toJS)];

RTCConfiguration getRtcConfiguration() {
  return RTCConfiguration(iceServers:  getIceServers().toJS);
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

  /*
  const firebaseConfig = {
    apiKey: "AIzaSyDVw7DovZvclhRSyqTTbShcJui5Wtu724U",
    authDomain: "dart2d-73e64.firebaseapp.com",
    databaseURL: "https://dart2d-73e64-default-rtdb.europe-west1.firebasedatabase.app",
    projectId: "dart2d-73e64",
    storageBucket: "dart2d-73e64.firebasestorage.app",
    messagingSenderId: "827330473786",
    appId: "1:827330473786:web:16f850ebf8c32488be2a03",
    measurementId: "G-S4SYYYEL59"
  };
// test
  var options = FirebaseOptions(
      appId: "1:827330473786:web:16f850ebf8c32488be2a03",
      apiKey: "AIzaSyDVw7DovZvclhRSyqTTbShcJui5Wtu724U",
      projectId: "dart2d-73e64",
      messagingSenderId: 'ignore',
      authDomain: "dart2d-73e64.firebaseapp.com");

  Firebase.initializeApp(options: options).then((app) {
    FirebaseDatabase db = new FirebaseDatabase(app: app,
        databaseURL: 'https://dart2d-73e64-default-rtdb.europe-west1.firebasedatabase.app/');
    db
        .reference()
        .child("sessions")
        .onChildAdded
        .listen((Data) {
      print("added $Data");
    });
  });*/

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

  int newStepMillis = TIMEOUT_MILLIS - frameTimeMillis;
  if (frameTimeMillis > 70) {
    print("Slow frametime of $millis!");
  }
  if (newStepMillis > 80) {
    print("HIGH STEPTIME MILLIS OF ${newStepMillis}");
  }
  new Timer(new Duration(milliseconds: newStepMillis), step);
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
  connectTo(ConnectionWrapper wrapper, Negotiator negotiator) {
    RTCPeerConnection connection = new RTCPeerConnection(getRtcConfiguration());
    _addConnectionListeners(wrapper, connection);
    RTCDataChannelInit init = RTCDataChannelInit(ordered: false, maxRetransmits: 0);
    RTCDataChannel channel = connection.createDataChannel('dart2d', init);
    channel.onopen = (Event event) {
      wrapper.readyDataChannel(channel);
      log.info("Outbound datachannel to ${wrapper.id} ready.");
    }.toJS;
    channel.onmessage = (MessageEvent e) {
      if (!wrapper.hasReadyDataChannel()) {
        log.warning(
            "Receiving data on channel not marked as open, forcing open!");
        wrapper.readyDataChannel(channel);
      }
      wrapper.receiveData(e.data);
    }.toJS;

    _listenForAndSendIceCandidatesToPeer(connection, negotiator);
    connection.createOffer().toDart.then((desc) {
      RTCLocalSessionDescriptionInit localInit =
        RTCLocalSessionDescriptionInit();
      localInit.sdp = desc!.sdp;
      localInit.type = desc.type;
      connection.setLocalDescription(localInit).toDart.then((_) {
        negotiator.sdpReceived(desc!.sdp, desc.type);
      });
    });
    return connection;
  }

  /**
   * Someone sent us an offer and wants to connect.
   */
  createInboundConnection(ConnectionWrapper wrapper,
      Negotiator negotiator, WebRtcDanceProto proto) {
    // Create a local peer object.
    RTCPeerConnection connection = new RTCPeerConnection(getRtcConfiguration());
    _addConnectionListeners(wrapper, connection);
    // We expect there to be a datachannel available here eventually.
    connection.ondatachannel = (RTCDataChannelEvent e) {
      e.channel.onopen = (Event openEvent) {
        wrapper.readyDataChannel(e.channel);
        log.info("Inbound datachannel to ${negotiator.otherId} ready.");
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
    RTCSessionDescriptionInit init = RTCSessionDescriptionInit(type: proto.sdpType, sdp: proto.sdp);
    _listenForAndSendIceCandidatesToPeer(connection, negotiator);
    connection.setRemoteDescription(init).toDart.then((_) {
      for (String candidate in proto.candidates) {
        _addIceCandidateReceived(connection, candidate);
      }
      connection.createAnswer().toDart.then((desc) {
        RTCLocalSessionDescriptionInit local = RTCLocalSessionDescriptionInit();
        local.sdp = desc!.sdp;
        local.type = desc.type;
        connection.setLocalDescription(local).toDart.then((_) {
            negotiator.sdpReceived(desc.sdp, desc.type);
          });
        });
    });
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
        wrapper.close("ICE closed!");
      } else if (connection.iceConnectionState == 'failed') {
        wrapper.error("ICE failed!");
      } else if (connection.iceConnectionState == 'disconnected') {
        // This technically not a final state...
        wrapper.close("ICE disconnected");
      } else {
        log.warning(
            "Unhandled ICE connection state ${connection.iceConnectionState}");
      }
      log.info(
          "ICE connection to ${wrapper.id} state ${connection.iceConnectionState}");
    }.toJS;
  }

  handleGotAnswer(dynamic connection,  WebRtcDanceProto proto) {
    RTCPeerConnection rtcPeerConnection = connection as RTCPeerConnection;
    RTCSessionDescriptionInit init = RTCSessionDescriptionInit(type: proto.sdpType, sdp:proto.sdp);
    rtcPeerConnection.setRemoteDescription(init).toDart;
  }

  Future<String> getStats(dynamic connection) {
    return (connection as RTCPeerConnection).getStats().toDart
        .then((stats) => getRtcConnectionStats(stats));
  }

  _listenForAndSendIceCandidatesToPeer(
      RTCPeerConnection connection, Negotiator negotiator) {
    connection.onicecandidate = (RTCPeerConnectionIceEvent e) {
      if (e.candidate == null) {
        negotiator.onIceCandidate(null);
      } else {
        negotiator.onIceCandidate(e.candidate!.candidate);
        // In the event last candidate signaling isn't supported.
        new Timer(new Duration(milliseconds: 1500), () {negotiator.onIceCandidate(null);});
      }
    }.toJS;
  }

  _addIceCandidateReceived(
      dynamic connection, String iceCandidate) {
    RTCPeerConnection rtcPeerConnection = connection as RTCPeerConnection;
    RTCIceCandidateInit init = new RTCIceCandidateInit(candidate:iceCandidate, sdpMLineIndex:0);
    rtcPeerConnection.addIceCandidate(init);
  }
}


