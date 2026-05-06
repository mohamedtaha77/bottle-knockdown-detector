// App entry point.
//
// Wraps the widget tree in Riverpod's [ProviderScope] so that all
// screens and services can access shared state via providers.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: BottleKnockdownApp()));
}

/// Root widget — configures Material 3 theme and sets [HomeScreen] as the
/// landing page.
class BottleKnockdownApp extends StatelessWidget {
  const BottleKnockdownApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bottle Knockdown Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
