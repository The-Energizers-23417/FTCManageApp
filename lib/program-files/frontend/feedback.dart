import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// FeedbackPage allows users to submit feedback, bug reports, or suggestions.
/// Submissions are stored in Firestore for admin review.
/// 
/// Storage structure:
/// - Main collection: feedback_submissions/<autoId>
/// - User-specific copy: users/<uid>/feedback/<autoId>
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _feedbackController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  bool _isSending = false;

  // Submission metadata
  String _type = 'Feedback'; // Options: Feedback, Bug, Suggestion
  int _severity = 2; // Range: 1..5 (used primarily for bugs)

  @override
  void dispose() {
    _feedbackController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  /// Sends the collected feedback data to Firestore.
  Future<void> _sendFeedbackToFirestore() async {
    final title = _titleController.text.trim();
    final feedback = _feedbackController.text.trim();

    if (feedback.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your feedback first.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      final email = user?.email;

      // Construct the feedback payload
      final payload = <String, dynamic>{
        'title': title.isEmpty ? null : title,
        'message': feedback,
        'type': _type,
        'severity': _severity,
        'createdAt': FieldValue.serverTimestamp(),

        // User identity for administrative tracking
        'user': {
          'uid': uid,
          'email': email,
        },

        // Workflow management fields
        'status': 'open', // Statuses: open, in_progress, done
        'adminNotes': null,
      };

      final db = FirebaseFirestore.instance;

      // 1. Save to the central administrative collection
      final docRef = await db.collection('feedback_submissions').add(payload);

      // 2. Save a reference copy under the user's profile for history tracking
      if (uid != null) {
        await db
            .collection('users')
            .doc(uid)
            .collection('feedback')
            .doc(docRef.id)
            .set(payload);
      }

      if (!mounted) return;
      
      // Reset input fields upon success
      _titleController.clear();
      _feedbackController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your feedback has been sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send feedback: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const TopAppBar(title: 'Feedback'),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'We would love to hear your feedback!',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Category selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Type', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _chip('Feedback'),
                      _chip('Bug'),
                      _chip('Suggestion'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Severity slider displayed only for bug reports
                  if (_type == 'Bug') ...[
                    Text('Severity (1 = minor, 5 = critical)',
                        style: theme.textTheme.labelLarge),
                    Slider(
                      value: _severity.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: _severity.toString(),
                      onChanged: _isSending
                          ? null
                          : (v) => setState(() => _severity = v.round()),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Title input
          TextField(
            controller: _titleController,
            enabled: !_isSending,
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),

          const SizedBox(height: 12),

          // Main feedback message input
          TextField(
            controller: _feedbackController,
            enabled: !_isSending,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Enter your feedback here...',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          // Submit button
          FilledButton.icon(
            onPressed: _isSending ? null : _sendFeedbackToFirestore,
            icon: _isSending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_isSending ? 'Sending...' : 'Send Feedback'),
          ),

          const SizedBox(height: 10),
          Text(
            'Submissions are securely stored in Firebase for administrative review.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  /// Builds a selection chip for the feedback type.
  Widget _chip(String label) {
    final selected = _type == label;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: _isSending ? null : (_) => setState(() => _type = label),
    );
  }
}
