import 'dart:math';

import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-connection/api_global.dart';

/// Represents the average performance metrics of a team across different match phases.
class PhaseStrength {
  final double autoAvg;
  final double teleopAvg;
  final double endgameAvg;

  PhaseStrength({
    required this.autoAvg,
    required this.teleopAvg,
    required this.endgameAvg,
  });

  /// The combined average score across all phases.
  double get total => autoAvg + teleopAvg + endgameAvg;

  /// Identifies the phase where the team is statistically most productive.
  String get strongestPhase {
    final a = autoAvg;
    final t = teleopAvg;
    final e = endgameAvg;
    if (a >= t && a >= e) return 'Autonomous';
    if (t >= a && t >= e) return 'TeleOp';
    return 'Endgame';
  }
}

/// Defines a performance tier based on average scoring potential.
class Tier {
  final double minTotal;
  final String name;

  const Tier(this.minTotal, this.name);
}

/// Predefined performance categories for ranking teams.
const List<Tier> kTiersDesc = [
  Tier(120, 'Top level'),
  Tier(100, 'Elite'),
  Tier(80, 'Strong'),
  Tier(60, 'Solid'),
  Tier(40, 'Developing'),
  Tier(0, 'Rookie'),
];

/// Maps a total score average to its corresponding performance tier.
Tier tierForTotal(double total) {
  for (final t in kTiersDesc) {
    if (total >= t.minTotal) return t;
  }
  return kTiersDesc.last;
}

/// Identifies the next achievable tier for a team.
Tier? nextTier(double total) {
  for (var i = 0; i < kTiersDesc.length; i++) {
    final t = kTiersDesc[i];
    if (total >= t.minTotal) {
      final aboveIndex = i - 1;
      if (aboveIndex >= 0) return kTiersDesc[aboveIndex];
      return null; // Already at the highest tier.
    }
  }
  return kTiersDesc.first;
}

/// Calculates the score difference required to reach the next tier.
double pointsToNextTier(double total) {
  final nt = nextTier(total);
  if (nt == null) return 0.0;
  return max(0.0, nt.minTotal - total);
}

/// Converts a total score into a normalized progress value (0 to 1) for UI bars.
double tierProgress01(double total) => (total / 120.0).clamp(0.0, 1.0);

/// Encapsulates statistical data for match score predictions.
class PredictionStats {
  final int playedCount;
  final double meanTotal;
  final double stdTotal;
  final double low;
  final double high;

  PredictionStats({
    required this.playedCount,
    required this.meanTotal,
    required this.stdTotal,
    required this.low,
    required this.high,
  });
}

/// Safely attempts to convert a dynamic value to a double.
double? _tryNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Searches for a numeric value in a map using multiple possible keys (for API compatibility).
double? _findNumber(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    if (!m.containsKey(k)) continue;
    final v = _tryNum(m[k]);
    if (v != null) return v;
  }
  return null;
}

/// Fetches pre-calculated phase strengths from the FTCScout quick-stats endpoint.
Future<PhaseStrength?> fetchPhaseStrengthFromQuickStats({
  required int teamNumber,
  required int season,
  String? region,
}) async {
  final raw = await ftcScoutApi.getTeamQuickStats(
    teamNumber: teamNumber,
    season: season,
    region: region,
  );

  Map<String, dynamic>? m;

  if (raw is Map) {
    m = Map<String, dynamic>.from(raw);
  } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
    m = Map<String, dynamic>.from(raw.first as Map);
  }

  if (m == null) return null;

  // Handle various nesting levels used by the API.
  final wrapped = (m['quickStats'] is Map)
      ? Map<String, dynamic>.from(m['quickStats'] as Map)
      : (m['stats'] is Map)
      ? Map<String, dynamic>.from(m['stats'] as Map)
      : null;

  final root = wrapped ?? m;

  final auto = _findNumber(root, ['auto', 'autoAvg', 'auto_points_avg', 'autoNP']);
  final tele = _findNumber(root, ['teleop', 'teleopAvg', 'teleop_points_avg', 'dc', 'dcAvg']);
  final end = _findNumber(root, ['endgame', 'endgameAvg', 'endgame_points_avg', 'eg', 'egAvg']);

  if (auto == null || tele == null || end == null) return null;

  return PhaseStrength(autoAvg: auto, teleopAvg: tele, endgameAvg: end);
}

