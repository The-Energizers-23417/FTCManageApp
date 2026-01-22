import 'dart:math';

import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// Defines the scope of matches to consider for the own team's dashboard calculations.
enum OwnDashboardMode { allMatches, lastEventOnly }

/// Data point representing a score at a specific point in time or match index.
class ScorePoint {
  final int index;
  final double score;
  final DateTime? time;
  final String eventCode;
  final String matchId;

  ScorePoint({
    required this.index,
    required this.score,
    required this.time,
    required this.eventCode,
    required this.matchId,
  });
}

/// Provides a team-specific view of a match result and point breakdowns.
class MatchTeamView {
  final bool hasBeenPlayed;
  final bool isRed;
  final int? teamScore;
  final int? oppScore;

  final int autoPoints;
  final int dcPoints;
  final int penaltyCommitted;
  final int penaltyByOpp;

  // Detailed point breakdown.
  final int autoArtifactPoints;
  final int autoPatternPoints;

  final int dcBasePoints;
  final int dcArtifactPoints;
  final int dcPatternPoints;
  final int dcDepotPoints;

  // Ranking Point flags.
  final bool movementRp;
  final bool goalRp;
  final bool patternRp;

  final int rpTotal;

  MatchTeamView({
    required this.hasBeenPlayed,
    required this.isRed,
    required this.teamScore,
    required this.oppScore,
    required this.autoPoints,
    required this.dcPoints,
    required this.penaltyCommitted,
    required this.penaltyByOpp,

    required this.autoArtifactPoints,
    required this.autoPatternPoints,
    required this.dcBasePoints,
    required this.dcArtifactPoints,
    required this.dcPatternPoints,
    required this.dcDepotPoints,

    required this.movementRp,
    required this.goalRp,
    required this.patternRp,
    required this.rpTotal,
  });
}

/// Consolidated statistics for a particular competition event.
class EventStats {
  final String eventCode;
  final int played;
  final int wins;
  final int losses;
  final int ties;
  final double avgScore;
  final int maxScore;

  EventStats({
    required this.eventCode,
    required this.played,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.avgScore,
    required this.maxScore,
  });
}

/// Contains the output of match score prediction algorithms.
class PredictionResult {
  final bool hasEnoughData;
  final double predictedScore;
  final double? predictedAuto;
  final double? predictedTeleop;
  final double trendPerMatch;
  final double r2;
  final double ema;
  final double low;
  final double high;

  PredictionResult({
    required this.hasEnoughData,
    required this.predictedScore,
    required this.predictedAuto,
    required this.predictedTeleop,
    required this.trendPerMatch,
    required this.r2,
    required this.ema,
    required this.low,
    required this.high,
  });
}

/// The set of all computed analytics for the 'Own Team' dashboard.
class OwnDashboardComputed {
  final List<TeamMatchSummary> filteredMatches;
  final List<ScorePoint> series;
  final PredictionResult prediction;
  final Map<String, EventStats> eventStatsByCode;
  final String? lastEventCode;

  OwnDashboardComputed({
    required this.filteredMatches,
    required this.series,
    required this.prediction,
    required this.eventStatsByCode,
    required this.lastEventCode,
  });
}

/// Core computational engine for the team's own performance metrics.
class OwnScoreCalculator {
  /// Entry point for computing all dashboard analytics from raw match history.
  static OwnDashboardComputed compute({
    required int teamNumber,
    required List<TeamMatchSummary> matches,
    required OwnDashboardMode mode,
  }) {
    // 1. Identify the most recent event.
    String? lastEventCode;
    DateTime latest = DateTime(1970);
    for (final m in matches) {
      final t = m.scheduledTime;
      if (t != null && t.isAfter(latest)) {
        latest = t;
        lastEventCode = m.eventCode;
      }
    }

    // 2. Filter matches based on the selected display mode.
    List<TeamMatchSummary> filtered = matches;
    if (mode == OwnDashboardMode.lastEventOnly && lastEventCode != null) {
      filtered = matches.where((m) => m.eventCode == lastEventCode).toList();
    }

    // 3. Build per-event summaries.
    final eventStats = _buildEventStats(teamNumber: teamNumber, matches: filtered);

    // 4. Prepare data series for the chart.
    final playedSorted = filtered
        .where((m) => m.hasBeenPlayed)
        .toList()
      ..sort((a, b) => (a.scheduledTime ?? DateTime(1970))
          .compareTo(b.scheduledTime ?? DateTime(1970)));

    final series = <ScorePoint>[];
    for (int i = 0; i < playedSorted.length; i++) {
      final m = playedSorted[i];
      final v = viewForMatch(teamNumber: teamNumber, m: m);
      final score = v.teamScore ?? 0;
      series.add(ScorePoint(
        index: i,
        score: score.toDouble(),
        time: m.scheduledTime,
        eventCode: m.eventCode,
        matchId: m.matchId.toString(),
      ));
    }

    // 5. Calculate predictions using EMA and Linear Regression.
    final prediction = _predictFromSeries(
      teamNumber: teamNumber,
      matches: playedSorted,
      series: series,
    );

    return OwnDashboardComputed(
      filteredMatches: filtered,
      series: series,
      prediction: prediction,
      eventStatsByCode: eventStats,
      lastEventCode: lastEventCode,
    );
  }

