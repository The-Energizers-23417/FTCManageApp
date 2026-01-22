// lib/program-files/frontend/other_team_prediction.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/calculations_predictions_other_teams.dart';

enum MatchResult { win, loss, tie, notPlayed }

/// OtherTeamPredictionPage allows users to search for any team and view their projected performance.
/// It also supports favoriting teams for quick access via chips.
class OtherTeamPredictionPage extends StatefulWidget {
  const OtherTeamPredictionPage({super.key});

  @override
  State<OtherTeamPredictionPage> createState() => _OtherTeamPredictionPageState();
}

class _OtherTeamPredictionPageState extends State<OtherTeamPredictionPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Controller for the team search input.
  final TextEditingController _teamController = TextEditingController();

  // Loading and error states.
  bool _loading = false;
  String? _error;

  int _season = 2025;

  // Currently loaded team data.
  int? _teamNumber;
  Map<String, dynamic>? _teamInfo;
  List<TeamMatchSummary> _matches = [];

  // Display filters and chart visibility.
  OtherDashboardMode _mode = OtherDashboardMode.allMatches;
  bool _showChart = true;

  // Result of predictive calculations.
  OtherDashboardComputed? _computed;

  int _currentIndex = 0;

  // Local list of favorited team numbers.
  List<int> _favorites = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _teamController.dispose();
    super.dispose();
  }

  /// Loads the user's favorite teams from Firestore.
  Future<void> _loadFavorites() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _db.collection('users').doc(user.uid).get();
      final raw = doc.data()?['favoriteTeams'];
      final list = <int>[];
      if (raw is List) {
        for (final v in raw) {
          final n = int.tryParse(v.toString());
          if (n != null) list.add(n);
        }
      }
      setState(() => _favorites = list);
    } catch (_) {
      // Fail silently if favorites cannot be loaded.
    }
  }

  /// Adds or removes the currently loaded team from the user's favorites list.
  Future<void> _toggleFavorite() async {
    final user = _auth.currentUser;
    final tn = _teamNumber;
    if (user == null || tn == null) return;

    final next = List<int>.from(_favorites);
    final isFav = next.contains(tn);
    if (isFav) {
      next.remove(tn);
    } else {
      next.add(tn);
    }

    setState(() => _favorites = next);

    // Sync updated list to Firestore.
    await _db.collection('users').doc(user.uid).set(
      {'favoriteTeams': next},
      SetOptions(merge: true),
    );
  }

  bool get _isFavorite => _teamNumber != null && _favorites.contains(_teamNumber);

  /// Performs a search for a team and loads their data into the page.
  Future<void> _searchAndLoad() async {
    FocusScope.of(context).unfocus();
    final query = _teamController.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Enter a team number or name.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _computed = null;
      _teamNumber = null;
      _matches = [];
      _teamInfo = null;
    });

    try {
      int? teamNumberToLoad;
      final isNumber = int.tryParse(query) != null;

      if (isNumber) {
        teamNumberToLoad = int.parse(query);
      } else {
        // Fallback to team name search if input is not numeric.
        final searchResults = await teamSearcherRepository.searchTeams(query);
        if (searchResults.isNotEmpty) {
          final firstResult = searchResults.first;
          if (firstResult['teamNumber'] != null) {
            teamNumberToLoad = firstResult['teamNumber'] as int?;
          }
        } else {
          setState(() {
            _error = 'No team found matching "$query".';
            _loading = false;
          });
          return;
        }
      }

      if (teamNumberToLoad == null) {
        setState(() {
          _error = 'Could not find a valid team number for "$query".';
          _loading = false;
        });
        return;
      }
      
      // Load detailed team info and match summaries from repository.
      final data = await teamSearcherRepository.loadTeamDetail(
        teamNumber: teamNumberToLoad,
        season: _season,
      );

      _teamInfo = data.teamInfo;
      _matches = data.matches;
      _teamNumber = teamNumberToLoad;

      _recompute();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Triggers recalculation of statistics using the prediction engine.
  void _recompute() {
    final tn = _teamNumber;
    if (tn == null) return;

    _computed = OtherScoreCalculator.compute(
      teamNumber: tn,
      matches: _matches,
      mode: _mode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Team Prediction',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTabSelected: (i) => setState(() => _currentIndex = i),
        items: const [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView(theme, _error!)
          : RefreshIndicator(
        onRefresh: _searchAndLoad,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    // Persistent Search Card with Favorites
                    _searchCard(theme, primaryColor),
                    const SizedBox(height: 16),

                    // Team Identity Header with Season Selection
                    _topHeader(theme, primaryColor),
                    const SizedBox(height: 20),

                    if (_teamNumber == null) ...[
                      _emptyState(theme, 'Search for a team to view their performance predictions.'),
                    ] else if (_computed != null) ...[
                      // KPI Score Breakdown
                      _statsOverviewGrid(theme, _computed!.prediction),
                      const SizedBox(height: 20),

                      // Interactive Data Visualization
                      if (_showChart)
                        _chartCard(
                          theme,
                          primaryColor,
                          _computed!.series,
                          _computed!.prediction,
                          isDark,
                        ),
                      if (_showChart) const SizedBox(height: 20),

                      // Season Record Summary
                      _seasonSummaryCard(theme, _computed!),
                      const SizedBox(height: 20),

                      // List of matches grouped by competition events
                      _matchesByEventList(theme, primaryColor, _computed!),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Card containing the team search input and quick-access favorite chips.
  Widget _searchCard(ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search Team', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _teamController,
                  decoration: const InputDecoration(
                    labelText: 'Team Number or Name',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _searchAndLoad(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _searchAndLoad,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Load'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Favorite team quick chips.
          if (_favorites.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in _favorites.take(12))
                  ActionChip(
                    avatar: const Icon(Icons.star, size: 16),
                    label: Text('Team $n'),
                    onPressed: () {
                      _teamController.text = n.toString();
                      _searchAndLoad();
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Card header showing identity of currently loaded team and data scope controls.
  Widget _topHeader(ThemeData theme, Color primaryColor) {
    final info = _teamInfo ?? {};
    final name = (info['nameFull'] ?? info['name'] ?? 'Unknown').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _teamNumber == null ? 'No team selected' : 'Team ${_teamNumber!}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _teamNumber == null ? '—' : name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Toggle favorite status.
            IconButton(
              tooltip: _isFavorite ? 'Remove favorite' : 'Add favorite',
              onPressed: _teamNumber == null ? null : _toggleFavorite,
              icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
              color: _isFavorite ? Colors.amber : theme.iconTheme.color,
            ),

            _seasonSelector(theme),
          ],
        ),
        const SizedBox(height: 16),
        _controlBar(theme),
      ],
    );
  }

  /// UI component for selecting the competition season.
  Widget _seasonSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _season,
          isDense: true,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          items: const [
            DropdownMenuItem(value: 2024, child: Text('2024 - Into The Deep')),
            DropdownMenuItem(value: 2025, child: Text('2025 - Decode')),
            DropdownMenuItem(value: 2026, child: Text('2026 - Future Season')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _season = v);
            // Re-load data if a team is currently loaded.
            if (_teamNumber != null) {
              _teamController.text = _teamNumber!.toString();
              await _searchAndLoad();
            }
          },
        ),
      ),
    );
  }

  /// Selection bar for data filtering scope and toggling UI elements.
  Widget _controlBar(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SegmentedButton<OtherDashboardMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: OtherDashboardMode.allMatches, label: Text('All Matches')),
              ButtonSegment(value: OtherDashboardMode.lastEventOnly, label: Text('Last Event Only')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              setState(() {
                _mode = s.first;
                _recompute();
              });
            },
          ),
          const SizedBox(width: 12),
          FilterChip(
            label: const Text('Chart'),
            selected: _showChart,
            showCheckmark: false,
            avatar: _showChart ? const Icon(Icons.check, size: 16) : null,
            onSelected: (v) => setState(() => _showChart = v),
          ),
        ],
      ),
    );
  }

  /// Grid of Key Performance Indicators based on predictive modeling.
  Widget _statsOverviewGrid(ThemeData theme, PredictionResult p) {
    final pred = p.predictedScore;
    final trend = p.trendPerMatch;

    // Visual trend indicators.
    Color trendColor = theme.colorScheme.onSurface;
    IconData trendIcon = Icons.remove;
    if (trend > 0.5) {
      trendColor = Colors.green;
      trendIcon = Icons.trending_up;
    } else if (trend < -0.5) {
      trendColor = Colors.red;
      trendIcon = Icons.trending_down;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 600 ? 4 : 2;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            _kpiCard(theme, 'Predicted Score', pred.toStringAsFixed(1), icon: Icons.psychology),
            _kpiCard(
              theme,
              'Trend / Match',
              (trend > 0 ? '+' : '') + trend.toStringAsFixed(1),
              valueColor: trendColor,
              customIcon: Icon(trendIcon, color: trendColor, size: 20),
            ),
            _kpiCard(theme, 'Auto Avg', p.predictedAuto?.toStringAsFixed(1) ?? '-', icon: Icons.smart_toy),
            _kpiCard(theme, 'TeleOp Avg', p.predictedTeleop?.toStringAsFixed(1) ?? '-', icon: Icons.gamepad),
          ],
        );
      },
    );
  }

  /// UI helper for a KPI metric card.
  Widget _kpiCard(
      ThemeData theme,
      String label,
      String value, {
        IconData? icon,
        Color? valueColor,
        Widget? customIcon,
      }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (customIcon != null)
                customIcon
              else if (icon != null)
                Icon(icon, size: 18, color: theme.colorScheme.primary.withOpacity(0.7)),
            ],
          ),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor ?? theme.textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// Card wrapper for the interactive performance progression chart.
  Widget _chartCard(
      ThemeData theme,
      Color primaryColor,
      List<ScorePoint> series,
      PredictionResult p,
      bool isDark,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Score Progression',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: InteractiveScoreChart(
              series: series,
              predictedNext: p.predictedScore,
              low: p.low,
              high: p.high,
              axisColor: theme.dividerColor,
              textStyle: theme.textTheme.bodySmall,
              lineColor: primaryColor,
              backgroundColor: theme.colorScheme.surface,
            ),
          ),
        ],
      ),
    );
  }

  /// Summarizes seasonal aggregates like win/loss record and peak score.
  Widget _seasonSummaryCard(ThemeData theme, OtherDashboardComputed c) {
    int totalWins = 0, totalLosses = 0, totalTies = 0, maxScore = 0;

    for (var s in c.eventStatsByCode.values) {
      totalWins += s.wins;
      totalLosses += s.losses;
      totalTies += s.ties;
      if (s.maxScore > maxScore) maxScore = s.maxScore;
    }

    final totalPlayed = totalWins + totalLosses + totalTies;
    final winRate = totalPlayed == 0 ? 0.0 : (totalWins / totalPlayed * 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryStat(theme, 'Record (W-L-T)', '$totalWins-$totalLosses-$totalTies', Colors.orange),
          _summaryStat(theme, 'Win Rate', '${winRate.toStringAsFixed(1)}%', Colors.green),
          _summaryStat(theme, 'High Score', '$maxScore', Colors.purple),
        ],
      ),
    );
  }

  /// Helper for consistent display of summary metrics.
  Widget _summaryStat(ThemeData theme, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      ],
    );
  }

  /// Builds a vertical list of event cards, each containing collapsible match details.
  Widget _matchesByEventList(ThemeData theme, Color primaryColor, OtherDashboardComputed c) {
    final tn = _teamNumber;
    if (tn == null) return _emptyState(theme, 'No team data loaded.');

    // Organize matches by event.
    final grouped = <String, List<TeamMatchSummary>>{};
    for (final m in c.filteredMatches) {
      grouped.putIfAbsent(m.eventCode, () => []).add(m);
    }

    if (grouped.isEmpty) return _emptyState(theme, 'No matches found for this team.');

    // Sort events by date, newest first.
    final eventCodes = grouped.keys.toList();
    eventCodes.sort((a, b) {
      final sa = c.eventStatsByCode[a]?.firstMatchTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final sb = c.eventStatsByCode[b]?.firstMatchTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return sb.compareTo(sa);
    });

    return Column(
      children: eventCodes.map((code) {
        final matches = grouped[code]!;
        // Sort matches newest first.
        matches.sort((a, b) => (b.scheduledTime ?? DateTime(1970)).compareTo(a.scheduledTime ?? DateTime(1970)));

        final eventStat = c.eventStatsByCode[code];
        final eventDate = eventStat?.firstMatchTime;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor.withOpacity(0.3)),
          ),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            initiallyExpanded: eventCodes.first == code,
            leading: Icon(Icons.event, color: primaryColor),
            title: Text('Event $code', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: eventStat != null
                ? Text('${_formatDate(eventDate)} • Avg: ${eventStat.avgScore.toStringAsFixed(1)} • W-L-T: ${eventStat.wins}-${eventStat.losses}-${eventStat.ties}')
                : Text('${matches.length} matches'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: matches.map((m) => _matchCard(theme, m, tn)).toList(),
          ),
        );
      }).toList(),
    );
  }

  /// Builds a detailed collapsible card for an individual match.
  Widget _matchCard(ThemeData theme, TeamMatchSummary m, int teamNumber) {
    final v = OtherScoreCalculator.viewForMatch(teamNumber: teamNumber, m: m);
    final outcome = _resultForMatch(v);

    final isWin = outcome == MatchResult.win;
    final isTie = outcome == MatchResult.tie;
    final isLoss = outcome == MatchResult.loss;

    // Semantic status indicator color.
    Color statusColor = theme.dividerColor;
    if (v.hasBeenPlayed) {
      if (isWin) statusColor = Colors.green;
      else if (isTie) statusColor = Colors.orange;
      else if (isLoss) statusColor = Colors.red;
    }

    // Alliance-specific visual tinting for identification.
    final bool teamIsRed = v.teamIsRed;
    final Color allianceTint = teamIsRed
        ? Colors.red.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.10)
        : Colors.blue.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.10);

    final int? redScore = m.redScore;
    final int? blueScore = m.blueScore;

    final String scoreLine = !v.hasBeenPlayed || redScore == null || blueScore == null
        ? 'Upcoming'
        : 'R ${redScore.toString()}  -  B ${blueScore.toString()}  (${isWin ? "W" : (isTie ? "T" : "L")})';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: allianceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text('Match ${m.matchId}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            if (v.hasBeenPlayed && redScore != null && blueScore != null) ...[
              Text('R $redScore', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.red)),
              Text('  -  ', style: theme.textTheme.bodyMedium),
              Text('B $blueScore', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.blue)),
              const SizedBox(width: 8),
              Text('(${isWin ? "W" : (isTie ? "T" : "L")})', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: statusColor)),
            ] else ...[
              Text(scoreLine, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        trailing: Text(_formatDate(m.scheduledTime), style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          // Alliance details.
          _allianceInfoRow(theme, m, teamNumber),
          const SizedBox(height: 12),

          // Points breakdown table.
          _scoreBreakdownSection(theme, v),

          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RP Total: ${v.rpTotal}', style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 4,
                children: [
                  if (v.movementRp) _miniBadge(theme, 'MV'),
                  if (v.goalRp) _miniBadge(theme, 'GL'),
                  if (v.patternRp) _miniBadge(theme, 'PT'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Displays alliance teammates and opponents.
  Widget _allianceInfoRow(ThemeData theme, TeamMatchSummary m, int myTeam) {
    final bool myIsRed = m.redTeams.contains(myTeam);
    final myAlliance = myIsRed ? m.redTeams : m.blueTeams;
    final oppAlliance = myIsRed ? m.blueTeams : m.redTeams;

    final partners = myAlliance.where((t) => t != myTeam).join(', ');
    final opponents = oppAlliance.join(', ');

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.group, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Partner: ', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
              Expanded(child: Text(partners.isEmpty ? '-' : partners, style: theme.textTheme.bodySmall)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.sports_kabaddi, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text('Against: ', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
              Expanded(child: Text(opponents, style: theme.textTheme.bodySmall)),
            ],
          ),
        ],
      ),
    );
  }

  /// Detailed point breakdown organized by match phase.
  Widget _scoreBreakdownSection(ThemeData theme, MatchTeamView v) {
    return Column(
      children: [
        _breakdownHeader(theme, 'Autonomous', v.autoPoints, Colors.purpleAccent),
        _breakdownRow(theme, 'Artifacts', v.autoArtifactPoints),
        _breakdownRow(theme, 'Pattern', v.autoPatternPoints),
        const SizedBox(height: 8),

        _breakdownHeader(theme, 'TeleOp', v.dcPoints, Colors.blueAccent),
        _breakdownRow(theme, 'Artifacts', v.dcArtifactPoints),
        _breakdownRow(theme, 'Base', v.dcBasePoints),
        if (v.dcPatternPoints > 0) _breakdownRow(theme, 'Pattern', v.dcPatternPoints),
        if (v.dcDepotPoints > 0) _breakdownRow(theme, 'Depot', v.dcDepotPoints),
        const SizedBox(height: 8),

        // Penalty status.
        if (v.penaltyCommitted > 0 || v.penaltyByOpp > 0)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Penalty (Committed / Received)', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              Text('${v.penaltyCommitted} / ${v.penaltyByOpp}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
      ],
    );
  }

  /// Helper header for point breakdown categories.
  Widget _breakdownHeader(ThemeData theme, String title, int total, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: color, margin: const EdgeInsets.only(right: 6)),
          Text(title, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: color)),
          const Spacer(),
          Text('$total pts', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// Helper row for individual breakdown metrics.
  Widget _breakdownRow(ThemeData theme, String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          Text(value.toString(), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// Indicator badge for Ranking Point achievements.
  Widget _miniBadge(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
    );
  }

  /// Calculates the match outcome based on team views.
  MatchResult _resultForMatch(MatchTeamView v) {
    if (!v.hasBeenPlayed || v.teamScore == null || v.oppScore == null) return MatchResult.notPlayed;
    if (v.teamScore! > v.oppScore!) return MatchResult.win;
    if (v.teamScore! < v.oppScore!) return MatchResult.loss;
    return MatchResult.tie;
  }

  /// UI for empty data states.
  Widget _emptyState(ThemeData theme, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.inbox, size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor)),
          ],
        ),
      ),
    );
  }

  /// Standard error display view.
  Widget _errorView(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Something went wrong', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(error, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _searchAndLoad,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ───────────────────────── Interactive Chart Implementation ─────────────────────────

/// A stateful widget representing a smooth interactive line chart for score history.
class InteractiveScoreChart extends StatefulWidget {
  final List<ScorePoint> series;
  final double predictedNext;
  final double low;
  final double high;
  final Color axisColor;
  final TextStyle? textStyle;
  final Color lineColor;
  final Color backgroundColor;

  const InteractiveScoreChart({
    super.key,
    required this.series,
    required this.predictedNext,
    required this.low,
    required this.high,
    required this.axisColor,
    required this.textStyle,
    required this.lineColor,
    required this.backgroundColor,
  });

  @override
  State<InteractiveScoreChart> createState() => _InteractiveScoreChartState();
}

class _InteractiveScoreChartState extends State<InteractiveScoreChart> {
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.series.length < 2) {
      return Center(child: Text('Not enough data for chart', style: widget.textStyle));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          // Track touch/drag to show vertical cursor and tooltip.
          onHorizontalDragUpdate: (details) => _updateHover(details.localPosition.dx, constraints.maxWidth),
          onHorizontalDragEnd: (_) => setState(() => _hoverIndex = null),
          onTapDown: (details) => _updateHover(details.localPosition.dx, constraints.maxWidth),
          onTapUp: (_) => setState(() => _hoverIndex = null),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ScoreChartPainter(
              series: widget.series,
              predictedNext: widget.predictedNext,
              low: widget.low,
              high: widget.high,
              axisColor: widget.axisColor,
              textStyle: widget.textStyle,
              lineColor: widget.lineColor,
              hoverIndex: _hoverIndex,
              backgroundColor: widget.backgroundColor,
            ),
          ),
        );
      },
    );
  }

  /// Maps horizontal offset to a data index in the provided series.
  void _updateHover(double dx, double width) {
    final padL = 30.0; final padR = 12.0;
    final w = max(1.0, width - padL - padR);
    double t = ((dx - padL) / w).clamp(0.0, 1.0);
    final idx = (t * (widget.series.length)).round();
    setState(() => _hoverIndex = idx);
  }
}

