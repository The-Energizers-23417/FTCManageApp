import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// FeedbackPage allows authenticated users to submit feedback directly to Firestore.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _feedbackController = TextEditingController();
  bool _isSending = false;

  /// Submits the feedback text to the 'feedback' collection in Firestore.
  Future<void> _sendFeedback() async {
    final user = _auth.currentUser;
    // Basic validation: user must be logged in and feedback must not be empty.
    if (user == null || _feedbackController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await _db.collection('feedback').add({
        'text': _feedbackController.text.trim(),
        'userId': user.uid,
        'userEmail': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear input after successful submission.
      _feedbackController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your feedback!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const TopAppBar(
        title: 'Feedback',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: -1,
        onTabSelected: (i) {},
        items: const [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Let us know what you think!',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'We value your feedback and use it to improve the app.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            
            // Multiline input field for the feedback content.
            TextField(
              controller: _feedbackController,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Type your feedback here...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Submission button with loading indicator.
            ElevatedButton.icon(
              onPressed: _isSending ? null : _sendFeedback,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Submit'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
