library performance_governor;

import 'dart:math';

/// Discrete adaptive rendering quality levels driven by measured frame rate.
enum QualityTier {
  high,
  medium,
  low,
}

/// Tracks smoothed rendering FPS and governs **both** local rendering detail
/// and per-connection network send rate (`ConnectionFrameHandler`) in stages:
///
/// 1. **Lower rendering detail FIRST:** When FPS dips, visual detail steps down
///    (`HIGH -> MEDIUM -> LOW`) while keeping network send rate at full `15 Hz`
///    so multiplayer responsiveness stays crisp if shedding draw work recovers FPS.
/// 2. **More aggressive when Commander:** Because the Commander runs authoritative
///    collisions, powerups, and packet forwarding (and hands off command if FPS
///    collapses below 30), Commanders step down visual detail earlier (`< 53 FPS`
///    and `< 40 FPS`), faster (`0.50s` hold), and to leaner budgets (`0.50` / `0.20`).
/// 3. **Throttle network FPS only after visual detail has stepped down:** Only
///    when already in `MEDIUM`/`LOW` quality and smoothed FPS is *still* low
///    does [targetNetworkFrameRate] scale network FPS down toward `6 Hz`,
///    recovering smoothly with asymmetric hysteresis.
class PerformanceGovernor {
  static const double CLIENT_STEP_DOWN_MEDIUM_FPS = 48.0;
  static const double CLIENT_STEP_DOWN_LOW_FPS = 34.0;
  static const double CLIENT_STEP_UP_FPS = 55.0;
  static const double CLIENT_STEP_DOWN_HOLD_SECONDS = 0.75;
  static const double CLIENT_STEP_UP_HOLD_SECONDS = 4.0;

  // Commanders shed rendering detail earlier & faster, and wait longer before
  // restoring heavy visual polish.
  static const double COMMANDER_STEP_DOWN_MEDIUM_FPS = 53.0;
  static const double COMMANDER_STEP_DOWN_LOW_FPS = 40.0;
  static const double COMMANDER_STEP_UP_FPS = 57.0;
  static const double COMMANDER_STEP_DOWN_HOLD_SECONDS = 0.50;
  static const double COMMANDER_STEP_UP_HOLD_SECONDS = 5.0;

  QualityTier _tier = QualityTier.high;
  double _smoothedFps = 60.0;
  bool _hasSample = false;
  double _lowHoldSeconds = 0.0;
  double _highHoldSeconds = 0.0;

  QualityTier get tier => _tier;
  double get smoothedFps => _smoothedFps;

  /// Client visual detail multiplier in `[0.25, 1.0]` for the current [tier].
  double get detailScale => detailScaleForRole(isCommander: false);

  /// Role-aware visual detail multiplier (`Commander` uses leaner `0.50` / `0.20`
  /// budgets vs `Client` `0.60` / `0.25`).
  double detailScaleForRole({bool isCommander = false}) {
    switch (_tier) {
      case QualityTier.high:
        return 1.0;
      case QualityTier.medium:
        return isCommander ? 0.50 : 0.60;
      case QualityTier.low:
        return isCommander ? 0.20 : 0.25;
    }
  }

  /// Combines the hysteresis-governed detail scale with an immediate safeguard
  /// against sudden severe frame drops (or explicit `FpsCounter.setFpsForTest`
  /// overrides before hold time has accumulated).
  double effectiveDetailScale(
    double currentMeasuredFps, {
    bool isCommander = false,
  }) {
    final double governed = detailScaleForRole(isCommander: isCommander);
    if (currentMeasuredFps <= 0.0) {
      return governed;
    }
    double instantCap = 1.0;
    if (isCommander) {
      if (currentMeasuredFps < 28.0) {
        instantCap = 0.20;
      } else if (currentMeasuredFps < 40.0) {
        instantCap = 0.40;
      } else if (currentMeasuredFps < 53.0) {
        instantCap = 0.65;
      }
    } else {
      if (currentMeasuredFps < 25.0) {
        instantCap = 0.25;
      } else if (currentMeasuredFps < 35.0) {
        instantCap = 0.50;
      } else if (currentMeasuredFps < 48.0) {
        instantCap = 0.75;
      }
    }
    return min(governed, instantCap);
  }

