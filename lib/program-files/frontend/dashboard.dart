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
import 'package:ftcmanageapp/program-files/frontend/strategy_whiteboard.dart';
import 'package:ftcmanageapp/program-files/frontend/tasklist_team.dart';
import 'package:ftcmanageapp/program-files/frontend/team_searcher.dart';
import 'package:ftcmanageapp/program-files/frontend/widgets/dashboard_tile.dart';

/// Metadata for a single tile on the dashboard.
class DashboardTileDef {
  final String label;
  final String description;
  final IconData icon;
  final void Function(BuildContext context)? onTap;

  bool get comingSoon => onTap == null;

  const DashboardTileDef({
    required this.label,
    required this.description,
    required this.icon,
    this.onTap,
  });
}

/// Metadata for a grouped section of tiles on the dashboard.
class DashboardSectionDef {
  final String title;
  final IconData icon;
  final List<DashboardTileDef> tiles;

  const DashboardSectionDef({
    required this.title,
    required this.icon,
    required this.tiles,
  });
}

/// Centralized provider for dashboard structure to ensure consistency across the app.
class DashboardMetadata {
  static List<DashboardSectionDef> getSections(BuildContext? context) {
    return [
      DashboardSectionDef(
        title: 'Analysis & Insights',
        icon: Icons.analytics_outlined,
        tiles: [
          DashboardTileDef(
            label: 'Team Searcher',
            description: 'Search for other FTC teams and see their stats.',
            icon: Icons.person_search_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const TeamSearcherPage())),
          ),
          DashboardTileDef(
            label: 'My Team Score',
            description: 'Analyze your own team\'s scoring performance.',
            icon: Icons.bar_chart_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const OwnTeamScorePage())),
          ),
          DashboardTileDef(
            label: 'Other Team Prediction',
            description: 'Predict the outcome of matches based on team data.',
            icon: Icons.insights_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const OtherTeamPredictionPage())),
          ),
          DashboardTileDef(
            label: 'Alliance Selection',
            description: 'Tools to help with picking the best alliance partners.',
            icon: Icons.groups_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const AllianceSelectionPage())),
          ),
        ],
      ),
      DashboardSectionDef(
        title: 'Match Simulation & Scores',
        icon: Icons.sports_esports_outlined,
        tiles: [
          DashboardTileDef(
            label: 'Match Simulator',
            description: 'Simulate matches to practice strategy.',
            icon: Icons.play_circle_outline,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const MatchSimulatorPage())),
          ),
          DashboardTileDef(
            label: 'Predictive Simulator',
            description: 'Advanced simulation using historical performance.',
            icon: Icons.query_stats_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const MatchSimulatorV2Page())),
          ),
          DashboardTileDef(
            label: 'Points Calculator',
            description: 'Quickly estimate match points during practice.',
            icon: Icons.calculate_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const PointEstimateCalculatorPage())),
          ),
          DashboardTileDef(
            label: 'Practice Score Keeper',
            description: 'Track and log your scores during practice runs.',
            icon: Icons.edit_note_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const PracticeCalculatorPage())),
          ),
          DashboardTileDef(
            label: 'Drive Practice Game',
            description: 'A fun mini-game to sharpen your driving reflexes.',
            icon: Icons.videogame_asset_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const MiniGamePage())),
          ),
        ],
      ),
      DashboardSectionDef(
        title: 'Preparation & Strategy',
        icon: Icons.lightbulb_outline,
        tiles: [
          DashboardTileDef(
            label: 'Strategy Whiteboard',
            description: 'Draw and plan your match strategies visually.',
            icon: Icons.draw_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const StrategyWhiteboardPage())),
          ),
          DashboardTileDef(
            label: 'Pre-Match Checklist',
            description: 'Ensure everything is ready before your match.',
            icon: Icons.fact_check_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const PreMatchChecklistPage())),
          ),
          DashboardTileDef(
            label: 'Auto Path Visualizer',
            description: 'Visualize your autonomous paths on the field.',
            icon: Icons.map_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const AutoPathVisualizerPage())),
          ),
          DashboardTileDef(
            label: 'Auto Path Route',
            description: 'Plan complex routes for your autonomous period.',
            icon: Icons.alt_route_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => AutoPathRoutePage(title: 'Auto Path Route'))),
          ),
          DashboardTileDef(
            label: 'Battery Management',
            description: 'Track battery usage and charging status.',
            icon: Icons.battery_charging_full_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const BatteryPage())),
          ),
        ],
      ),
      DashboardSectionDef(
        title: 'Tools & Engineering',
        icon: Icons.build_circle_outlined,
        tiles: [
          DashboardTileDef(
            label: 'Robot Configuration',
            description: 'Manage your robot\'s hardware settings and config.',
            icon: Icons.settings_input_component,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const RobotConfigPage())),
          ),
          DashboardTileDef(
            label: 'Pit Practice',
            description: 'Prepare for judging with practice interviews.',
            icon: Icons.question_answer_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const PitInterviewPracticePage())),
          ),
          DashboardTileDef(
            label: 'Resource Hub',
            description: 'Competition manual and rules.',
            icon: Icons.menu_book_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ResourceHubPage())),
          ),
          DashboardTileDef(
            label: 'Time Tracking',
            description: 'Log and manage team member participation hours.',
            icon: Icons.timer_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const HourRegistrationPage())),
          ),
          DashboardTileDef(
            label: 'Scrumboard',
            icon: Icons.view_kanban_outlined,
            description: 'Manage engineering tasks using Scrum methodology.',
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ScrumBoardPage())),
          ),
          DashboardTileDef(
            label: 'Team Tasklist',
            description: 'General to-do list for team organization.',
            icon: Icons.checklist_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const TaskListTeamPage())),
          ),
          DashboardTileDef(
            label: 'Portfolio',
            description: 'Track and organize entries for your Engineering Portfolio.',
            icon: Icons.auto_stories_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const PortfolioPage())),
          ),
        ],
      ),
      DashboardSectionDef(
        title: 'Business & Outreach',
        icon: Icons.business_center_outlined,
        tiles: [
          DashboardTileDef(
            label: 'Business Hub',
            description: 'Central dashboard for business and outreach tracking.',
            icon: Icons.dashboard_customize_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const BusinessDashboardPage())),
          ),
          DashboardTileDef(
            label: 'Income Tracker',
            description: 'Log and monitor team income and grants.',
            icon: Icons.add_chart,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const IncomeManagerPage())),
          ),
          DashboardTileDef(
            label: 'Expense Tracker',
            description: 'Manage team spending and budget.',
            icon: Icons.analytics_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ExpenseManagerPage())),
          ),
          DashboardTileDef(
            label: 'Sponsor Board',
            description: 'Track sponsor relationships and contributions.',
            icon: Icons.handshake_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const SponsorManagerPage())),
          ),
          DashboardTileDef(
            label: 'Event Organizer',
            description: 'Plan and manage team events and outreach.',
            icon: Icons.event_note_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const EventManagerPage())),
          ),
        ],
      ),
      DashboardSectionDef(
        title: 'Meta & Settings',
        icon: Icons.settings_outlined,
        tiles: [
          DashboardTileDef(
            label: 'About the Devs',
            description: 'Learn more about the creators of this app.',
            icon: Icons.info_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const AboutUsPage())),
          ),
          DashboardTileDef(
            label: 'Feedback',
            description: 'Submit bug reports or feature requests.',
            icon: Icons.feedback_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const FeedbackPage())),
          ),
          DashboardTileDef(
            label: 'Help',
            description: 'User guide and documentation for the app.',
            icon: Icons.help_outline,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const HelpPage())),
          ),
          DashboardTileDef(
            label: 'Setup',
            description: 'Configure your team settings and preferences.',
            icon: Icons.settings_outlined,
            onTap: context == null ? null : (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const SetupPage())),
          ),
        ],
      ),
    ];
  }
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

  // Visibility state (Synced with Firestore)
  Map<String, bool> _sectionVisibility = {};
  Map<String, bool> _tileVisibility = {};

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

  /// Saves current visibility maps to Firebase Firestore.
  Future<void> _syncVisibilityToFirebase() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    await _db.collection('users').doc(user.uid).update({
      'sectionVisibility': _sectionVisibility,
      'tileVisibility': _tileVisibility,
    });
  }

  /// Toggles and saves section visibility.
  void _toggleSection(String title) {
    setState(() {
      _sectionVisibility[title] = !(_sectionVisibility[title] ?? true);
    });
    _syncVisibilityToFirebase();
  }

  /// Toggles individual tile visibility.
  void _toggleTile(String label) {
    setState(() {
      _tileVisibility[label] = !(_tileVisibility[label] ?? true);
    });
    _syncVisibilityToFirebase();
  }

  /// Expands all sections.
  void _expandAll() {
    final sections = DashboardMetadata.getSections(null);
    setState(() {
      for (final section in sections) {
        _sectionVisibility[section.title] = true;
      }
    });
    _syncVisibilityToFirebase();
  }

  /// Collapses all sections.
  void _collapseAll() {
    final sections = DashboardMetadata.getSections(null);
    setState(() {
      for (final section in sections) {
        _sectionVisibility[section.title] = false;
      }
    });
    _syncVisibilityToFirebase();
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
        _overclockColor = Colors.primaries[math.Random().nextInt(Colors.primaries.length)];
        _rotation += 0.4;
      });
    });

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

  /// Sets up a real-time listener for user data to update battery status and visibility settings.
  void _listenToUserData() {
    final user = _auth.currentUser;
    if (user == null) return;

    _userDocSub?.cancel();
    _userDocSub = _db.collection('users').doc(user.uid).snapshots().listen((snap) {
      if (!snap.exists || !mounted) return;

      final data = snap.data() ?? {};
      final setupData = (data['setupData'] as Map<String, dynamic>?) ?? {};

      // Load visibility settings from Firebase
      final fsSectionVis = (data['sectionVisibility'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as bool));
      final fsTileVis = (data['tileVisibility'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as bool));

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
        if (fsSectionVis != null) _sectionVisibility = fsSectionVis;
        if (fsTileVis != null) _tileVisibility = fsTileVis;
        
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

  /// Opens a dialog to manage visibility of tiles within a specific section.
  void _showTileManager(BuildContext context, DashboardSectionDef section) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(section.icon, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Manage ${section.title}",
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: section.tiles.length,
                      itemBuilder: (context, index) {
                        final tile = section.tiles[index];
                        final isVisible = _tileVisibility[tile.label] ?? true;
                        return CheckboxListTile(
                          title: Text(tile.label),
                          secondary: Icon(tile.icon, size: 20),
                          value: isVisible,
                          activeColor: Theme.of(context).colorScheme.primary,
                          onChanged: (val) {
                            _toggleTile(tile.label);
                            setModalState(() {});
                          },
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = DashboardMetadata.getSections(context);

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

          if (width >= 2600) {
            crossAxisCount = 7;
            childAspectRatio = 2.2;
          } else if (width >= 2200) {
            crossAxisCount = 6;
            childAspectRatio = 2.1;
          } else if (width >= 1800) {
            crossAxisCount = 5;
            childAspectRatio = 2.0;
          } else if (width >= 1400) {
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
                constraints: const BoxConstraints(maxWidth: 3000),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _welcomeHeaderCard(theme),
                      const SizedBox(height: 16),
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _expandAll,
                              icon: const Icon(Icons.unfold_more, size: 18),
                              label: const Text("Expand All"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                side: BorderSide(color: theme.colorScheme.primary.withAlpha(100)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _collapseAll,
                              icon: const Icon(Icons.unfold_less, size: 18),
                              label: const Text("Collapse All"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                side: BorderSide(color: theme.colorScheme.primary.withAlpha(100)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
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

  Widget _welcomeHeaderCard(ThemeData theme) {
    final primary = theme.colorScheme.primary;

    String title = _loadingHeader ? 'Welcome' : 'Welcome Team ${_teamNumber ?? '-'}';
    String subtitle = _loadingHeader ? 'Loading team info...' : (_teamName ?? 'Unknown team');

    if (_headerError != null) {
      title = 'Welcome';
      subtitle = 'Could not load team info. Tap to retry.';
    }

    return GestureDetector(
      onTap: null,
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
            if (_batterySummary.total > 0) ...[
              const Divider(height: 24),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BatteryPage()),
                ),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Battery Status',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildBatterySummary(theme),
                  ],
                ),
              ),
            ],
            if (_nextMatch != null) ...[
              const Divider(height: 24),
              _buildNextMatch(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNextMatch(ThemeData theme) {
    final match = _nextMatch!;
    final myTeam = _teamNumber;
    if (myTeam == null) return const SizedBox.shrink();

    final isRed = match.alliance == 'Red';
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
            Expanded(child: _allianceTeam(theme, 'Partner', isRed ? redPartner : bluePartner, isRed: isRed)),
            const SizedBox(width: 12),
            Expanded(child: _allianceTeam(theme, 'Opponent 1', redOpponent1, isRed: !isRed)),
            Expanded(child: _allianceTeam(theme, 'Opponent 2', redOpponent2, isRed: !isRed)),
          ],
        ),
      ],
    );
  }

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
            border: Border.all(color: hasNumber ? color.withAlpha(120) : theme.dividerColor.withAlpha(120)),
          ),
          child: Center(
            child: Text(
              hasNumber ? teamNumber.toString() : '-',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: hasNumber ? (isRed ? Colors.red.shade800 : Colors.blue.shade800) : theme.textTheme.bodyMedium?.color?.withAlpha(150),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBatterySummary(ThemeData theme) {
    return Row(
      children: [
        _batteryStat(icon: Icons.check_circle, label: 'Full', value: _batterySummary.full, color: Colors.green.shade600),
        _batteryStat(icon: Icons.radio_button_checked, label: 'Okay', value: _batterySummary.ok, color: Colors.blue.shade600),
        _batteryStat(icon: Icons.warning_amber, label: 'Low', value: _batterySummary.low, color: Colors.amber.shade700),
        _batteryStat(icon: Icons.error, label: 'Critical', value: _batterySummary.critical, color: Colors.red.shade700, highlight: true),
      ],
    );
  }

  Widget _batteryStat({required IconData icon, required String label, required int value, required Color color, bool highlight = false}) {
    final theme = Theme.of(context);
    final decoration = highlight && value > 0 ? BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(12)) : null;

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
                Text(value.toString(), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withAlpha(170))),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required BuildContext context, required DashboardSectionDef section, required int crossAxisCount, required double childAspectRatio}) {
    final theme = Theme.of(context);
    final isVisible = _sectionVisibility[section.title] ?? true;
    final visibleTiles = section.tiles.where((t) => _tileVisibility[t.label] ?? true).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              InkWell(
                onTap: () => _toggleSection(section.title),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(section.icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(section.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Icon(isVisible ? Icons.expand_less : Icons.expand_more, size: 20, color: theme.textTheme.bodySmall?.color),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.tune, size: 20),
                onPressed: () => _showTileManager(context, section),
                tooltip: "Manage Tiles",
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.primary.withAlpha(180),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: visibleTiles.isEmpty 
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withAlpha(80), borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.dividerColor.withAlpha(40))),
                  child: Column(
                    children: [
                      Icon(Icons.visibility_off_outlined, color: theme.disabledColor),
                      const SizedBox(height: 8),
                      Text("All tiles hidden in this section", style: TextStyle(color: theme.disabledColor)),
                    ],
                  ),
                )
              : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleTiles.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: childAspectRatio),
            itemBuilder: (context, tileIndex) {
              final tile = visibleTiles[tileIndex];
              return DashboardTile(label: tile.label, icon: tile.icon, onTap: tile.onTap == null ? null : () => tile.onTap?.call(context), comingSoon: tile.comingSoon);
            },
          ),
          secondChild: const SizedBox(width: double.infinity, height: 0),
          crossFadeState: isVisible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 300),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