/// Painter for the score progression chart.
class _ScoreChartPainter extends CustomPainter {
  final List<ScorePoint> series;
  final double predictedNext;
  final double low;
  final double high;
  final Color axisColor;
  final TextStyle? textStyle;
  final Color lineColor;
  final int? hoverIndex;
  final Color backgroundColor;

  _ScoreChartPainter({
    required this.series,
    required this.predictedNext,
    required this.low,
    required this.high,
    required this.axisColor,
    required this.textStyle,
    required this.lineColor,
    this.hoverIndex,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final padL = 30.0; final padR = 12.0; final padT = 20.0; final padB = 20.0;
    final w = max(1.0, size.width - padL - padR);
    final h = max(1.0, size.height - padT - padB);

    // Calculate Y-axis scaling.
    final scores = series.map((p) => p.score).toList();
    double minY = scores.isEmpty ? 0 : scores.reduce(min);
    double maxY = scores.isEmpty ? 100 : scores.reduce(max);
    minY = min(minY, low); maxY = max(maxY, high);

    final range = maxY - minY;
    if (range < 10) { maxY += 5; minY = max(0, minY - 5); }
    else { maxY += range * 0.1; minY = max(0, minY - range * 0.1); }

    double xOf(int idx) => padL + (idx / series.length) * w;
    double yOf(double v) {
      final t = (v - minY) / (maxY - minY);
      return padT + (1 - t) * h;
    }

    // Grid rendering.
    final gridPaint = Paint()..color = axisColor.withOpacity(0.2)..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = padT + (h * i / 4);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
    }

    // Y-axis numerical labels.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawYLabel(double val, double y) {
      tp.text = TextSpan(text: val.toStringAsFixed(0), style: textStyle);
      tp.layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
    drawYLabel(maxY, padT); drawYLabel((maxY + minY) / 2, padT + h / 2); drawYLabel(minY, padT + h);

    // Render the smooth cubic bezier path.
    final linePaint = Paint()..color = lineColor..strokeWidth = 3..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;

    final path = Path();
    if (series.isNotEmpty) {
      path.moveTo(xOf(0), yOf(series[0].score));
      for (int i = 0; i < series.length - 1; i++) {
        final x1 = xOf(i); final y1 = yOf(series[i].score);
        final x2 = xOf(i + 1); final y2 = yOf(series[i + 1].score);
        final cx = (x1 + x2) / 2;
        path.cubicTo(cx, y1, cx, y2, x2, y2);
      }
    }
    canvas.drawPath(path, linePaint);

    // Gradient fill rendering.
    final fillPath = Path.from(path);
    fillPath.lineTo(xOf(series.length - 1), padT + h); fillPath.lineTo(xOf(0), padT + h); fillPath.close();
    final gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [lineColor.withOpacity(0.2), lineColor.withOpacity(0.0)]);
    canvas.drawPath(fillPath, Paint()..shader = gradient.createShader(Rect.fromLTRB(padL, padT, padL + w, padT + h)));

