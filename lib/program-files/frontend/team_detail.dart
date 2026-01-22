// lib/program-files/frontend/team_detail.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// TeamDetailPage provides a deep dive into a specific team's performance for a selected season.
/// It displays team metadata, seasonal statistics, and a chronological match history with point breakdowns.
class TeamDetailPage extends StatefulWidget {
  final int teamNumber;
  final String? teamName;
  final int season;

  const TeamDetailPage({
    super.key,
    required this.teamNumber,
    this.teamName,
    required this.season,
  });

  @override
  State<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends State<TeamDetailPage> {
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _teamInfo;
  List<TeamMatchSummary> _matches = [];

  int? _bestTeamScore; // The team's personal high score for the season

  @override
  void initState() {
    super.initState();
    _loadTeamData();
  }

  /// Loads team profile information and all relevant match summaries from the repository.
  Future<void> _loadTeamData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _matches = [];
      _bestTeamScore = null;
    });

    try {
      final data = await teamSearcherRepository.loadTeamDetail(
        teamNumber: widget.teamNumber,
        season: widget.season,
      );

      final matches = data.matches;

      // Identify the season high score for this team.
      int best = 0;
      for (final m in matches) {
        final s = _teamScore(m);
        if (s != null && s > best) best = s;
      }

      setState(() {
        _teamInfo = data.teamInfo;
        _matches = matches;
        _bestTeamScore = best > 0 ? best : null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ---------- DATA HELPERS ----------

  String _formatDateOnly(DateTime? dt) {
    if (dt == null) return 'Unknown date';
    return '${dt.day.toString().padLeft(2, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.year.toString().padLeft(4, '0')}';
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Time unknown';
    return '${dt.day.toString().padLeft(2, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.year.toString().padLeft(4, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Determines if the team was part of the Red alliance in a given match.
  bool _isTeamRed(TeamMatchSummary m) {
    if (m.redTeams.contains(widget.teamNumber)) return true;
    if (m.blueTeams.contains(widget.teamNumber)) return false;
    return m.alliance == 'Red';
  }

  int? _teamScore(TeamMatchSummary m) =>
      _isTeamRed(m) ? m.red.totalPoints : m.blue.totalPoints;

  int? _oppScore(TeamMatchSummary m) =>
      _isTeamRed(m) ? m.blue.totalPoints : m.red.totalPoints;

  MatchResult _resultForMatch(TeamMatchSummary m) {
    if (!m.hasBeenPlayed) return MatchResult.notPlayed;

    final ts = _teamScore(m);
    final os = _oppScore(m);
    if (ts == null || os == null) return MatchResult.notPlayed;

    if (ts > os) return MatchResult.win;
    if (ts < os) return MatchResult.loss;
    return MatchResult.tie;
  }

  /// Calculates the total Ranking Points (RP) earned by the team in a specific match.
  int _rpForMatch(TeamMatchSummary m) {
    if (!m.hasBeenPlayed) return 0;

    int rp = 0;
    switch (_resultForMatch(m)) {
      case MatchResult.win:
        rp += 2;
        break;
      case MatchResult.tie:
        rp += 1;
        break;
      case MatchResult.loss:
      case MatchResult.notPlayed:
        break;
    }

    final allianceScore = _isTeamRed(m) ? m.red : m.blue;
    if (allianceScore.movementRp) rp += 1;
    if (allianceScore.goalRp) rp += 1;
    if (allianceScore.patternRp) rp += 1;

    return rp;
  }

  // ---------- UI SECTIONS ----------

  /// Builds the top card containing team name, location, and season context.
  Widget _buildHeader(ThemeData theme) {
    final info = _teamInfo ?? {};
    final nameFull = info['nameFull'] ?? info['name'] ?? widget.teamName ?? '';
    final region = info['region'] ?? '';
    final country = info['country'] ?? '';
    final city = info['city'] ?? '';

    final locationParts = <String>[];
    if (city.toString().isNotEmpty) locationParts.add(city.toString());
    if (country.toString().isNotEmpty) locationParts.add(country.toString());
    final location = locationParts.isEmpty ? null : locationParts.join(', ');

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                widget.teamNumber.toString(),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team ${widget.teamNumber}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (nameFull.toString().isNotEmpty)
                    Text(
                      nameFull.toString(),
                      style: theme.textTheme.bodyLarge,
                    ),
                  const SizedBox(height: 4),
                  if (region.toString().isNotEmpty)
                    Text(
                      'Region: $region',
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (location != null)
                    Text(
                      'Location: $location',
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Season ${widget.season}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Displays aggregated performance metrics for the entire season.
  Widget _buildSeasonSummary(ThemeData theme) {
    if (_matches.isEmpty) {
      return const SizedBox.shrink();
    }

    int wins = 0, losses = 0, ties = 0, played = 0;
    int totalFor = 0, totalAgainst = 0;

    for (final m in _matches) {
      final res = _resultForMatch(m);
      if (res == MatchResult.notPlayed) continue;

      played++;
      final ts = _teamScore(m) ?? 0;
      final os = _oppScore(m) ?? 0;
      totalFor += ts;
      totalAgainst += os;

      switch (res) {
        case MatchResult.win: wins++; break;
        case MatchResult.loss: losses++; break;
        case MatchResult.tie: ties++; break;
        default: break;
      }
    }

    final avgFor = played > 0 ? totalFor / played : 0.0;
    final avgAgainst = played > 0 ? totalAgainst / played : 0.0;
    final winRate = played > 0 ? (wins / played * 100) : 0.0;

    final eventCodes = _matches.map((m) => m.eventCode).toSet();
    final eventCount = eventCodes.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Season Summary',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _summaryChip(theme, label: 'Record', value: '$wins – $losses – $ties'),
                const SizedBox(width: 8),
                _summaryChip(theme, label: 'Matches', value: '$played'),
                const SizedBox(width: 8),
                _summaryChip(theme, label: 'Win Rate', value: '${winRate.toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _summaryChip(theme, label: 'Events', value: '$eventCount'),
                  const SizedBox(width: 8),
                  _summaryChip(theme, label: 'Avg For', value: avgFor.toStringAsFixed(1)),
                  const SizedBox(width: 8),
                  _summaryChip(theme, label: 'Avg Against', value: avgAgainst.toStringAsFixed(1)),
                  if (_bestTeamScore != null) ...[
                    const SizedBox(width: 8),
                    _summaryChip(theme, label: 'Best', value: '$_bestTeamScore', icon: Icons.star),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// UI helper for consistent summary chip styling.
  Widget _summaryChip(ThemeData theme, {required String label, required String value, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.amber.shade700),
            const SizedBox(width: 4),
          ],
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// Groups all matches by event code for organized display.
  Map<String, List<TeamMatchSummary>> _groupByEvent() {
    final Map<String, List<TeamMatchSummary>> grouped = {};
    for (final m in _matches) {
      grouped.putIfAbsent(m.eventCode, () => []).add(m);
    }
    return grouped;
  }

  /// Calculates cumulative statistics for each event attended.
  Map<String, _EventStats> _buildEventStats() {
    final Map<String, _EventStats> stats = {};
    for (final m in _matches) {
      final stat = stats.putIfAbsent(m.eventCode, () => _EventStats());
      final res = _resultForMatch(m);
      switch (res) {
        case MatchResult.win: stat.wins++; break;
        case MatchResult.loss: stat.losses++; break;
        case MatchResult.tie: stat.ties++; break;
        case MatchResult.notPlayed: stat.notPlayed++; break;
      }
      stat.rp += _rpForMatch(m);
    }
    return stats;
  }

  /// Builds the primary list of events and their respective match lists.
  Widget _buildMatchesBody(ThemeData theme) {
    if (_matches.isEmpty) {
      return Expanded(
        child: Center(
          child: Text('No matches found for this season.', style: theme.textTheme.bodyMedium),
        ),
      );
    }

    final grouped = _groupByEvent();
    final eventStats = _buildEventStats();
    final eventCodes = grouped.keys.toList()..sort();

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: eventCodes.length,
        itemBuilder: (context, idx) {
          final eventCode = eventCodes[idx];
          final matches = grouped[eventCode]!
            ..sort((a, b) => (a.scheduledTime ?? DateTime(1970))
                .compareTo(b.scheduledTime ?? DateTime(1970)));

          final firstDate = matches.first.scheduledTime;
          final eventDate = _formatDateOnly(firstDate);

          final stat = eventStats[eventCode] ?? _EventStats();
          final record = '${stat.wins}-${stat.losses}-${stat.ties}';

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Theme(
              data: theme.copyWith(dividerColor: theme.dividerColor.withOpacity(0.15)),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
                leading: const Icon(Icons.event),
                title: Text('Event $eventCode', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$eventDate • ${matches.length} matches', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      'Record: $record • RP: ${stat.rp}',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                children: [
                  const SizedBox(height: 4),
                  for (final m in matches) _buildCollapsibleMatch(theme, m),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds a detailed, collapsible card for an individual match.
  Widget _buildCollapsibleMatch(ThemeData theme, TeamMatchSummary m) {
    final isRed = _isTeamRed(m);
    final redScore = m.red.totalPoints;
    final blueScore = m.blue.totalPoints;
    final allianceColor = isRed ? Colors.redAccent : Colors.blueAccent;

    final isBestMatch = _bestTeamScore != null && _teamScore(m) == _bestTeamScore;
    final rp = _rpForMatch(m);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: allianceColor.withOpacity(0.35), width: 1.4),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(
          children: [
            Text('Match ${m.matchId}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (isBestMatch) ...[
              const SizedBox(width: 6),
              Icon(Icons.star, size: 18, color: Colors.amber.shade700),
            ],
            const SizedBox(width: 10),
            
            // Highlighted Alliance Identity
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: allianceColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${m.alliance} alliance',
                style: TextStyle(color: allianceColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),

            const Spacer(),

            // Match Result Summary
            if (redScore != null && blueScore != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RichText(
                    text: TextSpan(
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      children: [
                        TextSpan(text: redScore.toString(), style: const TextStyle(color: Colors.redAccent)),
                        TextSpan(text: ' : ', style: TextStyle(color: theme.textTheme.titleMedium?.color)),
                        TextSpan(text: blueScore.toString(), style: const TextStyle(color: Colors.blueAccent)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildResultBadge(m),
                      const SizedBox(width: 6),
                      _rpBadge(rp),
                    ],
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildResultBadge(m),
                  const SizedBox(width: 6),
                  _rpBadge(rp),
                ],
              ),
          ],
        ),
        subtitle: Text(_formatDateTime(m.scheduledTime), style: theme.textTheme.bodySmall),
        children: [
          const SizedBox(height: 8),
          _buildMatchDetails(theme, m),
        ],
      ),
    );
  }

  /// Status badge for match outcomes (Win/Loss/Tie/Not Played).
  Widget _buildResultBadge(TeamMatchSummary m) {
    final result = _resultForMatch(m);
    switch (result) {
      case MatchResult.win: return _badge('WIN', Colors.green.shade700);
      case MatchResult.loss: return _badge('LOSS', Colors.red.shade700);
      case MatchResult.tie: return _badge('TIE', Colors.orange.shade700);
      case MatchResult.notPlayed: return _badge('NP', Colors.grey);
    }
  }

  /// Badge displaying Ranking Points earned.
  Widget _rpBadge(int rp) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.4)),
      ),
      child: Text(
        '$rp RP',
        style: const TextStyle(fontSize: 11, color: Colors.deepPurple, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _badge(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Provides detailed alliance compositions and full point breakdowns for a match.
  Widget _buildMatchDetails(ThemeData theme, TeamMatchSummary m) {
    final highlightRed = _isTeamRed(m);
    final highlightBlue = !highlightRed;

    final redTeams = m.redTeams.isEmpty ? '-' : m.redTeams.join(', ');
    final blueTeams = m.blueTeams.isEmpty ? '-' : m.blueTeams.join(', ');

    final textSmall = theme.textTheme.bodySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Alliance Rosters
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.redAccent.withOpacity(highlightRed ? 0.18 : 0.08),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Red alliance', style: textSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(redTeams, style: textSmall),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.blueAccent.withOpacity(highlightBlue ? 0.18 : 0.08),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Blue alliance', style: textSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(blueTeams, style: textSmall),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // RP Achievement Breakdown
        _buildRpBreakdown(theme, m),

        Text(
          'Score Breakdown',
          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),

        // Tabular Point Breakdown
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              _scoreHeader(theme, highlightRed, highlightBlue),
              const Divider(height: 1),

              _sectionLabel(theme, 'Autonomous'),
              _scoreRow(theme, 'Total auto', m.red.autoPoints, m.blue.autoPoints, highlightRed: highlightRed, highlightBlue: highlightBlue),
              _scoreRow(theme, 'Auto artifacts', m.red.autoArtifactPoints, m.blue.autoArtifactPoints, highlightRed: highlightRed, highlightBlue: highlightBlue),
              _scoreRow(theme, 'Auto pattern', m.red.autoPatternPoints, m.blue.autoPatternPoints, highlightRed: highlightRed, highlightBlue: highlightBlue),

              const Divider(height: 1),

              _sectionLabel(theme, 'Driver Controlled'),
              _scoreRow(theme, 'Total DC', m.red.dcPoints, m.blue.dcPoints, highlightRed: highlightRed, highlightBlue: highlightBlue),
              _scoreRow(theme, 'Base points', m.red.dcBasePoints, m.blue.dcBasePoints, highlightRed: highlightRed, highlightBlue: highlightBlue),
              _scoreRow(theme, 'Artifacts', m.red.dcArtifactPoints, m.blue.dcArtifactPoints, highlightRed: highlightRed, highlightBlue: highlightBlue),
              _scoreRow(theme, 'Pattern', m.red.dcPatternPoints, m.blue.dcPatternPoints, highlightRed: highlightRed, highlightBlue: highlightBlue),
              _scoreRow(theme, 'Depot', m.red.dcDepotPoints, m.blue.dcDepotPoints, highlightRed: highlightRed, highlightBlue: highlightBlue),

              const Divider(height: 1),

              _sectionLabel(theme, 'Penalties'),
              _scoreRow(theme, 'Committed', m.red.penaltyCommitted, m.blue.penaltyCommitted, highlightRed: highlightRed, highlightBlue: highlightBlue),
              _scoreRow(theme, 'Received', m.red.penaltyByOpp, m.blue.penaltyByOpp, highlightRed: highlightRed, highlightBlue: highlightBlue),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  /// Displays visual chips for each RP objective achieved in the match.
  Widget _buildRpBreakdown(ThemeData theme, TeamMatchSummary m) {
    if (!m.hasBeenPlayed) return const SizedBox.shrink();

    final alliance = _isTeamRed(m) ? m.red : m.blue;
    final res = _resultForMatch(m);
    int matchRp = 0;
    if (res == MatchResult.win) matchRp = 2;
    if (res == MatchResult.tie) matchRp = 1;

    if (matchRp == 0 && !alliance.movementRp && !alliance.goalRp && !alliance.patternRp) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ranking Points Breakdown',
          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (matchRp > 0)
              _rpDetailChip(theme, res == MatchResult.win ? 'Win' : 'Tie', '+$matchRp', Colors.orange),
            if (alliance.movementRp)
              _rpDetailChip(theme, 'Auto Move', '+1', Colors.deepPurple),
            if (alliance.goalRp)
              _rpDetailChip(theme, 'End Goal', '+1', Colors.deepPurple),
            if (alliance.patternRp)
              _rpDetailChip(theme, 'Pattern', '+1', Colors.deepPurple),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Detailed chip for specific RP achievements.
  Widget _rpDetailChip(ThemeData theme, String label, String score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(text: '$label ', style: TextStyle(color: color, fontWeight: FontWeight.normal)),
            TextSpan(text: score, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  /// Header row for the score breakdown table.
  Widget _scoreHeader(ThemeData theme, bool highlightRed, bool highlightBlue) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          const Expanded(flex: 2, child: SizedBox()),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: highlightRed ? Colors.redAccent.withOpacity(0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Red',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: highlightBlue ? Colors.blueAccent.withOpacity(0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Blue',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// Comparative score row for Red vs Blue alliances.
  Widget _scoreRow(
      ThemeData theme,
      String label,
      int? red,
      int? blue, {
        required bool highlightRed,
        required bool highlightBlue,
      }) {
    String fmt(int? v) => v?.toString() ?? '-';

    final textStyle = theme.textTheme.bodySmall;
    final labelStyle = textStyle?.copyWith(color: textStyle.color?.withOpacity(0.85));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: labelStyle)),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: highlightRed ? Colors.redAccent.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  fmt(red),
                  style: textStyle?.copyWith(
                    color: Colors.redAccent,
                    fontWeight: highlightRed ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: highlightBlue ? Colors.blueAccent.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  fmt(blue),
                  style: textStyle?.copyWith(
                    color: Colors.blueAccent,
                    fontWeight: highlightBlue ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    context.watch<ThemeService>();

    return Scaffold(
      appBar: TopAppBar(
        title: widget.teamName != null && widget.teamName!.isNotEmpty
            ? 'Team ${widget.teamNumber} - ${widget.teamName}'
            : 'Team ${widget.teamNumber}',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: theme.scaffoldBackgroundColor,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadTeamData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        )
            : Column(
          children: [
            _buildHeader(theme),
            _buildSeasonSummary(theme),
            const SizedBox(height: 8),
            _buildMatchesBody(theme),
          ],
        ),
      ),
    );
  }
}

enum MatchResult { win, loss, tie, notPlayed }

class _EventStats {
  int wins = 0;
  int losses = 0;
  int ties = 0;
  int notPlayed = 0;
  int rp = 0;
}