/// Internal helper to extract the relevant alliance data for a team from a match.
AllianceBreakdown _breakdownForTeam(TeamMatchSummary m, int teamNumber) {
  if (m.redTeams.contains(teamNumber) || (m.alliance ?? '').toLowerCase() == 'red') {
    return m.red;
  }
  return m.blue;
}

/// Computes average phase strengths manually from a provided list of match summaries.
PhaseStrength computePhaseStrengthFromMatches(
    List<TeamMatchSummary> matches,
    int teamNumber,
    ) {
  final played = matches.where((m) => m.hasBeenPlayed == true).toList();
  if (played.isEmpty) {
    return PhaseStrength(autoAvg: 0.0, teleopAvg: 0.0, endgameAvg: 0.0);
  }

  double autoSum = 0.0, teleopSum = 0.0, endgameSum = 0.0;

  for (final m in played) {
    final b = _breakdownForTeam(m, teamNumber);
    autoSum += b.autoPoints.toDouble();
    teleopSum += b.dcPoints.toDouble();
    endgameSum += b.dcBasePoints.toDouble();
  }

  final double n = played.length.toDouble();
  return PhaseStrength(
    autoAvg: autoSum / n,
    teleopAvg: teleopSum / n,
    endgameAvg: endgameSum / n,
  );
}

/// Computes a weighted performance prediction, giving more significance to recent matches.
PredictionStats computePredictionStatsWeighted(
    List<TeamMatchSummary> matches,
    int teamNumber, {
      int maxMatches = 12,
    }) {
  final played = matches.where((m) => m.hasBeenPlayed == true).toList();
  if (played.isEmpty) {
    return PredictionStats(playedCount: 0, meanTotal: 0.0, stdTotal: 0.0, low: 0.0, high: 0.0);
  }

  // Sort matches chronologically (newest first).
  played.sort((a, b) {
    final ta = a.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb = b.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  });

  final used = played.take(maxMatches).toList();

  // Exponential decay function for weights.
  double weightAt(int i) => pow(0.92, i).toDouble();

  final List<double> values = [];
  final List<double> weights = [];

  for (var i = 0; i < used.length; i++) {
    final m = used[i];
    final b = _breakdownForTeam(m, teamNumber);

    double? actualTotal;
    final bool inRed = m.redTeams.contains(teamNumber) || (m.alliance ?? '').toLowerCase() == 'red';
    actualTotal = (inRed ? m.redScore : m.blueScore)?.toDouble();

    // Fallback if full alliance scores are missing.
    final fallbackTotal = b.autoPoints.toDouble() + b.dcPoints.toDouble() + b.dcBasePoints.toDouble();

    values.add(actualTotal ?? fallbackTotal);
    weights.add(weightAt(i));
  }

  final double wSum = weights.fold<double>(0.0, (a, b) => a + b);
  final double mean = wSum == 0.0
      ? 0.0
      : (List.generate(values.length, (i) => values[i] * weights[i]).fold<double>(0.0, (a, b) => a + b) / wSum);

  // Calculate weighted variance.
  double varSum = 0.0;
  for (var i = 0; i < values.length; i++) {
    final double d = values[i] - mean;
    varSum += weights[i] * d * d;
  }

  final double variance = wSum == 0.0 ? 0.0 : (varSum / wSum);
  final double std = sqrt(max(0.0, variance));

  // Determine conservative prediction bounds.
  const double k = 0.85;
  final double low = max(0.0, mean - k * std);
  final double high = mean + k * std;

  return PredictionStats(
    playedCount: values.length,
    meanTotal: mean,
    stdTotal: std,
    low: low,
    high: high,
  );
}