  /// Transforms a raw match summary into a team-centric result object.
  static MatchTeamView viewForMatch({
    required int teamNumber,
    required TeamMatchSummary m,
  }) {
    final isRed = _isTeamRed(teamNumber, m);
    final mine = isRed ? m.red : m.blue;
    final opp = isRed ? m.blue : m.red;

    final teamScore = mine.totalPoints;
    final oppScore = opp.totalPoints;

    final res = _resultForMatch(teamScore, oppScore, m.hasBeenPlayed);

    int matchRp = 0;
    if (m.hasBeenPlayed) {
      if (res == MatchResult.win) matchRp = 2;
      if (res == MatchResult.tie) matchRp = 1;
    }

    final bonusRp =
        (mine.movementRp ? 1 : 0) + (mine.goalRp ? 1 : 0) + (mine.patternRp ? 1 : 0);

    return MatchTeamView(
      hasBeenPlayed: m.hasBeenPlayed,
      isRed: isRed,
      teamScore: teamScore,
      oppScore: oppScore,
      autoPoints: mine.autoPoints,
      dcPoints: mine.dcPoints,
      penaltyCommitted: mine.penaltyCommitted,
      penaltyByOpp: mine.penaltyByOpp,

      autoArtifactPoints: mine.autoArtifactPoints,
      autoPatternPoints: mine.autoPatternPoints,
      dcBasePoints: mine.dcBasePoints,
      dcArtifactPoints: mine.dcArtifactPoints,
      dcPatternPoints: mine.dcPatternPoints,
      dcDepotPoints: mine.dcDepotPoints,

      movementRp: mine.movementRp,
      goalRp: mine.goalRp,
      patternRp: mine.patternRp,
      rpTotal: matchRp + bonusRp,
    );
  }

  /// Checks if the specified team was on the Red alliance.
  static bool _isTeamRed(int teamNumber, TeamMatchSummary m) {
    if (m.redTeams.contains(teamNumber)) return true;
    if (m.blueTeams.contains(teamNumber)) return false;
    return m.alliance == 'Red';
  }

  /// Resolves the qualitative outcome of a match.
  static MatchResult _resultForMatch(int? ts, int? os, bool played) {
    if (!played || ts == null || os == null) return MatchResult.notPlayed;
    if (ts > os) return MatchResult.win;
    if (ts < os) return MatchResult.loss;
    return MatchResult.tie;
  }

  /// Groups and aggregates statistics across different competition events.
  static Map<String, EventStats> _buildEventStats({
    required int teamNumber,
    required List<TeamMatchSummary> matches,
  }) {
    final grouped = <String, List<TeamMatchSummary>>{};
    for (final m in matches) {
      grouped.putIfAbsent(m.eventCode, () => []).add(m);
    }

    final out = <String, EventStats>{};

    grouped.forEach((code, list) {
      int wins = 0, losses = 0, ties = 0, played = 0;
      final scores = <int>[];

      for (final m in list) {
        final v = viewForMatch(teamNumber: teamNumber, m: m);
        if (!v.hasBeenPlayed || v.teamScore == null || v.oppScore == null) continue;

        played++;
        scores.add(v.teamScore!);

        final res = _resultForMatch(v.teamScore, v.oppScore, true);
        if (res == MatchResult.win) wins++;
        if (res == MatchResult.loss) losses++;
        if (res == MatchResult.tie) ties++;
      }

      final avg = scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;
      final maxScore = scores.isEmpty ? 0 : scores.reduce(max);

      out[code] = EventStats(
        eventCode: code,
        played: played,
        wins: wins,
        losses: losses,
        ties: ties,
        avgScore: avg,
        maxScore: maxScore,
      );
    });

    return out;
  }

