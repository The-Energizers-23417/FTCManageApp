import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// Model representing an FTC Event with checklist, financial tracking, and assignments.
class FTCEvent {
  final String id;
  final String name;
  final DateTime date;
  final String location;
  final double budget;
  final double income;
  final double spent;
  final List<String> assignedMembers;

  FTCEvent({
    required this.id,
    required this.name,
    required this.date,
    required this.location,
    required this.budget,
    required this.income,
    required this.spent,
    required this.assignedMembers,
  });

  factory FTCEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FTCEvent(
      id: doc.id,
      name: data['name'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      location: data['location'] ?? '',
      budget: (data['budget'] ?? 0.0).toDouble(),
      income: (data['income'] ?? 0.0).toDouble(),
      spent: (data['spent'] ?? 0.0).toDouble(),
      assignedMembers: (data['assignedMembers'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

/// A page to organize and track team events, including checklists and financials directly in the overview.
class EventManagerPage extends StatefulWidget {
  const EventManagerPage({super.key});

  @override
  State<EventManagerPage> createState() => _EventManagerPageState();
}

class _EventManagerPageState extends State<EventManagerPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  List<String> _teamMembers = [];

  @override
  void initState() {
    super.initState();
    _loadTeamMembers();
  }

  Future<void> _loadTeamMembers() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) return;
    final setup = doc.data()?['setupData'] as Map<String, dynamic>?;
    if (setup == null) return;
    final members = setup['teamMembers'] as List<dynamic>? ?? [];
    setState(() {
      _teamMembers = members.map((m) => (m['firstName'] as String? ?? '').trim()).where((n) => n.isNotEmpty).toList();
    });
  }

  Stream<List<FTCEvent>> _eventStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('events')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => FTCEvent.fromFirestore(doc)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopAppBar(title: "Event Organizer"),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEventDialog(),
        child: const Icon(Icons.event_available),
      ),
      bottomNavigationBar: BottomNavBar(currentIndex: 0, onTabSelected: (_) {}, items: const []),
      body: StreamBuilder<List<FTCEvent>>(
        stream: _eventStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snapshot.data ?? [];

          if (events.isEmpty) {
            return const Center(child: Text("No events planned yet. Tap '+' to start."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: events.length,
            itemBuilder: (context, index) => _buildEventCard(events[index]),
          );
        },
      ),
    );
  }

  Widget _buildEventCard(FTCEvent event) {
    final user = _auth.currentUser;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        title: Text(event.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text("${event.date.day}-${event.date.month}-${event.date.year} • ${event.location}"),
        childrenPadding: const EdgeInsets.all(16),
        expandedAlignment: Alignment.topLeft,
        children: [
          const Divider(),
          // Assignments Section
          if (event.assignedMembers.isNotEmpty) ...[
            const Text("Assigned Team:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: event.assignedMembers.map((m) => Chip(
                label: Text(m, style: const TextStyle(fontSize: 10)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
            const SizedBox(height: 12),
          ],
          // Financials Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _eventStat("Planned", "€${event.budget.toStringAsFixed(0)}", Colors.blue),
              _eventStat("Income", "€${event.income.toStringAsFixed(0)}", Colors.green),
              _eventStat("Spent", "€${event.spent.toStringAsFixed(0)}", Colors.red),
            ],
          ),
          const SizedBox(height: 16),
          // Checklist Section
          const Text("Tasks & Checklist", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildChecklist(user?.uid ?? '', event),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _showEventDialog(event: event),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text("Edit Details"),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteEvent(event.id),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _eventStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildChecklist(String uid, FTCEvent event) {
    final controller = TextEditingController();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: "Add task...", isDense: true),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue),
              onPressed: () async {
                if (controller.text.isEmpty) return;
                
                final taskText = controller.text;
                
                // 1. Add to Event Checklist
                await _db.collection('users').doc(uid).collection('events').doc(event.id).collection('checklist').add({
                  'item': taskText,
                  'done': false,
                });

                // 2. ALSO Add to Main Scrumboard
                final boardId = 'default-board-$uid';
                await _db.collection('scrumBoards').doc(boardId).collection('tasks').add({
                  'title': "[${event.name}] $taskText",
                  'columnId': 'todo',
                  'assignees': event.assignedMembers,
                  'priority': 'normal',
                  'createdAt': FieldValue.serverTimestamp(),
                  'order': DateTime.now().millisecondsSinceEpoch,
                });

                controller.clear();
              },
            ),
          ],
        ),
        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('users').doc(uid).collection('events').doc(event.id).collection('checklist').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final items = snapshot.data!.docs;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final d = items[index].data() as Map<String, dynamic>;
                return CheckboxListTile(
                  title: Text(d['item'] ?? '', style: TextStyle(fontSize: 13, decoration: (d['done'] ?? false) ? TextDecoration.lineThrough : null)),
                  value: d['done'] ?? false,
                  dense: true,
                  onChanged: (val) => items[index].reference.update({'done': val}),
                  contentPadding: EdgeInsets.zero,
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteEvent(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Event?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      final user = _auth.currentUser;
      if (user != null) {
        await _db.collection('users').doc(user.uid).collection('events').doc(id).delete();
      }
    }
  }

