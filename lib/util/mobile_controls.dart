import 'dart:js_interop';

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/util.dart';
import 'package:injectable/injectable.dart';
import 'package:web/web.dart';
import 'package:logging/logging.dart' show Logger;
import 'dart:math';
import 'package:dart2d/res/sounds.dart';

@Singleton(scope: 'world')
class MobileControls {
  static const int JUMP_BUTTON = 0;
  static const int FIRE_BUTTON = 1;
  static const int ROPE_BUTTON = 2;
  static const int WEAPON_SELECT_BUTTON = 3;
  static const int SOUND_BUTTON = 4;

  final Logger log = new Logger('MobileControls');
  static const int BUTTON_SIZE = 50;
  static const int NO_BUTTON_TOUCH = -1;

  late bool _isTouchSupported;
  late KeyState _localKeyState;
  Bot _bot;
  Sounds sounds;
  late String _botNameIfEnabled;
  ConfigParams _configParams;
  late int width, height;
  late int _lastCanvasElementWidth;
  late int _lastCanvasElementHeight;
  late CanvasRenderingContext2D _canvas;
  late HtmlScreen _screen;
  List<Point<int>> _buttons = [];
  List<int> _buttonRadii = [];
  int _buttonRadius = BUTTON_SIZE;
  int _soundButtonRadius = 28;
  Map<int, int> _buttonToKey = {};
  Map<int, int> _touchIdToButtonDown = {};
  Map<int, int> _buttonIdToTouchId = {};
  Map<int, Point<int>> _touchStartPoints = {};
  Map<int, Point<int>> _touchPositions = {};
  Map<int, Point<int>> _touchDeltas = {};
  List<dynamic> _touchListeners = [];
  SelfPlayerInfoProvider _selfPlayerInfoProvider;
  DateTime _lastInput = new DateTime.now();

  MobileControls(
      this._selfPlayerInfoProvider,
      this._configParams,
      this._bot,
      this.sounds,
      HtmlScreen screen,
      KeyState localKeyState,
      @Named(TOUCH_SUPPORTED) bool touchSupported,
      WorldCanvas canvasElement) {
    this._isTouchSupported = touchSupported;
    this._localKeyState = localKeyState;
    var canvasHack = canvasElement;
    this._canvas = canvasHack.context2D;
    this._screen = screen;
    this.width = canvasHack.width;
    this.height = canvasHack.height;
    this._lastCanvasElementWidth = canvasHack.width;
    this._lastCanvasElementHeight = canvasHack.height;
    this._botNameIfEnabled = _configParams.getString(ConfigParam.BOT_ENABLED);

    _buttonToKey[JUMP_BUTTON] = KeyCodeDart.W;
    _buttonToKey[FIRE_BUTTON] = KeyCodeDart.F;
    _buttonToKey[ROPE_BUTTON] = KeyCodeDart.S;
    _buttonToKey[WEAPON_SELECT_BUTTON] = KeyCodeDart.E;

    _layoutButtons();
  }

  int get buttonRadius => _buttonRadius;

  int buttonRadiusFor(int index) {
    if (index >= 0 && index < _buttonRadii.length) {
      return _buttonRadii[index];
    }
    return _buttonRadius;
  }

