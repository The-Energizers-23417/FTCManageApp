import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// Defines the input mode for selecting alliance teams.
enum _SimMode { event, manual }

/// MatchSimulatorPage provides a tool to predict match outcomes based on team averages.
/// It supports selecting teams from a specific event or manual input.
class MatchSimulatorPage extends StatefulWidget {
  const MatchSimulatorPage({super.key});

  @override
  State<MatchSimulatorPage> createState() => _MatchSimulatorPageState();
}

class _MatchSimulatorPageState extends State<MatchSimulatorPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Identity and configuration state.
  bool _loadingProfile = true;
  String? _profileError;
  int? _myTeamNumber;

  _SimMode _mode = _SimMode.event;
  int _season = 2025;

  List<String> _events = <String>['GENERAL'];
  String _selectedEvent = 'GENERAL';

  // Event team loading state.
  bool _loadingEventTeams = false;
  String? _eventTeamsError;
  List<int> _eventTeams = [];

  // Controllers for manual team number input.
  final _redManual = [TextEditingController(), TextEditingController()];
  final _blueManual = [TextEditingController(), TextEditingController()];

  // Team selections for event mode.
  int? _redPick1;
  int? _redPick2;
  int? _bluePick1;
  int? _bluePick2;

  // Automation and processing state.
  bool _autoSimulate = true;
  bool _simulating = false;

  String? _inlineMessage;

  // Local caches for API responses and calculations.
  final Map<String, List<TeamMatchSummary>> _matchesCache = {};
  final Map<String, Map<String, dynamic>> _teamInfoCache = {};
  final Map<String, double> _avgCache = {};

  final Map<int, double> _teamAvg = {};
  double? _redTotal;
  double? _blueTotal;

  @override
  void initState() {
    super.initState();
    _loadProfileAndEvents();
  }

  @override
  void dispose() {
    for (final c in _redManual) {
      c.dispose();
    }
    for (final c in _blueManual) {
      c.dispose();
    }
    super.dispose();
  }

  /// Initial setup: loads team profile and identified events from Firestore.
  Future<void> _loadProfileAndEvents() async {
    setState(() {
      _loadingProfile = true;
      _profileError = null;
      _inlineMessage = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not logged in.');

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

      // Prepare sorted event list.
      final rest = events.where((e) => e != 'GENERAL').toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _events = ['GENERAL', ...rest];
        _selectedEvent = _events.first;
        _loadingProfile = false;
      });

      _applyGeneralRulesIfNeeded();

      await _maybeAutoLoadEventTeams();
    } catch (e) {
      setState(() {
        _loadingProfile = false;
        _profileError = e.toString();
      });
    }
  }

  // Cache key generators.
  String _teamKey(int teamNumber) => '$_season|$teamNumber';
  String _avgKey(int teamNumber) => '$_season|$_selectedEvent|$teamNumber';

  int? _parseTeam(String s) => int.tryParse(s.trim());

  /// Resets current simulation results.
  void _resetResults() {
    _inlineMessage = null;
    _redTotal = null;
    _blueTotal = null;
    _teamAvg.clear();
  }

  /// Ensures correct mode settings when 'GENERAL' event is selected.
  void _applyGeneralRulesIfNeeded() {
    if (_selectedEvent == 'GENERAL') {
      _mode = _SimMode.manual;
      _eventTeamsError = null;
      _loadingEventTeams = false;
      _eventTeams = [];
      _redPick1 = null;
      _redPick2 = null;
      _bluePick1 = null;
      _bluePick2 = null;
    }
  }

  /// Extracts alliance team numbers from manual input fields.
  List<int> _manualAllianceTeams(List<TextEditingController> ctrls) {
    final out = <int>[];
    for (final c in ctrls) {
      final tn = _parseTeam(c.text);
      if (tn != null) out.add(tn);
    }
    return out;
  }

  /// Returns the currently selected team numbers for an alliance based on active mode.
  List<int> _selectedAllianceTeams({required bool red}) {
    if (_selectedEvent == 'GENERAL' || _mode == _SimMode.manual) {
      return red ? _manualAllianceTeams(_redManual) : _manualAllianceTeams(_blueManual);
    }

    final a = red ? _redPick1 : _bluePick1;
    final b = red ? _redPick2 : _bluePick2;
    final out = <int>[];
    if (a != null) out.add(a);
    if (b != null) out.add(b);
    return out;
  }

  /// Ensures data for a specific team is present in the cache.
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

  /// Retrieves a team's formatted name from the cache.
  String _teamName(int teamNumber) {
    final info = _teamInfoCache[_teamKey(teamNumber)];
    if (info == null) return '';
    return (info['nameFull'] ?? info['name'] ?? info['nameShort'] ?? '').toString().trim();
  }

  /// Calculates the average total points for a team from a list of matches.
  double _computeAvgTotalPoints(List<TeamMatchSummary> matches, int teamNumber) {
    if (matches.isEmpty) return 0;

    double sum = 0;
    int n = 0;

    for (final m in matches) {
      if (m.hasBeenPlayed != true) continue;

      final isRed = m.redTeams.contains(teamNumber) || m.alliance == 'Red';
      final b = isRed ? m.red : m.blue;

      // Sum points across all phases.
      final total = b.autoPoints.toDouble() + b.dcPoints.toDouble() + b.dcBasePoints.toDouble();
      sum += total;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Loads and caches the estimated scoring contribution (avg/2) for a team.
  Future<double> _loadTeamAvgHalf(int teamNumber) async {
    final k = _avgKey(teamNumber);
    final cached = _avgCache[k];
    if (cached != null) return cached;

    await _ensureTeamLoaded(teamNumber);
    final matches = _matchesCache[_teamKey(teamNumber)] ?? <TeamMatchSummary>[];

    // Filter matches based on the selected event context.
    final filtered = _selectedEvent == 'GENERAL'
        ? matches.where((m) => m.hasBeenPlayed == true).toList()
        : matches
        .where((m) => m.hasBeenPlayed == true)
        .where((m) => m.eventCode.trim() == _selectedEvent)
        .toList();

    // A team's estimated contribution is their average alliance score divided by 2.
    final avg = _computeAvgTotalPoints(filtered, teamNumber);
    final avgHalf = avg / 2.0;

    _avgCache[k] = avgHalf;
    return avgHalf;
  }

  Future<void> _maybeAutoLoadEventTeams() async {
    if (_selectedEvent == 'GENERAL') return;
    if (_mode != _SimMode.event) return;
    await _autoLoadTeamsFromSelectedEvent();
  }

  /// Automatically discovers teams participating in the same event as the user's team.
  Future<void> _autoLoadTeamsFromSelectedEvent() async {
    setState(() {
      _loadingEventTeams = true;
      _eventTeamsError = null;
      _eventTeams = [];
      _redPick1 = null;
      _redPick2 = null;
      _bluePick1 = null;
      _bluePick2 = null;
      _resetResults();
    });

    try {
      final tn = _myTeamNumber;
      if (tn == null) {
        setState(() {
          _loadingEventTeams = false;
          _eventTeamsError = 'Set your team number in Setup first.';
        });
        return;
      }

      final dynamic myDetail = await teamSearcherRepository.loadTeamDetail(
        teamNumber: tn,
        season: _season,
      );

      final matches = (myDetail.matches is List) ? List<TeamMatchSummary>.from(myDetail.matches) : <TeamMatchSummary>[];

      final eventMatches = matches.where((m) => m.eventCode.trim() == _selectedEvent).toList();
      if (eventMatches.isEmpty) {
        setState(() {
          _loadingEventTeams = false;
          _eventTeamsError = 'No matches found for your team at this event.';
        });
        return;
      }

      final set = <int>{};
      for (final m in eventMatches) {
        set.addAll(m.redTeams);
        set.addAll(m.blueTeams);
      }

      final list = set.toList()..sort();

      setState(() {
        _eventTeams = list;
        _loadingEventTeams = false;
        _eventTeamsError = null;
      });

      // Prefetch data for identified teams.
      for (final t in list.take(30)) {
        try {
          await _ensureTeamLoaded(t);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (e) {
      setState(() {
        _loadingEventTeams = false;
        _eventTeamsError = 'Could not load event teams.';
      });
    }
  }

  /// Core simulation logic: aggregates team averages to predict alliance totals.
  Future<void> _simulate() async {
    FocusScope.of(context).unfocus();

    final redTeams = _selectedAllianceTeams(red: true);
    final blueTeams = _selectedAllianceTeams(red: false);

    if (redTeams.length != 2 || blueTeams.length != 2) {
      setState(() => _inlineMessage = 'Select exactly 2 teams for Red and 2 teams for Blue.');
      return;
    }

    setState(() {
      _simulating = true;
      _inlineMessage = null;
      _teamAvg.clear();
      _redTotal = null;
      _blueTotal = null;
    });

    try {
      double redSum = 0;
      for (final t in redTeams) {
        await _ensureTeamLoaded(t);
        final avgHalf = await _loadTeamAvgHalf(t);
        _teamAvg[t] = avgHalf;
        redSum += avgHalf;
      }

      double blueSum = 0;
      for (final t in blueTeams) {
        await _ensureTeamLoaded(t);
        final avgHalf = await _loadTeamAvgHalf(t);
        _teamAvg[t] = avgHalf;
        blueSum += avgHalf;
      }

      setState(() {
        _redTotal = redSum;
        _blueTotal = blueSum;
        _simulating = false;
      });
    } catch (e) {
      setState(() {
        _simulating = false;
        _inlineMessage = 'Simulation failed. Check team numbers / API connection.';
      });
    }
  }

  /// Triggers a simulation automatically if enabled and all teams are selected.
  Future<void> _maybeAutoSimulate() async {
    if (!_autoSimulate) return;

    final redTeams = _selectedAllianceTeams(red: true);
    final blueTeams = _selectedAllianceTeams(red: false);

    if (redTeams.length == 2 && blueTeams.length == 2) {
      await _simulate();
    }
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
            if (_profileError != null) _smallInfoCard(theme, _profileError!, isError: true),
            _controlsCard(theme),
            const SizedBox(height: 14),
            if (_inlineMessage != null) _smallInfoCard(theme, _inlineMessage!, isError: false),
            const SizedBox(height: 14),
            _resultCard(theme),
            const SizedBox(height: 14),
            _teamBreakdownCard(theme),
          ],
        ),
      ),
    );
  }

  /// Configuration card for simulation parameters.
  Widget _controlsCard(ThemeData theme) {
    final bool general = _selectedEvent == 'GENERAL';
    final bool showEventModeToggle = !general;
    final bool showEventPick = !general && _mode == _SimMode.event;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              Icon(Icons.tune, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Setup',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Selection Mode Toggle (Event vs Manual)
          if (showEventModeToggle) ...[
            Row(
              children: [
                Expanded(
                  child: RadioListTile<_SimMode>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Event'),
                    value: _SimMode.event,
                    groupValue: _mode,
                    onChanged: _simulating ? null : (v) async {
                      if (v == null) return;
                      setState(() {
                        _mode = v;
                        _resetResults();
                        _inlineMessage = null;
                      });
                      await _maybeAutoLoadEventTeams();
                      await _maybeAutoSimulate();
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<_SimMode>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Manual'),
                    value: _SimMode.manual,
                    groupValue: _mode,
                    onChanged: _simulating ? null : (v) async {
                      if (v == null) return;
                      setState(() {
                        _mode = v;
                        _resetResults();
                        _inlineMessage = null;
                        _eventTeams = [];
                        _eventTeamsError = null;
                        _loadingEventTeams = false;
                        _redPick1 = null;
                        _redPick2 = null;
                        _bluePick1 = null;
                        _bluePick2 = null;
                      });
                      await _maybeAutoSimulate();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Season and Event Selectors
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
                      _season = v;
                      _matchesCache.clear();
                      _teamInfoCache.clear();
                      _avgCache.clear();
                      _eventTeams.clear();
                      _redPick1 = null;
                      _redPick2 = null;
                      _bluePick1 = null;
                      _bluePick2 = null;
                      _resetResults();
                      _inlineMessage = null;
                    });
                    await _maybeAutoLoadEventTeams();
                    await _maybeAutoSimulate();
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
                      _selectedEvent = v;
                      _avgCache.clear();
                      _resetResults();
                      _inlineMessage = null;
                      _applyGeneralRulesIfNeeded();
                    });
                    await _maybeAutoLoadEventTeams();
                    await _maybeAutoSimulate();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto simulate'),
            subtitle: const Text('Automatically run when all 4 teams are selected'),
            value: _autoSimulate,
            onChanged: (v) async {
              setState(() => _autoSimulate = v);
              await _maybeAutoSimulate();
            },
          ),

          const SizedBox(height: 10),

          // Alliance Team Pickers (Dynamic Dropdowns or Manual Input)
          if (showEventPick) ...[
            _eventLoadStatus(theme),
            const SizedBox(height: 12),
            Text('Red Alliance (2 teams)',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _eventPickRow(
              theme,
              a: _redPick1,
              b: _redPick2,
              onA: (v) async {
                setState(() { _redPick1 = v; _resetResults(); });
                await _maybeAutoSimulate();
              },
              onB: (v) async {
                setState(() { _redPick2 = v; _resetResults(); });
                await _maybeAutoSimulate();
              },
              accent: Colors.red,
            ),
            const SizedBox(height: 12),
            Text('Blue Alliance (2 teams)',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _eventPickRow(
              theme,
              a: _bluePick1,
              b: _bluePick2,
              onA: (v) async {
                setState(() { _bluePick1 = v; _resetResults(); });
                await _maybeAutoSimulate();
              },
              onB: (v) async {
                setState(() { _bluePick2 = v; _resetResults(); });
                await _maybeAutoSimulate();
              },
              accent: Colors.blue,
            ),
          ] else ...[
            if (general)
              _smallInfoCard(
                theme,
                'GENERAL mode: enter any team numbers. Averages are computed from all played matches in the season (then divided by 2).',
                isError: false,
              ),
            const SizedBox(height: 10),
            Text('Red Alliance (2 teams)',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _manualRow(_redManual, accent: Colors.red),
            const SizedBox(height: 12),
            Text('Blue Alliance (2 teams)',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _manualRow(_blueManual, accent: Colors.blue),
          ],

          const SizedBox(height: 12),

          // Control Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _simulating ? null : () {
                    for (final c in _redManual) c.clear();
                    for (final c in _blueManual) c.clear();
                    setState(() {
                      _redPick1 = null; _redPick2 = null;
                      _bluePick1 = null; _bluePick2 = null;
                      _resetResults(); _inlineMessage = null;
                    });
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _simulating ? null : _simulate,
                  icon: _simulating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Simulate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Status indicator for event-based team discovery.
  Widget _eventLoadStatus(ThemeData theme) {
    final disabled = _selectedEvent == 'GENERAL';
    if (disabled) return _smallInfoRow(theme, 'Select an event to load teams automatically.');
    if (_loadingEventTeams) return _smallInfoCard(theme, 'Loading teams from $_selectedEvent…', isError: false, showSpinner: true);
    if (_eventTeams.isEmpty) {
      if (_eventTeamsError != null) return _smallInfoCard(theme, _eventTeamsError!, isError: false);
      return _smallInfoRow(theme, 'No teams loaded yet.');
    }

    return Row(
      children: [
        Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Loaded ${_eventTeams.length} teams from $_selectedEvent',
            style: theme.textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: 'Reload teams',
          onPressed: (_loadingEventTeams || _simulating) ? null : _autoLoadTeamsFromSelectedEvent,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  /// Helper for a standard small info row.
  Widget _smallInfoRow(ThemeData theme, String text) {
    return Row(
      children: [
        Icon(Icons.info_outline, color: theme.hintColor, size: 18),
        const SizedBox(width: 8),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }

  /// Row of dropdown pickers for selecting alliance teams from an event roster.
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
      prefixIcon: Icon(Icons.confirmation_number, color: accent.withValues(alpha: 0.9)),
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

  /// Row of text fields for manual team number entry.
  Widget _manualRow(List<TextEditingController> ctrls, {required Color accent}) {
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      hintText: 'e.g. 23417',
      prefixIcon: Icon(Icons.confirmation_number, color: accent.withValues(alpha: 0.9)),
    );

    Future<void> handleChanged() async {
      _resetResults();
      _inlineMessage = null;
      final a = _parseTeam(ctrls[0].text);
      final b = _parseTeam(ctrls[1].text);
      for (final t in [a, b]) {
        if (t != null) try { await _ensureTeamLoaded(t); } catch (_) {}
      }
      if (mounted) setState(() {});
      await _maybeAutoSimulate();
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrls[0],
            keyboardType: TextInputType.number,
            decoration: deco('Team 1'),
            onChanged: (_) => handleChanged(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: ctrls[1],
            keyboardType: TextInputType.number,
            decoration: deco('Team 2'),
            onChanged: (_) => handleChanged(),
          ),
        ),
      ],
    );
  }

  /// Card displaying the predicted winner and calculated scores.
  Widget _resultCard(ThemeData theme) {
    final red = _redTotal;
    final blue = _blueTotal;
    String winner = '—';
    if (red != null && blue != null) {
      if (red > blue) winner = 'Red';
      else if (blue > red) winner = 'Blue';
      else winner = 'Tie';
    }
    
    // Calculate a basic uncertainty range.
    double? redLow, redHigh, blueLow, blueHigh;
    if (red != null) { redLow = max(0, red - 6); redHigh = red + 6; }
    if (blue != null) { blueLow = max(0, blue - 6); blueHigh = blue + 6; }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Result', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Winner: $winner', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _resultRow(theme, label: 'Red predicted', value: red, rangeLow: redLow, rangeHigh: redHigh, color: Colors.red),
          const SizedBox(height: 10),
          _resultRow(theme, label: 'Blue predicted', value: blue, rangeLow: blueLow, rangeHigh: blueHigh, color: Colors.blue),
          const SizedBox(height: 12),
          Text(
            _selectedEvent == 'GENERAL'
                ? 'Averages are computed from all played matches in season $_season, then divided by 2.'
                : 'Averages are computed from played matches at event $_selectedEvent (season $_season), then divided by 2.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Individual row showing prediction for one alliance.
  Widget _resultRow(ThemeData theme, {required String label, required double? value, required double? rangeLow, required double? rangeHigh, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color.withValues(alpha: 0.9), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value == null ? '—' : value.toStringAsFixed(1), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              if (rangeLow != null && rangeHigh != null)
                Text('Range: ${rangeLow.toStringAsFixed(0)}–${rangeHigh.toStringAsFixed(0)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }

  /// Breakdown card showing individual team contributions to the simulation.
  Widget _teamBreakdownCard(ThemeData theme) {
    final redTeams = _selectedAllianceTeams(red: true);
    final blueTeams = _selectedAllianceTeams(red: false);
    
    if (redTeams.isEmpty && blueTeams.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Text(
          _selectedEvent == 'GENERAL'
              ? 'Enter 2 Red teams and 2 Blue teams.'
              : (_mode == _SimMode.event ? 'Pick 2 vs 2 from the event roster.' : 'Enter 2 Red teams and 2 Blue teams.'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      );
    }

    Widget row(int team, {required bool isRed}) {
      final avg = _teamAvg[team];
      final name = _teamName(team);
      final title = name.isEmpty ? 'Team $team' : 'Team $team • $name';
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: (isRed ? Colors.red : Colors.blue).withValues(alpha: 0.9), shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            Text(avg == null ? 'Avg/2: —' : 'Avg/2: ${avg.toStringAsFixed(1)}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Team Averages (Avg/2)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(_selectedEvent, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
            ],
          ),
          const SizedBox(height: 12),
          Text('Red Alliance', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...redTeams.map((t) => row(t, isRed: true)),
          const SizedBox(height: 8),
          Text('Blue Alliance', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...blueTeams.map((t) => row(t, isRed: false)),
        ],
      ),
    );
  }

  /// Small notification or error card for inline feedback.
  Widget _smallInfoCard(ThemeData theme, String text, {required bool isError, bool showSpinner = false}) {
    final bg = isError ? theme.colorScheme.errorContainer.withValues(alpha: 0.22) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28);
    final border = isError ? theme.colorScheme.error.withValues(alpha: 0.25) : theme.dividerColor.withValues(alpha: 0.25);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
      child: Row(
        children: [
          if (showSpinner) ...[
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
          ] else ...[
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