  void _showEventDialog({FTCEvent? event}) {
    final nameController = TextEditingController(text: event?.name);
    final locationController = TextEditingController(text: event?.location);
    final budgetController = TextEditingController(text: event?.budget.toString() ?? "0.0");
    final incomeController = TextEditingController(text: event?.income.toString() ?? "0.0");
    final spentController = TextEditingController(text: event?.spent.toString() ?? "0.0");
    DateTime selectedDate = event?.date ?? DateTime.now();
    List<String> selectedMembers = List.from(event?.assignedMembers ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(event == null ? "Plan Event" : "Edit Event"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: "Event Name")),
                TextField(controller: locationController, decoration: const InputDecoration(labelText: "Location")),
                const SizedBox(height: 16),
                const Text("Assign Team Members:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: _teamMembers.map((m) {
                    final isSelected = selectedMembers.contains(m);
                    return FilterChip(
                      label: Text(m, style: const TextStyle(fontSize: 10)),
                      selected: isSelected,
                      onSelected: (val) {
                        setDialogState(() {
                          if (val) selectedMembers.add(m);
                          else selectedMembers.remove(m);
                        });
                      },
                    );
                  }).toList(),
                ),
                const Divider(height: 32),
                TextField(controller: budgetController, decoration: const InputDecoration(labelText: "Budget (€)"), keyboardType: TextInputType.number),
                TextField(controller: incomeController, decoration: const InputDecoration(labelText: "Income (€)"), keyboardType: TextInputType.number),
                TextField(controller: spentController, decoration: const InputDecoration(labelText: "Spent (€)"), keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text("Date", style: TextStyle(fontSize: 14)),
                  subtitle: Text("${selectedDate.day}-${selectedDate.month}-${selectedDate.year}"),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                    if (picked != null) setDialogState(() => selectedDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final user = _auth.currentUser;
                if (user == null || nameController.text.isEmpty) return;

                final data = {
                  'name': nameController.text,
                  'location': locationController.text,
                  'budget': double.tryParse(budgetController.text) ?? 0.0,
                  'income': double.tryParse(incomeController.text) ?? 0.0,
                  'spent': double.tryParse(spentController.text) ?? 0.0,
                  'date': Timestamp.fromDate(selectedDate),
                  'assignedMembers': selectedMembers,
                };

                if (event == null) {
                  await _db.collection('users').doc(user.uid).collection('events').add(data);
                } else {
                  await _db.collection('users').doc(user.uid).collection('events').doc(event.id).update(data);
                }
                if (mounted) Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}
