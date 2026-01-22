// lib/program-files/frontend/practice_calculator.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// PracticeCalculatorPage provides a manual scoring tool for the FTC DECODE season.
/// It allows teams to track points for autonomous, teleop, endgame, and fouls during practice matches.
class PracticeCalculatorPage extends StatefulWidget {
  const PracticeCalculatorPage({super.key});

  @override
  State<PracticeCalculatorPage> createState() =>
      _PracticeCalculatorPageState();
}

enum ArtifactColor { none, green, purple }

enum Motif { motif1, motif2, motif3 }

class _PracticeCalculatorPageState extends State<PracticeCalculatorPage> {
  int _currentIndex = 0;

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // State – Scoring Inputs
  // ─────────────────────────────────────────────────────────────────────────────

  // AUTONOMOUS PHASE
  int autoLeaveRobots = 0; // Number of robots that left the starting zone (0-2)
  int autoClassified = 0;
  int autoOverflow = 0;

  // TELEOP (DRIVER CONTROLLED) PHASE
  int teleopClassified = 0;
  int teleopOverflow = 0;
  int teleopDepot = 0;

  // ENDGAME PHASE
  int parkPartial = 0;
  int parkFull = 0;
  bool parkBonusBothRobotsFull = false;

  // FOULS (Points deducted from current alliance)
  int minorFouls = 0;
  int majorFouls = 0;

  // Pattern Matching State
  Motif motif = Motif.motif2; // The active randomized motif for the match

  // State of individual color gates on the backdrop/grid
  final List<ArtifactColor> autoGateColors =
  List<ArtifactColor>.filled(9, ArtifactColor.none);
  final List<ArtifactColor> teleopGateColors =
  List<ArtifactColor>.filled(9, ArtifactColor.none);

  // ─────────────────────────────────────────────────────────────────────────────
  // Game Point Constants
  // ─────────────────────────────────────────────────────────────────────────────

  static const int leavePoints = 3;
  static const int classifiedPoints = 3;
  static const int overflowPoints = 1;
  static const int depotPoints = 1;
  static const int patternPoints = 2;
  static const int partialParkPoints = 5;
  static const int fullParkPoints = 10;
  static const int parkBonusPoints = 10;

  static const int minorFoulPoints = -10;
  static const int majorFoulPoints = -30;

  // Ranking Point (RP) Thresholds
  static const int movementThreshold = 16;
  static const int goalThreshold = 36;
  static const int patternThreshold = 18;

  // ─────────────────────────────────────────────────────────────────────────────
  // Pattern Logic Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  /// Returns the target color sequence for a specific match motif.
  List<ArtifactColor> _patternForMotif(Motif motif) {
    switch (motif) {
      case Motif.motif1:
        return const [
          ArtifactColor.green, ArtifactColor.purple, ArtifactColor.purple,
          ArtifactColor.green, ArtifactColor.purple, ArtifactColor.purple,
          ArtifactColor.green, ArtifactColor.purple, ArtifactColor.purple,
        ];
      case Motif.motif2:
        return const [
          ArtifactColor.purple, ArtifactColor.green, ArtifactColor.purple,
          ArtifactColor.purple, ArtifactColor.green, ArtifactColor.purple,
          ArtifactColor.purple, ArtifactColor.green, ArtifactColor.purple,
        ];
      case Motif.motif3:
        return const [
          ArtifactColor.purple, ArtifactColor.purple, ArtifactColor.green,
          ArtifactColor.purple, ArtifactColor.purple, ArtifactColor.green,
          ArtifactColor.purple, ArtifactColor.purple, ArtifactColor.green,
        ];
    }
  }

  /// Calculates the number of gates that match the target motif in the Auto phase.
  int get autoPatternMatches {
    final pattern = _patternForMotif(motif);
    int matches = 0;
    for (var i = 0; i < 9; i++) {
      final c = autoGateColors[i];
      if (c != ArtifactColor.none && c == pattern[i]) {
        matches++;
      }
    }
    return matches;
  }

