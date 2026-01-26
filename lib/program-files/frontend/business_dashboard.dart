import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';
import 'package:ftcmanageapp/program-files/frontend/sponsor_manager.dart';
import 'package:ftcmanageapp/program-files/frontend/income_manager.dart';
import 'package:ftcmanageapp/program-files/frontend/expense_manager.dart';
import 'package:ftcmanageapp/program-files/frontend/event_manager.dart';

/// The central Business Hub Dashboard.
/// It aggregates data from Finance, Sponsors, and Events to provide a high-level overview
/// of the team's sustainability and outreach progress.
class BusinessDashboardPage extends StatefulWidget {
  const BusinessDashboardPage({super.key});

  @override
  State<BusinessDashboardPage> createState() => _BusinessDashboardPageState();
}

class _BusinessDashboardPageState extends State<BusinessDashboardPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text("Please login")));

    return Scaffold(
      appBar: const TopAppBar(title: "Business Hub"),
      bottomNavigationBar: BottomNavBar(currentIndex: 0, onTabSelected: (_) {}, items: const []),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Top Navigation Bar for quick access to sub-modules (Incomes, Expenses, Sponsors, Events)
            _buildQuickNavigation(context),
            const SizedBox(height: 20),
            
            // Side-by-side Charts for wide screens (Web/Tablet), vertical for narrow (Mobile).
            // Visualizes Financial Health (In/Out) and Sponsorship Pipeline.
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildFinancialHealthChart(user.uid)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSponsorshipPipelineChart(user.uid)),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildFinancialHealthChart(user.uid),
                      const SizedBox(height: 16),
                      _buildSponsorshipPipelineChart(user.uid),
                    ],
                  );
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Displays breakdown of finances by specific categories (e.g., Parts, Travel, Fundraising)
            _buildCategoryCharts(user.uid),
            
            const SizedBox(height: 16),
            // Detailed List showing all planned FTC events, their dates, and individual financial outcomes.
            _buildDetailedEventList(user.uid),
            
            const SizedBox(height: 24),
            // Button to export raw financial data formatted for the Engineering Portfolio.
            _buildExportSection(user.uid),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// Builds a horizontal scrollable row of chips for quick navigation between trackers.
  Widget _buildQuickNavigation(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _navChip(context, "Income", Icons.add_chart, const IncomeManagerPage(), Colors.green),
          _navChip(context, "Expenses", Icons.analytics_outlined, const ExpenseManagerPage(), Colors.red),
          _navChip(context, "Sponsors", Icons.handshake_outlined, const SponsorManagerPage(), Colors.blue),
          _navChip(context, "Events", Icons.event_available, const EventManagerPage(), Colors.orange),
        ],
      ),
    );
  }

  /// Helper to build a styled navigation chip with team colors.
  Widget _navChip(BuildContext context, String label, IconData icon, Widget page, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        backgroundColor: color.withOpacity(0.1),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
    );
  }

  /// Visualizes the total financial balance using a Pie Chart.
  /// Aggregates data from both general finance records and event-specific finances.
  Widget _buildFinancialHealthChart(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').doc(uid).collection('finance').snapshots(),
      builder: (context, financeSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _db.collection('users').doc(uid).collection('events').snapshots(),
          builder: (context, eventSnapshot) {
            double totalIn = 0;
            double totalOut = 0;

            // 1. Process regular finance records
            if (financeSnapshot.hasData) {
              for (var doc in financeSnapshot.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                final amount = (d['amount'] ?? 0.0).toDouble();
                if (d['type'] == 'income') totalIn += amount; else totalOut += amount;
              }
            }

            // 2. Process event-specific income and spending
            if (eventSnapshot.hasData) {
              for (var doc in eventSnapshot.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                totalIn += (d['income'] ?? 0.0).toDouble();
                totalOut += (d['spent'] ?? 0.0).toDouble();
              }
            }

            final bool hasData = totalIn > 0 || totalOut > 0;

            return _cardWrapper(
              "Financial Health",
              Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: hasData 
                      ? PieChart(
                          PieChartData(
                            sections: [
                              PieChartSectionData(value: totalIn == 0 ? 0.01 : totalIn, color: Colors.green, title: 'In', radius: 45, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              PieChartSectionData(value: totalOut == 0 ? 0.01 : totalOut, color: Colors.red, title: 'Out', radius: 45, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                            centerSpaceRadius: 35,
                          ),
                        )
                      : const Center(child: Text("No financial data", style: TextStyle(color: Colors.grey))),
                  ),
                  const SizedBox(height: 16),
                  _kpiRow("Total Budget", "€${(totalIn - totalOut).toStringAsFixed(2)}", Colors.blue),
                  _kpiRow("Total In", "€${totalIn.toStringAsFixed(2)}", Colors.green),
                  _kpiRow("Total Out", "€${totalOut.toStringAsFixed(2)}", Colors.red),
                ],
              ),
            );
          }
        );
      },
    );
  }

  /// Shows breakdown Pie Charts for income and expense categories.
  Widget _buildCategoryCharts(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').doc(uid).collection('finance').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        Map<String, double> incomeCats = {};
        Map<String, double> expenseCats = {};

        // Sort data into categorical maps
        for (var doc in snapshot.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final amount = (d['amount'] ?? 0.0).toDouble();
          final cat = d['category'] ?? 'General';
          if (d['type'] == 'income') {
            incomeCats[cat] = (incomeCats[cat] ?? 0) + amount;
          } else {
            expenseCats[cat] = (expenseCats[cat] ?? 0) + amount;
          }
        }

        return _cardWrapper(
          "Type Breakdowns",
          Column(
            children: [
              const Text("Income Categories", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 12),
              _buildCategoryPie(incomeCats, Colors.green),
              const Divider(height: 32),
              const Text("Expense Categories", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 12),
              _buildCategoryPie(expenseCats, Colors.red),
            ],
          ),
        );
      },
    );
  }

  /// Helper to build a small category PieChart with a legend.
  Widget _buildCategoryPie(Map<String, double> data, Color baseColor) {
    if (data.isEmpty) return const SizedBox(height: 100, child: Center(child: Text("No data", style: TextStyle(fontSize: 12, color: Colors.grey))));
    
    final sections = data.entries.toList();
    final List<Color> colors = [
      baseColor,
      baseColor.withOpacity(0.7),
      baseColor.withOpacity(0.4),
      Colors.blueGrey,
      Colors.teal,
      Colors.amber,
    ];

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PieChart(
            PieChartData(
              sections: sections.asMap().entries.map((e) {
                return PieChartSectionData(
                  value: e.value.value,
                  title: '',
                  radius: 35,
                  color: colors[e.key % colors.length],
                );
              }).toList(),
              centerSpaceRadius: 25,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Legend for categories
        Wrap(
          spacing: 8,
          children: sections.asMap().entries.map((e) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, color: colors[e.key % colors.length]),
              const SizedBox(width: 4),
              Text("${e.value.key}: €${e.value.value.toStringAsFixed(0)}", style: const TextStyle(fontSize: 10)),
            ],
          )).toList(),
        )
      ],
    );
  }

  /// Bar Chart showing the distribution of sponsors in the pipeline stages.
  Widget _buildSponsorshipPipelineChart(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').doc(uid).collection('sponsors').snapshots(),
      builder: (context, snapshot) {
        Map<String, int> counts = {};
        for (var status in SponsorStatus.values) {
          counts[status.id] = 0;
        }

        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final s = (doc.data() as Map<String, dynamic>)['status'] ?? '';
            counts[s] = (counts[s] ?? 0) + 1;
          }
        }

        return _cardWrapper(
          "Sponsorship Pipeline",
          SizedBox(
            height: 350,
            child: BarChart(
              BarChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: SponsorStatus.values.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: counts[entry.value.id]!.toDouble(),
                        color: entry.value.color,
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      )
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= SponsorStatus.values.length) return const Text("");
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(SponsorStatus.values[index].label.substring(0, 3), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Detailed list of all events with their date and individual cash flow summary.
  Widget _buildDetailedEventList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').doc(uid).collection('events').orderBy('date', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final events = snapshot.data!.docs;
        final now = DateTime.now();

        return _cardWrapper(
          "Event Schedule & Finances",
          Column(
            children: [
              if (events.isEmpty)
                const Center(child: Text("No events planned", style: TextStyle(color: Colors.grey)))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: events.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final d = events[index].data() as Map<String, dynamic>;
                    final date = (d['date'] as Timestamp).toDate();
                    final earned = (d['income'] ?? 0.0).toDouble();
                    final spent = (d['spent'] ?? 0.0).toDouble();
                    final isUpcoming = date.isAfter(now);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isUpcoming ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        child: Icon(isUpcoming ? Icons.event : Icons.event_available, color: isUpcoming ? Colors.orange : Colors.grey, size: 20),
                      ),
                      title: Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${date.day}/${date.month}/${date.year} • ${d['location'] ?? ''}"),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("€${earned.toStringAsFixed(0)} in", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text("€${spent.toStringAsFixed(0)} out", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Reusable styling wrapper for dashboard sections.
  Widget _cardWrapper(String title, Widget child) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  /// Builds a horizontal KPI row for financial summaries.
  Widget _kpiRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  /// Export section containing the raw numbers generation button.
  Widget _buildExportSection(String uid) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        onPressed: () => _exportRawNumbers(uid),
        icon: const Icon(Icons.calculate_outlined),
        label: const Text("Portfolio Raw Numbers"),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  /// Generates a concise plain-text report of raw financial data, sponsorships, and event finances.
  /// Copies the result directly to the system clipboard.
  Future<void> _exportRawNumbers(String uid) async {
    final financeSnap = await _db.collection('users').doc(uid).collection('finance').get();
    final sponsorSnap = await _db.collection('users').doc(uid).collection('sponsors').get();
    final eventSnap = await _db.collection('users').doc(uid).collection('events').get();

    StringBuffer report = StringBuffer();
    
    double tIn = 0; double tOut = 0;
    List<String> expenseList = [];

    // Aggregate generic finance data
    for (var d in financeSnap.docs) {
      final data = d.data() as Map<String, dynamic>;
      final amount = (data['amount'] ?? 0.0).toDouble();
      if (data['type'] == 'income') {
        tIn += amount;
      } else {
        tOut += amount;
        expenseList.add("- ${data['title']}: € ${amount.toStringAsFixed(2)} (${data['category'] ?? 'Other'})");
      }
    }
    
    // Aggregate event finance data
    for (var d in eventSnap.docs) {
      final data = d.data() as Map<String, dynamic>;
      final inc = (data['income'] ?? 0).toDouble(); 
      final exp = (data['spent'] ?? 0).toDouble();
      tIn += inc;
      tOut += exp;
      if (exp > 0) {
        expenseList.add("- Event [${data['name']}]: € ${exp.toStringAsFixed(2)}");
      }
    }

    report.writeln("FTC TEAM - RAW FINANCIAL DATA");
    report.writeln("-----------------------------");
    report.writeln("TOTAL REVENUE:  € ${tIn.toStringAsFixed(2)}");
    report.writeln("TOTAL EXPENSES: € ${tOut.toStringAsFixed(2)}");
    report.writeln("NET BALANCE:    € ${(tIn - tOut).toStringAsFixed(2)}");

    report.writeln("\nEXPENSE BREAKDOWN:");
    if (expenseList.isEmpty) {
      report.writeln("- No expenses recorded.");
    } else {
      for (var e in expenseList) report.writeln(e);
    }

    report.writeln("\nSPONSORSHIP REVENUE:");
    bool foundSponsor = false;
    for (var d in sponsorSnap.docs) {
      final data = d.data() as Map<String, dynamic>;
      if (data['status'] == 'sponsored') {
        report.writeln("- ${data['name']}: € ${(data['fixedAmount'] ?? 0.0).toStringAsFixed(2)}");
        foundSponsor = true;
      }
    }
    if (!foundSponsor) report.writeln("- No sponsors secured yet.");

    report.writeln("\nEVENT FINANCIALS:");
    if (eventSnap.docs.isEmpty) {
      report.writeln("- No events planned.");
    } else {
      for (var d in eventSnap.docs) {
        final data = d.data() as Map<String, dynamic>;
        final inc = (data['income'] ?? 0.0).toDouble();
        final exp = (data['spent'] ?? 0.0).toDouble();
        report.writeln("- ${data['name']}: In €${inc.toStringAsFixed(0)} / Out €${exp.toStringAsFixed(0)}");
      }
    }

    Clipboard.setData(ClipboardData(text: report.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Raw numbers & expenses copied to clipboard!"),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }
}
