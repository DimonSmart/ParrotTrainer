import 'dart:math' as math;

enum SoundTransition { started, ended }

abstract interface class SoundDetector {
  double get currentLevelDb;
  bool get isSoundDetected;
  SoundTransition? addSample(double levelDb, DateTime now);
  void setThreshold(double thresholdDb);
  void reset();
}

class ThresholdSoundDetector implements SoundDetector {
  ThresholdSoundDetector({
    required double initialThresholdDb,
    this.attack = const Duration(milliseconds: 180),
    this.release = const Duration(milliseconds: 350),
    this.hysteresisDb = 3,
  }) : _thresholdDb = initialThresholdDb;

  final Duration attack;
  final Duration release;
  final double hysteresisDb;
  double _thresholdDb;
  double _levelDb = -80;
  bool _detected = false;
  DateTime? _candidateSince;

  @override
  double get currentLevelDb => _levelDb;
  @override
  bool get isSoundDetected => _detected;

  @override
  SoundTransition? addSample(double levelDb, DateTime now) {
    final bounded = levelDb.clamp(-80.0, 0.0);
    _levelDb = _levelDb <= -79.9 ? bounded : (_levelDb * 0.65 + bounded * 0.35);
    final shouldBeActive = _detected
        ? _levelDb >= _thresholdDb - hysteresisDb
        : _levelDb >= _thresholdDb;
    if (shouldBeActive == _detected) {
      _candidateSince = null;
      return null;
    }
    _candidateSince ??= now;
    final required = shouldBeActive ? attack : release;
    if (now.difference(_candidateSince!) < required) return null;
    _detected = shouldBeActive;
    _candidateSince = null;
    return _detected ? SoundTransition.started : SoundTransition.ended;
  }

  @override
  void setThreshold(double thresholdDb) => _thresholdDb = thresholdDb;

  @override
  void reset() {
    _detected = false;
    _candidateSince = null;
  }
}

double dbToNormalized(double db) =>
    ((db.clamp(-80.0, 0.0) + 80) / 80).clamp(0, 1);
double normalizedToDb(double normalized) =>
    math.max(-80, math.min(0, normalized * 80 - 80));
