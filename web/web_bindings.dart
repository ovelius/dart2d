import 'dart:convert';
import 'dart:js_interop';
import 'package:dart2d/bindings/annotations.dart';
import 'package:injectable/injectable.dart';
import 'package:web/web.dart';


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
  late WebSocket _socket;
  bool _ready = false;

  WebSocketServerChannel() {
    _socket = new WebSocket(_socketUrl());
    _socket.onOpen.listen((_) => _ready = true);
    _socket.onClose.listen((_) => _ready = false);
  }

  sendData(Map<dynamic, dynamic> data) {
    if (!_ready) {
      throw new StateError("Socket not read! State is ${_socket.readyState}");
    }
    _socket.send(jsonEncode(data).toJS);
  }

  Stream<dynamic> dataStream() {
    return _socket.onMessage.map((MessageEvent e) => jsonDecode(e.data.toString()));
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

  String _socketUrl([String? id = null]) {
    return id == null ?
    'ws://anka.locutus.se:8089/peerjs' :
    'ws://anka.locutus.se:8089/peerjs?id=$id';
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

@JS()
external ImageData createImageData(int w, int h);
@JS()
external bool isTouchDevice();
@JS()
external String getRtcConnectionStats(RTCStatsReport stats);

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

