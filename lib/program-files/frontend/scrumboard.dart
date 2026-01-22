// lib/program-files/frontend/scrumboard.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// Defines the fixed stages of a task in the Scrum process.
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

  int get defaultOrder {
    switch (this) {
      case ScrumColumnType.backlog: return 0;
      case ScrumColumnType.todo: return 1;
      case ScrumColumnType.doing: return 2;
      case ScrumColumnType.review: return 3;
      case ScrumColumnType.done: return 4;
    }
  }
}

/// Represents the importance level of a task.
enum TaskPriority { low, normal, high }

extension TaskPriorityExt on TaskPriority {
  String get id {
    switch (this) {
      case TaskPriority.low: return 'low';
      case TaskPriority.normal: return 'normal';
      case TaskPriority.high: return 'high';
    }
  }

  String get label {
    switch (this) {
      case TaskPriority.low: return 'Low';
      case TaskPriority.normal: return 'Normal';
      case TaskPriority.high: return 'High';
    }
  }

  int get sortRank {
    // Used for sorting: High priority should appear first.
    switch (this) {
      case TaskPriority.high: return 0;
      case TaskPriority.normal: return 1;
      case TaskPriority.low: return 2;
    }
  }

  static TaskPriority fromId(String? id) {
    switch (id) {
      case 'low': return TaskPriority.low;
      case 'high': return TaskPriority.high;
      case 'normal':
      default: return TaskPriority.normal;
    }
  }
}

/// Data model for a single task within the Scrum board.
class ScrumTask {
  final String id;
  final String title;
  final String? description;
  final String columnId;

  // Supports both legacy single assignee and new multi-assignee models.
  final String? assigneeName;
  final List<String> assignees;

  // Specific team roles associated with the task (e.g. CAD, Mechanical).
  final List<String> roles;

  final String? assigneeId;
  final DateTime? deadline;
  final int order;
  final TaskPriority priority;

  ScrumTask({
    required this.id,
    required this.title,
    required this.columnId,
    required this.order,
    required this.priority,
    this.description,
    this.assigneeName,
    required this.assignees,
    required this.roles,
    this.assigneeId,
    this.deadline,
  });

  factory ScrumTask.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final Timestamp? deadlineTs = data['deadline'];

    final assigneesRaw = data['assignees'] as List<dynamic>?;
    final assignees = assigneesRaw == null
        ? <String>[]
        : assigneesRaw.whereType<String>().toList();

    final rolesRaw = data['roles'] as List<dynamic>?;
    final roles =
    rolesRaw == null ? <String>[] : rolesRaw.whereType<String>().toList();

    final priorityId = data['priority'] as String? ?? 'normal';

    return ScrumTask(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'],
      columnId: data['columnId'] ?? 'backlog',
      assigneeName: data['assigneeName'],
      assignees: assignees,
      roles: roles,
      assigneeId: data['assigneeId'],
      deadline: deadlineTs != null ? deadlineTs.toDate() : null,
      order: data['order'] ?? 0,
      priority: TaskPriorityExt.fromId(priorityId),
    );
  }
}

/// Data model for an item within a task's checklist.
class ScrumSubtask {
  final String id;
  final String title;
  final bool isDone;

  ScrumSubtask({
    required this.id,
    required this.title,
    required this.isDone,
  });

  factory ScrumSubtask.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScrumSubtask(
      id: doc.id,
      title: data['title'] ?? '',
      isDone: data['isDone'] ?? false,
    );
  }
}

/// ScrumBoardPage provides a digital Kanban board for managing team tasks.
/// It features columns for different workflow stages, task priority management, and checklists.
class ScrumBoardPage extends StatefulWidget {
  const ScrumBoardPage({super.key});

  @override
  State<ScrumBoardPage> createState() => _ScrumBoardPageState();
}

class _ScrumBoardPageState extends State<ScrumBoardPage> {
  late String _boardId;
  bool _isInitializing = true;

  String _personFilter = '';

  // Lists of members and roles derived from team setup data.
  List<String> _teamMembers = [];
  List<String> _allRoles = [];

  @override
  void initState() {
    super.initState();
    _initBoard();
  }

  /// Initializes the board ID and ensures all required structure exists in Firestore.
  Future<void> _initBoard() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      // Assign a unique board ID per team or fallback to a public board.
      if (user == null) {
        _boardId = 'public-board';
      } else {
        _boardId = 'default-board-${user.uid}';
      }

      await _ensureBoardAndColumns(_boardId);

