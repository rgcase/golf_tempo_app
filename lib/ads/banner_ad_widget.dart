import 'package:flutter/material.dart';

class BannerAdPlaceholder extends StatelessWidget {
  const BannerAdPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 56,
        width: double.infinity,
        alignment: Alignment.center,
        color: Colors.black12,
        child: const Text('Ad banner'),
      ),
    );
  }
}
