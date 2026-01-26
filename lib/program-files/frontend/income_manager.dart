import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// A page specifically for tracking team income.
class IncomeManagerPage extends StatefulWidget {
  const IncomeManagerPage({super.key});

  @override
  State<IncomeManagerPage> createState() => _IncomeManagerPageState();
}

class _IncomeManagerPageState extends State<IncomeManagerPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot> _incomeStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    
    // Using a simpler query first to avoid index requirement issues
    // We filter in memory if necessary or ensure indices are communicated.
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('finance')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopAppBar(title: "Income Tracking"),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddIncomeDialog(),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavBar(currentIndex: 0, onTabSelected: (_) {}, items: const []),
      body: StreamBuilder<QuerySnapshot>(
        stream: _incomeStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          // Filter for income only in memory to prevent "missing index" errors
          final allDocs = snapshot.data?.docs ?? [];
          final docs = allDocs.where((d) => (d.data() as Map<String, dynamic>)['type'] == 'income').toList();
          
          // Sort by date manually
          docs.sort((a, b) {
            final dateA = (a.data() as Map<String, dynamic>)['date'] as Timestamp?;
            final dateB = (b.data() as Map<String, dynamic>)['date'] as Timestamp?;
            if (dateA == null || dateB == null) return 0;
            return dateB.compareTo(dateA);
          });

          double totalIncome = 0;
          for (var doc in docs) totalIncome += (doc.data() as Map<String, dynamic>)['amount'] ?? 0.0;

          return Column(
            children: [
              _buildHeader(totalIncome),
              Expanded(
                child: docs.isEmpty 
                  ? const Center(child: Text("No income recorded yet."))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final dateTs = data['date'] as Timestamp?;
                        final date = dateTs?.toDate() ?? DateTime.now();
                        final amount = (data['amount'] ?? 0.0).toDouble();
                        final category = data['category'] ?? 'Sponsorship';
                        
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
                            title: Text(data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                children: [
                                  Text("${date.day}-${date.month}-${date.year}"),
                                  const SizedBox(width: 8),
                                  _buildTag(category),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "+ €${amount.toStringAsFixed(2)}", 
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  onPressed: () => _confirmDelete(docs[index].id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTag(String category) {
    Color tagColor;
    switch (category.toLowerCase()) {
      case 'sponsorship': tagColor = Colors.blue; break;
      case 'fundraising': tagColor = Colors.orange; break;
      case 'grant': tagColor = Colors.purple; break;
      default: tagColor = Colors.teal;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tagColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tagColor.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        category,
        style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildHeader(double total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        border: const Border(bottom: BorderSide(color: Colors.green, width: 0.5)),
      ),
      child: Column(
        children: [
          const Text("Total Income", style: TextStyle(fontSize: 14)),
          Text("€${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Record?"),
        content: const Text("Are you sure you want to remove this income record?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final user = _auth.currentUser;
      if (user != null) {
        await _db.collection('users').doc(user.uid).collection('finance').doc(id).delete();
      }
    }
  }

  void _showAddIncomeDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final catCtrl = TextEditingController(text: "Sponsorship");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Log Income"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Description")),
            TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: "Amount (€)"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            TextField(controller: catCtrl, decoration: const InputDecoration(labelText: "Category (e.g. Sponsorship, Grant)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final user = _auth.currentUser;
              if (user == null || titleCtrl.text.isEmpty) return;
              await _db.collection('users').doc(user.uid).collection('finance').add({
                'title': titleCtrl.text,
                'amount': double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0.0,
                'type': 'income',
                'category': catCtrl.text,
                'date': FieldValue.serverTimestamp(), // Better for consistency
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
