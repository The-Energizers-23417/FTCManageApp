import 'dart:math';

/// Model representing a single battery unit.
class BatteryItem {
  final String label; // Unique identifier for the battery (e.g., "B1").
  final double? voltage; // Current voltage reading, if available.
  final int priority; // Charging urgency level (higher means more urgent).

  const BatteryItem({
    required this.label,
    this.voltage,
    this.priority = 0,
  });

  /// Creates a copy of the battery item with updated fields.
  BatteryItem copyWith({
    String? label,
    double? voltage,
    int? priority,
  }) =>
      BatteryItem(
        label: label ?? this.label,
        voltage: voltage ?? this.voltage,
        priority: priority ?? this.priority,
      );
}

/// Represents an optimized plan for charging batteries across available chargers.
class BatteryBatchPlan {
  final int chargerCount; // Number of available chargers.
  final List<List<BatteryItem>> batches; // Batteries grouped by charging cycles.

  const BatteryBatchPlan({
    required this.chargerCount,
    required this.batches,
  });

  /// Total number of charging batches required.
  int get batchCount => batches.length;

  /// Total number of batteries included in the charging plan.
  int get plannedBatteries =>
      batches.fold<int>(0, (sum, b) => sum + b.length);
}

/// Utility class for battery-related data processing and logic.
class BatteryCalc {
  /// Parses battery configuration and status from the Firestore 'setupData' map.
  static List<BatteryItem> batteriesFromSetupData(Map<String, dynamic> setupData) {
    final List<dynamic> rawBats = (setupData['batteries'] as List<dynamic>?) ?? [];
    final Map<String, dynamic> voltMap =
        (setupData['batteryVoltages'] as Map<String, dynamic>?) ?? {};
    final Map<String, dynamic> priorityMap =
        (setupData['batteryPriorities'] as Map<String, dynamic>?) ?? {};

    final List<BatteryItem> out = [];
    for (final b in rawBats) {
      if (b is Map) {
        final label = (b['label'] ?? '').toString().trim();
        if (label.isEmpty) continue;

        final rawVolt = voltMap[label];
        final voltage = (rawVolt is num) ? rawVolt.toDouble() : null;
        
        final rawPrio = priorityMap[label];
        int priority = 0;
        if (rawPrio is int) {
          priority = rawPrio;
        } else if (rawPrio is bool) {
          // Support legacy boolean priority markers.
          priority = rawPrio ? 1 : 0;
        }

        out.add(BatteryItem(
          label: label,
          voltage: voltage,
          priority: priority,
        ));
      }
    }

    // Sort batteries alphabetically for a consistent user interface.
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  /// Extracts the charger count from the setup data.
  static int chargerCountFromSetupData(Map<String, dynamic> setupData) {
    final v = setupData['chargerCount'];
    if (v is int && v > 0) return v;
    if (v is num && v.toInt() > 0) return v.toInt();
    return 1; // Default to at least one charger.
  }

  /// Generates a charging schedule based on voltage thresholds and priority levels.
  static BatteryBatchPlan buildChargePlan({
    required List<BatteryItem> batteries,
    required int chargerCount,
    required double emptyVoltageThreshold,
  }) {
    final cc = chargerCount <= 0 ? 1 : chargerCount;

    // Only include batteries that fall below the 'empty' threshold.
    final toCharge = batteries
        .where((b) => (b.voltage ?? 0) < emptyVoltageThreshold)
        .toList();

    // Sorting logic: prioritize higher urgency, then sort by lowest voltage.
    toCharge.sort((a, b) {
      if (a.priority != b.priority) {
        return b.priority.compareTo(a.priority);
      }
      return (a.voltage ?? 15.0).compareTo(b.voltage ?? 15.0);
    });

    // Chunk the filtered list into batches based on charger availability.
    final List<List<BatteryItem>> batches = [];
    for (var i = 0; i < toCharge.length; i += cc) {
      final end = (i + cc < toCharge.length) ? i + cc : toCharge.length;
      batches.add(toCharge.sublist(i, end));
    }

    return BatteryBatchPlan(chargerCount: cc, batches: batches);
  }

  /// Converts a list of batteries into a map of voltages for Firestore storage.
  static Map<String, dynamic> buildVoltageMap(List<BatteryItem> batteries) {
    final Map<String, dynamic> map = {};
    for (final b in batteries) {
      if (b.voltage != null) {
        map[b.label] = b.voltage;
      }
    }
    return map;
  }

  /// Converts a list of batteries into a map of priorities for Firestore storage.
  static Map<String, dynamic> buildPriorityMap(List<BatteryItem> batteries) {
    final Map<String, dynamic> map = {};
    for (final b in batteries) {
      if (b.priority != 0) {
        map[b.label] = b.priority;
      }
    }
    return map;
  }
}