  void updateCanvasSize(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) {
      return;
    }
    if (newWidth != width || newHeight != height) {
      width = newWidth;
      height = newHeight;
      _layoutButtons();
    }
  }

  void _layoutButtons() {
    final int shortSide = min(width, height);
    _buttonRadius = (shortSide * 0.095).round().clamp(30, 48);
    final int fireRadius = (_buttonRadius * 1.08).round().clamp(32, 52);
    _soundButtonRadius = (_buttonRadius * 0.68).round().clamp(22, 32);

    final int edgeMargin = max(14, (_buttonRadius * 0.38).round());
    final double step = _buttonRadius * 2.38;

    final int rightEdgeX = max(_buttonRadius + edgeMargin,
        width - edgeMargin - _buttonRadius);
    final int bottomEdgeY = max(fireRadius + edgeMargin,
        height - edgeMargin - fireRadius);

    // Ergonomic bottom-right thumb arc:
    // - FIRE (1): comfortable primary bottom-inner thumb resting spot
    // - JUMP (0): outer-right arc button
    // - ROPE (2): upper-inner arc button above FIRE
    final Point<int> jumpPos = Point<int>(
      rightEdgeX,
      (bottomEdgeY - step * 0.78).round().clamp(
          _buttonRadius + edgeMargin, height - _buttonRadius - edgeMargin),
    );
    final Point<int> firePos = Point<int>(
      (rightEdgeX - step * 0.96).round().clamp(
          fireRadius + edgeMargin, width - fireRadius - edgeMargin),
      bottomEdgeY,
    );
    final Point<int> ropePos = Point<int>(
      (rightEdgeX - step * 0.96).round().clamp(
          _buttonRadius + edgeMargin, width - _buttonRadius - edgeMargin),
      (bottomEdgeY - step * 1.16).round().clamp(
          _buttonRadius + edgeMargin, height - _buttonRadius - edgeMargin),
    );

    // Top-right weapon badge / wheel trigger (away from left-thumb movement
    // zone and top-left HUD message banners).
    final int weaponPad = max(_buttonRadius, 36) + edgeMargin;
    final Point<int> weaponPos = Point<int>(
      (width - weaponPad).clamp(weaponPad, max(weaponPad, width - weaponPad)),
      weaponPad.clamp(
          _buttonRadius + 8, max(_buttonRadius + 8, height - _buttonRadius - 8)),
    );

    // Top-center sound mute/unmute pill badge.
    final int soundY =
        (edgeMargin + _soundButtonRadius).clamp(_soundButtonRadius + 6, height ~/ 2);
    final Point<int> soundPos = Point<int>(width ~/ 2, soundY);

    _buttons = <Point<int>>[
      jumpPos,
      firePos,
      ropePos,
      weaponPos,
      soundPos,
    ];
    _buttonRadii = <int>[
      _buttonRadius,
      fireRadius,
      _buttonRadius,
      max(_buttonRadius, 38),
      _soundButtonRadius,
    ];
  }

  Point<int> buttonLocation(int index) {
    return _buttons[index];
  }

  bool _isGameplayControlsActive() {
    if (!_isTouchSupported || _botNameIfEnabled.isNotEmpty) {
      return false;
    }
    try {
      final PlayerInfoProto? selfInfo = _selfPlayerInfoProvider.getSelfInfo();
      if (selfInfo == null || !selfInfo.inGame) {
        return false;
      }
    } catch (_) {
      return false;
    }
    return !isPortrait();
  }

  int _hitTestButton(int x, int y) {
    // Allow a small 10% touch halo while prioritizing the closest button center.
    int bestIndex = -1;
    double bestDistSq = double.infinity;
    for (int i = 0; i < _buttons.length; i++) {
      final Point<int> btn = _buttons[i];
      final double hitR = _buttonRadii[i] * 1.10;
      final double dx = (x - btn.x).toDouble();
      final double dy = (y - btn.y).toDouble();
      final double distSq = dx * dx + dy * dy;
      if (distSq <= hitR * hitR && distSq < bestDistSq) {
        bestDistSq = distSq;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  bool isButtonTouch(int x, int y) {
    return _hitTestButton(x, y) != -1;
  }

  draw(double duration) {
    if (_botNameIfEnabled.isNotEmpty) {
      _bot.tick(duration);
      return;
    }
    if (!_isTouchSupported) {
      return;
    }
    try {
      final HTMLCanvasElement c = _canvas.canvas;
      if (c.width > 0 &&
          c.height > 0 &&
          (c.width != _lastCanvasElementWidth ||
              c.height != _lastCanvasElementHeight)) {
        _lastCanvasElementWidth = c.width;
        _lastCanvasElementHeight = c.height;
        updateCanvasSize(c.width, c.height);
      }
    } catch (_) {}

    PlayerInfoProto? selfInfo = _selfPlayerInfoProvider.getSelfInfo();
    if (selfInfo == null || !selfInfo.inGame) {
      if (_touchIdToButtonDown.isNotEmpty) {
        releaseAllTouches();
      }
      return;
    }
    if (isPortrait()) {
      // Bring up game table while holding phone in portrait.
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

    // 1. Draw left-thumb virtual joystick feedback when actively moving/aiming.
    _drawActiveJoystickFeedback();

    // 2. Draw action buttons & weapon button frame.
    _drawCartoonActionButton(
      index: JUMP_BUTTON,
      label: "JUMP",
      accentHex: "#4cd964",
      fillRgb: "36, 78, 56",
    );
    _drawCartoonActionButton(
      index: FIRE_BUTTON,
      label: "FIRE",
      accentHex: "#ff6b4a",
      fillRgb: "92, 34, 34",
    );
    _drawCartoonActionButton(
      index: ROPE_BUTTON,
      label: "ROPE",
      accentHex: "#5ce6ff",
      fillRgb: "30, 62, 88",
    );
    _drawWeaponButtonBackdrop();
    _drawSoundButton();

    _canvas.restore();
  }

  void _drawActiveJoystickFeedback() {
    final int? moveTouchId = _buttonIdToTouchId[NO_BUTTON_TOUCH];
    if (moveTouchId == null) {
      return;
    }
    final Point<int>? origin = _touchStartPoints[moveTouchId];
    if (origin == null) {
      return;
    }
    final Point<int> current = _touchPositions[moveTouchId] ?? origin;
    final double baseR = _buttonRadius * 1.15;
    final double knobR = _buttonRadius * 0.48;
    double dx = (current.x - origin.x).toDouble();
    double dy = (current.y - origin.y).toDouble();
    final double dist = sqrt(dx * dx + dy * dy);
    if (dist > baseR && dist > 0) {
      dx = dx / dist * baseR;
      dy = dy / dist * baseR;
    }

    _canvas.save();
    _canvas.fillStyle = "rgba(16, 26, 44, 0.28)".toJS;
    _canvas.strokeStyle = "rgba(255, 255, 255, 0.48)".toJS;
    _canvas.lineWidth = 2.5;
    _canvas.beginPath();
    _canvas.arc(origin.x, origin.y, baseR, 0, pi * 2);
    _canvas.fill();
    _canvas.stroke();

    _canvas.fillStyle = "rgba(255, 232, 110, 0.68)".toJS;
    _canvas.strokeStyle = "rgba(18, 28, 44, 0.85)".toJS;
    _canvas.lineWidth = 2.5;
    _canvas.beginPath();
    _canvas.arc(origin.x + dx, origin.y + dy, knobR, 0, pi * 2);
    _canvas.fill();
    _canvas.stroke();
    _canvas.restore();
  }

  void _drawCartoonActionButton({
    required int index,
    required String label,
    required String accentHex,
    required String fillRgb,
  }) {
    final Point<int> btn = _buttons[index];
    final bool pressed = buttonIsDown(index);
    final double r = _buttonRadii[index] * (pressed ? 0.93 : 1.0);

    _canvas.save();
    // Subtle drop shadow.
    _canvas.fillStyle = "rgba(8, 14, 24, 0.40)".toJS;
    _canvas.beginPath();
    _canvas.arc(btn.x + 2, btn.y + 3, r, 0, pi * 2);
    _canvas.fill();

    // Translucent tinted button body.
    _canvas.fillStyle =
        "rgba($fillRgb, ${pressed ? '0.82' : '0.58'})".toJS;
    _canvas.beginPath();
    _canvas.arc(btn.x, btn.y, r, 0, pi * 2);
    _canvas.fill();

    // Crisp dark outer ring + bright inner rim.
    _canvas.strokeStyle = "rgba(14, 20, 30, 0.85)".toJS;
    _canvas.lineWidth = 3.2;
    _canvas.stroke();

    _canvas.strokeStyle = (pressed ? "#ffe97a" : accentHex).toJS;
    _canvas.lineWidth = pressed ? 3.0 : 2.2;
    _canvas.beginPath();
    _canvas.arc(btn.x, btn.y, max(4.0, r - 2.5), 0, pi * 2);
    _canvas.stroke();

    // Bold readable label centered inside button.
    final int fontPx = (r * 0.36).round().clamp(11, 17);
    _canvas.font = '900 ${fontPx}px "Trebuchet MS", Arial, sans-serif';
    _canvas.textAlign = "center";
    _canvas.textBaseline = "middle";
    _canvas.lineJoin = "round";
    _canvas.strokeStyle = "#101824".toJS;
    _canvas.lineWidth = 3.2;
    _canvas.strokeText(label, btn.x, btn.y + 0.5);
    _canvas.fillStyle = (pressed ? "#ffe97a" : "#ffffff").toJS;
    _canvas.fillText(label, btn.x, btn.y + 0.5);
    _canvas.restore();
  }

  void _drawWeaponButtonBackdrop() {
    final Point<int> btn = _buttons[WEAPON_SELECT_BUTTON];
    final bool pressed = buttonIsDown(WEAPON_SELECT_BUTTON);
    final double r = _buttonRadii[WEAPON_SELECT_BUTTON].toDouble();

    _canvas.save();
    _canvas.fillStyle =
        "rgba(20, 30, 48, ${pressed ? '0.72' : '0.46'})".toJS;
    _canvas.beginPath();
    _canvas.arc(btn.x, btn.y, r, 0, pi * 2);
    _canvas.fill();

    _canvas.strokeStyle = (pressed ? "#ffe97a" : "rgba(255, 255, 255, 0.55)").toJS;
    _canvas.lineWidth = 2.2;
    _canvas.stroke();
    _canvas.restore();
  }

  void _drawSoundButton() {
    final Point<int> btn = _buttons[SOUND_BUTTON];
    final double r = _buttonRadii[SOUND_BUTTON].toDouble();

    _canvas.save();
    _canvas.fillStyle = "rgba(18, 26, 40, 0.56)".toJS;
    _canvas.beginPath();
    _canvas.arc(btn.x, btn.y, r, 0, pi * 2);
    _canvas.fill();
    _canvas.strokeStyle = "rgba(255, 255, 255, 0.45)".toJS;
    _canvas.lineWidth = 1.8;
    _canvas.stroke();

    final int fontPx = (r * 0.82).round().clamp(16, 24);
    _canvas.font = '${fontPx}px Arial, sans-serif';
    _canvas.textAlign = "center";
    _canvas.textBaseline = "middle";
    final String sound = sounds.soundEnabled ? "🔊" : "🔇";
    _canvas.fillStyle = "#ffffff".toJS;
    _canvas.fillText(sound, btn.x, btn.y + 1);
    _canvas.restore();
  }

  listenForTouch(dynamic d) {
    _touchListeners.add(d);
  }

  bool isPortrait() {
    try {
      final dynamic orientation = _screen.orientation;
      if (orientation != null) {
        final String type = orientation.type as String;
        return type.contains("portrait");
      }
    } catch (_) {}
    return height > width;
  }

  void touchDown(int id, int x, int y) {
    _lastInput = new DateTime.now();
    // Clear any stale state from a previous touch with the same identifier.
    _touchDeltas.remove(id);
    _touchStartPoints[id] = new Point(x, y);
    _touchPositions[id] = new Point(x, y);

    final bool gameplayActive = _isGameplayControlsActive();
    final int hitButton = gameplayActive ? _hitTestButton(x, y) : -1;

    for (dynamic d in _touchListeners) {
      d(x, y);
    }

    if (!gameplayActive) {
      return;
    }

    if (hitButton != -1) {
      if (_buttonToKey.containsKey(hitButton)) {
        // Release previous touch on this button if another finger took it over.
        final int? prevTouch = _buttonIdToTouchId[hitButton];
        if (prevTouch != null && prevTouch != id) {
          _touchIdToButtonDown.remove(prevTouch);
        }
        _buttonIdToTouchId[hitButton] = id;
        _touchIdToButtonDown[id] = hitButton;
        _localKeyState.onKeyDown(_buttonToKey[hitButton]!);
      } else if (hitButton == SOUND_BUTTON) {
        sounds.soundEnabled = !sounds.soundEnabled;
        log.info("Sound enabled ${sounds.soundEnabled}");
      }
    } else {
      _touchIdToButtonDown[id] = NO_BUTTON_TOUCH;
      // Do not hijack an already-held movement/aim thumb with a second stray tap.
      if (!_buttonIdToTouchId.containsKey(NO_BUTTON_TOUCH)) {
        _buttonIdToTouchId[NO_BUTTON_TOUCH] = id;
      }
    }
  }

  void touchUp(int id) {
    final int? index = _touchIdToButtonDown.remove(id);
    if (index != null && index != NO_BUTTON_TOUCH && _buttonToKey.containsKey(index)) {
      if (_buttonIdToTouchId[index] == id) {
        _buttonIdToTouchId.remove(index);
        _localKeyState.onKeyUp(_buttonToKey[index]!);
      }
    } else if (index == NO_BUTTON_TOUCH &&
        _buttonIdToTouchId[NO_BUTTON_TOUCH] == id) {
      _buttonIdToTouchId.remove(NO_BUTTON_TOUCH);
      // If another non-button touch is still held down, hand movement control to it.
      for (final MapEntry<int, int> entry in _touchIdToButtonDown.entries) {
        if (entry.value == NO_BUTTON_TOUCH) {
          _buttonIdToTouchId[NO_BUTTON_TOUCH] = entry.key;
          break;
        }
      }
    }
    _touchStartPoints.remove(id);
    _touchPositions.remove(id);
    _touchDeltas.remove(id);
  }

  void touchCancel(int id) {
    touchUp(id);
  }

  void releaseAllTouches() {
    for (final int buttonIdx in _buttonIdToTouchId.keys.toList()) {
      if (buttonIdx != NO_BUTTON_TOUCH && _buttonToKey.containsKey(buttonIdx)) {
        _localKeyState.onKeyUp(_buttonToKey[buttonIdx]!);
      }
    }
    _touchIdToButtonDown.clear();
    _buttonIdToTouchId.clear();
    _touchStartPoints.clear();
    _touchPositions.clear();
    _touchDeltas.clear();
  }

  void touchMove(int id, int x, int y) {
    final Point<int>? startPoint = _touchStartPoints[id];
    if (startPoint == null) {
      return;
    }
    _touchPositions[id] = new Point(x, y);
    _touchDeltas[id] = new Point(startPoint.x - x, startPoint.y - y);
    _lastInput = new DateTime.now();
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