      if (user != null) {
        await _loadTeamData(user.uid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing board: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  /// Creates board and column documents if they do not yet exist in Firestore.
  Future<void> _ensureBoardAndColumns(String boardId) async {
    final boardRef =
    FirebaseFirestore.instance.collection('scrumBoards').doc(boardId);

    final boardSnapshot = await boardRef.get();
    if (!boardSnapshot.exists) {
      await boardRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'name': 'Default Scrum Board',
      });
    }

    final columnsRef = boardRef.collection('columns');
    for (final columnType in ScrumColumnType.values) {
      final docId = columnType.id;
      final colDoc = await columnsRef.doc(docId).get();
      if (!colDoc.exists) {
        await columnsRef.doc(docId).set({
          'title': columnType.title,
          'order': columnType.defaultOrder,
          'type': columnType.id,
        });
      }
    }
  }

  /// Extracts team members and unique roles from the user's setupData in Firestore.
  Future<void> _loadTeamData(String uid) async {
    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userDoc.exists) return;

      final rootData = userDoc.data() as Map<String, dynamic>;
      final setupData = rootData['setupData'] as Map<String, dynamic>?;

      if (setupData == null) return;

      final teamMembersRaw = setupData['teamMembers'] as List<dynamic>?;

      final members = <String>[];
      final roleSet = <String>{};

      if (teamMembersRaw != null) {
        for (final m in teamMembersRaw) {
          if (m is Map<String, dynamic>) {
            final name = m['firstName'] as String? ?? '';
            if (name.isNotEmpty) members.add(name);
            
            final rolesRaw = m['roles'] as List<dynamic>?;
            if (rolesRaw != null) {
              for (final r in rolesRaw) {
                if (r is String && r.isNotEmpty) roleSet.add(r);
              }
            }
          }
        }
      }

