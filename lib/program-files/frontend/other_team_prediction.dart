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
/// It features a smart back-button flow: Team View -> Search Results -> Dashboard.
class OtherTeamPredictionPage extends StatefulWidget {
  const OtherTeamPredictionPage({super.key});

  @override
  State<OtherTeamPredictionPage> createState() => _OtherTeamPredictionPageState();
}

class _OtherTeamPredictionPageState extends State<OtherTeamPredictionPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  final TextEditingController _teamController = TextEditingController();

  bool _loading = false;
  bool _searching = false;
  String? _error;
  int _season = 2025;

  int? _teamNumber;
  Map<String, dynamic>? _teamInfo;
  List<TeamMatchSummary> _matches = [];
  List<Map<String, dynamic>> _searchResults = [];

  OtherDashboardMode _mode = OtherDashboardMode.allMatches;
  bool _showChart = true;
  OtherDashboardComputed? _computed;

  int _currentIndex = 0;
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
    } catch (_) {}
  }

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
    await _db.collection('users').doc(user.uid).set(
      {'favoriteTeams': next},
      SetOptions(merge: true),
    );
  }

  bool get _isFavorite => _teamNumber != null && _favorites.contains(_teamNumber);

  Future<void> _performSearch() async {
    FocusScope.of(context).unfocus();
    final query = _teamController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final tn = int.tryParse(query);
      if (tn != null) {
        await _loadByNumber(tn);
        setState(() => _searching = false);
        return;
      }

      final results = await teamSearcherRepository.searchTeams(query);
      setState(() {
        _searchResults = results;
        _searching = false;
        if (results.isEmpty) {
          _error = 'No teams found matching "$query".';
        } else {
          _teamNumber = null;
          _computed = null;
        }
      });
    } catch (e) {
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadByNumber(int tn) async {
    setState(() {
      _loading = true;
      _error = null;
      _teamNumber = tn;
      _teamController.text = tn.toString();
    });

    try {
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

    // Handle back button to go from Team View -> Results List instead of popping route
    return PopScope(
      canPop: _teamNumber == null && _searchResults.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          if (_teamNumber != null) {
            _teamNumber = null;
            _computed = null;
          } else if (_searchResults.isNotEmpty) {
            _searchResults = [];
          }
        });
      },
      child: Scaffold(
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
            : RefreshIndicator(
          onRefresh: () async {
            if (_teamNumber != null) await _loadByNumber(_teamNumber!);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    children: [
                      _searchCard(theme, primaryColor),
                      const SizedBox(height: 16),
      
                      if (_error != null) _errorView(theme, _error!),
      
                      if (_searching) ...[
                        const SizedBox(height: 32),
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('Searching for teams...'),
                      ] else if (_searchResults.isNotEmpty && _teamNumber == null) ...[
                        _resultsHeader(theme),
                        const SizedBox(height: 12),
                        _buildResultsList(theme, primaryColor),
                      ] else if (_teamNumber != null && _computed != null) ...[
                        _topHeader(theme, primaryColor),
                        const SizedBox(height: 20),
                        _statsOverviewGrid(theme, _computed!.prediction),
                        const SizedBox(height: 20),
                        if (_showChart)
                          _chartCard(
                            theme,
                            primaryColor,
                            _computed!.series,
                            _computed!.prediction,
                            isDark,
                          ),
                        if (_showChart) const SizedBox(height: 20),
                        _seasonSummaryCard(theme, _computed!),
                        const SizedBox(height: 20),
                        _matchesByEventList(theme, primaryColor, _computed!),
                      ] else if (!_searching && _error == null) ...[
                        _emptyState(theme, 'Search for a team name or number to view performance predictions.'),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchCard(ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Find Team', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Autocomplete<Map<String, dynamic>>(
            displayStringForOption: (team) {
              final number = team['number'] ?? team['teamNumber'] ?? '';
              final name = team['nameShort'] ?? team['shortName'] ?? team['nameFull'] ?? team['name'] ?? '';
              return "$number - $name";
            },
            optionsBuilder: (TextEditingValue textEditingValue) async {
              if (textEditingValue.text.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
              return await teamSearcherRepository.searchTeams(textEditingValue.text);
            },
            onSelected: (selection) {
              final tnRaw = selection['number'] ?? selection['teamNumber'];
              final tn = int.tryParse(tnRaw.toString());
              if (tn != null) _loadByNumber(tn);
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (_teamController.text != controller.text && controller.text.isEmpty && _teamNumber != null) {
                controller.text = _teamController.text;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: 'Team Number or Name',
                  hintText: 'e.g. 14496 or "Decode"',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            controller.clear();
                            _teamController.clear();
                            setState(() {
                              _searchResults = [];
                              _teamNumber = null;
                              _computed = null;
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (val) => _teamController.text = val,
                onSubmitted: (val) => _performSearch(),
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _performSearch,
              icon: const Icon(Icons.search),
              label: const Text('Search & List Results'),
            ),
          ),
          if (_favorites.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in _favorites.take(8))
                  ActionChip(
                    avatar: const Icon(Icons.star, size: 16),
                    label: Text('Team $n'),
                    onPressed: () => _loadByNumber(n),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultsHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.list, color: theme.colorScheme.primary, size: 20),
        const SizedBox(width: 8),
        Text('Matching Teams (${_searchResults.length})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildResultsList(ThemeData theme, Color primaryColor) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final team = _searchResults[index];
        final number = team['number'] ?? team['teamNumber'] ?? '';
        final name = team['nameShort'] ?? team['shortName'] ?? team['nameFull'] ?? team['name'] ?? '';
        final city = team['city'] ?? '';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: primaryColor.withOpacity(0.1), child: Text(number.toString(), style: TextStyle(color: primaryColor, fontSize: 12, fontWeight: FontWeight.bold))),
            title: Text(name.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: city.isNotEmpty ? Text(city.toString()) : null,
            trailing: const Icon(Icons.analytics_outlined),
            onTap: () {
              final tn = int.tryParse(number.toString());
              if (tn != null) _loadByNumber(tn);
            },
          ),
        );
      },
    );
  }

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
                  Text('Team ${_teamNumber!}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 4),
                  Text(name, style: theme.textTheme.titleMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(tooltip: _isFavorite ? 'Remove favorite' : 'Add favorite', onPressed: _toggleFavorite, icon: Icon(_isFavorite ? Icons.star : Icons.star_border), color: _isFavorite ? Colors.amber : theme.iconTheme.color),
            _seasonSelector(theme),
          ],
        ),
        const SizedBox(height: 16),
        _controlBar(theme),
      ],
    );
  }

  Widget _seasonSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _season,
          isDense: true,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          items: const [DropdownMenuItem(value: 2024, child: Text('2024')), DropdownMenuItem(value: 2025, child: Text('2025')), DropdownMenuItem(value: 2026, child: Text('2026'))],
          onChanged: (v) async { if (v == null) return; setState(() => _season = v); if (_teamNumber != null) await _loadByNumber(_teamNumber!); },
        ),
      ),
    );
  }

  Widget _controlBar(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SegmentedButton<OtherDashboardMode>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: OtherDashboardMode.allMatches, label: Text('All Matches')), ButtonSegment(value: OtherDashboardMode.lastEventOnly, label: Text('Last Event'))],
            selected: {_mode},
            onSelectionChanged: (s) { setState(() { _mode = s.first; _recompute(); }); },
          ),
          const SizedBox(width: 12),
          FilterChip(label: const Text('Chart'), selected: _showChart, onSelected: (v) => setState(() => _showChart = v)),
          const SizedBox(width: 12),
          ActionChip(
            avatar: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Results List'),
            onPressed: () => setState(() { _teamNumber = null; _computed = null; }),
          ),
        ],
      ),
    );
  }

  Widget _statsOverviewGrid(ThemeData theme, PredictionResult p) {
    final trend = p.trendPerMatch;
    Color trendColor = theme.colorScheme.onSurface;
    IconData trendIcon = Icons.remove;
    if (trend > 0.5) { trendColor = Colors.green; trendIcon = Icons.trending_up; }
    else if (trend < -0.5) { trendColor = Colors.red; trendIcon = Icons.trending_down; }
    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
      return GridView.count(crossAxisCount: crossAxisCount, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.6, children: [_kpiCard(theme, 'Predicted Score', p.predictedScore.toStringAsFixed(1), icon: Icons.psychology), _kpiCard(theme, 'Trend / Match', (trend > 0 ? '+' : '') + trend.toStringAsFixed(1), valueColor: trendColor, customIcon: Icon(trendIcon, color: trendColor, size: 20)), _kpiCard(theme, 'Auto Avg', p.predictedAuto?.toStringAsFixed(1) ?? '-', icon: Icons.smart_toy), _kpiCard(theme, 'TeleOp Avg', p.predictedTeleop?.toStringAsFixed(1) ?? '-', icon: Icons.gamepad)]);
    });
  }

  Widget _kpiCard(ThemeData theme, String label, String value, {IconData? icon, Color? valueColor, Widget? customIcon}) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))], border: Border.all(color: theme.dividerColor.withOpacity(0.5))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(label, style: theme.textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis)), if (customIcon != null) customIcon else if (icon != null) Icon(icon, size: 18, color: theme.colorScheme.primary.withOpacity(0.7))]), Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: valueColor))]));
  }

  Widget _chartCard(ThemeData theme, Color primaryColor, List<ScorePoint> series, PredictionResult p, bool isDark) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.dividerColor.withOpacity(0.5)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text('Score Progression', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 16), SizedBox(height: 220, child: InteractiveScoreChart(series: series, predictedNext: p.predictedScore, low: p.low, high: p.high, axisColor: theme.dividerColor, textStyle: theme.textTheme.bodySmall, lineColor: primaryColor, backgroundColor: theme.colorScheme.surface))]));
  }

  Widget _seasonSummaryCard(ThemeData theme, OtherDashboardComputed c) {
    int totalWins = 0, totalLosses = 0, totalTies = 0, maxScore = 0;
    for (var s in c.eventStatsByCode.values) { totalWins += s.wins; totalLosses += s.losses; totalTies += s.ties; if (s.maxScore > maxScore) maxScore = s.maxScore; }
    final totalPlayed = totalWins + totalLosses + totalTies;
    final winRate = totalPlayed == 0 ? 0.0 : (totalWins / totalPlayed * 100);
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.dividerColor.withOpacity(0.5)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_summaryStat(theme, 'Record', '$totalWins-$totalLosses-$totalTies', Colors.orange), _summaryStat(theme, 'Win Rate', '${winRate.toStringAsFixed(1)}%', Colors.green), _summaryStat(theme, 'High Score', '$maxScore', Colors.purple)]));
  }

  Widget _summaryStat(ThemeData theme, String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color)), const SizedBox(height: 4), Text(label, style: theme.textTheme.bodySmall)]);
  }

  Widget _matchesByEventList(ThemeData theme, Color primaryColor, OtherDashboardComputed c) {
    final tn = _teamNumber;
    if (tn == null) return const SizedBox.shrink();
    final grouped = <String, List<TeamMatchSummary>>{};
    for (final m in c.filteredMatches) { grouped.putIfAbsent(m.eventCode, () => []).add(m); }
    if (grouped.isEmpty) return _emptyState(theme, 'No matches found.');
    final eventCodes = grouped.keys.toList();
    eventCodes.sort((a, b) { final sa = c.eventStatsByCode[a]?.firstMatchTime ?? DateTime(0); final sb = c.eventStatsByCode[b]?.firstMatchTime ?? DateTime(0); return sb.compareTo(sa); });
    return Column(children: eventCodes.map((code) { final matches = grouped[code]!; matches.sort((a, b) => (b.scheduledTime ?? DateTime(0)).compareTo(a.scheduledTime ?? DateTime(0))); final eventStat = c.eventStatsByCode[code]; return Card(margin: const EdgeInsets.only(bottom: 12), elevation: 0, color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerColor.withOpacity(0.3))), child: ExpansionTile(initiallyExpanded: eventCodes.first == code, leading: Icon(Icons.event, color: primaryColor), title: Text('Event $code', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), subtitle: eventStat != null ? Text('Avg: ${eventStat.avgScore.toStringAsFixed(1)} • Record: ${eventStat.wins}-${eventStat.losses}-${eventStat.ties}') : null, childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12), children: matches.map((m) => _matchCard(theme, m, tn)).toList())); }).toList());
  }

  Widget _matchCard(ThemeData theme, TeamMatchSummary m, int teamNumber) {
    final v = OtherScoreCalculator.viewForMatch(teamNumber: teamNumber, m: m);
    final isWin = (v.teamScore ?? 0) > (v.oppScore ?? 0);
    final isTie = v.teamScore == v.oppScore;
    Color statusColor = v.hasBeenPlayed ? (isWin ? Colors.green : (isTie ? Colors.orange : Colors.red)) : theme.dividerColor;
    return Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: v.teamIsRed ? Colors.red.withOpacity(0.05) : Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.dividerColor.withOpacity(0.5))), child: ExpansionTile(leading: Container(width: 4, height: 32, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2))), title: Text('Match ${m.matchId}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)), subtitle: v.hasBeenPlayed ? Text('R ${m.redScore} - B ${m.blueScore}') : const Text('Upcoming'), children: [Padding(padding: const EdgeInsets.all(16), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Auto:'), Text('${v.autoPoints} pts')]), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TeleOp:'), Text('${v.dcPoints} pts')]), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('RP Total:'), Text('${v.rpTotal}')])]))]));
  }

  Widget _emptyState(ThemeData theme, String text) {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [Icon(Icons.search, size: 48, color: theme.disabledColor), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center, style: TextStyle(color: theme.disabledColor))])));
  }

  Widget _errorView(ThemeData theme, String error) {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error), const SizedBox(height: 16), const Text('Search Error', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const SizedBox(height: 8), Text(error, textAlign: TextAlign.center), const SizedBox(height: 24), FilledButton(onPressed: () => setState(() => _error = null), child: const Text('Clear'))])));
  }
}

