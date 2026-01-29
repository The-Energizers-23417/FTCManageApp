import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:url_launcher/url_launcher.dart';

/// A page that provides information about the developers and the team behind the app.
/// Includes version logs and social media links.
class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  int _easterEggCounter = 0;

  /// Helper method to open external URLs in the browser.
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      throw Exception('Could not launch $url');
    }
  }

  /// Increments a counter and shows a fun hidden message after several taps.
  void _handleEasterEgg() {
    setState(() {
      _easterEggCounter++;
    });

    if (_easterEggCounter >= 5) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Message from the Dev"),
          content: const Text("LET THE DEV WORK!!! ⚡"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Got it!"),
            ),
          ],
        ),
      );
      _easterEggCounter = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const TopAppBar(title: "About the Devs", showThemeToggle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Team Branding Section
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.bolt,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "The Energizers 23417",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Built with passion",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.textTheme.bodyMedium?.color?.withAlpha(180),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            
            // Interactive section with Easter Egg
            GestureDetector(
              onTap: _handleEasterEgg,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                color: Colors.transparent,
                child: _buildSection(
                  theme,
                  "About the Development",
                  "This application was developed with great passion and dedication by one of our team members. A tremendous amount of work and time has been invested into this project to create a valuable tool for the FTC community. We sincerely hope that using this app is a great experience and that it helps your team achieve your goals!",
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            _buildSection(
              theme,
              "Suggestions & Feedback",
              "We strive for constant improvement. If you have any suggestions, feedback, or new ideas, we would love to hear them! Together, we can make the app even better for everyone.",
            ),
            
            const SizedBox(height: 24),
            _buildSection(
              theme,
              "Our Team & Collaboration",
              "We are The Energizers 23417 from Roermond, Netherlands. We believe in Gracious Professionalism® and are always open to collaborations. Do you need help with a technical problem or want to work on a project together? Feel free to reach out to us.",
            ),

            const SizedBox(height: 24),
            _buildSection(
              theme,
              "Powered by FTC Scout",
              "A huge thank you to FTC Scout for providing the incredible API and data infrastructure. This app wouldn't be able to provide deep match analysis and team insights without their amazing work!",
            ),
            
            const SizedBox(height: 40),

            // Legal Disclaimer Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.error.withAlpha(100)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gavel, color: theme.colorScheme.error, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "Legal Disclaimer",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "By using this app, you accept all risks and agree that the developers are not responsible for any damages incurred.",
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Open Source Contribution Section
            Card(
              elevation: 0,
              color: theme.colorScheme.primaryContainer.withAlpha(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.primary.withAlpha(100)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      "Want to contribute or view the code?",
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        _launchURL('https://github.com/The-Energizers-23417/FTCManageApp');
                      },
                      icon: const Icon(Icons.code),
                      label: const Text("View on GitHub"),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
            
            // Social Media Integration
            Text(
              "Follow Us",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _socialButton(
                  icon: Icons.camera_alt,
                  label: "Instagram",
                  color: const Color(0xFFE4405F),
                  url: 'https://www.instagram.com/theenergizers_23417/',
                ),
                _socialButton(
                  icon: Icons.facebook,
                  label: "Facebook",
                  color: const Color(0xFF1877F2),
                  url: 'https://www.facebook.com/people/Energizers-Wings-Agora/61551464303705/',
                ),
                _socialButton(
                  icon: Icons.business,
                  label: "LinkedIn",
                  color: const Color(0xFF0A66C2),
                  url: 'https://nl.linkedin.com/company/ftc-the-energizers',
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Current Release Log
            _buildSection(
              theme,
              "Release Log - v1.2 (Security & Smart Search Update)",
              "What's new in this version:\n\n"
              "• Google Sign-In: Added support for one-tap login via Google (Mobile & Web).\n"
              "• Fuzzy Search: Team searcher is now smarter and handles typos or partial names.\n"
              "• Autocomplete: Prediction page now offers suggestions while typing to prevent errors.\n"
              "• Navigation: Fixed 'back button bug' in search flows for a smoother experience.\n"
              "• Dashboard Customization: Fine-grained control over which tiles to show, including detailed feature descriptions in Setup.\n"
              "• Cloud Sync: All dashboard and tile visibility settings are now synced across devices via Firebase.\n"
              "• Battery Shortcuts: Made the Dashboard battery status clickable for instant access.",
            ),

            const SizedBox(height: 24),

            // Previous Release Log
            _buildSection(
              theme,
              "Release Log - v1.1.1 (Bug fix + Improvements on UI)",
              "What's new in this version:\n\n"
              "• UI Enhancements: Improved Dashboard layout for Ultra-Wide and 4K monitors.\n"
              "• Dashboard Controls: Added 'Expand All' and 'Collapse All' buttons for category management.\n"
              "• Persistence: The app now remembers your collapsed/expanded sections locally.\n"
              "• Password Reset: Added 'Forgot Password' link to the login screen.",
            ),

            const SizedBox(height: 24),
            
            // Previous Release Log
            _buildSection(
              theme,
              "Release Log - v1.1 (Business & Engineering Update)",
              "What's new in this version:\n\n"
              "• Business Hub: Centralized dashboard for team finances and outreach.\n"
              "• Sponsor Manager: Kanban-style board to track sponsorships.\n"
              "• Finance Tracking: Separate modules for Income and Expenses.\n"
              "• Robot Configuration: Hub port management with Java export.\n"
              "• Pit Interview Practice: Interactive tool with shuffle mode.",
            ),

            const SizedBox(height: 24),

            // Older Release Log
            _buildSection(
              theme,
              "Previous Release - v1.0",
              "Features from the initial launch:\n\n"
              "• Scouting & Match Simulations powered by FTC Scout.\n"
              "• Auto Path Planning & Route visualization.\n"
              "• Team Management: Scrumboard, Task Lists, and Hour Tracking.\n"
              "• Battery Management system with voltage thresholds.",
            ),
            
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Text(
                    "Good luck on the field!",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Version 1.2",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withAlpha(120),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Builds a button for social media links.
  Widget _socialButton({required IconData icon, required String label, required Color color, required String url}) {
    return InkWell(
      onTap: () => _launchURL(url),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Helper to build a standard text section with a title and content.
  Widget _buildSection(ThemeData theme, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}