  /// Predicts future performance by blending Exponential Moving Average (EMA) and linear trend analysis.
  static PredictionResult _predictFromSeries({
    required int teamNumber,
    required List<TeamMatchSummary> matches,
    required List<ScorePoint> series,
  }) {
    // Statistically significant predictions require at least 3 historical matches.
    if (series.length < 3) {
      final last = series.isEmpty ? 0.0 : series.last.score;
      return PredictionResult(
        hasEnoughData: false,
        predictedScore: last,
        predictedAuto: null,
        predictedTeleop: null,
        trendPerMatch: 0,
        r2: 0,
        ema: last,
        low: max(0.0, last - 10),
        high: last + 10,
      );
    }

    // 1. Calculate Exponential Moving Average (EMA) to favor recent consistency.
    const alpha = 0.35;
    double ema = series.first.score;
    for (int i = 1; i < series.length; i++) {
      ema = alpha * series[i].score + (1 - alpha) * ema;
    }

    // 2. Perform Linear Regression to identify growth or decline trends.
    final xs = series.map((p) => p.index.toDouble()).toList();
    final ys = series.map((p) => p.score).toList();

    final reg = _linearRegression(xs, ys);
    final slope = reg.slope;
    final intercept = reg.intercept;
    final r2 = reg.r2;

    final nextX = (series.length).toDouble();
    final regPred = intercept + slope * nextX;

    // Blend EMA and regression based on the confidence (R²) of the trend.
    final w = r2.clamp(0.0, 1.0);
    final pred = (w * regPred) + ((1 - w) * ema);

    // Phase-specific predictions using basic trend logic.
    final autos = <double>[];
    final teleops = <double>[];

    for (final m in matches) {
      final v = viewForMatch(teamNumber: teamNumber, m: m);
      if (!v.hasBeenPlayed) continue;
      autos.add(v.autoPoints.toDouble());
      teleops.add(v.dcPoints.toDouble());
    }

    double? predAuto;
    double? predTele;
    if (autos.length >= 3) predAuto = _predictScalar(autos);
    if (teleops.length >= 3) predTele = _predictScalar(teleops);

    // Calculate the error margin using the standard deviation of residuals.
    final residuals = <double>[];
    for (int i = 0; i < xs.length; i++) {
      final yhat = intercept + slope * xs[i];
      residuals.add(ys[i] - yhat);
    }

    final sd = _stddev(residuals);
    final low = max(0.0, pred - 1.2 * sd);
    final high = pred + 1.2 * sd;

    return PredictionResult(
      hasEnoughData: true,
      predictedScore: pred,
      predictedAuto: predAuto,
      predictedTeleop: predTele,
      trendPerMatch: slope,
      r2: r2,
      ema: ema,
      low: low,
      high: high,
    );
  }

  /// Predicts a single numeric value using local trend analysis.
  static double _predictScalar(List<double> ys) {
    const alpha = 0.35;
    double ema = ys.first;
    for (int i = 1; i < ys.length; i++) {
      ema = alpha * ys[i] + (1 - alpha) * ema;
    }

    final n = min(6, ys.length);
    final recent = ys.sublist(ys.length - n);
    final slope = (recent.last - recent.first) / max(1, n - 1);

    return ema + 0.6 * slope;
  }

  /// Standard implementation of simple linear regression.
  static _LinReg _linearRegression(List<double> x, List<double> y) {
    final n = x.length;
    final meanX = x.reduce((a, b) => a + b) / n;
    final meanY = y.reduce((a, b) => a + b) / n;

    double ssXX = 0, ssXY = 0, ssYY = 0;

    for (int i = 0; i < n; i++) {
      final dx = x[i] - meanX;
      final dy = y[i] - meanY;
      ssXX += dx * dx;
      ssXY += dx * dy;
      ssYY += dy * dy;
    }

    final slope = ssXX == 0 ? 0.0 : (ssXY / ssXX);
    final intercept = meanY - slope * meanX;

    double sse = 0;
    for (int i = 0; i < n; i++) {
      final yhat = intercept + slope * x[i];
      final err = y[i] - yhat;
      sse += err * err;
    }

    final r2 = ssYY == 0 ? 0.0 : (1.0 - (sse / ssYY));
    return _LinReg(slope: slope, intercept: intercept, r2: r2.isFinite ? r2 : 0.0);
  }

  /// Calculates the standard deviation of a sample.
  static double _stddev(List<double> xs) {
    if (xs.length < 2) return 0;
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    double v = 0;
    for (final x in xs) {
      final d = x - mean;
      v += d * d;
    }
    v /= (xs.length - 1);
    return sqrt(v);
  }
}

/// Helper container for linear regression outputs.
class _LinReg {
  final double slope;
  final double intercept;
  final double r2;
  _LinReg({required this.slope, required this.intercept, required this.r2});
}

/// Represents possible match results.
enum MatchResult { win, loss, tie, notPlayed }
