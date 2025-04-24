import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:async';
import 'package:dart2d/bindings/annotations.dart';
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
  bool _ready = false;
  StreamController<Map<String, String>> _eventStream = StreamController();
  Completer<List<String>> _existingPeers = Completer();

  WebSocketServerChannel() {
    id = "testid-${Random().nextInt(100000)}";
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
    _ready = true;
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
  }

  void reconnect(String id) {
    setFireBaseConnection(true);
    openFirebaseChannel(id,
        this.existingPeersCallback.toJS,
        this.signalingMessageReceived.toJS);
  }

  bool ready() => _ready;
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

