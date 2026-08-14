class MicrophoneCalibration {
  const MicrophoneCalibration._();
  static double threshold({required List<double> samples, required double minimum, required double maximum, double marginDb = 10}) {
    if (samples.isEmpty) return minimum;
    final sorted = [...samples]..sort();
    final index = ((sorted.length - 1) * .95).ceil();
    return (sorted[index] + marginDb).clamp(minimum, maximum);
  }
}
