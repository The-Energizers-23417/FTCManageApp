import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// Defines the possible states of a sponsorship lead.
enum SponsorStatus { contacted, inDiscussion, awaitingMoney, sponsored, rejected }

extension SponsorStatusExt on SponsorStatus {
  String get id => toString().split('.').last;

  String get label {
    switch (this) {
      case SponsorStatus.contacted: return "Contacted";
      case SponsorStatus.inDiscussion: return "Discussion";
      case SponsorStatus.awaitingMoney: return "Awaiting Money";
      case SponsorStatus.sponsored: return "Sponsored";
      case SponsorStatus.rejected: return "Rejected";
    }
  }

  Color get color {
    switch (this) {
      case SponsorStatus.contacted: return Colors.blue;
      case SponsorStatus.inDiscussion: return Colors.orange;
      case SponsorStatus.awaitingMoney: return Colors.deepPurple;
      case SponsorStatus.sponsored: return Colors.green;
      case SponsorStatus.rejected: return Colors.red;
    }
  }
}

/// Defines the type of contribution provided by the sponsor.
enum SponsorType { money, materials, knowledge }

extension SponsorTypeExt on SponsorType {
  String get id => toString().split('.').last;
  
  String get label {
    switch (this) {
      case SponsorType.money: return "Money";
      case SponsorType.materials: return "Materials";
      case SponsorType.knowledge: return "Knowledge";
    }
  }

  IconData get icon {
    switch (this) {
      case SponsorType.money: return Icons.attach_money;
      case SponsorType.materials: return Icons.inventory_2_outlined;
      case SponsorType.knowledge: return Icons.psychology_outlined;
    }
  }

  Color get color {
    switch (this) {
      case SponsorType.money: return Colors.green;
      case SponsorType.materials: return Colors.blueGrey;
      case SponsorType.knowledge: return Colors.amber;
    }
  }
}

/// Model representing a sponsor or potential sponsor for the team.
class Sponsor {
  final String id;
  final String name;
  final String contactPerson;
  final String email;
  final String amount;
  final double fixedAmount;
  final bool isOneTime;
  final SponsorStatus status;
  final SponsorType type;
  final String notes;

  Sponsor({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.email,
    required this.amount,
    required this.fixedAmount,
    required this.isOneTime,
    required this.status,
    required this.type,
    required this.notes,
  });

  factory Sponsor.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Sponsor(
      id: doc.id,
      name: data['name'] ?? '',
      contactPerson: data['contactPerson'] ?? '',
      email: data['email'] ?? '',
      amount: data['amount'] ?? '',
      fixedAmount: (data['fixedAmount'] ?? 0.0).toDouble(),
      isOneTime: data['isOneTime'] ?? true,
      status: SponsorStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => SponsorStatus.contacted,
      ),
      type: SponsorType.values.firstWhere(
        (e) => e.toString().split('.').last == data['type'],
        orElse: () => SponsorType.money,
      ),
      notes: data['notes'] ?? '',
    );
  }
}

/// A page to track and manage team sponsorships using a Kanban-style board layout.
class SponsorManagerPage extends StatefulWidget {
  const SponsorManagerPage({super.key});

  @override
  State<SponsorManagerPage> createState() => _SponsorManagerPageState();
}

