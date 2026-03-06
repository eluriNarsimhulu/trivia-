// project_folder/lib/core/utils/logger.dart

import 'package:flutter/foundation.dart';

/// Centralized logging utility.
///
/// Logs are stripped in release builds because kDebugMode
/// is a compile-time constant.

void gameLog(String tag, String message) {
  if (kDebugMode) {
    debugPrint('[$tag] $message');
  }
}

void gameWarn(String tag, String message) {
  if (kDebugMode) {
    debugPrint('[$tag] ⚠️  $message');
  }
}

void gameError(String tag, String message) {
  if (kDebugMode) {
    debugPrint('[$tag] ❌ $message');
  }
}