  /// Computes the governed network framerate in `[minRate, maxRate]` (`6..15 Hz`),
  /// strictly prioritizing visual detail reduction **before** lowering network FPS:
  /// - At [QualityTier.high]: always returns `maxRate` (`15 Hz`) so visual detail
  ///   absorbs FPS dips first.
  /// - At [QualityTier.medium]: keeps `maxRate` (`15 Hz`) if lowering visuals kept
  ///   `_smoothedFps >= 44`; trims gently to `12 Hz` only if FPS is still `< 44`.
  /// - At [QualityTier.low]: visual detail is already minimal; if FPS is still
  ///   `< 46`, scales network rate smoothly from `12 Hz` down to `minRate` (`6 Hz`).
  int targetNetworkFrameRate({int minRate = 6, int maxRate = 15}) {
    if (!_hasSample || _tier == QualityTier.high) {
      return maxRate;
    }
    if (_tier == QualityTier.medium) {
      if (_smoothedFps >= 44.0) {
        return maxRate;
      }
      return max(minRate, min(maxRate, 12));
    }
    // QualityTier.low: rendering detail is already stripped to minimum.
    if (_smoothedFps >= 46.0) {
      return maxRate;
    }
    if (_smoothedFps <= 25.0) {
      return minRate;
    }
    final double frac = ((_smoothedFps - 25.0) / (46.0 - 25.0)).clamp(0.0, 1.0);
    final int scaled = (minRate + frac * (12 - minRate)).round();
    return scaled.clamp(minRate, maxRate);
  }

  /// Maps [targetNetworkFrameRate] onto the `[0..60]` draw-FPS input expected by
  /// `ConnectionFrameHandler.reportFrameRates(...)` so every governed integer
  /// rate in `6..15` translates 1-to-1 without modifying `ConnectionFrameHandler`'s
  /// mock interface.
  double equivalentDrawFpsForNetwork({int minRate = 6, int maxRate = 15}) {
    final int rate = targetNetworkFrameRate(minRate: minRate, maxRate: maxRate);
    if (rate >= maxRate) {
      return 60.0;
    }
    if (rate <= minRate) {
      return 24.0;
    }
    if (rate == 12) {
      return 48.0;
    }
    if (rate == 7) {
      return 30.0;
    }
    return (rate + 0.2) * (60.0 / maxRate);
  }

  /// Updates the smoothed FPS estimate and transitions quality tiers when
  /// sustained thresholds are met. Ignores uninitialized (`<= 0`) FPS readings
  /// and large tab-background hitch deltas (`dt > maxDt`).
  void update(
    double dt,
    double measuredFps, {
    bool isCommander = false,
    double maxDt = 0.25,
  }) {
    if (measuredFps <= 0.0 || dt <= 0.0 || dt > maxDt) {
      return;
    }

    if (!_hasSample) {
      _smoothedFps = measuredFps;
      _hasSample = true;
    } else {
      final double alpha = (dt * 3.0).clamp(0.02, 0.55);
      _smoothedFps += (measuredFps - _smoothedFps) * alpha;
    }

    final double medThreshold = isCommander
        ? COMMANDER_STEP_DOWN_MEDIUM_FPS
        : CLIENT_STEP_DOWN_MEDIUM_FPS;
    final double lowThreshold =
        isCommander ? COMMANDER_STEP_DOWN_LOW_FPS : CLIENT_STEP_DOWN_LOW_FPS;
    final double stepDownHold = isCommander
        ? COMMANDER_STEP_DOWN_HOLD_SECONDS
        : CLIENT_STEP_DOWN_HOLD_SECONDS;
    final double stepUpThreshold =
        isCommander ? COMMANDER_STEP_UP_FPS : CLIENT_STEP_UP_FPS;
    final double stepUpHold = isCommander
        ? COMMANDER_STEP_UP_HOLD_SECONDS
        : CLIENT_STEP_UP_HOLD_SECONDS;

    // 1. Check fast step-down conditions.
    final bool wantsStepDown =
        (_tier == QualityTier.high && _smoothedFps < medThreshold) ||
            (_tier == QualityTier.medium && _smoothedFps < lowThreshold);

    if (wantsStepDown) {
      _lowHoldSeconds += dt;
      _highHoldSeconds = 0.0;
      if (_lowHoldSeconds >= stepDownHold) {
        _lowHoldSeconds = 0.0;
        if (_tier == QualityTier.high) {
          _tier = _smoothedFps < lowThreshold
              ? QualityTier.low
              : QualityTier.medium;
        } else if (_tier == QualityTier.medium) {
          _tier = QualityTier.low;
        }
      }
      return;
    }

    _lowHoldSeconds = max(0.0, _lowHoldSeconds - dt * 0.5);

    // 2. Check conservative step-up condition when below HIGH.
    if (_tier != QualityTier.high && _smoothedFps >= stepUpThreshold) {
      _highHoldSeconds += dt;
      if (_highHoldSeconds >= stepUpHold) {
        _highHoldSeconds = 0.0;
        _tier =
            _tier == QualityTier.low ? QualityTier.medium : QualityTier.high;
      }
    } else {
      _highHoldSeconds = max(0.0, _highHoldSeconds - dt);
    }
  }

  void setTierForTest(QualityTier newTier, {double? smoothedFps}) {
    _tier = newTier;
    if (smoothedFps != null) {
      _smoothedFps = smoothedFps;
      _hasSample = true;
    }
    _lowHoldSeconds = 0.0;
    _highHoldSeconds = 0.0;
  }

  void reset() {
    _tier = QualityTier.high;
    _smoothedFps = 60.0;
    _hasSample = false;
    _lowHoldSeconds = 0.0;
    _highHoldSeconds = 0.0;
  }
}
