import 'dart:math';

abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

abstract interface class RandomSource {
  int nextInt(int max);
}

class DartRandomSource implements RandomSource {
  final Random _random = Random();
  @override
  int nextInt(int max) => _random.nextInt(max);
}
