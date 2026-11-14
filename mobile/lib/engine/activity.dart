import 'package:health/health.dart';

/// Today's measured activity from Android Health Connect, mapped to the same PAL
/// (physical-activity level) the target engine already uses — so a measured day
/// can replace the static activity level the user picked at sign-up.
class MeasuredActivity {
  final int steps;
  final double activeKcal; // active energy burned today (0 if unavailable)
  const MeasuredActivity(this.steps, this.activeKcal);

  /// Steps → PAL band (common step→activity cut-points).
  double get pal {
    if (steps >= 12500) return 1.9;
    if (steps >= 10000) return 1.725;
    if (steps >= 7500) return 1.55;
    if (steps >= 5000) return 1.375;
    return 1.2;
  }

  String get label {
    if (steps >= 12500) return 'Very active';
    if (steps >= 10000) return 'Active';
    if (steps >= 7500) return 'Moderate';
    if (steps >= 5000) return 'Light';
    return 'Sedentary';
  }
}

/// Reads steps + active energy from Health Connect. Every path degrades to null
/// (Health Connect unavailable, permission denied, or no data for today), so the
/// caller just hides the card — this never throws and never blocks the app.
class HealthConnect {
  static final Health _h = Health();
  static const _types = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];
  static const _perms = [HealthDataAccess.READ, HealthDataAccess.READ];

  /// Whether Health Connect is installed/available on this device.
  static Future<bool> available() async {
    try {
      await _h.configure();
      return (await _h.isHealthConnectAvailable());
    } catch (_) {
      return false;
    }
  }

  /// Request read access (prompts only if not already granted), then read today.
  static Future<MeasuredActivity?> today() async {
    try {
      await _h.configure();
      final has = await _h.hasPermissions(_types, permissions: _perms) ?? false;
      if (!has && !await _h.requestAuthorization(_types, permissions: _perms)) {
        return null;
      }
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await _h.getTotalStepsInInterval(midnight, now) ?? 0;
      double active = 0;
      try {
        // getHealthDataFromTypes already de-duplicates the points.
        final pts = await _h.getHealthDataFromTypes(
          types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
          startTime: midnight,
          endTime: now,
        );
        for (final p in pts) {
          final v = p.value;
          if (v is NumericHealthValue) active += v.numericValue.toDouble();
        }
      } catch (_) {/* active energy optional */}
      if (steps == 0 && active == 0) return null;
      return MeasuredActivity(steps, active);
    } catch (_) {
      return null;
    }
  }
}
