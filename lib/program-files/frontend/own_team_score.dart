import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/calculations_prediction_own_score.dart';

/// OwnTeamScorePage displays performance metrics, trends, and match history for the user's own team.
/// It uses historical data to predict future performance and visualize score progression.
class OwnTeamScorePage extends StatefulWidget {
  const OwnTeamScorePage({super.key});

  @override
  State<OwnTeamScorePage> createState() => _OwnTeamScorePageState();
}

class _OwnTeamScorePageState extends State<OwnTeamScorePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Page state
  bool _loading = true;
  String? _error;

  int? _teamNumber;
  int _season = 2025;

  Map<String, dynamic>? _teamInfo;
  List<TeamMatchSummary> _matches = [];

  // Display settings
  OwnDashboardMode _mode = OwnDashboardMode.allMatches;
  bool _showChart = true;

  // Result of statistical calculations
  OwnDashboardComputed? _computed;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Fetches team identity from Firestore and then match data from the API.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _computed = null;
      _matches = [];
      _teamInfo = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      // Retrieve the team number associated with the current user account.
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final tnRaw = userDoc.data()?['teamNumber'];
      final tn = int.tryParse(tnRaw?.toString() ?? '');
      if (tn == null) throw Exception('Team number not set in profile.');
      _teamNumber = tn;

      // Load comprehensive team details and match summaries.
      final data = await teamSearcherRepository.loadTeamDetail(
        teamNumber: tn,
        season: _season,
      );

      _teamInfo = data.teamInfo;
      _matches = data.matches;

      _recompute();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Triggers recalculation of statistics and predictions based on current filters.
  void _recompute() {
    final tn = _teamNumber;
    if (tn == null) return;
    _computed = OwnScoreCalculator.compute(
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
        title: 'Team Performance',
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
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    _topHeader(theme, primaryColor),
                    const SizedBox(height: 20),

                    if (_computed != null) ...[
                      // High-level KPI grid
                      _statsOverviewGrid(theme, _computed!.prediction),
                      const SizedBox(height: 20),

                      // Interactive score progression chart
                      if (_showChart)
                        _chartCard(theme, primaryColor, _computed!.series, _computed!.prediction, isDark),

                      if (_showChart) const SizedBox(height: 20),

                      // Aggregated season statistics
                      _seasonSummaryCard(theme, _computed!),
                      const SizedBox(height: 20),

                      // Grouped and collapsible match list
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

  /// Builds the top header with team identification and season selection.
  Widget _topHeader(ThemeData theme, Color primaryColor) {
    final info = _teamInfo ?? {};
    final name = (info['nameFull'] ?? info['name'] ?? 'Unknown').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team ${_teamNumber ?? "-"}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _seasonSelector(theme),
          ],
        ),
        const SizedBox(height: 16),
        _controlBar(theme),
      ],
    );
  }

  /// UI for selecting the competition season.
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
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _season = v;
            });
            _load();
          },
        ),
      ),
    );
  }

  /// Filter bar for choosing data scope and toggling visualization.
  Widget _controlBar(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SegmentedButton<OwnDashboardMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: OwnDashboardMode.allMatches,
                label: Text('All Matches'),
              ),
              ButtonSegment(
                value: OwnDashboardMode.lastEventOnly,
                label: Text('Last Event Only'),
              ),
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

  /// Grid of Key Performance Indicators based on match history and trends.
  Widget _statsOverviewGrid(ThemeData theme, PredictionResult p) {
    final pred = p.predictedScore;
    final trend = p.trendPerMatch;

    // Visual indicators for performance trends.
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

  /// Helper widget for consistent KPI card styling.
  Widget _kpiCard(ThemeData theme, String label, String value, {IconData? icon, Color? valueColor, Widget? customIcon}) {
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
              if (customIcon != null) customIcon
              else if (icon != null) Icon(icon, size: 18, color: theme.colorScheme.primary.withOpacity(0.7)),
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

  /// Card wrapper for the interactive chart.
  Widget _chartCard(ThemeData theme, Color primaryColor, List<ScorePoint> series, PredictionResult p, bool isDark) {
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

  /// Displays high-level season aggregate data.
  Widget _seasonSummaryCard(ThemeData theme, OwnDashboardComputed c) {
    int totalWins = 0;
    int totalLosses = 0;
    int totalTies = 0;
    int maxScore = 0;

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

  /// Helper widget for displaying a single summary statistic.
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

  /// Builds a list of matches grouped by event, each within a collapsible panel.
  Widget _matchesByEventList(ThemeData theme, Color primaryColor, OwnDashboardComputed c) {
    // 1. Group matches by eventCode.
    final grouped = <String, List<TeamMatchSummary>>{};
    for (final m in c.filteredMatches) {
      grouped.putIfAbsent(m.eventCode, () => []).add(m);
    }

    if (grouped.isEmpty) {
      return _emptyState(theme, 'No matches found.');
    }

    // 2. Sort events by date of first match, newest first.
    final eventCodes = grouped.keys.toList();
    eventCodes.sort((a, b) {
      final listA = grouped[a]!;
      final listB = grouped[b]!;
      final timeA = listA.isEmpty ? DateTime(2099) : (listA.first.scheduledTime ?? DateTime(2099));
      final timeB = listB.isEmpty ? DateTime(2099) : (listB.first.scheduledTime ?? DateTime(2099));
      return timeB.compareTo(timeA);
    });

    return Column(
      children: eventCodes.map((code) {
        final matches = grouped[code]!;
        // Sort matches within each event: Newest first.
        matches.sort((a, b) => (b.scheduledTime ?? DateTime(1970))
            .compareTo(a.scheduledTime ?? DateTime(1970)));

        final eventStat = c.eventStatsByCode[code];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor.withOpacity(0.3))
          ),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            initiallyExpanded: eventCodes.first == code, // Open the most recent event by default.
            leading: Icon(Icons.event, color: primaryColor),
            title: Text(
              'Event $code',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: eventStat != null
                ? Text('Avg: ${eventStat.avgScore.toStringAsFixed(1)} • W-L-T: ${eventStat.wins}-${eventStat.losses}-${eventStat.ties}')
                : Text('${matches.length} matches'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: matches.map((m) => _matchCard(theme, m)).toList(),
          ),
        );
      }).toList(),
    );
  }

  /// Card displaying summary and breakdown for an individual match.
  Widget _matchCard(ThemeData theme, TeamMatchSummary m) {
    final tn = _teamNumber ?? 0;
    final v = OwnScoreCalculator.viewForMatch(teamNumber: tn, m: m);

    final isWin = _resultForMatch(v) == MatchResult.win;
    final isTie = _resultForMatch(v) == MatchResult.tie;
    final isLoss = _resultForMatch(v) == MatchResult.loss;

    // Status indicator color based on outcome.
    Color statusColor = theme.dividerColor;
    if (v.hasBeenPlayed) {
      if (isWin) statusColor = Colors.green;
      else if (isTie) statusColor = Colors.orange;
      else if (isLoss) statusColor = Colors.red;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
             color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.05),
             blurRadius: 4,
             offset: const Offset(0, 2),
          )
        ]
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(
          'Match ${m.matchId}',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          v.hasBeenPlayed
              ? '${v.teamScore} - ${v.oppScore}  (${isWin ? "W" : (isTie ? "T" : "L")})'
              : 'Upcoming',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: v.hasBeenPlayed ? statusColor : null,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatDate(m.scheduledTime),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
            Text(
              _formatTime(m.scheduledTime),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          // Alliance partner and opponent team numbers.
          _allianceInfoRow(theme, m, tn),
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
          )
        ],
      ),
    );
  }

  /// UI for displaying teammates and opponents in a match.
  Widget _allianceInfoRow(ThemeData theme, TeamMatchSummary m, int myTeam) {
    final myAlliance = m.redTeams.contains(myTeam) ? m.redTeams : m.blueTeams;
    final oppAlliance = m.redTeams.contains(myTeam) ? m.blueTeams : m.redTeams;
    
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

  /// Organized breakdown of points for all match phases.
  Widget _scoreBreakdownSection(ThemeData theme, MatchTeamView v) {
    return Column(
      children: [
        // Autonomous Phase
        _breakdownHeader(theme, 'Autonomous', v.autoPoints, Colors.purpleAccent),
        _breakdownRow(theme, 'Samples/Specimens', v.autoArtifactPoints),
        _breakdownRow(theme, 'Pattern/Park', v.autoPatternPoints),
        const SizedBox(height: 8),

        // TeleOp Phase
        _breakdownHeader(theme, 'TeleOp (Driver Controlled)', v.dcPoints, Colors.blueAccent),
        _breakdownRow(theme, 'Samples/Specimens', v.dcArtifactPoints),
        _breakdownRow(theme, 'Ascent/Parking', v.dcBasePoints),
        if (v.dcPatternPoints > 0) _breakdownRow(theme, 'Pattern', v.dcPatternPoints),
        if (v.dcDepotPoints > 0) _breakdownRow(theme, 'Depot', v.dcDepotPoints),
        const SizedBox(height: 8),

        // Penalty Status
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

  /// Section header for point breakdowns.
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

  /// Individual metric row in the point breakdown.
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

  /// Small indicator badge for RP milestones.
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

  /// Determines the match result for the current team view.
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

  /// Full-page error display.
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
              onPressed: _load,
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
    return '${dt.day}/${dt.month}';
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ───────────────────────── Interactive Chart Implementation ─────────────────────────

/// A stateful widget providing a smooth, interactive line chart for match scores.
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
      return Center(
        child: Text('Not enough data for chart', style: widget.textStyle),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          // Handle drag and tap events to show interactive tooltips.
          onHorizontalDragUpdate: (details) {
            _updateHover(details.localPosition.dx, constraints.maxWidth);
          },
          onHorizontalDragEnd: (_) {
            setState(() {
              _hoverIndex = null;
            });
          },
          onTapDown: (details) {
            _updateHover(details.localPosition.dx, constraints.maxWidth);
          },
          onTapUp: (_) {
            setState(() {
              _hoverIndex = null;
            });
          },
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

  /// Maps a horizontal pixel coordinate to a data index in the series.
  void _updateHover(double dx, double width) {
    final padL = 30.0;
    final padR = 12.0;
    final w = max(1.0, width - padL - padR);
    
    double t = (dx - padL) / w;
    t = t.clamp(0.0, 1.0);
    
    final exactIndex = t * (widget.series.length);
    int idx = exactIndex.round();
    
    setState(() {
      _hoverIndex = idx;
    });
  }
}

/// Custom painter for rendering the performance chart.
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
    // Define chart padding.
    final padL = 30.0;
    final padR = 12.0;
    final padT = 20.0; 
    final padB = 20.0;

    final w = max(1.0, size.width - padL - padR);
    final h = max(1.0, size.height - padT - padB);

    // Calculate Y-axis scaling bounds.
    final scores = series.map((p) => p.score).toList();
    double minY = scores.isEmpty ? 0 : scores.reduce(min);
    double maxY = scores.isEmpty ? 100 : scores.reduce(max);

    minY = min(minY, low);
    maxY = max(maxY, high);

    final range = maxY - minY;
    if (range < 10) {
      maxY += 5;
      minY = max(0, minY - 5);
    } else {
      maxY += range * 0.1;
      minY = max(0, minY - range * 0.1);
    }

    double xOf(int idx) {
      return padL + (idx / series.length) * w;
    }

    double yOf(double v) {
      final t = (v - minY) / (maxY - minY);
      return padT + (1 - t) * h;
    }

    // Render horizontal grid lines.
    final gridPaint = Paint()
      ..color = axisColor.withOpacity(0.2)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      double y = padT + (h * i / 4);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
    }

    // Render Y-axis numerical labels.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawYLabel(double val, double y) {
      tp.text = TextSpan(text: val.toStringAsFixed(0), style: textStyle);
      tp.layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
    drawYLabel(maxY, padT);
    drawYLabel((maxY+minY)/2, padT + h/2);
    drawYLabel(minY, padT + h);

    // Render the smooth cubic bezier chart line.
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    if (series.isNotEmpty) {
      path.moveTo(xOf(0), yOf(series[0].score));
      for (int i = 0; i < series.length - 1; i++) {
        final x1 = xOf(i);
        final y1 = yOf(series[i].score);
        final x2 = xOf(i + 1);
        final y2 = yOf(series[i + 1].score);

        final cx = (x1 + x2) / 2;
        path.cubicTo(cx, y1, cx, y2, x2, y2);
      }
    }
    canvas.drawPath(path, linePaint);

    // Render gradient fill area under the curve.
    final fillPath = Path.from(path);
    fillPath.lineTo(xOf(series.length - 1), padT + h);
    fillPath.lineTo(xOf(0), padT + h);
    fillPath.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [lineColor.withOpacity(0.2), lineColor.withOpacity(0.0)],
    );
    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTRB(padL, padT, padL + w, padT + h));
    canvas.drawPath(fillPath, fillPaint);

    // Render individual data points.
    final pointPaint = Paint()..color = lineColor;
    final bgPaint = Paint()..color = backgroundColor;

    for (int i = 0; i < series.length; i++) {
      final x = xOf(i);
      final y = yOf(series[i].score);
      canvas.drawCircle(Offset(x, y), 5, bgPaint);
      canvas.drawCircle(Offset(x, y), 3, pointPaint);
    }

    // Render the predicted next match data point and range band.
    final predX = xOf(series.length);
    final predY = yOf(predictedNext);

    final bandPaint = Paint()
      ..color = lineColor.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final bandTop = yOf(high);
    final bandBottom = yOf(low);
    final rangeRect = Rect.fromCenter(
        center: Offset(predX, (bandTop + bandBottom) / 2),
        width: 12,
        height: (bandBottom - bandTop).abs()
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rangeRect, const Radius.circular(4)), bandPaint);

    final predPointPaint = Paint()..color = lineColor.withOpacity(0.7);
    canvas.drawCircle(Offset(predX, predY), 4, predPointPaint);

    tp.text = TextSpan(text: 'Pred', style: textStyle?.copyWith(fontWeight: FontWeight.bold));
    tp.layout();
    tp.paint(canvas, Offset(predX - tp.width / 2, padT + h + 4));

    // Render the hover tooltip and vertical cursor line.
    if (hoverIndex != null) {
      final i = hoverIndex!;
      double targetX;
      String label;
      String subLabel;

      if (i < series.length) {
        targetX = xOf(i);
        label = '${series[i].score.toInt()} pts';
        subLabel = 'Match ${series[i].matchId}';
      } else {
        targetX = predX;
        label = '${predictedNext.toInt()} pts';
        subLabel = 'Prediction';
      }

      final lineHoverPaint = Paint()
        ..color = (textStyle?.color ?? Colors.black).withOpacity(0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      
      _drawDashedLine(canvas, Offset(targetX, padT), Offset(targetX, padT + h), lineHoverPaint);

      final tooltipText = TextSpan(
        children: [
          TextSpan(text: '$label\n', style: textStyle?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
          TextSpan(text: subLabel, style: textStyle?.copyWith(fontSize: 10, color: Colors.white.withOpacity(0.9))),
        ],
      );
      tp.text = tooltipText;
      tp.textAlign = TextAlign.center;
      tp.layout();

      final tooltipW = max(60.0, tp.width + 16);
      final tooltipH = tp.height + 12;
      
      double tipX = targetX;
      if (tipX - tooltipW / 2 < 0) tipX = tooltipW / 2;
      if (tipX + tooltipW / 2 > size.width) tipX = size.width - tooltipW / 2;
      
      final tipY = padT;
      
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(tipX, tipY + tooltipH/2), width: tooltipW, height: tooltipH),
        const Radius.circular(8),
      );
      
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFF333333).withOpacity(0.9));
      tp.paint(canvas, Offset(tipX - tp.width/2, tipY + 6));
    }
  }
  
  /// Helper to draw a dashed vertical line.
  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 5.0;
    double startY = p1.dy;
    while (startY < p2.dy) {
      canvas.drawLine(
        Offset(p1.dx, startY),
        Offset(p1.dx, min(startY + dashWidth, p2.dy)),
        paint,
      );
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _ScoreChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