  /// Calculates the number of gates that match the target motif in the TeleOp phase.
  int get teleopPatternMatches {
    final pattern = _patternForMotif(motif);
    int matches = 0;
    for (var i = 0; i < 9; i++) {
      final c = teleopGateColors[i];
      if (c != ArtifactColor.none && c == pattern[i]) {
        matches++;
      }
    }
    return matches;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Calculated Totals
  // ─────────────────────────────────────────────────────────────────────────────

  int get autoScore {
    return autoLeaveRobots * leavePoints +
        autoClassified * classifiedPoints +
        autoOverflow * overflowPoints +
        autoPatternMatches * patternPoints;
  }

  int get teleopScore {
    return teleopClassified * classifiedPoints +
        teleopOverflow * overflowPoints +
        teleopDepot * depotPoints +
        teleopPatternMatches * patternPoints +
        parkPartial * partialParkPoints +
        parkFull * fullParkPoints +
        (parkBonusBothRobotsFull ? parkBonusPoints : 0);
  }

  int get foulScoreAgainstUs {
    return minorFouls * minorFoulPoints + majorFouls * majorFoulPoints;
  }

  int get totalScore => autoScore + teleopScore - foulScoreAgainstUs;

  // RP Metric Calculators
  int get movementScore =>
      autoLeaveRobots * leavePoints +
          parkPartial * partialParkPoints +
          parkFull * fullParkPoints +
          (parkBonusBothRobotsFull ? parkBonusPoints : 0);

  int get goalArtifactCount =>
      autoClassified + autoOverflow + teleopClassified + teleopOverflow;

  int get patternScore =>
      (autoPatternMatches + teleopPatternMatches) * patternPoints;

  // Boolean flags for RP achievement
  bool get movementRp => movementScore >= movementThreshold;
  bool get goalRp => goalArtifactCount >= goalThreshold;
  bool get patternRp => patternScore >= patternThreshold;

  // ─────────────────────────────────────────────────────────────────────────────
  // Action Handlers
  // ─────────────────────────────────────────────────────────────────────────────

  /// Randomly selects a new motif for the match.
  void _randomizeMotif() {
    final r = Random().nextInt(3);
    setState(() {
      motif = Motif.values[r];
    });
  }

  /// Resets all inputs to their starting values.
  void _resetAll() {
    setState(() {
      autoLeaveRobots = 0;
      autoClassified = 0;
      autoOverflow = 0;
      teleopClassified = 0;
      teleopOverflow = 0;
      teleopDepot = 0;
      parkPartial = 0;
      parkFull = 0;
      parkBonusBothRobotsFull = false;
      minorFouls = 0;
      majorFouls = 0;
      motif = Motif.motif2;
      for (var i = 0; i < 9; i++) {
        autoGateColors[i] = ArtifactColor.none;
        teleopGateColors[i] = ArtifactColor.none;
      }
    });
  }

  /// Helper to increment or decrement an integer state value within bounds.
  void _changeInt({
    required bool increase,
    required int min,
    required int max,
    required int current,
    required ValueChanged<int> onChanged,
  }) {
    var newValue = current + (increase ? 1 : -1);
    newValue = newValue.clamp(min, max);
    if (newValue != current) {
      onChanged(newValue);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Builds a row with a label and +/- buttons for numeric input.
  Widget _buildCounterRow(ThemeData theme, String label, int value,
      {int min = 0, int max = 999, required ValueChanged<int> onChanged}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _counterBtn(theme, Icons.remove, () => _changeInt(
                    increase: false, min: min, max: max, current: value, onChanged: onChanged)),
                Container(
                  constraints: const BoxConstraints(minWidth: 30),
                  alignment: Alignment.center,
                  child: Text(
                    '$value',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _counterBtn(theme, Icons.add, () => _changeInt(
                    increase: true, min: min, max: max, current: value, onChanged: onChanged)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Helper for building individual increment/decrement buttons.
  Widget _counterBtn(ThemeData theme, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        setState(onTap);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(icon, size: 20, color: theme.colorScheme.primary),
      ),
    );
  }

  /// Builds the interactive table for assigning colors to specific gates.
  Widget _buildGateTable(ThemeData theme, List<ArtifactColor> colors) {
    final pattern = _patternForMotif(motif);

    Widget _buildOption(int index, ArtifactColor optionValue, Color activeColor) {
      final current = colors[index];
      final isSelected = current == optionValue;
      final target = pattern[index];

      // Highlight mismatches if a color is selected but doesn't match the motif target.
      final isMismatch = current != ArtifactColor.none && current != target;
      final showError = isMismatch && isSelected && optionValue != ArtifactColor.none;

      return InkWell(
        onTap: () => setState(() => colors[index] = optionValue),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 32,
          width: 32,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected && optionValue != ArtifactColor.none
                ? activeColor
                : Colors.transparent,
            border: Border.all(
              color: showError
                  ? Colors.red
                  : (isSelected && optionValue == ArtifactColor.none
                  ? theme.disabledColor
                  : theme.dividerColor.withOpacity(0.3)),
              width: showError ? 2 : (isSelected ? 2 : 1),
            ),
          ),
          child: isSelected
              ? Icon(
              optionValue == ArtifactColor.none ? Icons.close : Icons.check,
              size: 18,
              color: optionValue == ArtifactColor.none ? theme.disabledColor : Colors.white
          )
              : null,
        ),
      );
    }

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FixedColumnWidth(40),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Gate', style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Green', style: theme.textTheme.labelSmall?.copyWith(color: Colors.green), textAlign: TextAlign.center),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Purple', style: theme.textTheme.labelSmall?.copyWith(color: Colors.purpleAccent), textAlign: TextAlign.center),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Clear', style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
            ),
          ],
        ),
        const TableRow(children: [SizedBox(height: 8), SizedBox(), SizedBox(), SizedBox()]),
        for (int i = 0; i < 9; i++)
          TableRow(
            children: [
              Text('${i + 1}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              Center(child: _buildOption(i, ArtifactColor.green, Colors.green)),
              Center(child: _buildOption(i, ArtifactColor.purple, Colors.purpleAccent)),
              Center(child: _buildOption(i, ArtifactColor.none, Colors.transparent)),
            ],
          ),
      ],
    );
  }

  /// Card for selecting and visualizing the active match motif.
  Widget _buildMotifCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active Motif',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _randomizeMotif,
                  icon: const Icon(Icons.shuffle, size: 16),
                  label: const Text('Random'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<Motif>(
                segments: const [
                  ButtonSegment(value: Motif.motif1, label: Text('1 (21)')),
                  ButtonSegment(value: Motif.motif2, label: Text('2 (22)')),
                  ButtonSegment(value: Motif.motif3, label: Text('3 (23)')),
                ],
                selected: {motif},
                onSelectionChanged: (newSet) {
                  setState(() => motif = newSet.first);
                },
                showSelectedIcon: false,
                style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ),
            const SizedBox(height: 16),
            Text('Target Pattern:', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            // Visual representation of the required color pattern.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(9, (index) {
                final c = _patternForMotif(motif)[index];
                return Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c == ArtifactColor.green
                        ? Colors.green
                        : Colors.purpleAccent,
                    border: Border.all(color: theme.dividerColor, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: (c == ArtifactColor.green ? Colors.green : Colors.purpleAccent).withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeService = context.watch<ThemeService>();
    final settings = themeService.settings;
    final isDark = theme.brightness == Brightness.dark;
    
    // Choose appropriate primary color based on theme mode.
    final primaryColor = isDark ? settings.headerDark : settings.headerLight;
    const headerTextColor = Colors.white;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: TopAppBar(
        title: 'Calculator',
        showThemeToggle: true,
        showLogout: true,
        actions: [
          IconButton(
            onPressed: _resetAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Scores',
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
        items: const [],
      ),
      body: Column(
        children: [
          // ─── Score Overview Header ───
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              children: [
                // Display total score prominently.
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TOTAL SCORE',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              )),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                )
                              ],
                            ),
                            child: Text(
                              '$totalScore',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: headerTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Display breakdowns for match phases.
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _miniScore(theme, 'AUTO', '$autoScore', isDark),
                          const SizedBox(width: 16),
                          _miniScore(theme, 'TELEOP', '$teleopScore', isDark),
                          const SizedBox(width: 16),
                          _miniScore(theme, 'FOUL', '-$foulScoreAgainstUs', isDark, color: Colors.redAccent),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Ranking Point Progress row.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _rpBadge(theme, 'MOVEMENT', movementRp,
                        '$movementScore / $movementThreshold pts'),
                    _rpBadge(
                        theme, 'GOAL', goalRp, '$goalArtifactCount / $goalThreshold items'),
                    _rpBadge(theme, 'PATTERN', patternRp,
                        '$patternScore / $patternThreshold pts'),
                  ],
                ),
              ],
            ),
          ),

          // ─── Input Form Content ───
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMotifCard(theme),
                  const SizedBox(height: 16),

                  // AUTONOMOUS INPUT SECTION
                  _buildSectionCard(
                    theme,
                    title: 'Autonomous',
                    color: Colors.orange.shade700,
                    children: [
                      _buildCounterRow(theme, 'Leaving Robots', autoLeaveRobots,
                          max: 2,
                          onChanged: (v) => setState(() => autoLeaveRobots = v)),
                      _buildCounterRow(theme, 'Classified Artifacts', autoClassified,
                          onChanged: (v) => setState(() => autoClassified = v)),
                      _buildCounterRow(theme, 'Overflow Artifacts', autoOverflow,
                          onChanged: (v) => setState(() => autoOverflow = v)),
                      const SizedBox(height: 16),
                      Text('Gate Pattern (Matches: $autoPatternMatches)',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildGateTable(theme, autoGateColors),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // TELEOP INPUT SECTION
                  _buildSectionCard(
                    theme,
                    title: 'Driver Controlled',
                    color: Colors.blue.shade700,
                    children: [
                      _buildCounterRow(
                          theme, 'Classified Artifacts', teleopClassified,
                          onChanged: (v) => setState(() => teleopClassified = v)),
                      _buildCounterRow(theme, 'Overflow Artifacts', teleopOverflow,
                          onChanged: (v) => setState(() => teleopOverflow = v)),
                      _buildCounterRow(theme, 'Depot Artifacts', teleopDepot,
                          onChanged: (v) => setState(() => teleopDepot = v)),
                      const SizedBox(height: 16),
                      Text('Gate Pattern (Matches: $teleopPatternMatches)',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildGateTable(theme, teleopGateColors),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ENDGAME INPUT SECTION
                  _buildSectionCard(
                    theme,
                    title: 'Endgame',
                    color: Colors.teal.shade700,
                    children: [
                      _buildCounterRow(theme, 'Partially Parked', parkPartial,
                          max: 2, onChanged: (v) => setState(() => parkPartial = v)),
                      _buildCounterRow(theme, 'Fully Parked', parkFull,
                          max: 2, onChanged: (v) => setState(() => parkFull = v)),
                      const Divider(height: 24),
                      SwitchListTile(
                        title: Text('Both fully parked bonus',
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                        value: parkBonusBothRobotsFull,
                        activeColor: Colors.teal,
                        onChanged: (v) =>
                            setState(() => parkBonusBothRobotsFull = v),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // FOULS INPUT SECTION
                  _buildSectionCard(
                    theme,
                    title: 'Fouls (Against Us)',
                    color: Colors.redAccent,
                    children: [
                      _buildCounterRow(theme, 'Minor Fouls', minorFouls,
                          onChanged: (v) => setState(() => minorFouls = v)),
                      _buildCounterRow(theme, 'Major Fouls', majorFouls,
                          onChanged: (v) => setState(() => majorFouls = v)),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Displays a small labeled score component.
  Widget _miniScore(ThemeData theme, String label, String value, bool isDark, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.bold)),
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color ?? (isDark ? Colors.white : Colors.black87),
            )),
      ],
    );
  }

  /// Displays status and progress for a specific Ranking Point objective.
  Widget _rpBadge(ThemeData theme, String label, bool achieved, String info) {
    return Expanded(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 4),
            width: double.infinity,
            decoration: BoxDecoration(
              color: achieved ? Colors.green.withOpacity(0.15) : theme.dividerColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: achieved ? Colors.green.withOpacity(0.5) : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: achieved ? Colors.green : theme.disabledColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(info, 
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9)),
        ],
      ),
    );
  }

  /// Helper to build a standardized section card with a colored header.
  Widget _buildSectionCard(ThemeData theme,
      {required String title, required Color color, required List<Widget> children}) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: color.withOpacity(0.1),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
