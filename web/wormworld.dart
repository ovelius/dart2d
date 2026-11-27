library spaceworld;

import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/util/util.dart';
import 'dart:math';
import 'package:dart2d/bindings/annotations.dart';
import 'dart:js_interop';
import 'package:web/web.dart';
import 'injector.dart';
import 'injector.config.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:async';

const bool RELOAD_ON_ERROR = false;
final Logger log = new Logger('WormWorldMain');

late DateTime lastStep;
late WormWorld world;
late GaReporter gaReporter;

void main() {
  configureDependencies();
  init();
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

  setKeyListeners(world, canvasElement);
  setPageLifecycleListeners(world);

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

  // Register non-passive touch listeners and map viewport touch coordinates to
  // internal canvas coordinates so CSS scaling, centering, and fullscreen work
  // accurately on all mobile browsers.
  MobileControls controls = getIt<MobileControls>();
  final AddEventListenerOptions touchOpts =
      AddEventListenerOptions(passive: false);

  Point<int> clientCoordsToCanvasPoint(num clientX, num clientY) {
    final DOMRect rect = canvasElement.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) {
      return Point<int>(clientX.round(), clientY.round());
    }
    final double scaleX = canvasElement.width / rect.width;
    final double scaleY = canvasElement.height / rect.height;
    final int x = ((clientX - rect.left) * scaleX).round();
    final int y = ((clientY - rect.top) * scaleY).round();
    return Point<int>(
      x.clamp(0, max(0, canvasElement.width - 1)),
      y.clamp(0, max(0, canvasElement.height - 1)),
    );
  }

  Point<int> toCanvasPoint(Touch t) =>
      clientCoordsToCanvasPoint(t.clientX, t.clientY);

  int lastTouchMillis = 0;

  canvasElement.addEventListener(
      'touchstart',
      ((Event ev) {
        lastTouchMillis = DateTime.now().millisecondsSinceEpoch;
        final TouchEvent e = ev as TouchEvent;
        e.preventDefault();
        final TouchList touches = e.changedTouches;
        for (int i = 0; i < touches.length; i++) {
          final Touch? t = touches.item(i);
          if (t != null) {
            final Point<int> pt = toCanvasPoint(t);
            controls.touchDown(t.identifier, pt.x, pt.y);
          }
        }
      }).toJS,
      touchOpts);

  canvasElement.addEventListener(
      'touchmove',
      ((Event ev) {
        lastTouchMillis = DateTime.now().millisecondsSinceEpoch;
        final TouchEvent e = ev as TouchEvent;
        e.preventDefault();
        final TouchList touches = e.changedTouches;
        for (int i = 0; i < touches.length; i++) {
          final Touch? t = touches.item(i);
          if (t != null) {
            final Point<int> pt = toCanvasPoint(t);
            controls.touchMove(t.identifier, pt.x, pt.y);
          }
        }
      }).toJS,
      touchOpts);

  final JSFunction onTouchEndOrCancel = ((Event ev) {
    lastTouchMillis = DateTime.now().millisecondsSinceEpoch;
    final TouchEvent e = ev as TouchEvent;
    e.preventDefault();
    final TouchList touches = e.changedTouches;
    for (int i = 0; i < touches.length; i++) {
      final Touch? t = touches.item(i);
      if (t != null) {
        controls.touchUp(t.identifier);
      }
    }
  }).toJS;

  canvasElement.addEventListener('touchend', onTouchEndOrCancel, touchOpts);
  canvasElement.addEventListener('touchcancel', onTouchEndOrCancel, touchOpts);

  // Fallback for pointer/mouse taps on browsers or hybrid touchscreens that
  // dispatch pointer/click events instead of TouchEvents (guarded by
  // lastTouchMillis so touch devices never double-fire!).
  canvasElement.addEventListener(
      'click',
      ((Event ev) {
        final int now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastTouchMillis < 650) {
          return;
        }
        if (!world.loaderCompleted()) {
          final MouseEvent m = ev as MouseEvent;
          final Point<int> pt = clientCoordsToCanvasPoint(m.clientX, m.clientY);
          final bool wasTouch = controls.isTouchSupported;
          controls.touchDown(-99, pt.x, pt.y);
          controls.touchUp(-99);
          controls.setTouchSupported(wasTouch);
        }
      }).toJS);
  window.addEventListener(
      'blur',
      ((Event _) {
        controls.releaseAllTouches();
      }).toJS);

  startTimer();
}

void startTimer() {
  lastStep = new DateTime.now();
  _scheduleNextStep(TIMEOUT_MILLIS);
}

void _scheduleNextStep(int fallbackDelayMillis) {
  if (!document.hidden) {
    window.requestAnimationFrame(((num _) {
      step();
    }).toJS);
  } else {
    new Timer(new Duration(milliseconds: max(1, fallbackDelayMillis)), step);
  }
}

void step() {
  DateTime startStep = new DateTime.now();
  int millis =
      startStep.millisecondsSinceEpoch - lastStep.millisecondsSinceEpoch;
  double secs = (max(0, millis) / 1000.0).clamp(0.0, 0.1);

  world.frameDraw(secs);

  lastStep = startStep;
  int frameTimeMillis = new DateTime.now().millisecondsSinceEpoch -
      startStep.millisecondsSinceEpoch;

  int newStepMillis = max(1, TIMEOUT_MILLIS - frameTimeMillis);
  if (frameTimeMillis > 70) {
    print("Slow frametime of $frameTimeMillis ms!");
  }
  _scheduleNextStep(newStepMillis);
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

// Immediately hand off the commander role when the tab closes or moves to the
// background so other peers don't freeze waiting for the inactivity timeout or
// throttled background timer (~1 FPS) to trigger a slow-framerate transfer.
void setPageLifecycleListeners(WormWorld world) {
  final onClose = ((Event _) {
    world.network().transferCommander("tab closing");
    world.network().sendGoodbye("tab closing");
  }).toJS;
  // Listen to both beforeunload and pagehide for reliable coverage across tab
  // close, reload, and navigation (transferCommander is idempotent).
  window.addEventListener('beforeunload', onClose);
  window.addEventListener('pagehide', onClose);
  // Browsers heavily throttle timers in background tabs, so transfer commander
  // as soon as the page becomes hidden.
  document.addEventListener('visibilitychange', ((Event _) {
    if (document.hidden) {
      world.network().transferCommander("tab backgrounded");
    }
  }).toJS);
}



