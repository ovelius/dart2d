import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
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
  static const CHANGE_TARGET_TIME = 3.0;

  final Logger log = new Logger('Bot');
  Network _network;
  SpriteIndex _spriteIndex;
  SelfPlayerInfoProvider _selfPlayerInfoProvider;
  late KeyState _localKeyState;

  double _weaponChangeTime = WEAPON_CHANGE_TIME;
  double _changeTargetTime = CHANGE_TARGET_TIME;
  Random _random = new Random();

  LocalPlayerSprite? _controlledSprite = null;
  LocalPlayerSprite? _currentTargetSprite = null;

  int _stuckFrames = 0;
  Vec2? _stuckAt = null;

  Bot(this._network, this._spriteIndex, this._selfPlayerInfoProvider, KeyState localKeyState) {
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
    _changeTargetTime -= duration;
    if (_weaponChangeTime < 0.0) {
      _localKeyState.onKeyDown(KeyCodeDart.Q);
      _localKeyState.onKeyUp(KeyCodeDart.Q);
      _weaponChangeTime = WEAPON_CHANGE_TIME + _random.nextDouble() * WEAPON_CHANGE_SKEW;
    }
  }

  bool _findPlayerSprite() {
    PlayerInfoProto? info = _selfPlayerInfoProvider.getSelfInfo();
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
    if (stuck.sum() < 10) {
      _stuckFrames++;
    } else {
      _stuckFrames = 0;
      _localKeyState.onKeyUp(KeyCodeDart.W);
      _stuckAt = _controlledSprite!.position;
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
    if (_currentTargetSprite == null) {
      _currentTargetSprite = _findNewTarget();
      if (_currentTargetSprite != null) {
        log.info("Selected target ${_currentTargetSprite} delta position: ${_controlledSprite!.position - _currentTargetSprite!.position}");
      }
    } else if (_changeTargetTime < 0) {
      _changeTargetTime += CHANGE_TARGET_TIME;
      _currentTargetSprite = _findNewTarget();
    }
  }

  LocalPlayerSprite? _findNewTarget() {
    LocalPlayerSprite? selectedSprite = null;
    double shortestDistance = double.infinity;
    for (PlayerInfoProto info in _network.getGameState().playerInfoList()) {
      LocalPlayerSprite? candidate = _spriteIndex[info
          .spriteId] as LocalPlayerSprite?;
      if (candidate == null || !candidate.inGame()
          || candidate.networkId == _controlledSprite!.networkId) {
        continue;
      }
      double dst = _controlledSprite!.distanceTo(candidate);
      if (dst < shortestDistance) {
        shortestDistance = dst;
        selectedSprite = candidate;
      }
    }
    return selectedSprite;
  }

  void _aimUp() {
    _localKeyState.onKeyUp(KeyCodeDart.DOWN);
    _localKeyState.onKeyDown(KeyCodeDart.UP);
  }

  void _aimDown() {
    _localKeyState.onKeyUp(KeyCodeDart.UP);
    _localKeyState.onKeyDown(KeyCodeDart.DOWN);
  }


  void _aimAndWalkToTarget() {
    LocalPlayerSprite? target = _currentTargetSprite;
    if (target == null) {
      return;
    }
    Vec2 dir = target.position - _controlledSprite!.position;
    double angle = dir.toAngle();
    double gunAngle = _controlledSprite!.gun.angle;
    if (_controlledSprite!.angle > 0.002) {
      gunAngle += 2*pi;
      if (angle < 0) {
        angle += 2*pi;
      }
    }
    if (_controlledSprite!.angle < 0.002) {
      if (angle < gunAngle) {
        _aimUp();
      } else {
        _aimDown();
      }
    } else {
      if (angle > gunAngle) {
        _aimUp();
      } else {
        _aimDown();
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
