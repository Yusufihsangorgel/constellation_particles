import 'package:flutter/material.dart';
import 'package:constellation_particles/constellation_particles.dart';

void main() => runApp(const _ExampleApp());

class _ExampleApp extends StatelessWidget {
  const _ExampleApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0E14),
        body: Stack(
          children: [
            const Positioned.fill(
              child: ConstellationParticles(
                particleCount: 140,
                color: Color(0xFF64FFDA),
                speed: 1.1,
              ),
            ),
            Center(
              child: Text(
                'move your cursor',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white24, letterSpacing: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
