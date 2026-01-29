import 'dart:math';
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

  /// Searches for teams by name or number using the FTCScout API with improved ranking and fuzzy-like fallback.
  Future<List<Map<String, dynamic>>> searchTeams(String query) async {
    if (query.trim().isEmpty) return [];
    
    final cleanQuery = query.trim();
    
    // 1. Initial attempt with full query
    var raw = await ftcScoutApi.searchTeams(searchText: cleanQuery, limit: 40);
    List<Map<String, dynamic>> results = [];
    if (raw is List) {
      results = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    // 2. If no results and it's a name, try a more relaxed search (handle potential typos at the end)
    if (results.isEmpty && cleanQuery.length > 3 && int.tryParse(cleanQuery) == null) {
      final fallbackQuery = cleanQuery.substring(0, (cleanQuery.length * 0.8).floor());
      if (fallbackQuery.length >= 3) {
        final rawFallback = await ftcScoutApi.searchTeams(searchText: fallbackQuery, limit: 40);
        if (rawFallback is List) {
          results = rawFallback.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    }

    // 3. Rank results based on similarity to original query to bring best matches to top
    if (results.isNotEmpty) {
      results.sort((a, b) {
        final scoreA = _calculateMatchScore(cleanQuery, a);
        final scoreB = _calculateMatchScore(cleanQuery, b);
        return scoreB.compareTo(scoreA); // Highest score first
      });
    }

    return results;
  }

  /// Calculates a relevance score for a team based on the search query.
  double _calculateMatchScore(String query, Map<String, dynamic> team) {
    final q = query.toLowerCase();
    final number = (team['number'] ?? team['teamNumber'] ?? '').toString();
    final nameShort = (team['nameShort'] ?? team['shortName'] ?? '').toString().toLowerCase();
    final nameFull = (team['nameFull'] ?? team['name'] ?? '').toString().toLowerCase();
    final city = (team['city'] ?? '').toString().toLowerCase();

    if (number == q) return 100.0; // Perfect number match
    if (number.startsWith(q)) return 90.0; // Number prefix match
    
    if (nameShort == q || nameFull == q) return 85.0; // Perfect name match
    if (nameShort.startsWith(q) || nameFull.startsWith(q)) return 75.0; // Name prefix match
    
    if (nameFull.contains(q)) return 60.0; // Name contains query
    if (city.contains(q)) return 40.0; // City match
    
    // Fuzzy bonus: check if many characters overlap
    int charMatches = 0;
    final combinedName = nameShort + nameFull;
    for (int i = 0; i < q.length; i++) {
      if (combinedName.contains(q[i])) charMatches++;
    }
    
    return (charMatches / q.length) * 20.0;
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
