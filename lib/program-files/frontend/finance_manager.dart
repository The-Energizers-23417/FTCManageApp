import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// Defines the type of financial transaction.
enum TransactionType { income, expense }

/// Model representing a single financial transaction (Income or Expense).
class Transaction {
  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final String category;

  Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
  });

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Transaction(
      id: doc.id,
      title: data['title'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      type: data['type'] == 'income' ? TransactionType.income : TransactionType.expense,
      category: data['category'] ?? 'General',
    );
  }
}

/// A page to track and organize team income and expenses.
class FinanceManagerPage extends StatefulWidget {
  const FinanceManagerPage({super.key});

  @override
  State<FinanceManagerPage> createState() => _FinanceManagerPageState();
}

class _FinanceManagerPageState extends State<FinanceManagerPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Stream<List<Transaction>> _transactionStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('finance')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => Transaction.fromFirestore(doc)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopAppBar(title: "Income & Expenses"),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTransactionDialog(),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: StreamBuilder<List<Transaction>>(
        stream: _transactionStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final transactions = snapshot.data ?? [];

          double totalIncome = 0;
          double totalExpense = 0;
          for (var t in transactions) {
            if (t.type == TransactionType.income) totalIncome += t.amount;
            else totalExpense += t.amount;
          }

          return Column(
            children: [
              _buildSummaryHeader(totalIncome, totalExpense),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) => _buildTransactionCard(transactions[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader(double income, double expense) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem("Income", income, Colors.green),
          _summaryItem("Expenses", expense, Colors.red),
          _summaryItem("Balance", income - expense, Colors.blue),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, double amount, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        Text(
          "€${amount.toStringAsFixed(2)}",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildTransactionCard(Transaction t) {
    final isIncome = t.type == TransactionType.income;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isIncome ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
          child: Icon(isIncome ? Icons.add : Icons.remove, color: isIncome ? Colors.green : Colors.red),
        ),
        title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${t.date.day}-${t.date.month}-${t.date.year} • ${t.category}"),
        trailing: Text(
          "${isIncome ? '+' : '-'} €${t.amount.toStringAsFixed(2)}",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isIncome ? Colors.green : Colors.red,
          ),
        ),
        onLongPress: () => _deleteTransaction(t.id),
      ),
    );
  }

  Future<void> _deleteTransaction(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Transaction?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final user = _auth.currentUser;
      if (user != null) {
        await _db.collection('users').doc(user.uid).collection('finance').doc(id).delete();
      }
    }
  }

  void _showTransactionDialog() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final categoryController = TextEditingController(text: "General");
    TransactionType selectedType = TransactionType.expense;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Add Transaction"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(value: TransactionType.income, label: Text("Income"), icon: Icon(Icons.add)),
                  ButtonSegment(value: TransactionType.expense, label: Text("Expense"), icon: Icon(Icons.remove)),
                ],
                selected: {selectedType},
                onSelectionChanged: (val) => setDialogState(() => selectedType = val.first),
              ),
              const SizedBox(height: 16),
              TextField(controller: titleController, decoration: const InputDecoration(labelText: "Description")),
              TextField(controller: amountController, decoration: const InputDecoration(labelText: "Amount (€)"), keyboardType: TextInputType.number),
              TextField(controller: categoryController, decoration: const InputDecoration(labelText: "Category")),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final user = _auth.currentUser;
                if (user == null || titleController.text.isEmpty) return;

                await _db.collection('users').doc(user.uid).collection('finance').add({
                  'title': titleController.text,
                  'amount': double.tryParse(amountController.text) ?? 0.0,
                  'date': Timestamp.now(),
                  'type': selectedType == TransactionType.income ? 'income' : 'expense',
                  'category': categoryController.text,
                });

                if (mounted) Navigator.pop(context);
              },
              child: const Text("Add"),
            ),
          ],
        ),
      ),
    );
  }
}
