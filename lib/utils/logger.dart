// Global logger instance used by all services for debug/info/error output.
//
// Messages are printed to the Android logcat via the `logger` package.
// Use `adb logcat | findstr "bottle"` (or similar) to filter at runtime.
import 'package:logger/logger.dart';

final appLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 1,
    errorMethodCount: 5,
    lineLength: 80,
    colors: false,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);