    // Data points.
    final pointPaint = Paint()..color = lineColor;
    final bgPaint = Paint()..color = backgroundColor;
    for (int i = 0; i < series.length; i++) {
      final x = xOf(i); final y = yOf(series[i].score);
      canvas.drawCircle(Offset(x, y), 5, bgPaint); canvas.drawCircle(Offset(x, y), 3, pointPaint);
    }

    // Prediction visualization.
    final predX = xOf(series.length); final predY = yOf(predictedNext);
    final rangeRect = Rect.fromCenter(center: Offset(predX, (yOf(high) + yOf(low)) / 2),
      width: 12, height: (yOf(low) - yOf(high)).abs());
    canvas.drawRRect(RRect.fromRectAndRadius(rangeRect, const Radius.circular(4)), Paint()..color = lineColor.withOpacity(0.15));
    canvas.drawCircle(Offset(predX, predY), 4, Paint()..color = lineColor.withOpacity(0.7));

    tp.text = TextSpan(text: 'Pred', style: textStyle?.copyWith(fontWeight: FontWeight.bold));
    tp.layout(); tp.paint(canvas, Offset(predX - tp.width / 2, padT + h + 4));

    // Interactive hover effects (Tooltip & Cursor).
    if (hoverIndex != null) {
      final i = hoverIndex!;
      double targetX; String label; String subLabel;

      if (i < series.length) {
        targetX = xOf(i); label = '${series[i].score.toInt()} pts'; subLabel = 'Match ${series[i].matchId}';
      } else {
        targetX = predX; label = '${predictedNext.toInt()} pts'; subLabel = 'Prediction';
      }

      final lineHoverPaint = Paint()..color = (textStyle?.color ?? Colors.black).withOpacity(0.4)..strokeWidth = 1..style = PaintingStyle.stroke;
      _drawDashedLine(canvas, Offset(targetX, padT), Offset(targetX, padT + h), lineHoverPaint);

      tp.text = TextSpan(children: [
        TextSpan(text: '$label\n', style: textStyle?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
        TextSpan(text: subLabel, style: textStyle?.copyWith(fontSize: 10, color: Colors.white.withOpacity(0.9))),
      ]);
      tp.textAlign = TextAlign.center; tp.layout();

      final tooltipW = max(60.0, tp.width + 16); final tooltipH = tp.height + 12;
      double tipX = targetX.clamp(tooltipW / 2, size.width - tooltipW / 2);
      final rrect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(tipX, padT + tooltipH / 2), width: tooltipW, height: tooltipH), const Radius.circular(8));
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFF333333).withOpacity(0.9));
      tp.paint(canvas, Offset(tipX - tp.width / 2, padT + 6));
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0; const dashSpace = 5.0;
    double startY = p1.dy;
    while (startY < p2.dy) {
      canvas.drawLine(Offset(p1.dx, startY), Offset(p1.dx, min(startY + dashWidth, p2.dy)), paint);
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _ScoreChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.hoverIndex != hoverIndex || oldDelegate.lineColor != lineColor || oldDelegate.backgroundColor != backgroundColor;
}
