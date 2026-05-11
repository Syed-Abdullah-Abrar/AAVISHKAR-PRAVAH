import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations (portrait only for field use)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Enable Flutter error reporting in debug mode
  FlutterError.onError = (details) {
    // Log to crash reporting service in production
    // ignore: avoid_print
    print('Flutter Error: ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };

  // Run app with Riverpod for state management
  runApp(
    const ProviderScope(
      child: O2App(),
    ),
  );
}
