import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// A page specifically for tracking team expenses.
class ExpenseManagerPage extends StatefulWidget {
  const ExpenseManagerPage({super.key});

  @override
  State<ExpenseManagerPage> createState() => _ExpenseManagerPageState();
}

class _ExpenseManagerPageState extends State<ExpenseManagerPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot> _expenseStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    
    // Fetch all finance records and filter in memory to avoid mandatory Firestore indexing errors
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('finance')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopAppBar(title: "Expense Tracking"),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddExpenseDialog(),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavBar(currentIndex: 0, onTabSelected: (_) {}, items: const []),
      body: StreamBuilder<QuerySnapshot>(
        stream: _expenseStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          // Filter for expenses and sort in memory
          final allDocs = snapshot.data?.docs ?? [];
          final docs = allDocs.where((d) => (d.data() as Map<String, dynamic>)['type'] == 'expense').toList();
          
          docs.sort((a, b) {
            final dateA = (a.data() as Map<String, dynamic>)['date'] as Timestamp?;
            final dateB = (b.data() as Map<String, dynamic>)['date'] as Timestamp?;
            if (dateA == null || dateB == null) return 0;
            return dateB.compareTo(dateA);
          });

          double totalExpense = 0;
          for (var doc in docs) totalExpense += (doc.data() as Map<String, dynamic>)['amount'] ?? 0.0;

          return Column(
            children: [
              _buildHeader(totalExpense),
              Expanded(
                child: docs.isEmpty 
                  ? const Center(child: Text("No expenses recorded yet."))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final dateTs = data['date'] as Timestamp?;
                        final date = dateTs?.toDate() ?? DateTime.now();
                        final amount = (data['amount'] ?? 0.0).toDouble();
                        final category = data['category'] ?? 'Parts';

                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            title: Text(data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
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
                                  "- €${amount.toStringAsFixed(2)}", 
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
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
      case 'parts': tagColor = Colors.redAccent; break;
      case 'tools': tagColor = Colors.blueGrey; break;
      case 'travel': tagColor = Colors.amber; break;
      case 'event': tagColor = Colors.deepOrange; break;
      default: tagColor = Colors.blueGrey;
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
        color: Colors.red.withOpacity(0.1),
        border: const Border(bottom: BorderSide(color: Colors.red, width: 0.5)),
      ),
      child: Column(
        children: [
          const Text("Total Expenses", style: TextStyle(fontSize: 14)),
          Text("€${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.red)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Record?"),
        content: const Text("Are you sure you want to remove this expense record?"),
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

  void _showAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final catCtrl = TextEditingController(text: "Parts");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Log Expense"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Description")),
            TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: "Amount (€)"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            TextField(controller: catCtrl, decoration: const InputDecoration(labelText: "Category (e.g. Parts, Tools, Travel)")),
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
                'type': 'expense',
                'category': catCtrl.text,
                'date': FieldValue.serverTimestamp(),
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
