import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

// -------------------------------------------------------------
// ENUMS AND EXTENSIONS
// -------------------------------------------------------------

/// Defines the various stages of a task in the team's workflow.
enum ScrumColumnType { backlog, todo, doing, review, done }

extension ScrumColumnTypeExt on ScrumColumnType {
  String get id {
    switch (this) {
      case ScrumColumnType.backlog: return 'backlog';
      case ScrumColumnType.todo: return 'todo';
      case ScrumColumnType.doing: return 'doing';
      case ScrumColumnType.review: return 'review';
      case ScrumColumnType.done: return 'done';
    }
  }

  String get title {
    switch (this) {
      case ScrumColumnType.backlog: return 'Backlog';
      case ScrumColumnType.todo: return 'To Do';
      case ScrumColumnType.doing: return 'Doing';
      case ScrumColumnType.review: return 'Review';
      case ScrumColumnType.done: return 'Done';
    }
  }
}

/// Represents the urgency level of a team task.
enum TaskPriority { low, normal, high }

extension TaskPriorityExt on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.low: return "Low";
      case TaskPriority.normal: return "Normal";
      case TaskPriority.high: return "High";
    }
  }

  static TaskPriority fromId(String? id) {
    switch (id) {
      case "low": return TaskPriority.low;
      case "high": return TaskPriority.high;
      default: return TaskPriority.normal;
    }
  }
}

// -------------------------------------------------------------
// DATA MODELS
// -------------------------------------------------------------

/// Model representing a task within the team's task list.
class TeamTask {
  final String id;
  final String title;
  final String columnId;
  final List<String> assignees;
  final List<String> roles;
  final DateTime? deadline;
  final TaskPriority priority;

  TeamTask({
    required this.id,
    required this.title,
    required this.columnId,
    required this.assignees,
    required this.roles,
    required this.deadline,
    required this.priority,
  });

  /// Factory constructor to create a TeamTask from a Firestore document snapshot.
  factory TeamTask.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final Timestamp? dl = data['deadline'];

    return TeamTask(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      columnId: (data['columnId'] ?? 'todo').toString(),
      assignees: (data['assignees'] as List<dynamic>? ?? []).cast<String>(),
      roles: (data['roles'] as List<dynamic>? ?? []).cast<String>(),
      deadline: dl != null ? dl.toDate() : null,
      priority: TaskPriorityExt.fromId(data['priority']?.toString()),
    );
  }
}

// -------------------------------------------------------------
// TASK LIST PAGE
// -------------------------------------------------------------

/// TaskListTeamPage provides a flat, searchable, and sortable list view of all team tasks.
/// This acts as a centralized list interface for the team's Scrum data.
class TaskListTeamPage extends StatefulWidget {
  const TaskListTeamPage({super.key});

  @override
  State<TaskListTeamPage> createState() => _TaskListTeamPageState();
}

class _TaskListTeamPageState extends State<TaskListTeamPage> {
  late String _boardId;

  // Configuration data loaded from team setup.
  List<String> _teamMembers = [];
  List<String> _roles = [];

  bool _isLoading = true;

  // Active UI filters.
  String _selectedPerson = "";
  String _selectedRole = "";