class _SponsorManagerPageState extends State<SponsorManagerPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Returns a stream of sponsors for the logged-in user.
  Stream<List<Sponsor>> _sponsorStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('sponsors')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => Sponsor.fromFirestore(doc)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final columnBackground = isDark ? const Color(0xFF1F1F1F) : Colors.grey.shade100;

    return Scaffold(
      appBar: const TopAppBar(title: "Sponsor Board"),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSponsorDialog(),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: StreamBuilder<List<Sponsor>>(
        stream: _sponsorStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allSponsors = snapshot.data ?? [];

          return LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: SponsorStatus.values.map((status) {
                    final columnSponsors = allSponsors.where((s) => s.status == status).toList();
                    return Container(
                      width: 300,
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: columnBackground,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  status.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 16,
                                    color: theme.textTheme.titleMedium?.color,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  columnSponsors.length.toString(),
                                  style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          ...columnSponsors.map((s) => _buildSponsorCard(s)).toList(),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSponsorCard(Sponsor sponsor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showSponsorDialog(sponsor: sponsor),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      sponsor.name, 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 15,
                        color: theme.textTheme.titleMedium?.color,
                      )
                    ),
                  ),
                  if (sponsor.type == SponsorType.money)
                    Text(
                      "€${sponsor.fixedAmount.toStringAsFixed(0)}",
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Category Tags
              Wrap(
                spacing: 4,
                children: [
                  _buildTag(sponsor.type.label, sponsor.type.color, sponsor.type.icon),
                  _buildTag(sponsor.isOneTime ? "One-time" : "Recurring", Colors.grey, sponsor.isOneTime ? Icons.event : Icons.repeat),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    sponsor.contactPerson, 
                    style: TextStyle(
                      fontSize: 12, 
                      color: isDark ? Colors.white70 : Colors.black87,
                    )
                  ),
                ],
              ),
              if (sponsor.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  sponsor.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey[700], fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (sponsor.status.index > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_left, size: 20),
                      onPressed: () => _updateSponsorStatus(sponsor, SponsorStatus.values[sponsor.status.index - 1]),
                    ),
                  if (sponsor.status.index < SponsorStatus.values.length - 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_right, size: 20),
                      onPressed: () => _updateSponsorStatus(sponsor, SponsorStatus.values[sponsor.status.index + 1]),
                    ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label, 
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSponsorStatus(Sponsor sponsor, SponsorStatus newStatus) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Log income if transitioning to 'sponsored'
    if (newStatus == SponsorStatus.sponsored && sponsor.status != SponsorStatus.sponsored) {
      await _logSponsorshipIncome(sponsor);
    }

    await _db.collection('users').doc(user.uid).collection('sponsors').doc(sponsor.id).update({
      'status': newStatus.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Logs a transaction in the finance tracking if a money sponsorship is received.
  Future<void> _logSponsorshipIncome(Sponsor sponsor) async {
    final user = _auth.currentUser;
    if (user == null || sponsor.type != SponsorType.money || sponsor.fixedAmount <= 0) return;

    await _db.collection('users').doc(user.uid).collection('finance').add({
      'title': "Sponsorship: ${sponsor.name}",
      'amount': sponsor.fixedAmount,
      'type': 'income',
      'category': 'Sponsorship',
      'date': Timestamp.now(),
    });
  }

  void _showSponsorDialog({Sponsor? sponsor}) {
    final nameController = TextEditingController(text: sponsor?.name);
    final contactController = TextEditingController(text: sponsor?.contactPerson);
    final emailController = TextEditingController(text: sponsor?.email);
    final fixedAmountController = TextEditingController(text: sponsor?.fixedAmount.toString() ?? "0.0");
    final notesController = TextEditingController(text: sponsor?.notes);
    SponsorStatus selectedStatus = sponsor?.status ?? SponsorStatus.contacted;
    SponsorType selectedType = sponsor?.type ?? SponsorType.money;
    bool isOneTime = sponsor?.isOneTime ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(sponsor == null ? "Add Sponsor" : "Edit Sponsor"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: "Company Name")),
                TextField(controller: contactController, decoration: const InputDecoration(labelText: "Contact Person")),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email/Phone")),
                const SizedBox(height: 16),
                DropdownButtonFormField<SponsorType>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: "Sponsorship Type"),
                  items: SponsorType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                  onChanged: (val) => setDialogState(() => selectedType = val!),
                ),
                const SizedBox(height: 12),
                if (selectedType == SponsorType.money)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: fixedAmountController, 
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Amount (€)", prefixText: "€"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          const Text("One-time?", style: TextStyle(fontSize: 12)),
                          Switch(value: isOneTime, onChanged: (val) => setDialogState(() => isOneTime = val)),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<SponsorStatus>(
                  value: selectedStatus,
                  decoration: const InputDecoration(labelText: "Status"),
                  items: SponsorStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                  onChanged: (val) => setDialogState(() => selectedStatus = val!),
                ),
                TextField(controller: notesController, decoration: const InputDecoration(labelText: "Notes"), maxLines: 3),
              ],
            ),
          ),
          actions: [
            if (sponsor != null)
              TextButton(
                onPressed: () async {
                  final user = _auth.currentUser;
                  if (user != null) {
                    await _db.collection('users').doc(user.uid).collection('sponsors').doc(sponsor.id).delete();
                    if (mounted) Navigator.pop(context);
                  }
                },
                child: const Text("Delete", style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final user = _auth.currentUser;
                if (user == null || nameController.text.isEmpty) return;

                final data = {
                  'name': nameController.text,
                  'contactPerson': contactController.text,
                  'email': emailController.text,
                  'fixedAmount': double.tryParse(fixedAmountController.text) ?? 0.0,
                  'isOneTime': isOneTime,
                  'status': selectedStatus.id,
                  'type': selectedType.id,
                  'notes': notesController.text,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                // Check if we should log income (if moving to sponsored now)
                if (selectedStatus == SponsorStatus.sponsored && (sponsor == null || sponsor.status != SponsorStatus.sponsored)) {
                  // Temporarily create a dummy sponsor object to pass to logic
                  final tempSponsor = Sponsor(
                    id: '', 
                    name: nameController.text, 
                    contactPerson: contactController.text, 
                    email: emailController.text, 
                    amount: '', 
                    fixedAmount: double.tryParse(fixedAmountController.text) ?? 0.0, 
                    isOneTime: isOneTime, 
                    status: selectedStatus, 
                    type: selectedType, 
                    notes: notesController.text
                  );
                  await _logSponsorshipIncome(tempSponsor);
                }

                if (sponsor == null) {
                  await _db.collection('users').doc(user.uid).collection('sponsors').add(data);
                } else {
                  await _db.collection('users').doc(user.uid).collection('sponsors').doc(sponsor.id).update(data);
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
