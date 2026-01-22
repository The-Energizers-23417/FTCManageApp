import 'dart:math';

import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// Defines the scope of matches to consider for predictions.
enum OtherDashboardMode { allMatches, lastEventOnly }

/// Represents a single match score for data visualization.
class ScorePoint {
  final int matchId;
  final double score;

  const ScorePoint({
    required this.matchId,
    required this.score,
  });
}

/// Contains the result of performance prediction algorithms.
class PredictionResult {
  final double predictedScore;
  final double low;
  final double high;
  final double trendPerMatch;
  final double? predictedAuto;
  final double? predictedTeleop;

  const PredictionResult({
    required this.predictedScore,
    required this.low,
    required this.high,
    required this.trendPerMatch,
    required this.predictedAuto,
    required this.predictedTeleop,
  });
}

/// Stores aggregated statistics for a team at a specific event.
class EventStats {
  final int wins;
  final int losses;
  final int ties;
  final double avgScore;
  final int maxScore;
  final DateTime? firstMatchTime;

  const EventStats({
    required this.wins,
    required this.losses,
    required this.ties,
    required this.avgScore,
    required this.maxScore,
    required this.firstMatchTime,
  });
}

/// Provides a team-centric view of a match, including breakdowns and RP.
class MatchTeamView {
  final bool hasBeenPlayed;
  final bool teamIsRed;
  final int? teamScore;
  final int? oppScore;

  // Point breakdowns
  final int autoPoints;
  final int autoArtifactPoints;
  final int autoPatternPoints;
  final int dcPoints;
  final int dcBasePoints;
  final int dcArtifactPoints;
  final int dcPatternPoints;
  final int dcDepotPoints;
  final int penaltyCommitted;
  final int penaltyByOpp;

  // Ranking Point status
  final bool movementRp;
  final bool goalRp;
  final bool patternRp;
  final int rpTotal;

  const MatchTeamView({
    required this.hasBeenPlayed,
    required this.teamIsRed,
    required this.teamScore,
    required this.oppScore,
    required this.autoPoints,
    required this.autoArtifactPoints,
    required this.autoPatternPoints,
    required this.dcPoints,
    required this.dcBasePoints,
    required this.dcArtifactPoints,
    required this.dcPatternPoints,
    required this.dcDepotPoints,
    required this.penaltyCommitted,
    required this.penaltyByOpp,
    required this.movementRp,
    required this.goalRp,
    required this.patternRp,
    required this.rpTotal,
  });
}

/// Container for all computed data required by the 'Other Team' prediction dashboard.
class OtherDashboardComputed {
  final List<TeamMatchSummary> filteredMatches;
  final PredictionResult prediction;
  final List<ScorePoint> series;
  final Map<String, EventStats> eventStatsByCode;

  const OtherDashboardComputed({
    required this.filteredMatches,
    required this.prediction,
    required this.series,
    required this.eventStatsByCode,
  });
}

/// Calculator for performance analytics and predictions of other teams.
class OtherScoreCalculator {
  /// Computes metrics and predictions based on a team's match history.
  static OtherDashboardComputed compute({
    required int teamNumber,
    required List<TeamMatchSummary> matches,
    required OtherDashboardMode mode,
  }) {
    final played = matches.where((m) => m.hasBeenPlayed == true).toList();

    // Determine the most recent event.
    String? lastEventCode;
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final m in played) {
      final t = m.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (t.isAfter(latest)) {
        latest = t;
        lastEventCode = m.eventCode;
      }
    }

    List<TeamMatchSummary> filtered = List<TeamMatchSummary>.from(matches);

    // Apply filtering based on dashboard mode.
    if (mode == OtherDashboardMode.lastEventOnly && lastEventCode != null) {
      filtered = filtered.where((m) => m.eventCode == lastEventCode).toList();
    }

    final eventStats = _buildEventStats(teamNumber: teamNumber, matches: filtered);
    final series = _buildSeries(teamNumber: teamNumber, matches: filtered);

    final prediction = _predictFromSeries(
      series: series,
      matches: filtered.where((m) => m.hasBeenPlayed == true).toList(),
      teamNumber: teamNumber,
    );

