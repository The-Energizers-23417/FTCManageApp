import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/frontend/team_detail.dart';

import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// AllianceSelectionPage facilitates the selection process for tournament alliances.
/// It uses Ranking Points (RP) and customizable weighted metrics to help teams identify the best partners.
class AllianceSelectionPage extends StatefulWidget {
  const AllianceSelectionPage({super.key});

  @override
  State<AllianceSelectionPage> createState() => _AllianceSelectionPageState();
}

class _AllianceSelectionPageState extends State<AllianceSelectionPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  int _season = 2025;
  int? _myTeamNumber;

  List<String> _eventCodes = const ['ALL'];
  String _selectedEventCode = 'ALL';

  bool _loadingTeams = false;
  String? _teamsError;
  List<int> _eventTeams = [];

  // State management for the interactive draft process.
  final List<_DraftPick> _picks = [];
  final Set<int> _pickedTeams = {};
  int? _currentCaptain;

  // Weighting percentages for calculating the selection score.
  double wAutoPct = 100;
  double wTeleopPct = 100;
  double wEndPct = 100;
  double wPenPct = 100;

  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  // Local caches to optimize performance and reduce API redundancy.
  final Map<String, dynamic> _teamDetailCache = {};
  final Map<int, Map<String, dynamic>> _teamInfoCache = {};
  final Map<int, List<TeamMatchSummary>> _matchesCache = {};
  final Map<String, Map<int, _TeamStats>> _statsCache = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _search = _searchCtrl.text.trim());
    });
    _boot();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Entry point: loads profile data and initializes event selection.
  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not logged in.');

      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};

      final tnRaw = data['teamNumber'];
      _myTeamNumber = int.tryParse(tnRaw?.toString() ?? '');

      if (_myTeamNumber == null) {
        throw Exception('Team number missing in profile.');
      }

      await _ensureTeamLoaded(_myTeamNumber!);

      // Identify all unique event codes the team has participated in.
      final myMatches = _matchesCache[_myTeamNumber!] ?? <TeamMatchSummary>[];
      final codes = <String>{'ALL'};
      for (final m in myMatches) {
        final c = (m.eventCode).toString().trim();
        if (c.isNotEmpty) codes.add(c);
      }
      final sorted = codes.toList()
        ..sort((a, b) {
          if (a == 'ALL') return -1;
          if (b == 'ALL') return 1;
          return a.compareTo(b);
        });

      setState(() {
        _eventCodes = sorted;
        _selectedEventCode = _eventCodes.first;
        _loading = false;
      });

      await _loadEventTeams();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _detailKey(int team) => '$_season|$team';
  String _statsKey() => '$_season|$_selectedEventCode';

  /// Fetches and caches full team details from the repository.
  Future<void> _ensureTeamLoaded(int teamNumber) async {
    final k = _detailKey(teamNumber);
    if (_teamDetailCache.containsKey(k)) return;

    final dynamic detail = await teamSearcherRepository.loadTeamDetail(
      teamNumber: teamNumber,
      season: _season,
    );

    _teamDetailCache[k] = detail;

    final infoRaw = detail.teamInfo;
    final matchesRaw = detail.matches;

    _teamInfoCache[teamNumber] = (infoRaw is Map)
        ? Map<String, dynamic>.from(infoRaw as Map)
        : <String, dynamic>{};

    _matchesCache[teamNumber] = (matchesRaw is List)
        ? List<TeamMatchSummary>.from(matchesRaw)
        : <TeamMatchSummary>[];
  }

  /// Retrieves a team's name from the local cache.
  String _teamName(int teamNumber) {
    final info = _teamInfoCache[teamNumber];
    if (info == null) return '';
    return (info['name'] ?? info['nameFull'] ?? info['nameShort'] ?? '').toString().trim();
  }

  /// Determines if a specific team was on the Red alliance in a given match.
  bool _isTeamRedInMatch(TeamMatchSummary m, int teamNumber) {
    if (m.redTeams.contains(teamNumber)) return true;
    if (m.blueTeams.contains(teamNumber)) return false;
    return (m.alliance == 'Red');
  }

  /// Calculates the Ranking Points earned by a team in a specific match.
  int _rpForMatch(TeamMatchSummary m, int teamNumber) {
    if (m.hasBeenPlayed != true) return 0;

    final isRed = _isTeamRedInMatch(m, teamNumber);
    final myScore = isRed ? (m.red.totalPoints) : (m.blue.totalPoints);
    final oppScore = isRed ? (m.blue.totalPoints) : (m.red.totalPoints);

    int rp = 0;
    if (myScore > oppScore) rp += 2;
    if (myScore == oppScore) rp += 1;

    final alliance = isRed ? m.red : m.blue;
    if (alliance.movementRp) rp += 1;
    if (alliance.goalRp) rp += 1;
    if (alliance.patternRp) rp += 1;

    return rp;
  }

  double _pct(double v) => v / 100.0;

  /// Aggregates performance statistics for a team across filtered matches.
  _TeamStats _computeStatsForTeam(List<TeamMatchSummary> matches, int teamNumber) {
    final filtered = matches
        .where((m) => m.hasBeenPlayed == true)
        .where((m) => _selectedEventCode == 'ALL' ? true : (m.eventCode.trim() == _selectedEventCode))
        .toList();

    if (filtered.isEmpty) {
      return _TeamStats.empty(teamNumber);
    }

    int played = 0;
    int rpSum = 0;
    double autoSum = 0, teleopSum = 0, endSum = 0, penSum = 0;

    for (final m in filtered) {
      played++;
      rpSum += _rpForMatch(m, teamNumber);

      final isRed = _isTeamRedInMatch(m, teamNumber);
      final a = isRed ? m.red : m.blue;

      autoSum += a.autoPoints.toDouble();
      teleopSum += a.dcPoints.toDouble();
      endSum += a.dcBasePoints.toDouble();
      penSum += a.penaltyCommitted.toDouble();
    }

    final autoAvg = autoSum / played;
    final teleAvg = teleopSum / played;
    final endAvg = endSum / played;
    final penAvg = penSum / played;

    // Apply weights to compute a custom selection score.
    final weighted = (_pct(wAutoPct) * autoAvg) +
                     (_pct(wTeleopPct) * teleAvg) +
                     (_pct(wEndPct) * endAvg) -
                     (_pct(wPenPct) * penAvg);

    return _TeamStats(
      team: teamNumber,
      matches: played,
      rp: rpSum,
      autoAvg: autoAvg,
      teleopAvg: teleAvg,
      endAvg: endAvg,
      penCommittedAvg: penAvg,
      weightedScore: weighted,
    );
  }

  /// Returns cached stats for a team or computes them from match history.
  Future<_TeamStats> _getStatsForTeam(int teamNumber) async {
    final k = _statsKey();
    final cache = _statsCache.putIfAbsent(k, () => <int, _TeamStats>{});
    final existing = cache[teamNumber];
    if (existing != null) return existing;

    await _ensureTeamLoaded(teamNumber);
    final matches = _matchesCache[teamNumber] ?? <TeamMatchSummary>[];
    final stats = _computeStatsForTeam(matches, teamNumber);

    cache[teamNumber] = stats;
    return stats;
  }

  /// Identifies all unique teams participating in the current event context.
  Future<void> _loadEventTeams() async {
    final my = _myTeamNumber;
    if (my == null) return;

    setState(() {
      _loadingTeams = true;
      _teamsError = null;
      _eventTeams = [];
      _resetDraft();
    });

    try {
      await _ensureTeamLoaded(my);
      final myMatches = _matchesCache[my] ?? <TeamMatchSummary>[];

      // Discover teams through participation in shared matches.
      final seed = <int>{};
      for (final m in myMatches.where((m) => m.hasBeenPlayed == true)) {
        if (_selectedEventCode != 'ALL' && m.eventCode.trim() != _selectedEventCode) continue;
        seed.addAll(m.redTeams);
        seed.addAll(m.blueTeams);
      }

      if (seed.isEmpty) {
        throw Exception('No matches found for event $_selectedEventCode.');
      }

      final confirmed = <int>[];
      for (final t in seed) {
        try {
          await _ensureTeamLoaded(t);
          final matches = _matchesCache[t] ?? <TeamMatchSummary>[];
          final has = matches.any((m) {
            if (!m.hasBeenPlayed) return false;
            if (_selectedEventCode == 'ALL') return true;
            return m.eventCode.trim() == _selectedEventCode;
          });
          if (has) confirmed.add(t);
        } catch (_) {}
      }

      confirmed.sort();

      setState(() {
        _eventTeams = confirmed;
        _loadingTeams = false;
      });

      // Background-fetch stats for the top teams.
      for (final t in confirmed.take(25)) {
        try {
          await _getStatsForTeam(t);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (e) {
      setState(() {
        _loadingTeams = false;
        _teamsError = e.toString();
      });
    }
  }

  /// Resets the selection state.
  void _resetDraft() {
    _picks.clear();
    _pickedTeams.clear();
    _currentCaptain = null;
  }

  /// Logic to determine which team is currently picking based on RP rank.
  Future<void> _recomputeCurrentCaptain() async {
    if (_eventTeams.isEmpty) {
      setState(() => _currentCaptain = null);
      return;
    }

    // Sort all teams by RP to establish selection priority.
    final stats = await Future.wait(_eventTeams.map(_getStatsForTeam));
    stats.sort((a, b) => b.rp.compareTo(a.rp));

    final captainsWhoPicked = _picks.map((p) => p.captain).toSet();

    int? picker;
    for (final s in stats) {
      final team = s.team;
      // Captains cannot have been picked as partners already.
      if (_pickedTeams.contains(team)) continue;
      // Captains cannot pick again if they have already made their choice.
      if (captainsWhoPicked.contains(team)) continue;
      picker = team;
      break;
    }

    setState(() => _currentCaptain = picker);
  }

  /// Finalizes a pick for the current captain.
  Future<void> _pickTeam(int partnerTeam) async {
    final captain = _currentCaptain;
    if (captain == null) return;

    if (partnerTeam == captain) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("A captain cannot pick their own team.")),
      );
      return;
    }

    if (_pickedTeams.contains(partnerTeam) || _pickedTeams.contains(captain)) {
      return;
    }

    setState(() {
      _picks.add(_DraftPick(captain: captain, partner: partnerTeam));
      _pickedTeams.add(captain);
      _pickedTeams.add(partnerTeam);
    });

    await _recomputeCurrentCaptain();
  }

  /// Undoes the last recorded pick.
  void _undoLastPick() {
    if (_picks.isEmpty) return;

    setState(() {
      final last = _picks.removeLast();
      _pickedTeams.remove(last.captain);
      _pickedTeams.remove(last.partner);
    });

    _recomputeCurrentCaptain();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Alliance Selection',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
        showFooter: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _boot,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            if (_error != null) _errorCard(theme, _error!),

            _setupCard(theme),
            const SizedBox(height: 12),

            _weightsCard(theme),
            const SizedBox(height: 12),

            _draftStatusCard(theme),
            const SizedBox(height: 12),

            _teamListCard(theme),
          ],
        ),
      ),
    );
  }

  /// Configuration card for season and event selection.
  Widget _setupCard(ThemeData theme) {
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
              Icon(Icons.settings, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Setup',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Reload Teams',
                onPressed: _loadingTeams ? null : () async => _loadEventTeams(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),

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
                  onChanged: _loadingTeams
                      ? null
                      : (v) async {
                    if (v == null) return;
                    setState(() {
                      _season = v;
                      _teamDetailCache.clear();
                      _teamInfoCache.clear();
                      _matchesCache.clear();
                      _statsCache.clear();
                      _eventTeams = [];
                      _teamsError = null;
                      _resetDraft();
                    });
                    await _boot();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedEventCode,
                  decoration: const InputDecoration(
                    labelText: 'Event',
                    prefixIcon: Icon(Icons.flag),
                  ),
                  items: _eventCodes
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: _loadingTeams
                      ? null
                      : (v) async {
                    if (v == null) return;
                    setState(() {
                      _selectedEventCode = v;
                      _statsCache.remove(_statsKey());
                      _eventTeams = [];
                      _teamsError = null;
                      _resetDraft();
                    });
                    await _loadEventTeams();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              if (_loadingTeams)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _loadingTeams
                      ? 'Loading Teams...'
                      : _eventTeams.isEmpty
                      ? 'No teams available.'
                      : 'Found ${_eventTeams.length} Teams',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),

          if (_teamsError != null) ...[
            const SizedBox(height: 6),
            Text(_teamsError!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  /// Card for configuring custom weights for team analysis.
  Widget _weightsCard(ThemeData theme) {
    Widget pctSlider(String label, double value, ValueChanged<double> onChanged) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.toStringAsFixed(0)}%',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Slider(
            value: value,
            min: 0,
            max: 200,
            divisions: 20,
            label: '${value.toStringAsFixed(0)}%',
            onChanged: _loadingTeams ? null : (v) => onChanged(v),
            onChangeEnd: (_) {
              setState(() { _statsCache.remove(_statsKey()); });
            },
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Custom Sorting Weights (0–200%)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Draft order is RP-based. These weights adjust the recommended partner ranking.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),

          pctSlider('Auto', wAutoPct, (v) => setState(() => wAutoPct = v)),
          pctSlider('Teleop', wTeleopPct, (v) => setState(() => wTeleopPct = v)),
          pctSlider('Endgame', wEndPct, (v) => setState(() => wEndPct = v)),
          pctSlider('Penalties (Negative)', wPenPct, (v) => setState(() => wPenPct = v)),

          const SizedBox(height: 10),

          Text(
            'Formula: Score = (Auto × ${wAutoPct.toInt()}%) + (Teleop × ${wTeleopPct.toInt()}%) + '
                '(Endgame × ${wEndPct.toInt()}%) − (Penalties × ${wPenPct.toInt()}%)',
            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  /// Card tracking the current state of the alliance selection draft.
  Widget _draftStatusCard(ThemeData theme) {
    final picker = _currentCaptain;

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
              Icon(Icons.emoji_events, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Draft Status',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _picks.isEmpty ? null : _undoLastPick,
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  setState(() => _resetDraft());
                  await _recomputeCurrentCaptain();
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Indicator for whose turn it is to select.
          FutureBuilder<void>(
            future: _recomputeCurrentCaptain(),
            builder: (context, snap) {
              final capText = picker == null ? 'None' : _labelForTeam(picker);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin_circle),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Currently Picking: $capText',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (picker != null)
                      IconButton(
                        tooltip: 'Captain Info',
                        onPressed: () => _openTeamDetail(picker),
                        icon: const Icon(Icons.info_outline),
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          if (_picks.isEmpty)
            Text(
              'Select teams from the list below to build alliances.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recorded Picks', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final p in _picks) _pickRow(theme, p),
              ],
            ),
        ],
      ),
    );
  }

  /// UI row for an individual draft selection.
  Widget _pickRow(ThemeData theme, _DraftPick p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_labelForTeam(p.captain)}  →  ${_labelForTeam(p.partner)}',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Captain Details',
            onPressed: () => _openTeamDetail(p.captain),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Partner Details',
            onPressed: () => _openTeamDetail(p.partner),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }

  /// Scrollable list of available teams, ranked by the computed selection score.
  Widget _teamListCard(ThemeData theme) {
    final availableTeams = _eventTeams.where((t) => !_pickedTeams.contains(t)).toList();

    final query = _search.toLowerCase();
    List<int> filtered = availableTeams;

    if (query.isNotEmpty) {
      filtered = availableTeams.where((t) {
        final name = _teamName(t).toLowerCase();
        return t.toString().contains(query) || name.contains(query);
      }).toList();
    }

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
              Icon(Icons.list_alt, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Available Teams',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${filtered.length} remaining',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search by Number or Name',
              prefixIcon: Icon(Icons.search),
            ),
          ),

          const SizedBox(height: 12),

          if (_eventTeams.isEmpty)
            Text(
              'Select an event to load team data.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            )
          else if (_currentCaptain == null)
            Text(
              'All teams selected.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            )
          else
            FutureBuilder<List<_TeamRowVM>>(
              future: _buildTeamRows(filtered),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final rows = snap.data!;
                // Primary sorting based on the custom weighted score.
                rows.sort((a, b) => b.stats.weightedScore.compareTo(a.stats.weightedScore));

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _teamTile(theme, rows[i]),
                );
              },
            ),
        ],
      ),
    );
  }

  /// Aggregates data for multiple teams into view models for the list.
  Future<List<_TeamRowVM>> _buildTeamRows(List<int> teams) async {
    final out = <_TeamRowVM>[];
    for (final t in teams) {
      try {
        final stats = await _getStatsForTeam(t);
        out.add(_TeamRowVM(team: t, name: _teamName(t), stats: stats));
      } catch (_) {
        out.add(_TeamRowVM(team: t, name: _teamName(t), stats: _TeamStats.empty(t)));
      }
    }
    return out;
  }

  /// Individual team tile in the ranking list.
  Widget _teamTile(ThemeData theme, _TeamRowVM vm) {
    final captain = _currentCaptain;
    final disabled = captain == null;

    final name = vm.name.trim();
    final title = name.isEmpty ? 'Team ${vm.team}' : 'Team ${vm.team} • $name';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'RP: ${vm.stats.rp} | Score: ${vm.stats.weightedScore.toStringAsFixed(1)} \n'
              'Avg: A:${vm.stats.autoAvg.toStringAsFixed(1)} T:${vm.stats.teleopAvg.toStringAsFixed(1)} '
              'E:${vm.stats.endAvg.toStringAsFixed(1)} P:${vm.stats.penCommittedAvg.toStringAsFixed(1)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'View Details',
              onPressed: () => _openTeamDetail(vm.team),
              icon: const Icon(Icons.info_outline),
            ),
            FilledButton(
              onPressed: (disabled || vm.team == captain) ? null : () async {
                await _pickTeam(vm.team);
              },
              child: const Text('Pick'),
            ),
          ],
        ),
        onTap: (disabled || vm.team == captain) ? null : () async {
          await _pickTeam(vm.team);
        },
      ),
    );
  }

  String _labelForTeam(int t) {
    final name = _teamName(t);
    return name.isEmpty ? t.toString() : '$t • $name';
  }

  void _openTeamDetail(int team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamDetailPage(
          teamNumber: team,
          teamName: _teamName(team),
          season: _season,
        ),
      ),
    );
  }

  Widget _errorCard(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(error, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Data model for a pick made during the draft.
class _DraftPick {
  final int captain;
  final int partner;
  const _DraftPick({required this.captain, required this.partner});
}

/// Consolidated performance statistics for a single team.
class _TeamStats {
  final int team;
  final int matches;
  final int rp;

  final double autoAvg;
  final double teleopAvg;
  final double endAvg;
  final double penCommittedAvg;

  final double weightedScore;

  const _TeamStats({
    required this.team,
    required this.matches,
    required this.rp,
    required this.autoAvg,
    required this.teleopAvg,
    required this.endAvg,
    required this.penCommittedAvg,
    required this.weightedScore,
  });

  static _TeamStats empty(int team) => _TeamStats(
    team: team,
    matches: 0,
    rp: 0,
    autoAvg: 0,
    teleopAvg: 0,
    endAvg: 0,
    penCommittedAvg: 0,
    weightedScore: 0,
  );
}

/// View model for a team list row.
class _TeamRowVM {
  final int team;
  final String name;
  final _TeamStats stats;
  const _TeamRowVM({required this.team, required this.name, required this.stats});
}
