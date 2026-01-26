import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// Defines the experience level of the team to filter relevant questions.
enum TeamStatus { all, newTeam, experiencedTeam }

/// A page that allows FTC teams to practice for their Pit Interviews.
/// It loads a question bank from a local JSON file and allows for category-based or shuffled practice.
class PitInterviewPracticePage extends StatefulWidget {
  const PitInterviewPracticePage({super.key});

  @override
  State<PitInterviewPracticePage> createState() => _PitInterviewPracticePageState();
}

class _PitInterviewPracticePageState extends State<PitInterviewPracticePage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  TeamStatus _selectedStatus = TeamStatus.all;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  /// Asynchronously loads the question bank from the local assets.
  Future<void> _loadQuestions() async {
    try {
      final String response = await rootBundle.loadString('files/resources/qeustions_pit_interviews.json');
      final data = await json.decode(response);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Could not load questions: $e";
          _loading = false;
        });
      }
    }
  }

  /// Filters the list of questions based on the selected team status.
  /// Certain questions are tagged for "(New Team)" or "(Experienced Team)".
  List<dynamic> _filterQuestions(List<dynamic> questions) {
    return questions.where((q) {
      final text = (q['text'] as String? ?? '').toLowerCase();
      
      final isNewTeamOnly = text.contains('(new team)');
      final isExpTeamOnly = text.contains('(experienced team)');

      if (_selectedStatus == TeamStatus.newTeam) {
        // If the team is new, exclude questions specifically for experienced teams.
        return !isExpTeamOnly;
      } else if (_selectedStatus == TeamStatus.experiencedTeam) {
        // If the team is experienced, exclude questions specifically for new teams.
        return !isNewTeamOnly;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopAppBar(
        title: "Pit Interview Practice",
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (i) {},
        items: const [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildMainList(),
    );
  }

  /// Builds the main menu with the team status selector and award categories.
  Widget _buildMainList() {
    final awards = _data?['awards'] as List<dynamic>? ?? [];
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Experience Level Selector
        const Text(
          "Team Experience",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<TeamStatus>(
          segments: const [
            ButtonSegment(value: TeamStatus.all, label: Text("All"), icon: Icon(Icons.list)),
            ButtonSegment(value: TeamStatus.newTeam, label: Text("New"), icon: Icon(Icons.fiber_new)),
            ButtonSegment(value: TeamStatus.experiencedTeam, label: Text("Experienced"), icon: Icon(Icons.history_edu)),
          ],
          selected: {_selectedStatus},
          onSelectionChanged: (Set<TeamStatus> newSelection) {
            setState(() {
              _selectedStatus = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 24),

        // Mixed/Shuffle Practice Mode
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 24),
          child: ListTile(
            leading: const Icon(Icons.shuffle, size: 32),
            title: const Text(
              "Mixed Practice (Shuffle)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            subtitle: const Text("Random questions from all awards"),
            trailing: const Icon(Icons.play_arrow),
            onTap: () {
              final allQuestions = <dynamic>[];
              for (var award in awards) {
                final questions = award['questions'] as List<dynamic>? ?? [];
                final filtered = _filterQuestions(questions);
                for (var q in filtered) {
                  final qWithAward = Map<String, dynamic>.from(q);
                  qWithAward['awardContext'] = award['award'];
                  allQuestions.add(qWithAward);
                }
              }
              // Randomize the entire set for mixed practice.
              allQuestions.shuffle();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AwardQuestionsPage(
                    awardName: "Mixed Practice",
                    questions: allQuestions,
                    showAwardContext: true,
                  ),
                ),
              );
            },
          ),
        ),
        
        const Text(
          "Practice by Award",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        // Individual Award Categories
        ...awards.map((award) {
          final filteredCount = _filterQuestions(award['questions'] as List<dynamic>? ?? []).length;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(
                award['award'] ?? 'Unknown Award',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("$filteredCount questions available (shuffled)"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final filteredQuestions = _filterQuestions(award['questions']);
                // Randomize specific award questions for every session.
                filteredQuestions.shuffle(); 
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AwardQuestionsPage(
                      awardName: award['award'],
                      questions: filteredQuestions,
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }
}

/// A sub-page that displays the actual questions for a specific selection.
class AwardQuestionsPage extends StatefulWidget {
  final String awardName;
  final List<dynamic> questions;
  final bool showAwardContext;

  const AwardQuestionsPage({
    super.key,
    required this.awardName,
    required this.questions,
    this.showAwardContext = false,
  });

  @override
  State<AwardQuestionsPage> createState() => _AwardQuestionsPageState();
}

class _AwardQuestionsPageState extends State<AwardQuestionsPage> {
  int _currentIndex = 0;
  bool _showFollowUps = false;

  /// Advance to the next question in the current list.
  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _showFollowUps = false;
      });
    }
  }

  /// Go back to the previous question.
  void _prevQuestion() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showFollowUps = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Scaffold(
        appBar: TopAppBar(title: widget.awardName),
        body: const Center(child: Text("No questions found for this selection.")),
      );
    }

    final question = widget.questions[_currentIndex];
    final followUps = question['follow_ups'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: TopAppBar(title: widget.awardName),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress indicator for the current session.
            LinearProgressIndicator(
              value: (_currentIndex + 1) / widget.questions.length,
              backgroundColor: Colors.grey[200],
            ),
            const SizedBox(height: 10),
            Text(
              "Question ${_currentIndex + 1} of ${widget.questions.length}",
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            // Display the specific award category if in mixed practice mode.
            if (widget.showAwardContext && question['awardContext'] != null) ...[
               Center(
                 child: Container(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                   decoration: BoxDecoration(
                     color: Theme.of(context).colorScheme.secondaryContainer,
                     borderRadius: BorderRadius.circular(20),
                   ),
                   child: Text(
                     question['awardContext'],
                     style: TextStyle(
                       fontWeight: FontWeight.bold,
                       color: Theme.of(context).colorScheme.onSecondaryContainer,
                     ),
                   ),
                 ),
               ),
               const SizedBox(height: 16),
            ],
            // The main question card.
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      question['text'] ?? '',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    // Display additional notes if available and relevant.
                    if (question['notes'] != null && question['notes'] != "N/A") ...[
                      const SizedBox(height: 12),
                      Text(
                        question['notes'],
                        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Follow-up questions expander.
            if (followUps.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showFollowUps = !_showFollowUps;
                  });
                },
                icon: Icon(_showFollowUps ? Icons.expand_less : Icons.expand_more),
                label: Text(_showFollowUps ? "Hide Follow-ups" : "Show Follow-ups"),
              ),
            if (_showFollowUps)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: followUps.length,
                  itemBuilder: (context, i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(child: Text(followUps[i])),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              const Spacer(),
            // Navigation buttons.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _currentIndex > 0 ? _prevQuestion : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("Back"),
                ),
                ElevatedButton.icon(
                  onPressed: _currentIndex < widget.questions.length - 1 ? _nextQuestion : () => Navigator.pop(context),
                  icon: Icon(_currentIndex < widget.questions.length - 1 ? Icons.arrow_forward : Icons.check),
                  label: Text(_currentIndex < widget.questions.length - 1 ? "Next" : "Finish"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