  // Active sorting states.
  bool _sortDeadlineAsc = true;
  bool _sortPriorityAsc = true;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  /// Initial state setup: identifies the correct Scrum board and loads team metadata.
  Future<void> _setup() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _boardId = "public-board";
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _boardId = "default-board-${user.uid}";
    await _loadTeamData(user.uid);

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  /// Extracts members and roles from the user's setupData in Firestore.
  Future<void> _loadTeamData(String uid) async {
    final userDoc =
    await FirebaseFirestore.instance.collection("users").doc(uid).get();

    if (!userDoc.exists) return;

    final setup = (userDoc.data()?["setupData"]) as Map<String, dynamic>?;
    if (setup == null) return;

    final membersRaw = setup["teamMembers"] as List<dynamic>? ?? [];

    final tempMembers = <String>[];
    final tempRoles = <String>{};

    for (var m in membersRaw) {
      if (m is Map<String, dynamic>) {
        final n = (m["firstName"] as String? ?? "").trim();
        if (n.isNotEmpty) tempMembers.add(n);

        for (var r in (m["roles"] as List? ?? [])) {
          if (r is String && r.trim().isNotEmpty) tempRoles.add(r.trim());
        }
      }
    }

    // Alphabetic sorting for cleaner dropdown menus.
    tempMembers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _teamMembers = tempMembers;
    _roles = tempRoles.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Returns a stream of tasks from the Scrum board collection.
  Stream<List<TeamTask>> _taskStream() {
    return FirebaseFirestore.instance
        .collection("scrumBoards")
        .doc(_boardId)
        .collection("tasks")
        .orderBy("order")
        .snapshots()
        .map((snap) => snap.docs.map(TeamTask.fromFirestore).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopAppBar(
        title: "Team Task List",
        showThemeToggle: true,
        showLogout: true,
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showAddTaskDialog(context),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Filter selection area.
          _buildFilters(context),
          // Sorting controls area.
          _buildSortButtons(context),
          Expanded(
            child: StreamBuilder<List<TeamTask>>(
              stream: _taskStream(),
              builder: (ctx, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                List<TeamTask> tasks = snapshot.data!;

                // Apply currently selected UI filters.
                if (_selectedPerson.isNotEmpty) {
                  tasks = tasks.where((t) => t.assignees.contains(_selectedPerson)).toList();
                }
                if (_selectedRole.isNotEmpty) {
                  tasks = tasks.where((t) => t.roles.contains(_selectedRole)).toList();
                }

                // Apply currently selected sorting logic.
                tasks = _applySorting(tasks);

                return ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (ctx, i) =>
                      _buildTaskTile(context, tasks[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // FILTER COMPONENTS
  // -------------------------------------------------------------

  /// Builds dropdowns for filtering the task list by assignee or role.
  Widget _buildFilters(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 650;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          // Filter by Person
          SizedBox(
            width: isPhone ? double.infinity : 250,
            child: DropdownButtonFormField<String>(
              value: _selectedPerson.isEmpty ? null : _selectedPerson,
              decoration: const InputDecoration(
                labelText: "Filter by Assignee",
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: "", child: Text("All members")),
                ..._teamMembers.map((m) => DropdownMenuItem(value: m, child: Text(m))),
              ],
              onChanged: (v) => setState(() => _selectedPerson = v ?? ""),
            ),
          ),
          // Filter by Role
          SizedBox(
            width: isPhone ? double.infinity : 250,
            child: DropdownButtonFormField<String>(
              value: _selectedRole.isEmpty ? null : _selectedRole,
              decoration: const InputDecoration(
                labelText: "Filter by Role",
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: "", child: Text("All roles")),
                ..._roles.map((r) => DropdownMenuItem(value: r, child: Text(r))),
              ],
              onChanged: (v) => setState(() => _selectedRole = v ?? ""),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // SORTING COMPONENTS
  // -------------------------------------------------------------

  /// Builds toggle buttons for sorting the task list.
  Widget _buildSortButtons(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          ElevatedButton.icon(
            icon: Icon(_sortDeadlineAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
            label: const Text("Sort by Deadline"),
            onPressed: () { setState(() => _sortDeadlineAsc = !_sortDeadlineAsc); },
          ),
          ElevatedButton.icon(
            icon: Icon(_sortPriorityAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
            label: const Text("Sort by Priority"),
            onPressed: () { setState(() => _sortPriorityAsc = !_sortPriorityAsc); },
          ),
        ],
      ),
    );
  }

  /// Logic to sort tasks based on selected criteria (Deadlines then Priority).
  List<TeamTask> _applySorting(List<TeamTask> tasks) {
    tasks.sort((a, b) {
      final aD = a.deadline?.millisecondsSinceEpoch ?? 9999999999999;
      final bD = b.deadline?.millisecondsSinceEpoch ?? 9999999999999;

      final deadlineCmp = _sortDeadlineAsc ? aD.compareTo(bD) : bD.compareTo(aD);
      if (deadlineCmp != 0) return deadlineCmp;

      final aP = a.priority.index;
      final bP = b.priority.index;
      return _sortPriorityAsc ? aP.compareTo(bP) : bP.compareTo(aP);
    });

    return tasks;
  }

  // -------------------------------------------------------------
  // LIST ITEM COMPONENTS
  // -------------------------------------------------------------

  /// Builds an individual list tile for a task.
  Widget _buildTaskTile(BuildContext context, TeamTask task) {
    final theme = Theme.of(context);
    final column = ScrumColumnType.values.firstWhere((c) => c.id == task.columnId);

    final deadlineText = task.deadline == null
        ? "No deadline"
        : "${task.deadline!.day}/${task.deadline!.month}/${task.deadline!.year}";

    final bool isDone = task.columnId == "done";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        title: Text(
          task.title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Stage: ${column.title}"),
            if (task.assignees.isNotEmpty) Text("Assigned: ${task.assignees.join(', ')}"),
            if (task.roles.isNotEmpty) Text("Roles: ${task.roles.join(', ')}"),
            Text("Deadline: $deadlineText"),
          ],
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _priorityChip(task.priority, context),
              const SizedBox(width: 8),
              if (!isDone)
                IconButton(
                  tooltip: "Mark as Done",
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: () => _markTaskDone(task),
                ),
            ],
          ),
        ),
        onTap: () => _openTaskDialog(context, task),
      ),
    );
  }

  /// Builds a visual chip representing task priority.
  Widget _priorityChip(TaskPriority p, BuildContext context) {
    Color bg = Colors.grey;
    switch (p) {
      case TaskPriority.high: bg = Colors.red; break;
      case TaskPriority.normal: bg = Theme.of(context).colorScheme.primary; break;
      case TaskPriority.low: bg = Theme.of(context).colorScheme.secondary; break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(p.label, style: const TextStyle(color: Colors.white)),
    );
  }

  // -------------------------------------------------------------
  // TASK ACTIONS
  // -------------------------------------------------------------

  /// Updates a task's stage to 'done' in Firestore and shows a success dialog.
  Future<void> _markTaskDone(TeamTask task) async {
    final ref = FirebaseFirestore.instance
        .collection("scrumBoards").doc(_boardId)
        .collection("tasks").doc(task.id);

    await ref.update({"columnId": "done"});

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("🎉 Task Completed!"),
          content: Text("Great job finishing '${task.title}'!"),
          actions: [
            TextButton(child: const Text("Nice!"), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      );
    }
  }

  /// Opens a modal dialog to view static details of a task.
  void _openTaskDialog(BuildContext context, TeamTask task) {
    final column = ScrumColumnType.values.firstWhere((c) => c.id == task.columnId);
    final String deadlineText = task.deadline == null
        ? "No deadline"
        : "${task.deadline!.day}/${task.deadline!.month}/${task.deadline!.year}";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Stage: ${column.title}"),
              if (task.assignees.isNotEmpty) Text("Assigned: ${task.assignees.join(', ')}"),
              if (task.roles.isNotEmpty) Text("Roles: ${task.roles.join(', ')}"),
              Text("Deadline: $deadlineText"),
              const SizedBox(height: 12),
              _priorityChip(task.priority, context),
            ],
          ),
        ),
        actions: [
          TextButton(child: const Text("Close"), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  /// Opens an interactive modal dialog to create a new team task.
  Future<void> _showAddTaskDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    String? selectedPerson;
    String? selectedRole;
    TaskPriority selectedPriority = TaskPriority.normal;
    DateTime? selectedDeadline;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text("Add New Task"),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Task Title")),
                  const SizedBox(height: 12),
                  // Assignee Selection Dropdown
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "Assign Member"),
                    items: _teamMembers.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (v) => setStateDialog(() => selectedPerson = v),
                  ),
                  const SizedBox(height: 12),
                  // Role/Subteam Selection Dropdown
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "Associated Role"),
                    items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setStateDialog(() => selectedRole = v),
                  ),
                  const SizedBox(height: 12),
                  // Priority Selection Dropdown
                  DropdownButtonFormField<TaskPriority>(
                    value: selectedPriority,
                    decoration: const InputDecoration(labelText: "Priority"),
                    items: TaskPriority.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
                    onChanged: (v) { if (v != null) setStateDialog(() => selectedPriority = v); },
                  ),
                  const SizedBox(height: 12),
                  // Deadline Selection Button
                  ElevatedButton(
                    child: Text(selectedDeadline == null
                        ? "Pick Deadline"
                        : "Deadline: ${selectedDeadline!.day}/${selectedDeadline!.month}/${selectedDeadline!.year}"),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx, initialDate: DateTime.now(),
                        firstDate: DateTime(2023), lastDate: DateTime(2050),
                      );
                      if (picked != null) setStateDialog(() => selectedDeadline = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(ctx)),
              ElevatedButton(
                child: const Text("Save Task"),
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) return;

                  final taskRef = FirebaseFirestore.instance
                      .collection("scrumBoards").doc(_boardId)
                      .collection("tasks").doc();

                  // Commit the new task to the global Scrum board.
                  await taskRef.set({
                    "title": titleCtrl.text.trim(),
                    "columnId": "todo",
                    "assignees": selectedPerson != null ? [selectedPerson!] : [],
                    "roles": selectedRole != null ? [selectedRole!] : [],
                    "priority": selectedPriority.label.toLowerCase(),
                    "deadline": selectedDeadline != null ? Timestamp.fromDate(selectedDeadline!) : null,
                    "order": DateTime.now().millisecondsSinceEpoch,
                  });

                  if (mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
