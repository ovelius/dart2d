import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';
import 'package:web/web.dart';

@JS()
external ImageData createImageData(int w, int h);
@JS()
external bool isTouchDevice();
@JS()
external String getRtcConnectionStats(RTCStatsReport stats);
@JS()
external void sendSignalingMessage(String src, String dst,String type, String payload);
@JS()
external void openFirebaseChannel(String id,
    JSFunction existingPeersCallback,
    JSFunction messageCallback);
@JS()
external void setFireBaseConnection(bool online);

@Injectable(as : GaReporter)
class RealGaReporter extends GaReporter {
  reportEvent(String action, [String? category, int? count, String? label]) {
    Map data = {'eventAction': action, 'hitType': 'event'};
    data['eventCategory'] = category;
    data['eventValue'] = count;
    data['eventLabel'] = label;
    print("FIXME REPORT EVENT ${jsonEncode(data)}");
    // context.callMethod('ga', ['send', new JsObject.jsify(data)]);
  }
}


@Singleton(as: ServerChannel)
class WebSocketServerChannel extends ServerChannel {
  late String id;
  bool _isConnected = false;
  StreamController<Map<String, String>> _eventStream = StreamController();
  Completer<List<String>> _existingPeers = Completer();

  WebSocketServerChannel() {
    id = "peer-${Uuid().v4()}";
  }

  Future<List<String>> openAndReadExistingPeers() {
    openFirebaseChannel(id,
      this.existingPeersCallback.toJS,
      this.signalingMessageReceived.toJS);
    return _existingPeers.future;
  }

  void existingPeersCallback(JSString json) {
    List<dynamic> existing = JsonCodec().decoder.convert(json.toDart);
    List<String> peers = [id];
    for (dynamic d in existing) {
      peers.add(Map<String, String>.from(d)["id"]!);
    }
    _isConnected = true;
    _existingPeers.complete(peers);
  }

  void signalingMessageReceived(JSString json) {
    Map<dynamic, dynamic> message = JsonCodec().decoder.convert(json.toDart);
    _eventStream.sink.add(Map<String, String>.from(message));
  }

  sendData(String dst, String type, String payload) {
    sendSignalingMessage(id, dst, type, payload);
  }

  Stream<Map<String,String>> dataStream() {
    return _eventStream.stream;
  }

  void disconnect() {
    setFireBaseConnection(false);
    _isConnected = false;
  }

  void reconnect(String id) {
    setFireBaseConnection(true);
    openFirebaseChannel(id,
        this.existingPeersCallback.toJS,
        this.signalingMessageReceived.toJS);
  }

  bool isConnected() => _isConnected;
}

@Injectable(as: ImageFactory)
class HtmlImageFactory implements ImageFactory {
  @override
  create() {
    return HTMLImageElement();
  }

  @override
  createWithSrc(String src) {
    HTMLImageElement image = HTMLImageElement();
    image.src = src;
    return image;
  }

  @override
  createWithSize(int x, y) {
    HTMLImageElement image = HTMLImageElement();
    image.width = x;
    image.height = y;
    return image;
  }
}

@Injectable(as: SoundFactory)
class HtmlSoundFactory implements SoundFactory {
  @override
  HTMLAudioElement createWithSrc(String src, _) {
    HTMLAudioElement audioElement = HTMLAudioElement();
    audioElement.src = src;
    return audioElement;
  }
  @override
  HTMLAudioElement clone(HTMLAudioElement other, _) {
    return other.cloneNode() as HTMLAudioElement;
  }
}

@Injectable(as : ImageDataFactory)
class HtmlImageDataFactory implements ImageDataFactory {
  @override
  createWithSize(int w, h) {
    return createImageData(w, h);
  }
}

@Injectable(as: CanvasFactory)
class HtmlCanvasFactory implements CanvasFactory {
  @override
  createCanvas(int width, height) {
    HTMLCanvasElement canvas = HTMLCanvasElement();
    canvas.width = width;
    canvas.height = height;
    return canvas;
  }

}

@Injectable(as : LocalStorage)
class HtmlLocalStorage extends LocalStorage {
  @override
  String? getItem(String key) {
    return window.localStorage.getItem(key);
  }

  @override
  void remove(String key) {
    window.localStorage.removeItem(key);
  }

  @override
  void setItem(String key, String value) {
    window.localStorage.setItem(key, value);
  }
}

class HtmlCanvasWrapper implements WorldCanvas {
  HTMLCanvasElement htmlCanvasElement;
  HtmlCanvasWrapper(this.htmlCanvasElement);
  @override
  get context2D => htmlCanvasElement.context2D;
  @override
  int get height => htmlCanvasElement.height;
  @override
  int get width => htmlCanvasElement.width;
}

class HtmlScreenWrapper implements HtmlScreen {
  Screen screen;
  HtmlScreenWrapper(this.screen);
  @override
  get orientation => screen.orientation;
}

@module
abstract class HtmlDomBindingsModule {
  HtmlScreen get screen => HtmlScreenWrapper(window.screen);
  WorldCanvas getCanvas() {
    Element? canvasElement = (document.querySelector(
        "#canvas"));
    if (!(canvasElement is HTMLCanvasElement)) {
      throw "CanvasElement missing, expect to find it a #canvas";
    }
    return HtmlCanvasWrapper(canvasElement);
  }
  @Named(RELOAD_FUNCTION)
  Function get reload => () { window.location.reload(); };

  @Named(WORLD_WIDTH)
  int get worldWidth => getCanvas().width;

  @Named(WORLD_HEIGHT)
  int get worldHeight => getCanvas().height;

  @Named(URI_PARAMS_MAP)
  Map<String, List<String>> urlParams() => Uri.base.queryParametersAll;

  @Named(TOUCH_SUPPORTED)
  bool touchSupported() => isTouchDevice();
}


List<RTCIceServer> getIceServers() => [RTCIceServer(urls:'stun:turn.goog'.toJS)];

RTCConfiguration getRtcConfiguration() {
  return RTCConfiguration(iceServers:  getIceServers().toJS);
}

/**
 * This is where the WebRTC magic happens.
 */
@Injectable(as: ConnectionFactory)
class RtcConnectionFactory extends ConnectionFactory {
  final Logger log = new Logger('RtcConnectionFactory');
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
        log.warning("Got ICE disconnected on ${wrapper.id} ");
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
    rtcPeerConnection.setRemoteDescription(init).toDart.then((_){
      for (String candidate in proto.candidates) {
        _addIceCandidateReceived(connection, candidate);
      }
    });
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

