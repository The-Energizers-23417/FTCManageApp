import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';

/// HourRegistrationPage allows team members to track their work hours.
/// Features include clocking in/out, adding notes, and reviewing past sessions.
class HourRegistrationPage extends StatefulWidget {
  const HourRegistrationPage({super.key});

  @override
  State<HourRegistrationPage> createState() => _HourRegistrationPageState();
}

class _HourRegistrationPageState extends State<HourRegistrationPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // State for loading team members
  bool _loadingMembers = true;
  String? _membersError;

  List<String> _memberNames = [];
  String? _selectedMemberName;

  bool _busy = false;

  // Ticker to update the elapsed time display in real-time
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadTeamMembers();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Helper to get the Firestore collection reference for hour sessions.
  CollectionReference<Map<String, dynamic>> _sessionsRef(String uid) {
    return _db.collection('users').doc(uid).collection('hourSessions');
  }

  /// Returns a stream of the currently active session for the selected member.
  Stream<QuerySnapshot<Map<String, dynamic>>> _runningSessionStream(String uid) {
    final member = _selectedMemberName;
    if (member == null || member.trim().isEmpty) {
      return const Stream.empty();
    }

    return _sessionsRef(uid)
        .where('memberName', isEqualTo: member)
        .where('isRunning', isEqualTo: true)
        .limit(1)
        .snapshots();
  }

  /// Returns a stream of completed sessions for the selected member.
  Stream<QuerySnapshot<Map<String, dynamic>>> _historyStream(String uid) {
    final member = _selectedMemberName;
    if (member == null || member.trim().isEmpty) {
      return const Stream.empty();
    }

    return _sessionsRef(uid)
        .where('memberName', isEqualTo: member)
        .where('isRunning', isEqualTo: false)
        .limit(50)
        .snapshots();
  }

  /// Loads the list of team members defined in the app setup.
  Future<void> _loadTeamMembers() async {
    setState(() {
      _loadingMembers = true;
      _membersError = null;
    });

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loadingMembers = false;
        _membersError = 'You are not signed in.';
      });
      return;
    }

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final setupData = (data['setupData'] as Map?)?.cast<String, dynamic>() ?? {};
      final teamMembers = setupData['teamMembers'];

      final names = <String>[];

      if (teamMembers is List) {
        for (final e in teamMembers) {
          if (e is Map && e['firstName'] != null) {
            final n = e['firstName'].toString().trim();
            if (n.isNotEmpty) names.add(n);
          }
        }
      }

      // Sort names alphabetically
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _memberNames = names;
        _selectedMemberName = (_selectedMemberName != null && names.contains(_selectedMemberName))
            ? _selectedMemberName
            : (names.isNotEmpty ? names.first : null);
        _loadingMembers = false;
      });
    } catch (e) {
      setState(() {
        _loadingMembers = false;
        _membersError = e.toString();
      });
    }
  }

  /// Starts a new tracking session for the selected member.
  Future<void> _clockIn(String uid) async {
    if (_selectedMemberName == null) {
      _toast('Please select a team member first.');
      return;
    }

    final noteController = TextEditingController();

    // Show confirmation and optional note dialog
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clock in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'You are clocking in as:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedMemberName!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Short note (optional)',
                hintText: 'What are you going to work on?',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final now = Timestamp.now();

      await _sessionsRef(uid).add({
        'isRunning': true,
        'memberName': _selectedMemberName,
        'clockInNote': noteController.text.trim(),
        'startAt': now,
        'endAt': null,
        'durationMinutes': null,
        'review': null,
        'effort': null,
        'effectiveness': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _toast('Clocked in!');
    } catch (e) {
      _toast('Clock in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ends the current tracking session and prompts the user for a summary/rating.
  Future<void> _clockOutWithReview({
    required String uid,
    required DocumentReference<Map<String, dynamic>> sessionRef,
    required Timestamp? startAt,
  }) async {
    final res = await showDialog<_ReviewResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReviewDialog(now: _now),
    );

    if (res == null) return;

    setState(() => _busy = true);
    try {
      final end = Timestamp.now();
      final start = startAt?.toDate();
      final durationMinutes = (start == null) ? null : DateTime.now().difference(start).inMinutes;

      await sessionRef.update({
        'isRunning': false,
        'endAt': end,
        'durationMinutes': durationMinutes,
        'review': res.whatDidYouDo.trim(),
        'effort': res.effort,
        'effectiveness': res.effectiveness,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _toast('Clocked out & saved!');
    } catch (e) {
      _toast('Clock out failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Manually adds a session that happened in the past.
  Future<void> _addManualSession(String uid) async {
    if (_selectedMemberName == null) {
      _toast('Please select a team member first.');
      return;
    }

    final res = await showDialog<_ManualEntryResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManualEntryDialog(
        initialMemberName: _selectedMemberName!,
      ),
    );

    if (res == null) return;

    setState(() => _busy = true);
    try {
      final start = res.startAt;
      final end = res.endAt;
      final durationMinutes = end.difference(start).inMinutes;

      await _sessionsRef(uid).add({
        'isRunning': false,
        'memberName': res.memberName,
        'clockInNote': 'Manual entry',
        'startAt': Timestamp.fromDate(start),
        'endAt': Timestamp.fromDate(end),
        'durationMinutes': durationMinutes,
        'review': res.review.trim(),
        'effort': res.effort,
        'effectiveness': res.effectiveness,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _toast('Manual session saved!');
    } catch (e) {
      _toast('Failed to save manual session: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Hour Registration',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: SafeArea(
        child: user == null
            ? const Center(child: Text('You are not signed in.'))
            : _loadingMembers
            ? const Center(child: CircularProgressIndicator())
            : _membersError != null
            ? _errorState(context, _membersError!)
            : RefreshIndicator(
          onRefresh: _loadTeamMembers,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
            children: [
              _memberCard(context),
              const SizedBox(height: 12),
              // Current Running Session UI
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _runningSessionStream(user.uid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _errorCard(context, 'Could not load running session.');
                  }
                  final docs = snap.data?.docs ?? [];
                  final running = docs.isNotEmpty ? docs.first : null;
                  return _runningCard(context, uid: user.uid, runningDoc: running);
                },
              ),
              const SizedBox(height: 12),
              _historyHeader(context, user.uid),
              const SizedBox(height: 8),
              // Past Sessions List
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _historyStream(user.uid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _errorCard(context, 'Could not load history.');
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final docs = snap.data!.docs.toList();

                  // Sort history by start time descending
                  docs.sort((a, b) {
                    final ta = (a.data()['startAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
                    final tb = (b.data()['startAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
                    return tb.compareTo(ta);
                  });

                  final limited = docs.take(25).toList();

                  if (limited.isEmpty) {
                    return _emptyCard(context, 'No completed sessions yet.');
                  }

                  return Column(
                    children: limited.map((d) => _historyTile(context, d.data())).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// UI for error states.
  Widget _errorState(BuildContext context, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load data:', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 6),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadTeamMembers,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  /// Standard card container for consistent UI.
  Widget _card(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  /// UI helper for inline error cards.
  Widget _errorCard(BuildContext context, String msg) {
    final theme = Theme.of(context);
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
          Expanded(child: Text(msg)),
        ],
      ),
    );
  }

  /// UI helper for empty state notifications.
  Widget _emptyCard(BuildContext context, String msg) {
    return _card(
      context,
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).hintColor),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ],
      ),
    );
  }

  /// Card for selecting which team member is using the tracker.
  Widget _memberCard(BuildContext context) {
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Who are you?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh team members',
                onPressed: _busy ? null : _loadTeamMembers,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_memberNames.isEmpty)
            Text(
              'No team members found in Setup → Team members.\nPlease add them first.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedMemberName,
              items: _memberNames.map((n) => DropdownMenuItem<String>(value: n, child: Text(n))).toList(),
              onChanged: _busy
                  ? null
                  : (v) {
                setState(() => _selectedMemberName = v);
              },
              decoration: const InputDecoration(
                labelText: 'Selected team member',
                prefixIcon: Icon(Icons.person),
              ),
            ),
        ],
      ),
    );
  }

  /// Card displaying the status of an active tracking session.
  Widget _runningCard(
      BuildContext context, {
        required String uid,
        required QueryDocumentSnapshot<Map<String, dynamic>>? runningDoc,
      }) {
    final theme = Theme.of(context);

    final isRunning = runningDoc != null;
    final data = runningDoc?.data() ?? {};
    final memberName = (data['memberName'] ?? '').toString();
    final startAt = data['startAt'] as Timestamp?;

    Duration? elapsed;
    if (startAt != null) {
      elapsed = _now.difference(startAt.toDate());
      if (elapsed.isNegative) elapsed = Duration.zero;
    }

    String formatDuration(Duration? d) {
      if (d == null) return '—';
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      final s = d.inSeconds.remainder(60);
      final hh = h.toString().padLeft(2, '0');
      final mm = m.toString().padLeft(2, '0');
      final ss = s.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    }

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isRunning ? Icons.timer : Icons.timer_off, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Current session',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!isRunning)
            Text(
              'No active session.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            )
          else ...[
            Text(
              memberName.isEmpty ? 'Unknown member' : memberName,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 6),
                Text('Elapsed: ${formatDuration(elapsed)}', style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : isRunning
                      ? null
                      : () => _clockIn(uid),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Clock in'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : isRunning
                      ? () => _clockOutWithReview(
                    uid: uid,
                    sessionRef: runningDoc!.reference,
                    startAt: startAt,
                  )
                      : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Clock out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyHeader(BuildContext context, String uid) {
    return Row(
      children: [
        Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          'Recent sessions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _busy ? null : () => _addManualSession(uid),
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add manually'),
        ),
      ],
    );
  }

  /// UI for a single history entry in the session list.
  Widget _historyTile(BuildContext context, Map<String, dynamic> d) {
    final theme = Theme.of(context);

    final member = (d['memberName'] ?? 'Unknown').toString();
    final startAt = d['startAt'] as Timestamp?;
    final endAt = d['endAt'] as Timestamp?;
    final durationMinutes = d['durationMinutes'];
    final review = (d['review'] ?? '').toString();
    final effort = d['effort'];
    final effectiveness = d['effectiveness'];

    String dateLine() {
      if (startAt == null) return '';
      final s = startAt.toDate();
      final e = endAt?.toDate();
      String two(int x) => x.toString().padLeft(2, '0');
      final startStr = '${two(s.day)}/${two(s.month)}/${s.year} ${two(s.hour)}:${two(s.minute)}';
      if (e == null) return startStr;
      final endStr = '${two(e.hour)}:${two(e.minute)}';
      return '$startStr → $endStr';
    }

    String durLine() {
      if (durationMinutes is int) {
        final h = durationMinutes ~/ 60;
        final m = durationMinutes % 60;
        if (h <= 0) return '${m}m';
        return '${h}h ${m}m';
      }
      return '—';
    }

    String scoreLine() {
      final e = (effort is int) ? effort : null;
      final f = (effectiveness is int) ? effectiveness : null;
      if (e == null && f == null) return 'No ratings';
      return 'Effort: ${e ?? "—"}/5 • Effectiveness: ${f ?? "—"}/5';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.35)),
                ),
                child: Text(
                  durLine(),
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateLine(),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 6),
          Text(scoreLine(), style: theme.textTheme.bodySmall),
          if (review.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Data model for the session review dialog.
class _ReviewResult {
  final String whatDidYouDo;
  final int effort;
  final int effectiveness;

  const _ReviewResult({
    required this.whatDidYouDo,
    required this.effort,
    required this.effectiveness,
  });
}

/// Dialog for entering a review and ratings after a session.
class _ReviewDialog extends StatefulWidget {
  final DateTime now;

  const _ReviewDialog({required this.now});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _controller = TextEditingController();
  int _effort = 3;
  int _effectiveness = 3;

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please write a short summary.');
      return;
    }
    Navigator.pop(
      context,
      _ReviewResult(
        whatDidYouDo: text,
        effort: _effort,
        effectiveness: _effectiveness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Session review'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Before you clock out, please fill in a quick review.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'What did you do?',
                hintText: 'Short summary of the work you did...',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 14),
            _slider(
              context,
              label: 'Effort (how hard did you work?)',
              value: _effort,
              onChanged: (v) => setState(() => _effort = v),
            ),
            const SizedBox(height: 10),
            _slider(
              context,
              label: 'Effectiveness (how productive was it?)',
              value: _effectiveness,
              onChanged: (v) => setState(() => _effectiveness = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Save & clock out'),
        ),
      ],
    );
  }

  /// Helper widget for consistent rating sliders.
  Widget _slider(
      BuildContext context, {
        required String label,
        required int value,
        required ValueChanged<int> onChanged,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$value',
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
              ),
              child: Text(
                '$value',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Data model for the manual entry dialog.
class _ManualEntryResult {
  final String memberName;
  final DateTime startAt;
  final DateTime endAt;
  final String review;
  final int effort;
  final int effectiveness;

  const _ManualEntryResult({
    required this.memberName,
    required this.startAt,
    required this.endAt,
    required this.review,
    required this.effort,
    required this.effectiveness,
  });
}

/// Dialog for manually entering hours after the session is over.
class _ManualEntryDialog extends StatefulWidget {
  final String initialMemberName;

  const _ManualEntryDialog({required this.initialMemberName});

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final _controller = TextEditingController();
  int _effort = 3;
  int _effectiveness = 3;

  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = now;
    _startTime = TimeOfDay(hour: now.hour - 1, minute: now.minute);
    _endTime = TimeOfDay.fromDateTime(now);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickStartTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (t != null) setState(() => _startTime = t);
  }

  Future<void> _pickEndTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (t != null) setState(() => _endTime = t);
  }

  void _submit() {
    final review = _controller.text.trim();
    if (review.isEmpty) {
      setState(() => _error = 'Please write a short summary.');
      return;
    }

    final start = DateTime(_date.year, _date.month, _date.day, _startTime.hour, _startTime.minute);
    final end = DateTime(_date.year, _date.month, _date.day, _endTime.hour, _endTime.minute);

    if (end.isBefore(start)) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    Navigator.pop(
      context,
      _ManualEntryResult(
        memberName: widget.initialMemberName,
        startAt: start,
        endAt: end,
        review: review,
        effort: _effort,
        effectiveness: _effectiveness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String two(int x) => x.toString().padLeft(2, '0');
    final dateStr = '${two(_date.day)}/${two(_date.month)}/${_date.year}';
    final startStr = '${two(_startTime.hour)}:${two(_startTime.minute)}';
    final endStr = '${two(_endTime.hour)}:${two(_endTime.minute)}';

    return AlertDialog(
      title: const Text('Manual Hour Entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(dateStr),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start'),
                    subtitle: Text(startStr),
                    onTap: _pickStartTime,
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End'),
                    subtitle: Text(endStr),
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            const Divider(),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'What did you do?',
                hintText: 'Work summary...',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 14),
            _slider(
              label: 'Effort (1-5)',
              value: _effort,
              onChanged: (v) => setState(() => _effort = v),
            ),
            _slider(
              label: 'Effectiveness (1-5)',
              value: _effectiveness,
              onChanged: (v) => setState(() => _effectiveness = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save session')),
      ],
    );
  }

  Widget _slider({required String label, required int value, required ValueChanged<int> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}