    return OtherDashboardComputed(
      filteredMatches: filtered,
      prediction: prediction,
      series: series,
      eventStatsByCode: eventStats,
    );
  }

  /// Extracts specific data for a team from a raw match summary.
  static MatchTeamView viewForMatch({
    required int teamNumber,
    required TeamMatchSummary m,
  }) {
    final bool teamIsRed = m.redTeams.contains(teamNumber);
    final teamBd = teamIsRed ? m.red : m.blue;
    final teamScore = teamIsRed ? m.redScore : m.blueScore;
    final oppScore = teamIsRed ? m.blueScore : m.redScore;

    final rpTotal = (teamBd.movementRp ? 1 : 0) + (teamBd.goalRp ? 1 : 0) + (teamBd.patternRp ? 1 : 0);

    return MatchTeamView(
      hasBeenPlayed: m.hasBeenPlayed,
      teamIsRed: teamIsRed,
      teamScore: teamScore,
      oppScore: oppScore,
      autoPoints: teamBd.autoPoints,
      autoArtifactPoints: teamBd.autoArtifactPoints,
      autoPatternPoints: teamBd.autoPatternPoints,
      dcPoints: teamBd.dcPoints,
      dcBasePoints: teamBd.dcBasePoints,
      dcArtifactPoints: teamBd.dcArtifactPoints,
      dcPatternPoints: teamBd.dcPatternPoints,
      dcDepotPoints: teamBd.dcDepotPoints,
      penaltyCommitted: teamBd.penaltyCommitted,
      penaltyByOpp: teamBd.penaltyByOpp,
      movementRp: teamBd.movementRp,
      goalRp: teamBd.goalRp,
      patternRp: teamBd.patternRp,
      rpTotal: rpTotal,
    );
  }

  /// Aggregates match data into event-level statistics.
  static Map<String, EventStats> _buildEventStats({
    required int teamNumber,
    required List<TeamMatchSummary> matches,
  }) {
    final byEvent = <String, List<TeamMatchSummary>>{};
    for (final m in matches.where((x) => x.hasBeenPlayed == true)) {
      byEvent.putIfAbsent(m.eventCode, () => []).add(m);
    }

    final out = <String, EventStats>{};

    for (final entry in byEvent.entries) {
      final code = entry.key;
      final list = entry.value;

      int w = 0, l = 0, t = 0;
      int maxScore = 0;
      double sum = 0;
      int n = 0;

      DateTime? firstTime;
      for (final m in list) {
        final v = viewForMatch(teamNumber: teamNumber, m: m);
        if (!v.hasBeenPlayed || v.teamScore == null || v.oppScore == null) continue;

        if (firstTime == null) {
          firstTime = m.scheduledTime;
        } else {
          final cur = m.scheduledTime;
          if (cur != null && cur.isAfter(firstTime)) firstTime = cur;
        }

        final ts = v.teamScore!;
        maxScore = max(maxScore, ts);
        sum += ts;
        n++;

        if (ts > v.oppScore!) {
          w++;
        } else if (ts < v.oppScore!) {
          l++;
        } else {
          t++;
        }
      }

      final avg = n == 0 ? 0.0 : (sum / n);

      out[code] = EventStats(
        wins: w,
        losses: l,
        ties: t,
        avgScore: avg,
        maxScore: maxScore,
        firstMatchTime: firstTime,
      );
    }

    return out;
  }

  /// Builds a chronological list of score data points.
  static List<ScorePoint> _buildSeries({
    required int teamNumber,
    required List<TeamMatchSummary> matches,
  }) {
    final played = matches.where((m) => m.hasBeenPlayed == true).toList();

    played.sort((a, b) {
      final ta = a.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final c = ta.compareTo(tb);
      if (c != 0) return c;
      return a.matchId.compareTo(b.matchId);
    });

    final out = <ScorePoint>[];
    for (final m in played) {
      final v = viewForMatch(teamNumber: teamNumber, m: m);
      if (v.teamScore == null) continue;
      out.add(ScorePoint(matchId: m.matchId, score: v.teamScore!.toDouble()));
    }
    return out;
  }

  /// Generates a prediction for the next match using linear regression on recent data.
  static PredictionResult _predictFromSeries({
    required List<ScorePoint> series,
    required List<TeamMatchSummary> matches,
    required int teamNumber,
  }) {
    if (series.isEmpty) {
      return const PredictionResult(
        predictedScore: 0,
        low: 0,
        high: 0,
        trendPerMatch: 0,
        predictedAuto: null,
        predictedTeleop: null,
      );
    }

    // Analyze the last 12 matches for trend detection.
    final nMax = min(12, series.length);
    final tail = series.sublist(series.length - nMax);

    final n = tail.length;
    double sumX = 0, sumY = 0, sumXX = 0, sumXY = 0;
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = tail[i].score;
      sumX += x;
      sumY += y;
      sumXX += x * x;
      sumXY += x * y;
    }

    final denom = (n * sumXX - sumX * sumX);
    final slope = denom.abs() < 1e-9 ? 0.0 : (n * sumXY - sumX * sumY) / denom;
    final intercept = (sumY - slope * sumX) / n;

    final nextX = n.toDouble();
    final rawPred = intercept + slope * nextX;

    // Calculate variance for confidence interval bounds.
    final mean = sumY / n;
    double variance = 0;
    for (int i = 0; i < n; i++) {
      final d = tail[i].score - mean;
      variance += d * d;
    }
    variance = variance / max(1, n - 1);
    final std = sqrt(variance);

    final pred = max(0.0, rawPred);
    final low = max(0.0, pred - (std * 1.5));
    final high = pred + (std * 1.5);

    double autoSum = 0;
    double teleSum = 0;
    int cnt = 0;

    final byId = <int, TeamMatchSummary>{};
    for (final m in matches) {
      if (m.hasBeenPlayed) byId[m.matchId] = m;
    }

    for (final p in tail) {
      final m = byId[p.matchId];
      if (m == null) continue;
      final v = viewForMatch(teamNumber: teamNumber, m: m);
      autoSum += v.autoPoints.toDouble();
      teleSum += v.dcPoints.toDouble();
      cnt++;
    }

    final predictedAuto = cnt == 0 ? null : (autoSum / cnt);
    final predictedTele = cnt == 0 ? null : (teleSum / cnt);

    return PredictionResult(
      predictedScore: pred,
      low: low,
      high: high,
      trendPerMatch: slope,
      predictedAuto: predictedAuto,
      predictedTeleop: predictedTele,
    );
  }
}
