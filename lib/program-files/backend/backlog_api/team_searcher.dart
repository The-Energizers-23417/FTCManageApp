import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-connection/api_global.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// Holds the complete details for a team, including profile info and match history.
class TeamDetailData {
  final Map<String, dynamic>? teamInfo;
  final List<TeamMatchSummary> matches;

  const TeamDetailData({
    required this.teamInfo,
    required this.matches,
  });
}

/// A repository class responsible for fetching and processing team-related data from the API.
class TeamSearcherRepository {
  const TeamSearcherRepository();

  /// Searches for teams by name or number using the FTCScout API.
  Future<List<Map<String, dynamic>>> searchTeams(String query) async {
    final raw = await ftcScoutApi.searchTeams(searchText: query, limit: 20);
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Loads full details for a specific team, including their match history for a given season.
  Future<TeamDetailData> loadTeamDetail({
    required int teamNumber,
    required int season,
  }) async {
    // 1. Fetch basic team information.
    final teamInfoRaw = await ftcScoutApi.getTeam(teamNumber);

    // 2. Fetch all match entries where this team participated.
    final teamMatchesRaw = await ftcScoutApi.getTeamMatches(
      teamNumber: teamNumber,
      season: season,
    );

    if (teamMatchesRaw is! List) {
      throw Exception('Unexpected response format for team matches.');
    }

    // 3. Identify all unique events the team attended.
    final eventCodes = <String>{};
    for (final m in teamMatchesRaw) {
      if (m is Map && m['eventCode'] != null) {
        eventCodes.add(m['eventCode'].toString());
      }
    }

    // 4. Fetch the full match list for every event attended.
    final Map<String, List<dynamic>> eventMatchesByCode = {};
    for (final code in eventCodes) {
      final eventMatchesRaw = await ftcScoutApi.getEventMatches(
        season: season,
        code: code,
      );
      if (eventMatchesRaw is List) {
        eventMatchesByCode[code] = eventMatchesRaw;
      }
    }

    // 5. Cross-reference team match entries with event match data to build summaries.
    final List<TeamMatchSummary> summaries = [];

    for (final tm in teamMatchesRaw) {
      if (tm is! Map) continue;

      final String eventCode = tm['eventCode']?.toString() ?? '';
      if (eventCode.isEmpty) continue;

      final matchIdRaw = tm['matchId'];
      final int? matchId = matchIdRaw is int ? matchIdRaw : int.tryParse(matchIdRaw.toString());
      if (matchId == null) continue;

      final List<dynamic> eventMatches = eventMatchesByCode[eventCode] ?? const [];
      Map<String, dynamic>? eventMatch;

      // Find the corresponding event-level match data for this specific team match.
      for (final em in eventMatches) {
        if (em is! Map) continue;

        final emId = em['id'];
        final emScores = em['scores'];
        final emMatchIdFromScores = (emScores is Map) ? emScores['matchId'] : null;

        if (emId == matchId || emMatchIdFromScores == matchId) {
          eventMatch = Map<String, dynamic>.from(em);
          break;
        }
      }

      // Build a unified summary for the match.
      final summary = buildTeamMatchSummary(
        teamMatch: Map<String, dynamic>.from(tm),
        eventMatch: eventMatch,
        teamNumber: teamNumber,
      );

      summaries.add(summary);
    }

    // 6. Sort the resulting match list chronologically.
    final sorted = sortMatchesByEventAndTime(summaries);

    final Map<String, dynamic>? teamInfo = teamInfoRaw is Map ? Map<String, dynamic>.from(teamInfoRaw) : null;

    return TeamDetailData(
      teamInfo: teamInfo,
      matches: sorted,
    );
  }
}

/// Global instance of the repository for use across the application.
const teamSearcherRepository = TeamSearcherRepository();