// ───────────────────────── Interactive Chart Implementation ─────────────────────────

class InteractiveScoreChart extends StatefulWidget {
  final List<ScorePoint> series;
  final double predictedNext;
  final double low;
  final double high;
  final Color axisColor;
  final TextStyle? textStyle;
  final Color lineColor;
  final Color backgroundColor;

  const InteractiveScoreChart({super.key, required this.series, required this.predictedNext, required this.low, required this.high, required this.axisColor, this.textStyle, required this.lineColor, required this.backgroundColor});

  @override
  State<InteractiveScoreChart> createState() => _InteractiveScoreChartState();
}

class _InteractiveScoreChartState extends State<InteractiveScoreChart> {
  int? _hoverIndex;
  @override
  Widget build(BuildContext context) {
    if (widget.series.length < 2) return Center(child: Text('Not enough data', style: widget.textStyle));
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onHorizontalDragUpdate: (details) => _updateHover(details.localPosition.dx, constraints.maxWidth),
        onHorizontalDragEnd: (_) => setState(() => _hoverIndex = null),
        child: CustomPaint(size: Size(constraints.maxWidth, constraints.maxHeight), painter: _ScoreChartPainter(series: widget.series, predictedNext: widget.predictedNext, low: widget.low, high: widget.high, axisColor: widget.axisColor, textStyle: widget.textStyle, lineColor: widget.lineColor, hoverIndex: _hoverIndex, backgroundColor: widget.backgroundColor)),
      );
    });
  }
  void _updateHover(double dx, double width) {
    final w = max(1.0, width - 42.0);
    double t = ((dx - 30.0) / w).clamp(0.0, 1.0);
    setState(() => _hoverIndex = (t * widget.series.length).round());
  }
}

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

  _ScoreChartPainter({required this.series, required this.predictedNext, required this.low, required this.high, required this.axisColor, this.textStyle, required this.lineColor, this.hoverIndex, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    final padL = 30.0; final padR = 12.0; final padT = 20.0; final padB = 20.0;
    final w = max(1.0, size.width - padL - padR);
    final h = max(1.0, size.height - padT - padB);

    final scores = series.map((p) => p.score).toList();
    double minY = min(scores.reduce(min), low);
    double maxY = max(scores.reduce(max), high);
    final range = maxY - minY;
    maxY += range * 0.1 + 5; minY = max(0, minY - range * 0.1 - 5);

    double xOf(int idx) => padL + (idx / series.length) * w;
    double yOf(double v) => padT + (1 - (v - minY) / (maxY - minY)) * h;

    final linePaint = Paint()..color = lineColor..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path();
    if (series.isNotEmpty) {
      path.moveTo(xOf(0), yOf(series[0].score));
      for (int i = 0; i < series.length - 1; i++) {
        final x1 = xOf(i); final y1 = yOf(series[i].score);
        final x2 = xOf(i+1); final y2 = yOf(series[i+1].score);
        path.cubicTo((x1+x2)/2, y1, (x1+x2)/2, y2, x2, y2);
      }
    }
    canvas.drawPath(path, linePaint);

    for (int i = 0; i < series.length; i++) {
      canvas.drawCircle(Offset(xOf(i), yOf(series[i].score)), 3, linePaint);
    }

    final predX = xOf(series.length);
    canvas.drawCircle(Offset(predX, yOf(predictedNext)), 4, linePaint..color = lineColor.withOpacity(0.5));
    canvas.drawLine(Offset(predX, yOf(low)), Offset(predX, yOf(high)), linePaint..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _ScoreChartPainter oldDelegate) => true;
}
