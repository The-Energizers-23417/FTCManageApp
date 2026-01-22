/// Represents a detailed point breakdown for an alliance in a match.
class AllianceBreakdown {
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

  final int totalPoints;

  /// Bonus ranking points provided by FTCScout data.
  final bool movementRp;
  final bool goalRp;
  final bool patternRp;

  const AllianceBreakdown({
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
    required this.totalPoints,
    required this.movementRp,
    required this.goalRp,
    required this.patternRp,
  });

  /// Returns an empty breakdown with all values initialized to zero or false.
  factory AllianceBreakdown.empty() => const AllianceBreakdown(
    autoPoints: 0,
    autoArtifactPoints: 0,
    autoPatternPoints: 0,
    dcPoints: 0,
    dcBasePoints: 0,
    dcArtifactPoints: 0,
    dcPatternPoints: 0,
    dcDepotPoints: 0,
    penaltyCommitted: 0,
    penaltyByOpp: 0,
    totalPoints: 0,
    movementRp: false,
    goalRp: false,
    patternRp: false,
  );

  /// Standardizes numeric parsing from dynamic JSON values.
  static int _int(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static bool _bool(Map<String, dynamic> json, String key) {
    final v = json[key];
    return v == true;
  }

  /// Maps a JSON payload from the API to an AllianceBreakdown instance.
  factory AllianceBreakdown.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return AllianceBreakdown.empty();
    }

    // FTCScout often segments artifact points into classifications and overflow.
    final autoArtifactsTotal = _int(json, 'autoArtifactPoints') +
        _int(json, 'autoArtifactClassifiedPoints') +
        _int(json, 'autoArtifactOverflowPoints');

    final dcArtifactsTotal = _int(json, 'dcArtifactPoints') +
        _int(json, 'dcArtifactClassifiedPoints') +
        _int(json, 'dcArtifactOverflowPoints');

    return AllianceBreakdown(
      autoPoints: _int(json, 'autoPoints'),
      autoArtifactPoints: autoArtifactsTotal,
      autoPatternPoints: _int(json, 'autoPatternPoints'),
      dcPoints: _int(json, 'dcPoints'),
      dcBasePoints: _int(json, 'dcBasePoints'),
      dcArtifactPoints: dcArtifactsTotal,
      dcPatternPoints: _int(json, 'dcPatternPoints'),
      dcDepotPoints: _int(json, 'dcDepotPoints'),
      penaltyCommitted: _int(json, 'penaltyPointsCommitted'),
      penaltyByOpp: _int(json, 'penaltyPointsByOpp'),
      totalPoints: _int(json, 'totalPoints'),
      movementRp: _bool(json, 'movementRp'),
      goalRp: _bool(json, 'goalRp'),
      patternRp: _bool(json, 'patternRp'),
    );
  }
}

/// Consolidated summary of a single match from the perspective of one team.
class TeamMatchSummary {
  final String eventCode;
  final int matchId;
  final String alliance; // "Red" or "Blue"
  final String? station;
  final String? role;

  final bool hasBeenPlayed;
  final int? redScore;
  final int? blueScore;
  final bool? isWin;
  final bool? isTie;

  final String tournamentLevel;
  final DateTime? scheduledTime;

  final List<int> redTeams;
  final List<int> blueTeams;

  final AllianceBreakdown red;
  final AllianceBreakdown blue;

  const TeamMatchSummary({
    required this.eventCode,
    required this.matchId,
    required this.alliance,
    required this.station,
    required this.role,
    required this.hasBeenPlayed,
    required this.redScore,
    required this.blueScore,
    required this.isWin,
    required this.isTie,
    required this.tournamentLevel,
    required this.scheduledTime,
    required this.redTeams,
    required this.blueTeams,
    required this.red,
    required this.blue,
  });
}

/// Safely casts a dynamic numeric value to an integer.
int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

