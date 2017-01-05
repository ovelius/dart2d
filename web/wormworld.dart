library spaceworld;

import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'dart:js';
import 'package:di/di.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:html';
import 'dart:async';

const bool USE_LOCAL_HOST_PEER = false;
const Duration TIMEOUT = const Duration(milliseconds: 21);

DateTime lastStep;
WormWorld world;

void main() {
  context['onSignIn'] = (param) {
    JsObject user = param;
    JsObject profile = user.callMethod('getBasicProfile');
    String name = profile.callMethod('getName');
    (querySelector("#nameInput") as InputElement).value = name;
    world.playerName = name;
  };

  CanvasElement canvasElement = (querySelector("#canvas") as CanvasElement);

  var peer = USE_LOCAL_HOST_PEER ? createLocalHostPeerJs() : createPeerJs();

  var injector = new ModuleInjector([new Module()
     ..bind(int, withAnnotation: const WorldWidth(), toValue: canvasElement.width)
     ..bind(int, withAnnotation: const WorldHeight(), toValue: canvasElement.height)
     ..bind(DynamicFactory, withAnnotation: const CanvasFactory(),  toValue:
         new DynamicFactory((args) => new CanvasElement(width:args[0], height:args[1])))
     ..bind(DynamicFactory, withAnnotation: const ImageFactory(),  toValue:
         new DynamicFactory((args) {
           if (args.length == 0) {
             return new ImageElement();
           } else if (args.length == 1) {
             return new ImageElement(src: args[0]);
           } else {
             return new ImageElement(width: args[0], height: args[1]);
           }
         }))
     ..bind(Object, withAnnotation: const WorldCanvas(), toValue: canvasElement)
     ..bind(Object,  withAnnotation: const PeerMarker(), toValue: peer)
     ..bind(KeyState, withAnnotation: const LocalKeyState(), toValue: new KeyState(null))
     ..bind(WormWorld)
     ..bind(ChunkHelper)
     ..bind(ImageIndex)
     ..bind(HudMessages)
     ..bind(ByteWorld)
     ..bind(PacketListenerBindings)
     ..bind(JsCallbacksWrapper, toImplementation:  JsCallbacksWrapperImpl)
     ..bind(SpriteIndex)
  ]);
  world = injector.get(WormWorld);

  setKeyListeners(world, canvasElement);

  querySelector("#sendMsg").onClick.listen((e) {
    var message = (querySelector("#chatMsg") as InputElement).value;
    world.displayHudMessageAndSendToNetwork(
        "${world.network.localPlayerName}: ${message}");
  });

  startTimer();
}

void setKeyListeners(WormWorld world, var canvasElement) {
  document.window.addEventListener("keydown", world.localKeyState.onKeyDown);
  document.window.addEventListener("keyup", world.localKeyState.onKeyUp);

  canvasElement.addEventListener("keydown", world.localKeyState.onKeyDown);
  canvasElement.addEventListener("keyup", world.localKeyState.onKeyUp);
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
  if (secs >= 0.041) {
    // Slow down the game instead of skipping frames.
    secs = 0.041;
  }
  world.frameDraw(secs);
  lastStep = now;

  int frameTimeMillis = new DateTime.now().millisecondsSinceEpoch -
      startStep.millisecondsSinceEpoch;
  if (frameTimeMillis > TIMEOUT.inMilliseconds) {}
  new Timer(TIMEOUT - new Duration(milliseconds: frameTimeMillis), step);
}

@Injectable()
class JsCallbacksWrapperImpl extends JsCallbacksWrapper {
  void bindOnFunction(var jsObject, String methodName, dynamic callback) {
    jsObject.callMethod(
        'on',
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
  return new JsObject(context['Peer'], [new JsObject.jsify({
    'key': 'peerconfig', // TODO: Change this.
    'host': 'anka.locutus.se',
    'port': 8089,
    'debug': 7,
    'config': {
      // TODO: Use list of public ICE servers instead.
      'iceServers': [{ 'url': 'stun:stun.l.google.com:19302' }]
    }
  })]);
}

createLocalHostPeerJs() {
  return new JsObject(context['Peer'], [new JsObject.jsify({
    'key': 'peerconfig', // TODO: Change this.
    'host': 'localhost',
    'port': 8089,
    'debug': 7,
    'config': {
      // TODO: Use list of public ICE servers instead.
      'iceServers': [{ 'url': 'stun:stun.l.google.com:19302' }]
    }
  })]);
}