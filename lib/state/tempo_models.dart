enum TempoRatio { threeToOne, twoToOne }

class TempoConfig {
  final TempoRatio ratio;
  final int backswingUnits;
  final int downswingUnits;

  const TempoConfig({
    required this.ratio,
    required this.backswingUnits,
    required this.downswingUnits,
  });

  int get totalUnits => backswingUnits + downswingUnits;
}
