import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-connection/api_global.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart' as scout;

import 'package:ftcmanageapp/program-files/backend/settings/battery/calculation_battery.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';

import 'package:ftcmanageapp/program-files/frontend/about_us.dart';
import 'package:ftcmanageapp/program-files/frontend/alliance_selection.dart';
import 'package:ftcmanageapp/program-files/frontend/auto_path_route.dart';
import 'package:ftcmanageapp/program-files/frontend/auto_path_visualizer.dart';
import 'package:ftcmanageapp/program-files/frontend/battery.dart';
import 'package:ftcmanageapp/program-files/frontend/feedback.dart';
import 'package:ftcmanageapp/program-files/frontend/help.dart';
import 'package:ftcmanageapp/program-files/frontend/hour_registration.dart';
import 'package:ftcmanageapp/program-files/frontend/match_simulator.dart';
import 'package:ftcmanageapp/program-files/frontend/match_simulator_prediction.dart';
import 'package:ftcmanageapp/program-files/frontend/mini_game.dart';
import 'package:ftcmanageapp/program-files/frontend/other_team_prediction.dart';
import 'package:ftcmanageapp/program-files/frontend/own_team_score.dart';
import 'package:ftcmanageapp/program-files/frontend/pit_interview_practice.dart';
import 'package:ftcmanageapp/program-files/frontend/point_estimate_calculator.dart';
import 'package:ftcmanageapp/program-files/frontend/portfolio.dart';
import 'package:ftcmanageapp/program-files/frontend/practice_calculator.dart';
import 'package:ftcmanageapp/program-files/frontend/pre_match_checklist.dart';
import 'package:ftcmanageapp/program-files/frontend/resource_hub.dart';
import 'package:ftcmanageapp/program-files/frontend/robot_config.dart';
import 'package:ftcmanageapp/program-files/frontend/scrumboard.dart';
import 'package:ftcmanageapp/program-files/frontend/setup.dart';
import 'package:ftcmanageapp/program-files/frontend/business_dashboard.dart';
import 'package:ftcmanageapp/program-files/frontend/income_manager.dart';
import 'package:ftcmanageapp/program-files/frontend/expense_manager.dart';
import 'package:ftcmanageapp/program-files/frontend/sponsor_manager.dart';
import 'package:ftcmanageapp/program-files/frontend/event_manager.dart';
import 'package:ftcmanageapp/program-files/frontend/tasklist_team.dart';
import 'package:ftcmanageapp/program-files/frontend/team_searcher.dart';
import 'package:ftcmanageapp/program-files/frontend/widgets/dashboard_tile.dart';

/// Definition for a single tile on the dashboard.
class _DashboardTileDef {
  final String label;
  final IconData icon;
  final void Function(BuildContext context)? onTap;

  bool get comingSoon => onTap == null;

  const _DashboardTileDef({
    required this.label,
    required this.icon,
    this.onTap,
  });
}

/// Represents a grouped section of tiles on the dashboard.
class _DashboardSection {
  final String title;
  final IconData icon;
  final List<_DashboardTileDef> tiles;

  const _DashboardSection({
    required this.title,
    required this.icon,
    required this.tiles,
  });
}

/// Helper class to summarize battery health status.
class _BatterySummary {
  final int total, full, ok, low, critical;
  const _BatterySummary({
    this.total = 0,
    this.full = 0,
    this.ok = 0,
    this.low = 0,
    this.critical = 0,
  });
}

/// Container for basic team information and match history.
class TeamDetail {
  final Map<String, dynamic> teamInfo;
  final List<scout.TeamMatchSummary> matches;

  TeamDetail({required this.teamInfo, required this.matches});
}

