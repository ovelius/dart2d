import 'package:dart2d/util/util.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'dart:math';

/**
 * A very stupid bot that can be activated by appening "bot' as an URL argument
 * of the session. Mainly for testing.
 */
@Injectable()
class Bot {
  static const WEAPON_CHANGE_TIME = 3.0;
  static const WEAPON_CHANGE_SKEW = 4.0;

  final Logger log = new Logger('Bot');
  GameState _gameState;
  SpriteIndex _spriteIndex;
  SelfPlayerInfoProvider _selfPlayerInfoProvider;
  late KeyState _localKeyState;

  double _weaponChangeTime = WEAPON_CHANGE_TIME;
  Random _random = new Random();

  LocalPlayerSprite? _controlledSprite = null;
  LocalPlayerSprite? _currentTargetSprite = null;

  int _stuckFrames = 0;
  Vec2? _stuckAt = null;

  Bot(this._gameState, this._spriteIndex, this._selfPlayerInfoProvider, KeyState localKeyState) {
    this._localKeyState = localKeyState;
  }

  tick(double duration) {
    if (_controlledSprite == null && !_findPlayerSprite()) {
      return;
    }

    _maybeJump();
    _verifyTarget();

    _aimAndWalkToTarget();
      _localKeyState.onKeyDown(KeyCodeDart.F);
  
    _weaponChangeTime -= duration;
    if (_weaponChangeTime < 0.0) {
      _localKeyState.onKeyDown(KeyCodeDart.Q);
      _localKeyState.onKeyUp(KeyCodeDart.Q);
      _weaponChangeTime = WEAPON_CHANGE_TIME + _random.nextDouble() * WEAPON_CHANGE_SKEW;
    }
  }

  bool _findPlayerSprite() {
    PlayerInfo? info = _selfPlayerInfoProvider.getSelfInfo();
    if (info == null) {
      return false;
    }
    _controlledSprite = _spriteIndex[info.spriteId] as LocalPlayerSprite?;
    log.info("Found controller target ${_controlledSprite}");
    _stuckAt = new Vec2.copy(_controlledSprite!.position);
    return true;
  }

  void _maybeJump() {
    Vec2 stuck = _stuckAt! - _controlledSprite!.position;
    if (stuck.sum() < 3) {
      _stuckFrames++;
    } else {
      _stuckFrames = 0;
      _localKeyState.onKeyUp(KeyCodeDart.W);
    }

    if (_stuckFrames > 7) {
      _localKeyState.onKeyDown(KeyCodeDart.W);
    }
  }

  void _verifyTarget() {
    log.fine("Identify: ${_controlledSprite} target ${_currentTargetSprite}");
    if (_currentTargetSprite != null) {
      if (!_currentTargetSprite!.inGame() || _currentTargetSprite!.remove) {
        log.info("Target lost ${_currentTargetSprite}");
        _currentTargetSprite = null;
      }
    }
  }

  void _aimAndWalkToTarget() {
    Vec2 dir = _currentTargetSprite!.position - _controlledSprite!.position;
    double angle = dir.toAngle();
    double gunAngle = _controlledSprite!.gun.angle;
    if (_controlledSprite!.angle > 0.002) {
      gunAngle += 2*pi;
    }
    if (_controlledSprite!.angle < 0.002) {
      if (angle < gunAngle) {
        _localKeyState.onKeyUp(KeyCodeDart.DOWN);
        _localKeyState.onKeyDown(KeyCodeDart.UP);
      } else {
        _localKeyState.onKeyUp(KeyCodeDart.UP);
        _localKeyState.onKeyDown(KeyCodeDart.DOWN);
      }
    } else {
      if (angle > gunAngle) {
        _localKeyState.onKeyUp(KeyCodeDart.DOWN);
        _localKeyState.onKeyDown(KeyCodeDart.UP);
      } else {
        _localKeyState.onKeyUp(KeyCodeDart.UP);
        _localKeyState.onKeyDown(KeyCodeDart.DOWN);
      }
    }

    if (dir.x > 0) {
      _localKeyState.onKeyUp(KeyCodeDart.A);
      _localKeyState.onKeyDown(KeyCodeDart.D);
    } else {
      _localKeyState.onKeyUp(KeyCodeDart.D);
      _localKeyState.onKeyDown(KeyCodeDart.A);
    }
  }
}
