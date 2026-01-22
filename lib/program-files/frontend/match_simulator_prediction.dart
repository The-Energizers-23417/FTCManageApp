import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

import 'package:ftcmanageapp/program-files/frontend/team_detail.dart';

/// Defines the source for selecting teams in the simulator.
enum _SimMode { event, openTeams }

/// MatchSimulatorV2Page provides an advanced predictive match simulator.
/// It uses recency-weighted averages to favor more recent performance data for predictions.
class MatchSimulatorV2Page extends StatefulWidget {
  const MatchSimulatorV2Page({super.key});

  @override
  State<MatchSimulatorV2Page> createState() => _MatchSimulatorV2PageState();
}

class _MatchSimulatorV2PageState extends State<MatchSimulatorV2Page> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Global loading and processing state.
  bool _loadingProfile = true;
  bool _loadingEventTeams = false;
  bool _simulating = false;

  String? _softError;

  int? _myTeamNumber;

  _SimMode _mode = _SimMode.event;
  int _season = 2025;

  List<String> _events = <String>['GENERAL'];
  String _selectedEvent = 'GENERAL';

  List<int> _eventTeams = [];

  // Input controllers for manual team entry.
  final _redManual = [TextEditingController(), TextEditingController()];
  final _blueManual = [TextEditingController(), TextEditingController()];

  // Team selections for event mode.
  int? _redPick1;
  int? _redPick2;
  int? _bluePick1;
  int? _bluePick2;

  // Weighting parameters for the predictive algorithm.
  static const int _lastNMatches = 5;
  static const double _decay = 0.85;

  // Local caches for data and computation results.
  final Map<String, List<TeamMatchSummary>> _matchesCache = {};
  final Map<String, Map<String, dynamic>> _teamInfoCache = {};
  final Map<String, double> _teamScoreCache = {};

  final Map<int, double> _teamScoreShown = {};
  double? _redTotal;
  double? _blueTotal;

  @override
  void initState() {
    super.initState();
    _loadProfileAndEvents();
  }

  @override
  void dispose() {
    for (final c in _redManual) c.dispose();
    for (final c in _blueManual) c.dispose();
    super.dispose();
  }

  /// Initial setup: loads profile team identification and available events from Firestore.
  Future<void> _loadProfileAndEvents() async {
    setState(() {
      _loadingProfile = true;
      _softError = null;
      _events = ['GENERAL'];
      _selectedEvent = 'GENERAL';
      _eventTeams = [];
      _redPick1 = _redPick2 = _bluePick1 = _bluePick2 = null;
      _redTotal = _blueTotal = null;
      _teamScoreShown.clear();
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _myTeamNumber = null;
          _loadingProfile = false;
          _events = ['GENERAL'];
          _selectedEvent = 'GENERAL';
        });
        return;
      }

      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};

      // Get user's own team number for event lookup context.
      final tnRaw = data['teamNumber'];
      _myTeamNumber = int.tryParse(tnRaw?.toString() ?? '');

      final setupData = (data['setupData'] is Map)
          ? Map<String, dynamic>.from(data['setupData'] as Map)
          : <String, dynamic>{};

      final eventsRaw = setupData['events'];

      final events = <String>['GENERAL'];
      if (eventsRaw is List) {
        for (final e in eventsRaw) {
          if (e is Map && e['name'] != null) {
            final name = e['name'].toString().trim();
            if (name.isNotEmpty) events.add(name);
          }
        }
      }

      // Sort events alphabetically.
      final rest = events.where((e) => e != 'GENERAL').toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _events = ['GENERAL', ...rest];
        _selectedEvent = _events.first;
        _loadingProfile = false;
      });

      await _maybeAutoLoadEventTeams();
    } catch (e) {
      setState(() {
        _loadingProfile = false;
        _softError = 'Profile load failed: $e';
      });
    }
  }

  // Cache key generators.
  String _teamKey(int teamNumber) => '$_season|$teamNumber';
  String _scoreKey(int teamNumber) => '$_season|$_selectedEvent|$teamNumber';

  int? _parseTeam(String s) => int.tryParse(s.trim());

  /// Clears only the simulation output results.
  void _resetResultsOnly() {
    _redTotal = null;
    _blueTotal = null;
    _teamScoreShown.clear();
  }

  /// Extracts alliance team numbers from manual input controllers.
  List<int> _manualAllianceTeams(List<TextEditingController> ctrls) {
    final out = <int>[];
    for (final c in ctrls) {
      final tn = _parseTeam(c.text);
      if (tn != null) out.add(tn);
    }
    return out;
  }

  /// Returns currently selected team numbers for an alliance based on selection mode.
  List<int> _selectedAllianceTeams({required bool red}) {
    if (_mode == _SimMode.openTeams) {
      return red ? _manualAllianceTeams(_redManual) : _manualAllianceTeams(_blueManual);
    }
    final a = red ? _redPick1 : _bluePick1;
    final b = red ? _redPick2 : _bluePick2;
    final out = <int>[];
    if (a != null) out.add(a);
    if (b != null) out.add(b);
    return out;
  }

  /// Ensures team information and match history are cached.
  Future<void> _ensureTeamLoaded(int teamNumber) async {
    final k = _teamKey(teamNumber);
    if (_matchesCache.containsKey(k) && _teamInfoCache.containsKey(k)) return;

    final dynamic detail = await teamSearcherRepository.loadTeamDetail(
      teamNumber: teamNumber,
      season: _season,
    );

    _matchesCache[k] = (detail.matches is List) ? List<TeamMatchSummary>.from(detail.matches) : [];
    _teamInfoCache[k] = (detail.teamInfo is Map) ? Map<String, dynamic>.from(detail.teamInfo) : {};
  }

  /// Retrieves a formatted team name from the local cache.
  String _teamName(int teamNumber) {
    final info = _teamInfoCache[_teamKey(teamNumber)];
    if (info == null) return '';
    return (info['nameFull'] ?? info['name'] ?? info['nameShort'] ?? '').toString().trim();
  }

  /// Calculates the raw total points for a team in a specific match.
  double _matchScoreForTeam(TeamMatchSummary m, int teamNumber) {
    final bool isRed = m.redTeams.contains(teamNumber) || (m.alliance == 'Red');
    final b = isRed ? m.red : m.blue;

    final autoP = (b.autoPoints).toDouble();
    final teleP = (b.dcPoints).toDouble();
    final endP = (b.dcBasePoints).toDouble();
    return autoP + teleP + endP;
  }

  /// Implements recency-weighted averaging to calculate a predictive match score.
  double _computeRecencyWeightedAvgMatchScore(List<TeamMatchSummary> matches, int teamNumber) {
    final played = matches.where((m) => m.hasBeenPlayed == true).toList();
    if (played.isEmpty) return 0;

    // Sort matches chronologically to identify the most recent ones.
    played.sort((a, b) {
      final ta = a.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.scheduledTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cmp = ta.compareTo(tb);
      if (cmp != 0) return cmp;
      return (a.matchId).compareTo(b.matchId);
    });

    // Take only the specified number of recent matches.
    final recent = played.length <= _lastNMatches
        ? played
        : played.sublist(played.length - _lastNMatches);

    double weightedSum = 0;
    double weightTotal = 0;

    for (int i = 0; i < recent.length; i++) {
      final m = recent[i];

      // Newest match has weight 1.0, older matches decrease exponentially.
      final int ageFromNewest = (recent.length - 1) - i;
      final double w = pow(_decay, ageFromNewest).toDouble();

      final score = _matchScoreForTeam(m, teamNumber);

      weightedSum += score * w;
      weightTotal += w;
    }

    return weightTotal <= 0 ? 0 : (weightedSum / weightTotal);
  }

  /// Loads and caches the estimated scoring contribution (avg/2) for a team.
  Future<double> _loadTeamScore(int teamNumber) async {
    final k = _scoreKey(teamNumber);
    final cached = _teamScoreCache[k];
    if (cached != null) return cached;

    await _ensureTeamLoaded(teamNumber);

    final all = _matchesCache[_teamKey(teamNumber)] ?? <TeamMatchSummary>[];

    // Filter matches based on the selected event context.
    final filtered = _selectedEvent == 'GENERAL'
        ? all.where((m) => m.hasBeenPlayed == true).toList()
        : all.where((m) => m.hasBeenPlayed == true && m.eventCode.trim() == _selectedEvent).toList();

    final avg = _computeRecencyWeightedAvgMatchScore(filtered, teamNumber);

    // Contribution estimate is alliance average divided by 2.
    final teamScore = avg / 2.0;

    _teamScoreCache[k] = teamScore;
    return teamScore;
  }

  Future<void> _maybeAutoLoadEventTeams() async {
    if (_mode != _SimMode.event) return;
    if (_selectedEvent == 'GENERAL') {
      setState(() {
        _eventTeams = [];
        _redPick1 = _redPick2 = _bluePick1 = _bluePick2 = null;
      });
      return;
    }
    await _autoLoadTeamsFromSelectedEvent();
  }

  /// Automatically discovers teams participating in the same event as the user's team.
  Future<void> _autoLoadTeamsFromSelectedEvent() async {
    setState(() {
      _loadingEventTeams = true;
      _softError = null;
      _eventTeams = [];
      _redPick1 = _redPick2 = _bluePick1 = _bluePick2 = null;
      _resetResultsOnly();
    });

    try {
      final tn = _myTeamNumber;
      if (tn == null) {
        throw Exception('Your teamNumber is missing in profile.');
      }

      final dynamic myDetail = await teamSearcherRepository.loadTeamDetail(
        teamNumber: tn,
        season: _season,
      );

      final matches = (myDetail.matches is List) ? List<TeamMatchSummary>.from(myDetail.matches) : <TeamMatchSummary>[];

      final eventMatches = matches.where((m) => m.eventCode.trim() == _selectedEvent).toList();
      if (eventMatches.isEmpty) {
        throw Exception('No matches found for your team ($tn) at event $_selectedEvent.');
      }

      final set = <int>{};
      for (final m in eventMatches) {
        set.addAll(m.redTeams);
        set.addAll(m.blueTeams);
      }

      final list = set.toList()..sort();

      // Prefetch data for the first set of teams to improve simulation speed.
      for (final t in list.take(40)) {
        try { await _ensureTeamLoaded(t); } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _eventTeams = list;
        _loadingEventTeams = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEventTeams = false;
        _softError = 'Event team load failed: $e';
      });
    }
  }

  /// Core simulation logic: aggregates recency-weighted scores to predict alliance results.
  Future<void> _simulate() async {
    FocusScope.of(context).unfocus();

    final redTeams = _selectedAllianceTeams(red: true);
    final blueTeams = _selectedAllianceTeams(red: false);

    // Validation: 2 distinct teams per alliance, 4 distinct teams overall.
    if (redTeams.length != 2 || blueTeams.length != 2) {
      _toast('Pick/enter exactly 2 teams for Red and 2 teams for Blue.');
      return;
    }
    if (redTeams.toSet().length != 2 || blueTeams.toSet().length != 2) {
      _toast('Duplicate team in one alliance.');
      return;
    }
    final all = [...redTeams, ...blueTeams];
    if (all.toSet().length != 4) {
      _toast('Same team selected on both alliances.');
      return;
    }

    setState(() {
      _simulating = true;
      _softError = null;
      _resetResultsOnly();
    });

    try {
      double redSum = 0;
      for (final t in redTeams) {
        await _ensureTeamLoaded(t);
        final s = await _loadTeamScore(t);
        _teamScoreShown[t] = s;
        redSum += s;
      }

      double blueSum = 0;
      for (final t in blueTeams) {
        await _ensureTeamLoaded(t);
        final s = await _loadTeamScore(t);
        _teamScoreShown[t] = s;
        blueSum += s;
      }

      if (!mounted) return;
      setState(() {
        _redTotal = redSum;
        _blueTotal = blueSum;
        _simulating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _simulating = false;
        _softError = 'Simulation failed: $e';
      });
    }
  }

  void _openTeam(int teamNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamDetailPage(
          teamNumber: teamNumber,
          teamName: _teamName(teamNumber),
          season: _season,
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Match simulator',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadProfileAndEvents,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _setupCard(theme),
            const SizedBox(height: 12),
            _formulaCard(theme),
            const SizedBox(height: 12),
            if (_softError != null) ...[
              _softErrorCard(theme, _softError!),
              const SizedBox(height: 12),
            ],
            _resultCard(theme),
            const SizedBox(height: 12),
            _teamBreakdownCard(theme),
          ],
        ),
      ),
    );
  }

  /// Explains the mathematical weighting used for predictions.
  Widget _formulaCard(ThemeData theme) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.functions, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Recency formula',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'We only use the last $_lastNMatches played matches (newest matters most).',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Weights: newest = 1.0, then ×$_decay, then ×$_decay², ...',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 8),
            Text(
              'RecencyAvg = (Σ(scoreᵢ × wᵢ)) / (Σ wᵢ)',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'scoreᵢ = autoPoints + dcPoints + dcBasePoints',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  /// Main configuration section for simulation inputs.
  Widget _setupCard(ThemeData theme) {
    final showEvent = _mode == _SimMode.event;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Setup',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _simulating ? null : _simulate,
                  icon: _simulating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Simulate'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Selection Mode Toggles
            Row(
              children: [
                Expanded(
                  child: RadioListTile<_SimMode>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Event'),
                    value: _SimMode.event,
                    groupValue: _mode,
                    onChanged: _simulating ? null : (v) async {
                      if (v == null) return;
                      setState(() {
                        _mode = v; _softError = null; _resetResultsOnly();
                      });
                      await _maybeAutoLoadEventTeams();
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<_SimMode>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Open teams'),
                    value: _SimMode.openTeams,
                    groupValue: _mode,
                    onChanged: _simulating ? null : (v) async {
                      if (v == null) return;
                      setState(() {
                        _mode = v; _softError = null; _eventTeams = [];
                        _redPick1 = _redPick2 = _bluePick1 = _bluePick2 = null;
                        _resetResultsOnly();
                      });
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Season and Event Pickers
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _season,
                    decoration: const InputDecoration(
                      labelText: 'Season',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    items: const [
                      DropdownMenuItem(value: 2024, child: Text('2024')),
                      DropdownMenuItem(value: 2025, child: Text('2025')),
                      DropdownMenuItem(value: 2026, child: Text('2026')),
                    ],
                    onChanged: _simulating ? null : (v) async {
                      if (v == null) return;
                      setState(() {
                        _season = v; _matchesCache.clear(); _teamInfoCache.clear(); _teamScoreCache.clear();
                        _eventTeams.clear(); _redPick1 = _redPick2 = _bluePick1 = _bluePick2 = null;
                        _resetResultsOnly();
                      });
                      await _maybeAutoLoadEventTeams();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedEvent,
                    decoration: const InputDecoration(
                      labelText: 'Event',
                      prefixIcon: Icon(Icons.flag),
                    ),
                    items: _events.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: _simulating ? null : (v) async {
                      if (v == null) return;
                      setState(() {
                        _selectedEvent = v; _teamScoreCache.clear(); _eventTeams.clear();
                        _redPick1 = _redPick2 = _bluePick1 = _bluePick2 = null;
                        _resetResultsOnly();
                      });
                      await _maybeAutoLoadEventTeams();
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Team Input Grid (Dropdowns or Manual Fields)
            if (showEvent) ...[
              if (_selectedEvent == 'GENERAL')
                Text(
                  'Pick a specific event to auto-load teams.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                )
              else
                Row(
                  children: [
                    if (_loadingEventTeams)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadingEventTeams
                            ? 'Loading teams from $_selectedEvent...'
                            : _eventTeams.isEmpty
                            ? 'No teams loaded yet.'
                            : 'Loaded ${_eventTeams.length} teams from $_selectedEvent',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reload teams',
                      onPressed: (_selectedEvent == 'GENERAL' || _loadingEventTeams || _simulating)
                          ? null
                          : () => _autoLoadTeamsFromSelectedEvent(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              const SizedBox(height: 12),

              Text('Red alliance (2 teams)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _eventPickRow(
                theme,
                a: _redPick1, b: _redPick2,
                onA: (v) => setState(() { _redPick1 = v; _resetResultsOnly(); }),
                onB: (v) => setState(() { _redPick2 = v; _resetResultsOnly(); }),
                accent: Colors.red,
              ),

              const SizedBox(height: 12),

              Text('Blue alliance (2 teams)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _eventPickRow(
                theme,
                a: _bluePick1, b: _bluePick2,
                onA: (v) => setState(() { _bluePick1 = v; _resetResultsOnly(); }),
                onB: (v) => setState(() { _bluePick2 = v; _resetResultsOnly(); }),
                accent: Colors.blue,
              ),
            ] else ...[
              Text('Red alliance (2 teams)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _manualRow(_redManual, accent: Colors.red),

              const SizedBox(height: 12),

              Text('Blue alliance (2 teams)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _manualRow(_blueManual, accent: Colors.blue),
            ],

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _simulating ? null : () {
                      for (final c in _redManual) c.clear();
                      for (final c in _blueManual) c.clear();
                      setState(() {
                        _redPick1 = _redPick2 = _bluePick1 = _bluePick2 = null;
                        _softError = null; _resetResultsOnly();
                      });
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear All'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// UI row for selecting alliance teams via dynamic dropdowns.
  Widget _eventPickRow(
      ThemeData theme, {
        required int? a,
        required int? b,
        required ValueChanged<int?> onA,
        required ValueChanged<int?> onB,
        required Color accent,
      }) {
    final disabled = _eventTeams.isEmpty || _loadingEventTeams || _simulating;

    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(Icons.confirmation_number, color: accent.withOpacity(0.9)),
    );

    String labelForTeam(int t) {
      final name = _teamName(t);
      if (name.isEmpty) return t.toString();
      return '$t • $name';
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: a,
            decoration: deco('Team 1'),
            items: _eventTeams.map((t) => DropdownMenuItem<int>(
              value: t,
              child: Text(labelForTeam(t), overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: disabled ? null : (v) async {
              onA(v);
              if (v != null) {
                try { await _ensureTeamLoaded(v); if (mounted) setState(() {}); } catch (_) {}
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: b,
            decoration: deco('Team 2'),
            items: _eventTeams.map((t) => DropdownMenuItem<int>(
              value: t,
              child: Text(labelForTeam(t), overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: disabled ? null : (v) async {
              onB(v);
              if (v != null) {
                try { await _ensureTeamLoaded(v); if (mounted) setState(() {}); } catch (_) {}
              }
            },
          ),
        ),
      ],
    );
  }

  /// UI row for manual team number text entry.
  Widget _manualRow(List<TextEditingController> ctrls, {required Color accent}) {
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(Icons.confirmation_number, color: accent.withOpacity(0.9)),
    );

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrls[0],
            keyboardType: TextInputType.number,
            decoration: deco('Team 1'),
            onChanged: (_) => setState(_resetResultsOnly),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: ctrls[1],
            keyboardType: TextInputType.number,
            decoration: deco('Team 2'),
            onChanged: (_) => setState(_resetResultsOnly),
          ),
        ),
      ],
    );
  }

  /// Card displaying the outcome of the simulation.
  Widget _resultCard(ThemeData theme) {
    final red = _redTotal;
    final blue = _blueTotal;

    String winner = '—';
    if (red != null && blue != null) {
      if (red > blue) winner = 'Red';
      else if (blue > red) winner = 'Blue';
      else winner = 'Tie';
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Predicted Outcome',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Winner: $winner',
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _scoreLine(theme, label: 'Red Predicted', value: red, color: Colors.red),
            const SizedBox(height: 8),
            _scoreLine(theme, label: 'Blue Predicted', value: blue, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  /// Single line representation of an alliance simulation result.
  Widget _scoreLine(ThemeData theme, {required String label, required double? value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(
            value == null ? '—' : value.toStringAsFixed(1),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Detailed card showing individual team scores and information.
  Widget _teamBreakdownCard(ThemeData theme) {
    final redTeams = _selectedAllianceTeams(red: true);
    final blueTeams = _selectedAllianceTeams(red: false);

    if (redTeams.length != 2 || blueTeams.length != 2) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Select/enter 2 teams per alliance to view individual breakdowns.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ),
      );
    }

    Widget teamRow(int team, {required bool isRed}) {
      final score = _teamScoreShown[team];
      final name = _teamName(team);
      final title = name.isEmpty ? 'Team $team' : 'Team $team • $name';

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: (isRed ? Colors.red : Colors.blue).withOpacity(0.9),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              score == null ? 'Score: —' : 'Score: ${score.toStringAsFixed(1)}',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'View team detail',
              icon: const Icon(Icons.info_outline),
              onPressed: () => _openTeam(team),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Individual Team Contribution Estimates',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  _selectedEvent,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Red Alliance', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...redTeams.map((t) => teamRow(t, isRed: true)),
            const SizedBox(height: 8),
            Text('Blue Alliance', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...blueTeams.map((t) => teamRow(t, isRed: false)),
          ],
        ),
      ),
    );
  }

  /// Small status card for informational or error messages.
  Widget _softErrorCard(ThemeData theme, String msg) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
