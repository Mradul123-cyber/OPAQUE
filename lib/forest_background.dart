import 'package:flutter/material.dart';

class ForestBackground extends StatelessWidget {
  const ForestBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/forest_background.png"),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}