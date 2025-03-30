import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/util/util.dart';
import 'package:injectable/injectable.dart';
import 'dart:math';
import 'util.dart';

@Singleton(scope: 'world')
class MobileControls {
  static const int BUTTON_SIZE = 40;
  static const int NO_BUTTON_TOUCH = -1;
  late bool _isTouchSupported;
  late KeyState _localKeyState;
  Bot _bot;
  late String _botNameIfEnabled;
  ConfigParams _configParams;
  late int _width, _height;
  late dynamic _canvas;
  late HtmlScreen _screen;
  List<Point<int>> _buttons = [];
  Map<int, int> _buttonToKey = {};
  Map<int, int> _touchIdToButtonDown = {};
  Map<int, int> _buttonIdToTouchId = {};
  Map<int, Point<int>> _touchStartPoints = {};
  Map<int, Point<int>> _touchDeltas = {};
  List<dynamic> _touchListeners = [];
  SelfPlayerInfoProvider _selfPlayerInfoProvider;
  DateTime _lastInput = new DateTime.now();

  MobileControls(
      this._selfPlayerInfoProvider,
      this._configParams,
      this._bot,
      HtmlScreen screen,
      KeyState localKeyState,
      @Named(TOUCH_SUPPORTED) bool touchSupported,
      WorldCanvas canvasElement) {
    this._isTouchSupported = touchSupported;
    this._localKeyState = localKeyState;
    var canvasHack = canvasElement;
    this._canvas = canvasHack.context2D;
    this._screen = screen;
    this._width = canvasHack.width;
    this._height = canvasHack.height;
    this._botNameIfEnabled = _configParams.getString(ConfigParam.BOT_ENABLED);
    int thirdX = (_width / 3).toInt();
    int halfY = (_height / 2 + BUTTON_SIZE + BUTTON_SIZE).toInt();
    int yDiff = 50;
    int xDiff = 90;

    // TODO used named keys.
    _buttons.add(new Point(thirdX * 2, halfY - yDiff));
    _buttonToKey[0] = KeyCodeDart.W;

    _buttons.add(new Point(thirdX * 2 + xDiff, halfY + yDiff));
    _buttonToKey[1] = KeyCodeDart.F;

    _buttons.add(new Point(thirdX * 2 + xDiff + xDiff, halfY - yDiff));
    _buttonToKey[2] = KeyCodeDart.S;

    _buttons.add(new Point(thirdX * 2, BUTTON_SIZE));
    _buttonToKey[3] = KeyCodeDart.E;

    _buttons.add(new Point(thirdX * 2 + xDiff + xDiff, BUTTON_SIZE));
    _buttonToKey[4] = KeyCodeDart.Q;
  }

  draw(double duration) {
    if (_botNameIfEnabled.isNotEmpty) {
      _bot.tick(duration);
    } else if (_isTouchSupported) {
      PlayerInfo? selfInfo = _selfPlayerInfoProvider.getSelfInfo();
      if (selfInfo == null || !selfInfo.inGame) {
        return;
      }
      if (isPortrait()) {
        // Bring up game table.
        if (!_localKeyState.keyIsDown(KeyCodeDart.SHIFT)) {
          _localKeyState.onKeyDown(KeyCodeDart.SHIFT);
        }
        return;
      } else {
        if (_localKeyState.keyIsDown(KeyCodeDart.SHIFT)) {
          _localKeyState.onKeyUp(KeyCodeDart.SHIFT);
        }
      }
      _canvas.save();
      for (int i = 0; i < _buttons.length; i++) {
        Point<int> btn = _buttons[i];
        if (buttonIsDown(i)) {
          _canvas.setFillColorRgb(255, 255, 255, 0.3);
        } else {
          _canvas.setFillColorRgb(255, 255, 255, 0.5);
        }
        _canvas.beginPath();
        _canvas.arc(btn.x, btn.y, BUTTON_SIZE, 0, pi * 2);
        _canvas.closePath();
        _canvas.fill();
      }
      _canvas.restore();
    }
  }

  listenForTouch(dynamic d) {
    _touchListeners.add(d);
  }

  bool isPortrait() {
    if (_screen.orientation == null) {
      return false;
    }
    return _screen.orientation.type.contains("portrait");
  }

  void touchDown(int id, int x, int y) {
    for (dynamic d in _touchListeners) {
      d(x, y);
    }
    bool buttonFound = false;
    for (int i = 0; i < _buttons.length; i++) {
      Point<int> btn = _buttons[i];
      if (x >= btn.x - BUTTON_SIZE && x <= btn.x + BUTTON_SIZE) {
        if (y >= btn.y - BUTTON_SIZE && y <= btn.y + BUTTON_SIZE) {
          _touchIdToButtonDown[id] = i;
          _buttonIdToTouchId[i] = id;
          _localKeyState.onKeyDown(_buttonToKey[i]!);
          buttonFound = true;
        }
      }
    }
    if (!buttonFound) {
      _touchIdToButtonDown[id] = NO_BUTTON_TOUCH;
      _buttonIdToTouchId[NO_BUTTON_TOUCH] = id;
    }
    _touchStartPoints[id] = new Point(x, y);
    _lastInput = new DateTime.now();
  }

  void touchUp(int id) {
    int? index = _touchIdToButtonDown.remove(id);
    if (index != NO_BUTTON_TOUCH) {
      _localKeyState.onKeyUp(_buttonToKey[index]!);
    }
    _buttonIdToTouchId.remove(index);
    _touchStartPoints.remove(id);
  }

  void touchMove(int id, int x, int y) {
    Point<int> startPoint = _touchStartPoints[id]!;
    _touchDeltas[id] = new Point(startPoint.x - x, startPoint.y - y);
  }

  bool buttonIsDown([int index = NO_BUTTON_TOUCH]) {
    return _buttonIdToTouchId.containsKey(index);
  }

  /**
   * Get the current touch delta for a button.
   */
  Point<int>? getTouchDeltaForButton([int index = NO_BUTTON_TOUCH]) {
    int? id = _buttonIdToTouchId[index];
    if (id == null) {
      return null;
    }
    return _touchDeltas[id];
  }

  Duration lastUserInput() {
    return new DateTime.now().difference(_lastInput);
  }
}