/// Merges team-specific match metadata with global event match data.
TeamMatchSummary buildTeamMatchSummary({
  required Map<String, dynamic> teamMatch,
  required Map<String, dynamic>? eventMatch,
  required int teamNumber,
}) {
  final String eventCode = teamMatch['eventCode']?.toString() ?? '';
  final String alliance = teamMatch['alliance']?.toString() ?? '';
  final String? station = teamMatch['station']?.toString();
  final String? role = teamMatch['allianceRole']?.toString();

  final dynamic matchIdRaw = teamMatch['matchId'];
  final int matchId =
  matchIdRaw is int ? matchIdRaw : int.parse(matchIdRaw.toString());

  bool hasBeenPlayed = false;
  String tournamentLevel = '';
  DateTime? scheduledTime;
  final List<int> redTeams = [];
  final List<int> blueTeams = [];
  AllianceBreakdown red = AllianceBreakdown.empty();
  AllianceBreakdown blue = AllianceBreakdown.empty();
  int? redScore;
  int? blueScore;
  bool? isWin;
  bool? isTie;

  if (eventMatch != null) {
    hasBeenPlayed = eventMatch['hasBeenPlayed'] == true;
    tournamentLevel = eventMatch['tournamentLevel']?.toString() ?? '';

    final scheduledRaw = eventMatch['scheduledStartTime']?.toString();
    if (scheduledRaw != null) {
      try {
        scheduledTime = DateTime.parse(scheduledRaw).toLocal();
      } catch (_) {
        // Leave null if parsing fails.
      }
    }

    final scores = eventMatch['scores'];
    if (scores is Map) {
      final redMap =
      scores['red'] is Map ? Map<String, dynamic>.from(scores['red']) : null;
      final blueMap =
      scores['blue'] is Map ? Map<String, dynamic>.from(scores['blue']) : null;

      red = AllianceBreakdown.fromJson(redMap);
      blue = AllianceBreakdown.fromJson(blueMap);

      redScore = red.totalPoints;
      blueScore = blue.totalPoints;

      // Determine match result logic.
      if (hasBeenPlayed && redScore != null && blueScore != null) {
        if (redScore == blueScore) {
          isTie = true;
          isWin = false;
        } else {
          final bool teamIsRed = alliance == 'Red';
          final int teamScore = teamIsRed ? redScore : blueScore;
          final int oppScore = teamIsRed ? blueScore : redScore;
          isTie = false;
          isWin = teamScore > oppScore;
        }
      }
    }

    // Extract participating team numbers for each alliance.
    final teamsList = eventMatch['teams'];
    if (teamsList is List) {
      for (final t in teamsList) {
        if (t is! Map) continue;
        final color = t['alliance']?.toString();
        final tnRaw = t['teamNumber'];
        final int? tn = tnRaw is int ? tnRaw : _asInt(tnRaw);
        if (tn == null) continue;

        if (color == 'Red') {
          redTeams.add(tn);
        } else if (color == 'Blue') {
          blueTeams.add(tn);
        }
      }
    }
  }

  return TeamMatchSummary(
    eventCode: eventCode,
    matchId: matchId,
    alliance: alliance,
    station: station,
    role: role,
    hasBeenPlayed: hasBeenPlayed,
    redScore: redScore,
    blueScore: blueScore,
    isWin: isWin,
    isTie: isTie,
    tournamentLevel: tournamentLevel,
    scheduledTime: scheduledTime,
    redTeams: redTeams,
    blueTeams: blueTeams,
    red: red,
    blue: blue,
  );
}

/// Sorts a match collection by Event -> Time -> Match ID.
List<TeamMatchSummary> sortMatchesByEventAndTime(
    List<TeamMatchSummary> matches,
    ) {
  final sorted = List<TeamMatchSummary>.from(matches);
  sorted.sort((a, b) {
    final eventCompare = a.eventCode.compareTo(b.eventCode);
    if (eventCompare != 0) return eventCompare;

    final aTime = a.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final timeCompare = aTime.compareTo(bTime);
    if (timeCompare != 0) return timeCompare;

    return a.matchId.compareTo(b.matchId);
  });
  return sorted;
}