/// The main dashboard page acting as the hub for all app features.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Header and identity state
  bool _loadingHeader = true;
  String? _headerError;
  int? _teamNumber;
  String? _teamName;
  final int _season = 2025;

  // Real-time data subscriptions and computed state
  StreamSubscription? _userDocSub;
  _BatterySummary _batterySummary = const _BatterySummary();
  scout.TeamMatchSummary? _nextMatch;
  String? _eventCode;

  // --- Easter Egg State ---
  int _easterEggTaps = 0;
  bool _overclockMode = false;
  Timer? _overclockTimer;
  Color _overclockColor = Colors.blue;
  double _rotation = 0;

  @override
  void initState() {
    super.initState();
    _loadWelcomeData();
    _listenToUserData();
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _overclockTimer?.cancel();
    super.dispose();
  }

  /// Triggers the "Overclock Mode" (Party Mode) easter egg.
  void _handleEasterEggTap() {
    _easterEggTaps++;
    if (_easterEggTaps >= 7) {
      _activateOverclockMode();
    }
  }

  /// Activates the "Overclock Mode" easter egg with visual effects.
  void _activateOverclockMode() {
    if (_overclockMode) return;
    
    setState(() {
      _overclockMode = true;
      _easterEggTaps = 0;
    });

    _overclockTimer?.cancel();
    _overclockTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        // Cycle through rainbow colors for the easter egg effect.
        _overclockColor = Colors.primaries[math.Random().nextInt(Colors.primaries.length)];
        _rotation += 0.4;
      });
    });

    // Automatically deactivate after 5 seconds.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _overclockTimer?.cancel();
        setState(() {
          _overclockMode = false;
          _rotation = 0;
        });
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚡ DECODE OVERCLOCK MODE ACTIVATED! ⚡'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Sets up a real-time listener for user data to update battery status and other dynamic info.
  void _listenToUserData() {
    final user = _auth.currentUser;
    if (user == null) return;

    _userDocSub?.cancel();
    _userDocSub = _db.collection('users').doc(user.uid).snapshots().listen((snap) {
      if (!snap.exists || !mounted) return;

      final setupData = (snap.data()?['setupData'] as Map<String, dynamic>?) ?? {};

      // Calculate battery status summary based on thresholds from Firestore.
      final batteries = BatteryCalc.batteriesFromSetupData(setupData);
      final thresholds = (setupData['voltageThresholds'] as Map<String, dynamic>?) ?? {};
      final emptyVolt = (thresholds['empty'] as num?)?.toDouble() ?? 12.0;
      final okayVolt = (thresholds['okay'] as num?)?.toDouble() ?? 12.4;
      final fullVolt = (thresholds['full'] as num?)?.toDouble() ?? 12.8;

      int full = 0, ok = 0, low = 0, critical = 0;
      for (final b in batteries) {
        if (b.voltage == null) continue;
        if (b.voltage! >= fullVolt) {
          full++;
        } else if (b.voltage! >= okayVolt) {
          ok++;
        } else if (b.voltage! >= emptyVolt) {
          low++;
        } else {
          critical++;
        }
      }

      setState(() {
        _batterySummary = _BatterySummary(
          total: batteries.length,
          full: full,
          ok: ok,
          low: low,
          critical: critical,
        );
      });
    });
  }

  /// Fetches team details and match history from the FTCScout API.
  Future<TeamDetail> _loadTeamDetail({required int teamNumber, required int season}) async {
    final teamInfo = await ftcScoutApi.getTeam(teamNumber);
    final List<dynamic> teamMatches = await ftcScoutApi.getTeamMatches(teamNumber: teamNumber, season: season);

    final matches = teamMatches.map<scout.TeamMatchSummary>((matchData) {
      return scout.buildTeamMatchSummary(
        teamMatch: matchData,
        eventMatch: null,
        teamNumber: teamNumber,
      );
    }).toList();

    return TeamDetail(teamInfo: teamInfo, matches: matches);
  }

  /// Loads team identity and upcoming match info for the dashboard header.
  Future<void> _loadWelcomeData() async {
    setState(() => _loadingHeader = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final userDoc = await _db.collection('users').doc(user.uid).get();
      final tnRaw = userDoc.data()?['teamNumber'];
      final tn = int.tryParse(tnRaw?.toString() ?? '');
      if (tn == null) throw Exception('teamNumber missing');

      final detail = await _loadTeamDetail(
        teamNumber: tn,
        season: _season,
      );

      final info = detail.teamInfo;
      final name = (info['nameFull'] ?? info['name'] ?? '').toString().trim();

      // Identify the next upcoming match based on current time.
      scout.TeamMatchSummary? nextMatch;
      final now = DateTime.now();

      detail.matches.sort((a, b) => (a.scheduledTime ?? DateTime(0)).compareTo(b.scheduledTime ?? DateTime(0)));

      for (final match in detail.matches) {
        if (match.redScore == 0 && match.blueScore == 0 && (match.scheduledTime ?? DateTime(0)).isAfter(now)) {
          nextMatch = match;
          break;
        }
      }

      String? eventCode;
      if (nextMatch != null) {
        eventCode = nextMatch.eventCode;
      } else if (detail.matches.isNotEmpty) {
        eventCode = detail.matches.last.eventCode;
      }

      if (!mounted) return;
      setState(() {
        _teamNumber = tn;
        _teamName = name.isEmpty ? null : name;
        _nextMatch = nextMatch;
        _eventCode = eventCode;
        _loadingHeader = false;
        _headerError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHeader = false;
        _headerError = e.toString();
      });
    }
  }

  /// Organizes all app features into categorized sections for the dashboard layout.
  List<_DashboardSection> _buildSections() {
    return [
      _DashboardSection(
        title: 'Analysis & Insights',
        icon: Icons.analytics_outlined,
        tiles: [
          _DashboardTileDef(
            label: 'Team Searcher',
            icon: Icons.person_search_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TeamSearcherPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'My Team Score',
            icon: Icons.bar_chart_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OwnTeamScorePage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Other Team Prediction',
            icon: Icons.insights_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OtherTeamPredictionPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Alliance Selection',
            icon: Icons.groups_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AllianceSelectionPage()),
            ),
          ),
        ],
      ),
      _DashboardSection(
        title: 'Match Simulation & Scores',
        icon: Icons.sports_esports_outlined,
        tiles: [
          _DashboardTileDef(
            label: 'Match Simulator',
            icon: Icons.play_circle_outline,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MatchSimulatorPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Predictive Simulator',
            icon: Icons.query_stats_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MatchSimulatorV2Page()),
            ),
          ),
          _DashboardTileDef(
            label: 'Points Calculator',
            icon: Icons.calculate_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PointEstimateCalculatorPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Practice Score Keeper',
            icon: Icons.edit_note_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PracticeCalculatorPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Drive Practice Game',
            icon: Icons.videogame_asset_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MiniGamePage()),
            ),
          ),
        ],
      ),
      _DashboardSection(
        title: 'Preparation & Strategy',
        icon: Icons.lightbulb_outline,
        tiles: [
          _DashboardTileDef(
            label: 'Pre-Match Checklist',
            icon: Icons.fact_check_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PreMatchChecklistPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Auto Path Visualizer',
            icon: Icons.map_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AutoPathVisualizerPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Auto Path Route',
            icon: Icons.alt_route_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AutoPathRoutePage(title: 'Auto Path Route')),
            ),
          ),
          _DashboardTileDef(
            label: 'Battery Management',
            icon: Icons.battery_charging_full_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BatteryPage()),
            ),
          ),
        ],
      ),
      _DashboardSection(
        title: 'Tools & Engineering',
        icon: Icons.build_circle_outlined,
        tiles: [
          _DashboardTileDef(
            label: 'Robot Configuration',
            icon: Icons.settings_input_component,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RobotConfigPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Pit Practice',
            icon: Icons.question_answer_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PitInterviewPracticePage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Resource Hub',
            icon: Icons.menu_book_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResourceHubPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Time Tracking',
            icon: Icons.timer_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HourRegistrationPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Scrumboard',
            icon: Icons.view_kanban_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScrumBoardPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Team Tasklist',
            icon: Icons.checklist_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TaskListTeamPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Portfolio',
            icon: Icons.auto_stories_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PortfolioPage()),
            ),
          ),
        ],
      ),
      _DashboardSection(
        title: 'Business & Outreach',
        icon: Icons.business_center_outlined,
        tiles: [
          _DashboardTileDef(
            label: 'Business Hub',
            icon: Icons.dashboard_customize_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BusinessDashboardPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Income Tracker',
            icon: Icons.add_chart,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IncomeManagerPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Expense Tracker',
            icon: Icons.analytics_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpenseManagerPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Sponsor Board',
            icon: Icons.handshake_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SponsorManagerPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Event Organizer',
            icon: Icons.event_note_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EventManagerPage()),
            ),
          ),
        ],
      ),
      _DashboardSection(
        title: 'Meta & Settings',
        icon: Icons.settings_outlined,
        tiles: [
          _DashboardTileDef(
            label: 'About the Devs',
            icon: Icons.info_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutUsPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Feedback',
            icon: Icons.feedback_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FeedbackPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Help',
            icon: Icons.help_outline,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpPage()),
            ),
          ),
          _DashboardTileDef(
            label: 'Setup',
            icon: Icons.settings_outlined,
            onTap: (context) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SetupPage()),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _buildSections();

    return Scaffold(
      appBar: const TopAppBar(
        title: "Dashboard",
        showThemeToggle: true,
        showLogout: true,
        showBackButton: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          int crossAxisCount;
          double childAspectRatio;

          // Responsive grid layout adjustment based on screen width.
          if (width >= 1400) {
            crossAxisCount = 4;
            childAspectRatio = 1.8;
          } else if (width >= 1000) {
            crossAxisCount = 3;
            childAspectRatio = 1.6;
          } else if (width >= 600) {
            crossAxisCount = 2;
            childAspectRatio = 1.4;
          } else {
            crossAxisCount = 1;
            childAspectRatio = 2.4;
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1600),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Overview summary card
                      _welcomeHeaderCard(theme),
                      const SizedBox(height: 10),
                      // Feature grid sections
                      for (final section in sections)
                        _buildSection(
                          context: context,
                          section: section,
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: childAspectRatio,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
    );
  }

  /// Builds the high-level status card at the top of the dashboard.
  Widget _welcomeHeaderCard(ThemeData theme) {
    final primary = theme.colorScheme.primary;

    String title = _loadingHeader ? 'Welcome' : 'Welcome Team ${_teamNumber ?? '-'}';
    String subtitle = _loadingHeader ? 'Loading team info...' : (_teamName ?? 'Unknown team');

    if (_headerError != null) {
      title = 'Welcome';
      subtitle = 'Could not load team info. Tap to retry.';
    }

    final canTap = !_loadingHeader;

    return GestureDetector(
      onTap: canTap ? _loadWelcomeData : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _overclockMode ? _overclockColor.withAlpha(20) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _overclockMode ? _overclockColor : theme.dividerColor.withAlpha(153)),
          boxShadow: [
            BoxShadow(
              color: _overclockMode ? _overclockColor.withAlpha(50) : Colors.black.withAlpha(15),
              blurRadius: _overclockMode ? 15 : 10,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Easter Egg Trigger Widget
                GestureDetector(
                  onTap: _handleEasterEggTap,
                  child: Transform.rotate(
                    angle: _overclockMode ? _rotation : 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _overclockMode ? _overclockColor.withAlpha(60) : primary.withAlpha(31),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _overclockMode ? _overclockColor : primary.withAlpha(51)),
                      ),
                      child: Icon(
                        _overclockMode ? Icons.bolt : Icons.verified,
                        color: _overclockMode ? _overclockColor : primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _overclockMode ? _overclockColor : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _overclockMode ? _overclockColor.withAlpha(200) : theme.textTheme.bodyMedium?.color?.withAlpha(191),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_headerError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _headerError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Current Battery Status Summary
            if (_batterySummary.total > 0) ...[
              const Divider(height: 24),
              Text(
                'Battery Status',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildBatterySummary(theme),
            ],
            // Next Upcoming Match Summary
            if (_nextMatch != null) ...[
              const Divider(height: 24),
              _buildNextMatch(theme),
            ],
          ],
        ),
      ),
    );
  }

  /// Displays information about the team's next upcoming match.
  Widget _buildNextMatch(ThemeData theme) {
    final match = _nextMatch!;
    final myTeam = _teamNumber;
    if (myTeam == null) return const SizedBox.shrink();

    final isRed = match.alliance == 'Red';

    // Extract alliance partners and opponents.
    final redPartner = match.redTeams.where((team) => team != myTeam).firstOrNull;
    final bluePartner = match.blueTeams.where((team) => team != myTeam).firstOrNull;

    final redOpponent1 = isRed ? match.blueTeams.elementAtOrNull(0) : match.redTeams.elementAtOrNull(0);
    final redOpponent2 = isRed ? match.blueTeams.elementAtOrNull(1) : match.redTeams.elementAtOrNull(1);

    final matchLabel = match.tournamentLevel.isEmpty ? 'Match ${match.matchId}' : '${match.tournamentLevel} ${match.matchId}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Next Match: $matchLabel (${match.eventCode})',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _allianceTeam(theme, 'You', myTeam, isRed: isRed)),
            Expanded(
              child: _allianceTeam(
                theme,
                'Partner',
                isRed ? redPartner : bluePartner,
                isRed: isRed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _allianceTeam(
                theme,
                'Opponent 1',
                redOpponent1,
                isRed: !isRed,
              ),
            ),
            Expanded(
              child: _allianceTeam(
                theme,
                'Opponent 2',
                redOpponent2,
                isRed: !isRed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// UI helper for displaying a team within an alliance row.
  Widget _allianceTeam(ThemeData theme, String title, int? teamNumber, {required bool isRed}) {
    final color = isRed ? Colors.red : Colors.blue;
    final hasNumber = teamNumber != null && teamNumber > 0;

    return Column(
      children: [
        Text(title, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: (hasNumber ? color.withAlpha(50) : theme.colorScheme.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: hasNumber ? color.withAlpha(120) : theme.dividerColor.withAlpha(120),
            ),
          ),
          child: Center(
            child: Text(
              hasNumber ? teamNumber.toString() : '-',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: hasNumber
                    ? (isRed ? Colors.red.shade800 : Colors.blue.shade800)
                    : theme.textTheme.bodyMedium?.color?.withAlpha(150),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the battery status row based on real-time calculated summary.
  Widget _buildBatterySummary(ThemeData theme) {
    return Row(
      children: [
        _batteryStat(
          icon: Icons.check_circle,
          label: 'Full',
          value: _batterySummary.full,
          color: Colors.green.shade600,
        ),
        _batteryStat(
          icon: Icons.radio_button_checked,
          label: 'Okay',
          value: _batterySummary.ok,
          color: Colors.blue.shade600,
        ),
        _batteryStat(
          icon: Icons.warning_amber,
          label: 'Low',
          value: _batterySummary.low,
          color: Colors.amber.shade700,
        ),
        _batteryStat(
          icon: Icons.error,
          label: 'Critical',
          value: _batterySummary.critical,
          color: Colors.red.shade700,
          highlight: true,
        ),
      ],
    );
  }

  /// UI helper for displaying individual battery metrics.
  Widget _batteryStat({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    final decoration = highlight && value > 0
        ? BoxDecoration(
      color: color.withAlpha(40),
      borderRadius: BorderRadius.circular(12),
    )
        : null;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: decoration,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  value.toString(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withAlpha(170),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a titled section containing interactive feature tiles.
  Widget _buildSection({
    required BuildContext context,
    required _DashboardSection section,
    required int crossAxisCount,
    required double childAspectRatio,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(section.icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                section.title,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: section.tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, tileIndex) {
            final tile = section.tiles[tileIndex];
            return DashboardTile(
              label: tile.label,
              icon: tile.icon,
              onTap: tile.onTap == null ? null : () => tile.onTap?.call(context),
              comingSoon: tile.comingSoon,
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
