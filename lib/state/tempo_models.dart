enum TempoRatio { threeToOne, twoToOne }

class TempoConfig {
  final TempoRatio ratio;
  final int backswingUnits;
  final int downswingUnits;
  final Duration totalCycle;

  const TempoConfig({
    required this.ratio,
    required this.backswingUnits,
    required this.downswingUnits,
    required this.totalCycle,
  });

  int get totalUnits => backswingUnits + downswingUnits;
}
