// lib/program-files/frontend/pre_match_checklist.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// PreMatchChecklistPage provides a digital checklist for robot inspection and maintenance.
/// Users can create different lists for specific events or general upkeep, assign tasks to members, and track completion.
class PreMatchChecklistPage extends StatefulWidget {
  const PreMatchChecklistPage({super.key});

  @override
  State<PreMatchChecklistPage> createState() => _PreMatchChecklistPageState();
}

class _PreMatchChecklistPageState extends State<PreMatchChecklistPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // The unique identifier for the currently active checklist (e.g., "GENERAL" or an event code).
  String? _selectedKey;
  bool _busy = false;

  /// Returns a reference to the current team's document in Firestore.
  DocumentReference<Map<String, dynamic>> _userDocRef(String uid) =>
      _db.collection('users').doc(uid);

  /// Safely converts a dynamic value to a Map.
  Map<String, dynamic> _map(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Extracts event names from the team's setup data.
  List<String> _readEventCodes(Map<String, dynamic> setupData) {
    final raw = setupData['events'];
    if (raw is! List) return [];
    final out = <String>[];
    for (final e in raw) {
      if (e is Map && e['name'] != null) {
        final s = e['name'].toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  /// Extracts team member first names from the team's setup data.
  List<String> _readTeamMemberNames(Map<String, dynamic> setupData) {
    final raw = setupData['teamMembers'];
    if (raw is! List) return [];
    final out = <String>[];
    for (final m in raw) {
      if (m is Map && m['firstName'] != null) {
        final s = m['firstName'].toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
    final uniq = out.toSet().toList();
    uniq.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return uniq;
  }

  /// Returns a human-readable title for a given checklist key.
  String _labelForKey(String key) =>
      key == 'GENERAL' ? 'General Maintenance' : 'Event $key';

  /// Navigates to the root of the inspection lists in setupData.
  Map<String, dynamic> _readListsRoot(Map<String, dynamic> setupData) {
    final ri = _map(setupData['robotInspection']);
    final lists = _map(ri['lists']);
    return lists;
  }

  /// Reads a specific checklist by its key.
  Map<String, dynamic> _readOneList(Map<String, dynamic> setupData, String key) {
    final lists = _readListsRoot(setupData);
    return _map(lists[key]);
  }

  /// Extracts and filters valid tasks from a checklist map.
  List<Map<String, dynamic>> _readTasks(Map<String, dynamic> list) {
    final raw = list['tasks'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['text'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  /// Persists a checklist and its tasks to Firestore.
  Future<void> _saveList({
    required String uid,
    required String key,
    required Map<String, dynamic> list,
  }) async {
    await _userDocRef(uid).set(
      {
        'setupData': {
          'robotInspection': {
            'lists': {
              key: {
                ...list,
                'updatedAt': FieldValue.serverTimestamp(),
              }
            }
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }
      },
      SetOptions(merge: true),
    );
  }

  /// Ensures a document exists for the selected checklist key.
  Future<void> _ensureListExists({
    required String uid,
    required Map<String, dynamic> setupData,
    required String key,
  }) async {
    final existing = _readOneList(setupData, key);
    if (existing.isNotEmpty) return;

    await _saveList(
      uid: uid,
      key: key,
      list: {
        'label': _labelForKey(key),
        'createdAt': FieldValue.serverTimestamp(),
        'tasks': <Map<String, dynamic>>[],
      },
    );
  }

  /// Opens a sheet for the user to select which checklist to view or create.
  Future<String?> _pickKeySheet({
    required BuildContext context,
    required List<String> events,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              const ListTile(
                title: Text('Select List'),
                subtitle: Text('Pick an event or general maintenance checklist.'),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.build),
                  title: const Text('General Maintenance'),
                  onTap: () => Navigator.pop(ctx, 'GENERAL'),
                ),
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No events found. Configure events in Setup first.'),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('Events', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...events.map((e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.event),
                    title: Text(e),
                    onTap: () => Navigator.pop(ctx, e),
                  ),
                )),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Prompts the user for text input via a modal dialog.
  Future<String?> _textPrompt({required String title, required String hint}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    final text = c.text.trim();
    if (ok == true && text.isNotEmpty) return text;
    return null;
  }

  /// Opens a sheet for the user to assign a task to a specific team member.
  Future<String?> _pickAssignee({
    required BuildContext context,
    required List<String> members,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              const ListTile(
                title: Text('Assign Task'),
                subtitle: Text('Optionally assign this task to a team member.'),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_off),
                  title: const Text('Unassigned'),
                  onTap: () => Navigator.pop(ctx, ''),
                ),
              ),
              const SizedBox(height: 8),
              ...members.map((m) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(m),
                  onTap: () => Navigator.pop(ctx, m),
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  Color _borderColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08);
  }

  /// Helper widget for displaying task metadata badges.
  Widget _chip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    if (user == null) {
      return const Scaffold(
        appBar: TopAppBar(title: 'Robot Inspection'),
        body: Center(child: Text('Not logged in.')),
      );
    }

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Robot Inspection',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(currentIndex: 0, onTabSelected: (_) {}, items: const []),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userDocRef(user.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('Failed to load from Firebase.'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final data = snap.data!.data() ?? {};
          final setupData = _map(data['setupData']);

          final events = _readEventCodes(setupData);
          final members = _readTeamMemberNames(setupData);

          final selectedKey = _selectedKey;

          final list = selectedKey == null ? <String, dynamic>{} : _readOneList(setupData, selectedKey);
          final tasks = selectedKey == null ? <Map<String, dynamic>>[] : _readTasks(list);

          final creatorName = (user.email ?? user.uid).toString();

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
            children: [
              // Header Card for List Selection and Task Creation
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _borderColor(context)),
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active Checklist',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedKey == null ? 'No list selected' : _labelForKey(selectedKey),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                            final picked = await _pickKeySheet(context: context, events: events);
                            if (picked == null) return;

                            setState(() => _selectedKey = picked);

                            setState(() => _busy = true);
                            try {
                              await _ensureListExists(uid: user.uid, setupData: setupData, key: picked);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                          icon: const Icon(Icons.playlist_add_check),
                          label: const Text('Change List'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    // Task Creation Button
                    if (selectedKey != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                            final text = await _textPrompt(
                              title: 'New Task',
                              hint: 'Describe the inspection task…',
                            );
                            if (text == null) return;

                            final assignee = await _pickAssignee(context: context, members: members);
                            if (assignee == null) return;

                            final updated = List<Map<String, dynamic>>.from(tasks)
                              ..add({
                                'text': text,
                                'done': false,
                                'assignedTo': assignee.isEmpty ? null : assignee,
                                'createdByUid': user.uid,
                                'createdByName': creatorName,
                                'createdAt': Timestamp.now(),
                              });

                            setState(() => _busy = true);
                            try {
                              await _saveList(
                                uid: user.uid,
                                key: selectedKey,
                                list: {
                                  'label': (list['label'] ?? _labelForKey(selectedKey)).toString(),
                                  'createdAt': list['createdAt'] ?? FieldValue.serverTimestamp(),
                                  'tasks': updated,
                                },
                              );
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                          icon: const Icon(Icons.add_task),
                          label: const Text('Add Task'),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Task List Content
              if (selectedKey == null)
                _emptyState(context, 'Please select a checklist to begin.')
              else if (tasks.isEmpty)
                _emptyState(context, 'No tasks defined for this list. Add one above.')
              else
                ...List.generate(tasks.length, (i) {
                  final t = tasks[i];
                  final text = (t['text'] ?? '').toString();
                  final done = t['done'] == true;
                  final assignedTo = (t['assignedTo'] ?? '').toString();
                  final createdBy = (t['createdByName'] ?? '').toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _borderColor(context)),
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: Row(
                      children: [
                        // Task Completion Checkbox
                        Checkbox(
                          value: done,
                          onChanged: _busy
                              ? null
                              : (v) async {
                            final updated = List<Map<String, dynamic>>.from(tasks);
                            updated[i] = {
                              ...t,
                              'text': text,
                              'done': v == true,
                            };

                            setState(() => _busy = true);
                            try {
                              await _saveList(
                                uid: user.uid,
                                key: selectedKey,
                                list: {
                                  'label': (list['label'] ?? _labelForKey(selectedKey)).toString(),
                                  'createdAt': list['createdAt'] ?? FieldValue.serverTimestamp(),
                                  'tasks': updated,
                                },
                              );
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                text,
                                style: done
                                    ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                                )
                                    : Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              // Metadata Badges (Creator and Assignee)
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (createdBy.isNotEmpty)
                                    _chip(context, Icons.star_outline, 'Creator: $createdBy'),
                                  if (assignedTo.isNotEmpty)
                                    _chip(context, Icons.person, 'Assigned to: $assignedTo'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Assign Button
                        IconButton(
                          tooltip: 'Update Assignment',
                          onPressed: _busy
                              ? null
                              : () async {
                            final picked = await _pickAssignee(context: context, members: members);
                            if (picked == null) return;

                            final updated = List<Map<String, dynamic>>.from(tasks);
                            updated[i] = {
                              ...t,
                              'assignedTo': picked.isEmpty ? null : picked,
                            };

                            setState(() => _busy = true);
                            try {
                              await _saveList(
                                uid: user.uid,
                                key: selectedKey,
                                list: {
                                  'label': (list['label'] ?? _labelForKey(selectedKey)).toString(),
                                  'createdAt': list['createdAt'] ?? FieldValue.serverTimestamp(),
                                  'tasks': updated,
                                },
                              );
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                          icon: const Icon(Icons.person_add_alt_1),
                        ),
                        // Delete Button
                        IconButton(
                          tooltip: 'Remove Task',
                          onPressed: _busy
                              ? null
                              : () async {
                            final updated = List<Map<String, dynamic>>.from(tasks)..removeAt(i);

                            setState(() => _busy = true);
                            try {
                              await _saveList(
                                uid: user.uid,
                                key: selectedKey,
                                list: {
                                  'label': (list['label'] ?? _labelForKey(selectedKey)).toString(),
                                  'createdAt': list['createdAt'] ?? FieldValue.serverTimestamp(),
                                  'tasks': updated,
                                },
                              );
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  /// UI for empty list states.
  Widget _emptyState(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor(context)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).disabledColor),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
