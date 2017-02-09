library spaceworld;

import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'dart:math';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'dart:js';
import 'package:di/di.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:html';
import 'dart:async';

const bool USE_LOCAL_HOST_PEER = false;
const Duration TIMEOUT = const Duration(milliseconds: 21);

DateTime lastStep;
WormWorld world;

void main() {
  CanvasElement canvasElement = (querySelector("#canvas") as CanvasElement);
  //TODO should we really to this?
  canvasElement.width = max(window.screen.width, window.screen.height);
  canvasElement.height = min(window.screen.width, window.screen.height);

  var peer = USE_LOCAL_HOST_PEER ? createLocalHostPeerJs() : createPeerJs();

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
      ..bind(Object,
          withAnnotation: const WorldCanvas(), toValue: canvasElement)
      ..bind(Object, withAnnotation: const HtmlScreen(), toValue: window.screen)
      ..bind(Object, withAnnotation: const PeerMarker(), toValue: peer)
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

class HtmlDomBindingsModule extends Module {
  HtmlDomBindingsModule() {
    bind(JsCallbacksWrapper, toImplementation: JsCallbacksWrapperImpl);
    bind(DynamicFactory,
        withAnnotation: const CanvasFactory(),
        toValue: new DynamicFactory(
            (args) => new CanvasElement(width: args[0], height: args[1])));
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
class JsCallbacksWrapperImpl extends JsCallbacksWrapper {
  void bindOnFunction(var jsObject, String methodName, dynamic callback) {
    jsObject.callMethod('on',
        new JsObject.jsify([methodName, new JsFunction.withThis(callback)]));
  }

  void callJsMethod(var jsObject, String methodName) {
    jsObject.callMethod(methodName);
  }

  dynamic connectToPeer(var jsPeer, String id) {
    var metaData = new JsObject.jsify({
      'label': 'dart2d',
      'reliable': 'false',
      'metadata': {},
      'serialization': 'none',
    });
    return jsPeer.callMethod('connect', [id, metaData]);
  }
}

createPeerJs() {
  return new JsObject(context['Peer'], [
    new JsObject.jsify({
      'key': 'peerconfig', // TODO: Change this.
      'host': 'anka.locutus.se',
      'port': 8089,
      'debug': 7,
      'config': {
        // TODO: Use list of public ICE servers instead.
        'iceServers': [
          {'url': 'stun:stun.l.google.com:19302'}
        ]
      }
    })
  ]);
}

createLocalHostPeerJs() {
  return new JsObject(context['Peer'], [
    new JsObject.jsify({
      'key': 'peerconfig', // TODO: Change this.
      'host': 'localhost',
      'port': 8089,
      'debug': 7,
      'config': {
        // TODO: Use list of public ICE servers instead.
        'iceServers': [
          {'url': 'stun:stun.l.google.com:19302'}
        ]
      }
    })
  ]);
}
