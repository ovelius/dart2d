import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';
import 'package:dart2d/keystate.dart';
import 'dart:math';

@Injectable()
class MobileControls {
  static const int BUTTON_SIZE = 40;
  static const int NO_BUTTON_TOUCH = -1;
  bool _isMobileBrowser;
  KeyState _localKeyState;
  int _width, _height;
  var _canvas = null;
  List<Point<int>> _buttons = [];
  Map<int, _fakeKeyCode> _buttonToKey = {};
  Map<int, int> _buttonsDown = {};
  Map<int, Point<int>> _touchStartPoints = {};

  MobileControls(
      @LocalKeyState() KeyState localKeyState,
      @TouchControls() bool isMobileBrowser,
      @WorldCanvas() Object canvasElement) {
    this._isMobileBrowser = isMobileBrowser;
    this._localKeyState = localKeyState;
    var canvasHack = canvasElement;
    this._canvas = canvasHack.context2D;
    this._width = canvasHack.width;
    this._height = canvasHack.height;

    num thirdX = _width / 3;
    num halfY = _height / 2 + BUTTON_SIZE + BUTTON_SIZE;
    num yDiff = 50;
    num xDiff = 90;

    // TODO used named keys.
    _buttons.add(new Point(thirdX * 2, halfY - yDiff));
    _buttonToKey[0] = new _fakeKeyCode(KeyCodeDart.W);

    _buttons.add(new Point(thirdX * 2 + xDiff, halfY + yDiff));
    _buttonToKey[1] = new _fakeKeyCode(KeyCodeDart.F);

    _buttons.add(new Point(thirdX * 2 + xDiff + xDiff, halfY - yDiff));
    _buttonToKey[2] = new _fakeKeyCode(KeyCodeDart.S);

    _buttons.add(new Point(thirdX * 2, BUTTON_SIZE));
    _buttonToKey[3] = new _fakeKeyCode(KeyCodeDart.E);

    _buttons.add(new Point(thirdX * 2 + xDiff + xDiff, BUTTON_SIZE));
    _buttonToKey[4] = new _fakeKeyCode(KeyCodeDart.Q);
  }

  draw() {
    if (_isMobileBrowser) {
      _canvas.save();
      _canvas.setFillColorRgb(255, 255, 255,  0.3);
      for (Point<int> btn in _buttons) {
        _canvas.beginPath();
        _canvas.arc(btn.x, btn.y, BUTTON_SIZE, 0, PI * 2);
        _canvas.closePath();
        _canvas.fill();
      }
      _canvas.restore();
    }
  }

  void TouchDown(int id, int x, int y) {
    for (int i = 0; i < _buttons.length; i++) {
      Point<int> btn = _buttons[i];
      if (x >= btn.x - BUTTON_SIZE && x <= btn.x + BUTTON_SIZE) {
        if (y >= btn.y - BUTTON_SIZE && y <= btn.y + BUTTON_SIZE) {
          _buttonsDown[id] = i;
          _localKeyState.onKeyDown(_buttonToKey[i]);
        }
      }
    }
    _touchStartPoints[id] = new Point(x, y);
  }

  void TouchUp(int id) {
    int index = _buttonsDown.remove(id);
    if (index != null) {
      _localKeyState.onKeyUp(_buttonToKey[index]);
    }
    _touchStartPoints.remove(id);
  }

  void TouchMove(int id, int x, int y) {
    Point<int> startPoint = _touchStartPoints[id];
    print("Delta X ${startPoint.x - x} Delta Y ${startPoint.y - y}");
  }
}

class _fakeKeyCode {
  int keyCode;
  _fakeKeyCode(this.keyCode);
}
