import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

// Repositories and computational logic.
import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/calculations_prediction_points.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// PointEstimateCalculatorPage provides a tool to evaluate team performance levels.
/// It calculates a team's "level" (tier), phase strengths, and weighted point predictions.
class PointEstimateCalculatorPage extends StatefulWidget {
  const PointEstimateCalculatorPage({super.key});

  @override
  State<PointEstimateCalculatorPage> createState() =>
      _PointEstimateCalculatorPageState();
}

class _PointEstimateCalculatorPageState
    extends State<PointEstimateCalculatorPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Search input and season context.
  final _teamController = TextEditingController();
  int _season = 2025;

  bool _loading = false;
  String? _error;

  // Currently analyzed team data.
  int? _teamNumber;
  Map<String, dynamic>? _teamInfo;
  List<TeamMatchSummary> _matches = [];

  // Resulting performance metrics.
  PhaseStrength? _strength;
  PredictionStats? _prediction;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _prefillFromProfile();
  }

  @override
  void dispose() {
    _teamController.dispose();
    super.dispose();
  }

  /// Automatically fills the search box with the user's team number if available.
  Future<void> _prefillFromProfile() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _db.collection('users').doc(user.uid).get();
      final tnRaw = doc.data()?['teamNumber'];
      final tn = int.tryParse(tnRaw?.toString() ?? '');
      if (tn != null) _teamController.text = tn.toString();
    } catch (_) {
      // Ignore prefill errors.
    }
  }

  /// Performs heavy data loading and analysis for a specific team number.
  Future<void> _analyzeTeamNumber(int tn) async {
    setState(() {
      _loading = true;
      _error = null;
      _teamNumber = tn;
      _teamInfo = null;
      _matches = [];
      _strength = null;
      _prediction = null;
    });

    try {
      final data = await teamSearcherRepository.loadTeamDetail(
        teamNumber: tn,
        season: _season,
      );

      final matches = List<TeamMatchSummary>.from(data.matches);

      // Sort matches chronologically (newest first for display).
      matches.sort((a, b) {
        final ta = a.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final c = tb.compareTo(ta);
        if (c != 0) return c;
        return b.matchId.compareTo(a.matchId);
      });

      // Calculate strengths: prioritize official Quick Stats, fallback to manual averages.
      PhaseStrength? strengthQs;
      try {
        strengthQs = await fetchPhaseStrengthFromQuickStats(
          teamNumber: tn,
          season: _season,
        );
      } catch (_) {
        strengthQs = null;
      }

      final strength = strengthQs ?? computePhaseStrengthFromMatches(matches, tn);

      // Generate weighted prediction using recent match history.
      final pred = computePredictionStatsWeighted(matches, tn);

      setState(() {
        _teamInfo = data.teamInfo;
        _matches = matches;
        _strength = strength;
        _prediction = pred;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Handles search button click or keyboard submit.
  Future<void> _search() async {
    FocusScope.of(context).unfocus();

    final input = _teamController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Please enter a team number');
      return;
    }

    // Direct analysis if input is numeric.
    final tn = int.tryParse(input);
    if (tn != null) {
      await _analyzeTeamNumber(tn);
      return;
    }

    // Otherwise, perform a name-based search and prompt user to pick.
    setState(() {
      _loading = true;
      _error = null;
      _teamNumber = null;
      _teamInfo = null;
      _matches = [];
      _strength = null;
      _prediction = null;
    });

    try {
      final results = await teamSearcherRepository.searchTeams(input);

      if (!mounted) return;
      setState(() => _loading = false);

      if (results.isEmpty) {
        setState(() => _error = 'No teams found matching "$input".');
        return;
      }

      final picked = await _pickTeamDialog(results);
      if (picked == null) return;

      final pickedNumber = int.tryParse(picked['teamNumber']?.toString() ?? '');
      if (pickedNumber == null) {
        setState(() => _error = 'Selected team has no valid team number.');
        return;
      }

      _teamController.text = pickedNumber.toString();
      await _analyzeTeamNumber(pickedNumber);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Team search failed: $e';
      });
    }
  }

  /// Shows a modal list for the user to select one team from multiple search results.
  Future<Map<String, dynamic>?> _pickTeamDialog(List<dynamic> results) async {
    final normalized = results
        .where((e) => e != null)
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
        .where((m) => (m['teamNumber'] != null))
        .toList();

    if (normalized.isEmpty) return null;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) {
        final theme = Theme.of(context);

        return AlertDialog(
          title: const Text('Select a team'),
          content: SizedBox(
            width: 520,
            height: min(420, normalized.length * 56.0 + 40),
            child: ListView.separated(
              itemCount: normalized.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = normalized[i];
                final num = (t['teamNumber'] ?? '').toString();
                final name = (t['nameFull'] ?? t['name'] ?? t['nameShort'] ?? '').toString();

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                    foregroundColor: theme.colorScheme.primary,
                    child: Text(
                      num.isEmpty ? '?' : num,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  title: Text(name.isEmpty ? 'Team $num' : name),
                  subtitle: Text('Team $num'),
                  onTap: () => Navigator.pop(context, t),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Points Estimate',
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
          : RefreshIndicator(
        onRefresh: _search,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // Input Configuration Card
            _searchCard(theme, primary),
            const SizedBox(height: 14),

            if (_error != null) _errorCard(theme, _error!),

            // Team Identity Card
            if (_teamNumber != null && _teamInfo != null) ...[
              const SizedBox(height: 14),
              _teamHeader(theme, primary),
            ],

            // Visual Tier and Level Tracking Card
            if (_strength != null) ...[
              const SizedBox(height: 14),
              _teamStrengthCard(theme, primary, _strength!),
            ],

            // Predictive Projection Card
            if (_prediction != null && _prediction!.playedCount > 0) ...[
              const SizedBox(height: 14),
              _predictionCard(theme, primary, _prediction!, _strength),
            ],

            // List of most recent matches for context.
            if (_matches.isNotEmpty) ...[
              const SizedBox(height: 14),
              _recentMatchesCard(theme),
            ],
          ],
        ),
      ),
    );
  }

  /// Card containing search input and season selector.
  Widget _searchCard(ThemeData theme, Color primary) {
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
          Row(
            children: [
              Icon(Icons.search, color: primary),
              const SizedBox(width: 8),
              Text(
                'Team Lookup',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _seasonDropdown(theme),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teamController,
            decoration: const InputDecoration(
              labelText: 'Team Number',
              hintText: 'e.g. 23417',
              prefixIcon: Icon(Icons.manage_search),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _search,
            icon: const Icon(Icons.bolt),
            label: const Text('Calculate Estimates'),
          ),
        ],
      ),
    );
  }

  /// Dropdown for selecting the competition year.
  Widget _seasonDropdown(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _season,
          isDense: true,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          items: const [
            DropdownMenuItem(value: 2024, child: Text('2024')),
            DropdownMenuItem(value: 2025, child: Text('2025')),
            DropdownMenuItem(value: 2026, child: Text('2026')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _season = v);
          },
        ),
      ),
    );
  }

  /// Card header showing basic information for the loaded team.
  Widget _teamHeader(ThemeData theme, Color primary) {
    final info = _teamInfo ?? {};
    final name = (info['nameFull'] ?? info['name'] ?? info['nameShort'] ?? 'Unknown').toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: primary.withOpacity(0.12),
            foregroundColor: primary,
            child: Text(
              (_teamNumber ?? 0).toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team $_teamNumber',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.75),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  /// Displays the calculated team tier and progress toward the next level.
  Widget _teamStrengthCard(ThemeData theme, Color primary, PhaseStrength strength) {
    final total = strength.total;
    final tier = tierForTotal(total);
    final nt = nextTier(total);
    final need = pointsToNextTier(total);
    final progress = tierProgress01(total);

    final nextText = (nt == null)
        ? 'Maximum Level Achieved'
        : 'Goal: ${nt.name} at ${nt.minTotal.toStringAsFixed(0)} pts';

    final needText = (nt == null)
        ? ''
        : '${need.toStringAsFixed(1)} pts required to level up';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: primary),
              const SizedBox(width: 8),
              Text(
                'Performance Level',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Chip(label: Text(tier.name)),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            '${total.toStringAsFixed(1)} Avg Points',
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, height: 1.0),
          ),
          const SizedBox(height: 10),

          LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 10),

          // Upgrade requirements information.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.upgrade, color: primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nextText,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (needText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          needText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Average point breakdown by match phase.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _phaseValue(theme, 'Auto', strength.autoAvg),
              _phaseValue(theme, 'TeleOp', strength.teleopAvg),
              _phaseValue(theme, 'Endgame', strength.endgameAvg),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            'Strongest Phase: ${strength.strongestPhase}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// UI helper for displaying individual phase point averages.
  Widget _phaseValue(ThemeData theme, String label, double v) {
    return Column(
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          v.toStringAsFixed(0),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          'avg',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Displays a weighted score prediction and a statistical confidence metric.
  Widget _predictionCard(
      ThemeData theme,
      Color primary,
      PredictionStats pred,
      PhaseStrength? strength,
      ) {
    // Confidence is derived from the inverse coefficient of variation.
    final confidence = pred.meanTotal <= 0
        ? 0.0
        : (1.0 - (pred.stdTotal / max(pred.meanTotal, 1.0))).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_graph, color: primary),
              const SizedBox(width: 8),
              Text(
                'Next Match Prediction',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Chip(label: Text('${pred.playedCount} matches analyzed')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${pred.meanTotal.toStringAsFixed(1)} pts',
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, height: 1.0),
          ),
          const SizedBox(height: 6),
          Text(
            'Estimated Range: ${pred.low.toStringAsFixed(0)} – ${pred.high.toStringAsFixed(0)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: confidence,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(width: 10),
              Text('Confidence: ${(confidence * 100).toStringAsFixed(0)}%'),
            ],
          ),
          if (strength != null) ...[
            const SizedBox(height: 10),
            Text(
              'Current Level: ${tierForTotal(strength.total).name}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Lists the most recently played matches for the team.
  Widget _recentMatchesCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recent Performance',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._matches.take(5).map((m) => _matchTile(theme, m)),
        ],
      ),
    );
  }

  /// Individual match summary row within the recent performance card.
  Widget _matchTile(ThemeData theme, TeamMatchSummary match) {
    final tn = _teamNumber;

    final inRed = tn != null && match.redTeams.contains(tn);
    final inBlue = tn != null && match.blueTeams.contains(tn);

    // Determine the alliance context for the target team.
    final isRed = inRed
        ? true
        : inBlue
        ? false
        : ((match.alliance).toLowerCase() == 'red');

    final bool? isWin = match.isWin;

    Color resultColor = theme.disabledColor;
    if (isWin == true) resultColor = Colors.green;
    if (isWin == false) resultColor = Colors.red;

    final oppTeams = isRed ? match.blueTeams : match.redTeams;
    final oppText = oppTeams.isEmpty ? 'Unknown' : oppTeams.join(', ');

    final scoreText = '${match.redScore ?? '-'} : ${match.blueScore ?? '-'}';
    final playedText = (match.hasBeenPlayed == true) ? 'Played' : 'Upcoming';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        isWin == true ? Icons.check_circle_outline : isWin == false ? Icons.highlight_off : Icons.help_outline,
        color: resultColor,
      ),
      title: Text(
        'Match ${match.matchId} @ ${match.eventCode}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('${isRed ? 'Red' : 'Blue'} Alliance vs $oppText • $playedText'),
      trailing: Text(scoreText, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}
