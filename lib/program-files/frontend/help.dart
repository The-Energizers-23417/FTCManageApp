import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';

/// HelpPage provides documentation and guidance for all major features of the application.
/// It includes an organized list of feature descriptions and a Frequently Asked Questions (FAQ) section.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    context.watch<ThemeService>();

    return Scaffold(
      appBar: const TopAppBar(
        title: "Help & FAQ",
        showThemeToggle: true,
        showLogout: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Features: Analysis
          _buildHelpSection(
            theme,
            title: 'Analysis & Insights',
            icon: Icons.analytics,
            children: [
              _buildHelpItem(
                theme,
                'Team Searcher',
                'Search for FTC teams and view their performance history and statistics.',
              ),
              _buildHelpItem(
                theme,
                'My Team Score',
                'View detailed statistics and match history for your own team.',
              ),
              _buildHelpItem(
                theme,
                'Other Team Prediction',
                'Predict the performance of other teams based on available data.',
              ),
            ],
          ),
          // Features: Simulation
          _buildHelpSection(
            theme,
            title: 'Match Simulation & Scores',
            icon: Icons.sports_esports,
            children: [
              _buildHelpItem(
                theme,
                'Match Simulator',
                'Simulate potential match outcomes by selecting alliances.',
              ),
              _buildHelpItem(
                theme,
                'Points Calculator',
                'Estimate points for different game scenarios and tasks.',
              ),
              _buildHelpItem(
                theme,
                'Practice Score Keeper',
                'Keep track of scores and save them during your practice sessions.',
              ),
              _buildHelpItem(
                theme,
                'Drive Practice Game',
                'A mini-game to sharpen your driving strategy and awareness.',
              ),
            ],
          ),
          // Features: Strategy
          _buildHelpSection(
            theme,
            title: 'Preparation & Strategy',
            icon: Icons.lightbulb,
            children: [
              _buildHelpItem(
                theme,
                'Pre-Match Checklist',
                'Ensure everything is ready before you hit the field.',
              ),
              _buildHelpItem(
                theme,
                'Auto Path Visualizer',
                'Visualize and plan your autonomous routes on the field.',
              ),
              _buildHelpItem(
                theme,
                'Battery Management',
                'Track battery voltages and health for optimal performance.',
              ),
            ],
          ),
          // Features: Tools
          _buildHelpSection(
            theme,
            title: 'Tools & Resources',
            icon: Icons.build,
            children: [
              _buildHelpItem(
                theme,
                'Resource Hub',
                'Access important FTC documents, manuals, and links.',
              ),
              _buildHelpItem(
                theme,
                'Time Tracking',
                'Track team members\' hours for outreach and awards.',
              ),
              _buildHelpItem(
                theme,
                'Scrumboard & Task List',
                'Manage team tasks and progress with agile methodologies.',
              ),
              _buildHelpItem(
                theme,
                'Portfolio',
                'Organize and document your season for the Engineering Portfolio.',
              ),
            ],
          ),
          const Divider(height: 32),
          // FAQ Section
          _buildHelpSection(
            theme,
            title: 'Frequently Asked Questions (FAQ)',
            icon: Icons.question_answer,
            children: [
              _buildHelpItem(
                theme,
                'How are predictions calculated?',
                'Predictions are based on historical data from FTC Scout, including OPR and previous match results of the current season.',
              ),
              _buildHelpItem(
                theme,
                'Why can\'t I see my team data?',
                'Check if you entered the correct team number in the Setup page. It may also take some time for new match data to be synchronized with the API.',
              ),
              _buildHelpItem(
                theme,
                'How does the battery monitor work?',
                'You can manually enter the voltage of your batteries after a test or match. The app indicates whether a battery is full, okay, or critically low based on set thresholds.',
              ),
              _buildHelpItem(
                theme,
                'Can I work offline?',
                'No, unfortunately not.',
              ),
              _buildHelpItem(
                theme,
                'What should I do if I find a bug?',
                'Go to the Feedback page and describe what went wrong. We\'ll try to solve it as soon as possible!',
              ),
            ],
          ),
          const Divider(height: 32),
          // Legal & Disclaimer Section
          _buildHelpSection(
            theme,
            title: 'Legal & Disclaimer',
            icon: Icons.gavel,
            children: [
              _buildHelpItem(
                theme,
                'Disclaimer of Liability',
                'This application is provided "as is" without warranties of any kind. The developers are not responsible for any data loss, security breaches, match inaccuracies, or any other damages that may result from using this app.',
              ),
              _buildHelpItem(
                theme,
                'Data Usage',
                'We use Firebase for data storage and authentication. While we strive to protect your data, we cannot guarantee absolute security. Use this app at your own risk.',
              ),
              _buildHelpItem(
                theme,
                'Third-Party Data',
                'Data used for scouting and predictions is fetched from third-party APIs (like FTC Scout). We are not responsible for the accuracy or availability of this data.',
              ),
            ],
          ),
          const SizedBox(height: 20),
          // CTA Card for more questions
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    'Still have questions?',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you have questions that are not listed here, please send us a message via the Feedback page!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper to build an expandable documentation section.
  Widget _buildHelpSection(ThemeData theme, {required String title, required IconData icon, required List<Widget> children}) {
    return ExpansionTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      children: children,
    );
  }

  /// Helper to build a single documentation item.
  Widget _buildHelpItem(ThemeData theme, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(description, style: theme.textTheme.bodyMedium),
          const Divider(),
        ],
      ),
    );
  }
}