      members.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final roles = roleSet.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _teamMembers = members;
        _allRoles = roles;
      });
    } catch (e) {
      // Fail silently if team data cannot be loaded.
    }
  }

  /// Returns the reference to the tasks collection for the current board.
  CollectionReference<Map<String, dynamic>> _tasksCollection() {
    return FirebaseFirestore.instance
        .collection('scrumBoards')
        .doc(_boardId)
        .collection('tasks');
  }

  /// Determines the next sort order value for a task within a specific column.
  Future<int> _getNextOrderForColumn(String columnId) async {
    final snapshot =
    await _tasksCollection().where('columnId', isEqualTo: columnId).get();

    int maxOrder = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final o = (data['order'] ?? 0) as int;
      if (o > maxOrder) maxOrder = o;
    }
    return maxOrder + 1;
  }

  Future<void> _addTask(String columnId) async {
    await _showTaskDialog(columnId: columnId);
  }

  Future<void> _editTask(ScrumTask task) async {
    await _showTaskDialog(existingTask: task);
  }

  /// Confirms and performs the deletion of a task and its subtasks.
  Future<void> _deleteTask(ScrumTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Permanently delete \"${task.title}\"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final taskRef = _tasksCollection().doc(task.id);

      // Clean up all associated subtasks.
      final subSnap = await taskRef.collection('subtasks').get();
      for (final d in subSnap.docs) {
        await d.reference.delete();
      }

      await taskRef.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting task: $e')),
        );
      }
    }
  }

  /// Unified dialog for adding or updating task details.
  Future<void> _showTaskDialog({
    String? columnId,
    ScrumTask? existingTask,
  }) async {
    final now = DateTime.now();
    final user = FirebaseAuth.instance.currentUser;

    final isEdit = existingTask != null;

    String title = existingTask?.title ?? '';
    String description = existingTask?.description ?? '';
    DateTime? deadline = existingTask?.deadline;

    final titleController = TextEditingController(text: title);
    final descriptionController = TextEditingController(text: description);
    final deadlineController = TextEditingController(
      text: deadline == null
          ? ''
          : '${deadline.day.toString().padLeft(2, '0')}/${deadline.month.toString().padLeft(2, '0')}/${deadline.year}',
    );

    final Set<String> selectedAssignees = {
      ...?existingTask?.assignees,
    };
    final Set<String> selectedRoles = {
      ...?existingTask?.roles,
    };

    TaskPriority selectedPriority =
        existingTask?.priority ?? TaskPriority.normal;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Task' : 'Add Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 12),

                    // Priority Selector
                    DropdownButtonFormField<TaskPriority>(
                      value: selectedPriority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: TaskPriority.values
                          .map(
                            (p) => DropdownMenuItem<TaskPriority>(
                          value: p,
                          child: Text(p.label),
                        ),
                      )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() { selectedPriority = value; });
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    // Assignee Selection (Multi-select via chips)
                    if (_teamMembers.isNotEmpty) ...[
                      const Text('Assignees'),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _teamMembers.map((name) {
                          final selected = selectedAssignees.contains(name);
                          return FilterChip(
                            label: Text(name),
                            selected: selected,
                            onSelected: (value) {
                              setStateDialog(() {
                                if (value) selectedAssignees.add(name);
                                else selectedAssignees.remove(name);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Role Selection (Multi-select via chips)
                    if (_allRoles.isNotEmpty) ...[
                      const Text('Roles / Subteam'),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _allRoles.map((role) {
                          final selected = selectedRoles.contains(role);
                          return FilterChip(
                            label: Text(role),
                            selected: selected,
                            onSelected: (value) {
                              setStateDialog(() {
                                if (value) selectedRoles.add(role);
                                else selectedRoles.remove(role);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 12),
                    // Deadline Picker
                    TextField(
                      readOnly: true,
                      controller: deadlineController,
                      decoration: const InputDecoration(
                        labelText: 'Deadline (Optional)',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 5),
                          initialDate: deadline ?? now,
                        );
                        if (picked != null) {
                          deadline = picked;
                          deadlineController.text =
                          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    title = titleController.text.trim();
                    description = descriptionController.text.trim();
                    if (title.isEmpty) return;
                    Navigator.of(ctx).pop();
                  },
                  child: Text(isEdit ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (title.isEmpty) return;

    try {
      if (isEdit) {
        // Update existing task document.
        final taskRef = _tasksCollection().doc(existingTask!.id);
        await taskRef.update({
          'title': title,
          'description': description.isEmpty ? null : description,
          'assignees': selectedAssignees.toList(),
          'roles': selectedRoles.toList(),
          'deadline': deadline != null ? Timestamp.fromDate(deadline!) : null,
          'priority': selectedPriority.id,
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task updated')));
      } else {
        // Create new task document.
        final newOrder = await _getNextOrderForColumn(columnId!);
        final userId = user?.uid;

        await _tasksCollection().add({
          'title': title,
          'description': description.isEmpty ? null : description,
          'columnId': columnId,
          'assignees': selectedAssignees.toList(),
          'roles': selectedRoles.toList(),
          'assigneeId': userId,
          'deadline': deadline != null ? Timestamp.fromDate(deadline!) : null,
          'order': newOrder,
          'priority': selectedPriority.id,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving task: $e')),
        );
      }
    }
  }

  /// Updates a task's stage and triggers success visuals if moved to DONE.
  Future<void> _moveTaskToColumn(ScrumTask task, String newColumnId) async {
    try {
      final taskDoc = _tasksCollection().doc(task.id);
      if (task.columnId == newColumnId) return;

      final newOrder = await _getNextOrderForColumn(newColumnId);
      await taskDoc.update({
        'columnId': newColumnId,
        'order': newOrder,
      });

      // Show celebratory popup if task was moved to 'Done'.
      if (newColumnId == ScrumColumnType.done.id) {
        String msg;
        if (task.assignees.isNotEmpty) {
          msg = '🎉 Good job ${task.assignees.join(', ')}!';
        } else if (task.roles.isNotEmpty) {
          msg = '🎉 Good job ${task.roles.first} team!';
        } else if ((task.assigneeName ?? '').isNotEmpty) {
          msg = '🎉 Good job ${task.assigneeName}!';
        } else {
          msg = '🎉 Good job team! Task completed!';
        }

        if (mounted) {
          await showDialog(
            context: context,
            builder: (dialogCtx) {
              final theme = Theme.of(dialogCtx);
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Text('Great work!'),
                    const SizedBox(width: 8),
                    Text('🎉', style: theme.textTheme.headlineSmall),
                  ],
                ),
                content: Text(msg, style: theme.textTheme.titleMedium),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Nice!'),
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error moving task: $e')),
        );
      }
    }
  }

  /// Adds a new subtask checklist item to a task.
  Future<void> _addSubtask(String taskId) async {
    final controller = TextEditingController();
    String title = '';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Subtask'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Subtask Title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                title = controller.text.trim();
                if (title.isEmpty) return;
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (title.isEmpty) return;

    try {
      await _tasksCollection()
          .doc(taskId)
          .collection('subtasks')
          .add({'title': title, 'isDone': false});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding subtask: $e')),
        );
      }
    }
  }

  /// Toggles the completion status of a subtask.
  Future<void> _toggleSubtask(
      String taskId, ScrumSubtask subtask) async {
    try {
      final subtaskRef = _tasksCollection()
          .doc(taskId)
          .collection('subtasks')
          .doc(subtask.id);

      await subtaskRef.update({'isDone': !subtask.isDone});

      // Provide feedback if all subtasks are finished.
      final allSubtasksSnap =
      await _tasksCollection().doc(taskId).collection('subtasks').get();

      if (allSubtasksSnap.docs.isNotEmpty &&
          allSubtasksSnap.docs
              .every((d) => (d.data()['isDone'] ?? false) == true)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Great work! All subtasks completed!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating subtask: $e')),
        );
      }
    }
  }

  /// Returns a stream of tasks for the board, ordered by their rank.
  Stream<List<ScrumTask>> _tasksStream() {
    return _tasksCollection().orderBy('order').snapshots().map(
          (snapshot) => snapshot.docs
          .map((doc) => ScrumTask.fromFirestore(doc))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final Color columnBackground =
    isDark ? const Color(0xFF1F1F1F) : Colors.grey.shade100;
    final Color cardBackground =
    isDark ? const Color(0xFF2A2A2A) : theme.cardColor;

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Scrum Board',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: Column(
        children: [
          // Filter Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Filter by Assignee',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() { _personFilter = value.trim().toLowerCase(); });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ScrumTask>>(
              stream: _tasksStream(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allTasks = snapshot.data ?? <ScrumTask>[];

                // Apply assignee filter to the stream data.
                final filteredTasks = _personFilter.isEmpty
                    ? allTasks
                    : allTasks.where((t) {
                  final single = (t.assigneeName ?? '').toLowerCase().contains(_personFilter);
                  final multi = t.assignees.map((a) => a.toLowerCase()).any((a) => a.contains(_personFilter));
                  return single || multi;
                }).toList();

                // Group and sort tasks by column.
                final Map<String, List<ScrumTask>> tasksByColumn = {};
                for (final type in ScrumColumnType.values) {
                  tasksByColumn[type.id] = [];
                }
                for (final t in filteredTasks) {
                  tasksByColumn.putIfAbsent(t.columnId, () => []);
                  tasksByColumn[t.columnId]!.add(t);
                }
                for (final entry in tasksByColumn.entries) {
                  entry.value.sort((a, b) {
                    final prioDiff = a.priority.sortRank.compareTo(b.priority.sortRank);
                    if (prioDiff != 0) return prioDiff;
                    return a.order.compareTo(b.order);
                  });
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: ScrumColumnType.values.map((colType) {
                            final columnTasks = tasksByColumn[colType.id] ?? [];

                            return SizedBox(
                              width: isWide ? constraints.maxWidth / ScrumColumnType.values.length : 280,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: _buildColumn(
                                  columnType: colType,
                                  tasks: columnTasks,
                                  columnBackground: columnBackground,
                                  cardBackground: cardBackground,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Builds an individual column for the Kanban board.
  Widget _buildColumn({
    required ScrumColumnType columnType,
    required List<ScrumTask> tasks,
    required Color columnBackground,
    required Color cardBackground,
  }) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(color: columnBackground, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    columnType.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Add Task',
                  icon: const Icon(Icons.add),
                  color: theme.colorScheme.primary,
                  onPressed: () => _addTask(columnType.id),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasks.isEmpty
                ? Center(
              child: Opacity(
                opacity: 0.5,
                child: Text('No tasks', style: theme.textTheme.bodySmall),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: tasks.length,
              itemBuilder: (ctx, index) {
                final task = tasks[index];
                return _TaskCard(
                  boardId: _boardId,
                  task: task,
                  cardBackground: cardBackground,
                  onAddSubtask: () => _addSubtask(task.id),
                  onToggleSubtask: (subtask) => _toggleSubtask(task.id, subtask),
                  onMoveLeft: () => _moveTaskToColumn(task, _getPreviousColumnId(task.columnId)),
                  onMoveRight: () => _moveTaskToColumn(task, _getNextColumnId(task.columnId)),
                  onEdit: () => _editTask(task),
                  onDelete: () => _deleteTask(task),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getPreviousColumnId(String currentId) {
    final order = ScrumColumnType.values.indexWhere((c) => c.id == currentId);
    if (order <= 0) return currentId;
    return ScrumColumnType.values[order - 1].id;
  }

  String _getNextColumnId(String currentId) {
    final order = ScrumColumnType.values.indexWhere((c) => c.id == currentId);
    if (order < 0 || order >= ScrumColumnType.values.length - 1) return currentId;
    return ScrumColumnType.values[order + 1].id;
  }
}

/// Visual card component representing a task and its properties.
class _TaskCard extends StatelessWidget {
  final String boardId;
  final ScrumTask task;
  final Color cardBackground;
  final VoidCallback onAddSubtask;
  final void Function(ScrumSubtask subtask) onToggleSubtask;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.boardId,
    required this.task,
    required this.cardBackground,
    required this.onAddSubtask,
    required this.onToggleSubtask,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final assigneesText = task.assignees.isNotEmpty ? task.assignees.join(', ') : (task.assigneeName ?? '');
    final rolesText = task.roles.isNotEmpty ? task.roles.join(', ') : '';

    // Assign semantic colors based on task priority.
    Color prioBg; Color prioText;
    switch (task.priority) {
      case TaskPriority.high: prioBg = theme.colorScheme.error; prioText = theme.colorScheme.onError; break;
      case TaskPriority.normal: prioBg = theme.colorScheme.primary; prioText = theme.colorScheme.onPrimary; break;
      case TaskPriority.low: prioBg = theme.colorScheme.secondary; prioText = theme.colorScheme.onSecondary; break;
    }

    // Determine deadline text and conditional styling.
    TextStyle deadlineStyle = theme.textTheme.bodySmall ?? const TextStyle();
    String deadlineText = '';
    if (task.deadline != null) {
      final d = task.deadline!;
      deadlineText = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      final diffDays = DateTime(d.year, d.month, d.day).difference(DateTime.now()).inDays;
      final isDone = task.columnId == ScrumColumnType.done.id;

      if (!isDone && diffDays < 0) {
        deadlineStyle = deadlineStyle.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold);
      } else if (!isDone && diffDays <= 2) {
        deadlineStyle = deadlineStyle.copyWith(color: theme.colorScheme.tertiary, fontWeight: FontWeight.w600);
      }
    }

    return Card(
      color: cardBackground,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Row(
          children: [
            Expanded(child: Text(task.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: prioBg, borderRadius: BorderRadius.circular(999)),
              child: Text(task.priority.label, style: theme.textTheme.labelSmall?.copyWith(color: prioText, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (assigneesText.isNotEmpty)
              Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [const Icon(Icons.person, size: 16), Text(assigneesText, style: theme.textTheme.bodySmall)]),
            if (rolesText.isNotEmpty)
              Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [const Icon(Icons.groups, size: 16), Text(rolesText, style: theme.textTheme.bodySmall)]),
            if (deadlineText.isNotEmpty)
              Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [const Icon(Icons.event, size: 16), Text(deadlineText, style: deadlineStyle)]),
            const SizedBox(height: 4),
            // Interaction buttons.
            Wrap(
              spacing: 0,
              children: [
                IconButton(tooltip: 'Move Left', icon: const Icon(Icons.arrow_left), color: theme.colorScheme.primary, onPressed: onMoveLeft),
                IconButton(tooltip: 'Move Right', icon: const Icon(Icons.arrow_right), color: theme.colorScheme.primary, onPressed: onMoveRight),
                IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), color: theme.colorScheme.secondary, onPressed: onEdit),
                IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete), color: theme.colorScheme.error, onPressed: onDelete),
              ],
            ),
          ],
        ),
        children: [
          if (task.description != null && task.description!.isNotEmpty) ...[
            Align(alignment: Alignment.centerLeft, child: Text(task.description!, style: theme.textTheme.bodyMedium)),
            const SizedBox(height: 8),
          ],
          // Subtask / Checklist section.
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Checklist', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(tooltip: 'Add Subtask', onPressed: onAddSubtask, icon: const Icon(Icons.add_task), color: theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 4),
          _SubtasksList(boardId: boardId, taskId: task.id, onToggleSubtask: onToggleSubtask),
        ],
      ),
    );
  }
}

/// Reactive list of subtasks loaded from Firestore.
class _SubtasksList extends StatelessWidget {
  final String boardId;
  final String taskId;
  final void Function(ScrumSubtask subtask) onToggleSubtask;

  const _SubtasksList({
    required this.boardId,
    required this.taskId,
    required this.onToggleSubtask,
  });

  @override
  Widget build(BuildContext context) {
    final subtasksRef = FirebaseFirestore.instance
        .collection('scrumBoards').doc(boardId)
        .collection('tasks').doc(taskId)
        .collection('subtasks');

    return StreamBuilder<QuerySnapshot>(
      stream: subtasksRef.snapshots(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final subtasks = snapshot.data!.docs
            .map((d) => ScrumSubtask.fromFirestore(d))
            .toList();

        if (subtasks.isEmpty) return const Text('No subtasks yet.');

        return Column(
          children: subtasks
              .map(
                (sub) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(sub.title),
              value: sub.isDone,
              onChanged: (_) => onToggleSubtask(sub),
            ),
          )
              .toList(),
        );
      },
    );
  }
}
