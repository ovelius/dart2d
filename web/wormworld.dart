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



