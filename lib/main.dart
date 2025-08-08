import 'package:flutter/material.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const GolfTempoApp());
}

class GolfTempoApp extends StatelessWidget {
  const GolfTempoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf Tempo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
