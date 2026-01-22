import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/settings/battery/calculation_battery.dart';

/// BatteryPage allows teams to track the voltage and health of their batteries.
/// It provides a charging plan based on battery priority and current voltage.
class BatteryPage extends StatefulWidget {
  const BatteryPage({super.key});

  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends State<BatteryPage> {
  // Local state for batteries and chargers
  List<BatteryItem> _localBatteries = const [];
  int _localChargerCount = 1;

  // Default voltage thresholds
  double _emptyVoltage = 12.0;
  double _okayVoltage = 12.4;
  double _fullVoltage = 12.8;

  // Timer for debouncing Firestore updates
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Returns a reference to the current user's document in Firestore.
  DocumentReference<Map<String, dynamic>> _userDocRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return FirebaseFirestore.instance.collection('users').doc('__no_user__');
    }
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  /// Automatically saves the current battery states to Firestore after a brief delay.
  Future<void> _autoSave() async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      try {
        final setupUpdate = <String, dynamic>{
          'batteryVoltages': BatteryCalc.buildVoltageMap(_localBatteries),
          'batteryPriorities': BatteryCalc.buildPriorityMap(_localBatteries),
          'voltageThresholds': {
            'empty': _emptyVoltage,
            'okay': _okayVoltage,
            'full': _fullVoltage,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Merge the battery update into the existing setupData
        await _userDocRef().set({
          'setupData': setupUpdate,
        }, SetOptions(merge: true));

      } catch (e) {
        // Silent catch for auto-save errors
      }
    });
  }

  /// Updates the voltage of a specific battery and triggers auto-save.
  void _setBatteryVoltage(String label, double? voltage) {
    setState(() {
      _localBatteries = _localBatteries.map((b) {
        if (b.label == label) {
          return b.copyWith(voltage: voltage);
        }
        return b;
      }).toList();
    });
    _autoSave();
  }

  /// Updates the charging priority of a specific battery.
  void _setPriority(String label, int priority) {
    setState(() {
      _localBatteries = _localBatteries.map((b) {
        if (b.label == label) return b.copyWith(priority: priority);
        return b;
      }).toList();
    });
    _autoSave();
  }

  /// Maps a voltage value to a status color based on defined thresholds.
  Color _getVoltageColor(double? voltage) {
    if (voltage == null) return Colors.grey;
    if (voltage < _emptyVoltage) return Colors.red;
    if (voltage < _okayVoltage) return Colors.orange;
    if (voltage >= _fullVoltage) return Colors.green;
    return Colors.blue;
  }

  /// Returns a color representing the priority level.
  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 5: return Colors.red;
      case 4: return Colors.deepOrange;
      case 3: return Colors.amber;
      case 2: return Colors.lightGreen;
      case 1: return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  /// Returns a human-readable label for a priority level.
  String _getPriorityLabel(int priority) {
    switch (priority) {
      case 5: return 'Critical';
      case 4: return 'Very High';
      case 3: return 'High';
      case 2: return 'Normal';
      case 1: return 'Low';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: const TopAppBar(title: 'Batteries', showThemeToggle: true, showLogout: true),
        body: const Center(child: Text('You are not logged in.')),
      );
    }

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Batteries',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (idx) {},
        items: const [],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userDocRef().snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error loading data: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final data = snap.data?.data() ?? {};
          final setupData = (data['setupData'] as Map<String, dynamic>?) ?? {};

          // Hydrate local state from Firestore data
          final batteriesFromDb = BatteryCalc.batteriesFromSetupData(setupData);
          final chargerCountFromDb = BatteryCalc.chargerCountFromSetupData(setupData);
          
          final thresholds = setupData['voltageThresholds'] as Map<String, dynamic>?;

          final labelsDb = batteriesFromDb.map((b) => b.label).join(',');
          final labelsLocal = _localBatteries.map((b) => b.label).join(',');
          
          // Synchronize local state if database labels have changed or local state is empty
          if (labelsDb != labelsLocal || _localBatteries.isEmpty) {
             _localBatteries = batteriesFromDb;
             _localChargerCount = chargerCountFromDb;
             
             if (thresholds != null) {
                _emptyVoltage = (thresholds['empty'] as num?)?.toDouble() ?? 12.0;
                _okayVoltage = (thresholds['okay'] as num?)?.toDouble() ?? 12.4;
                _fullVoltage = (thresholds['full'] as num?)?.toDouble() ?? 12.8;
             }
          }

          // Calculate the optimal charging plan
          final plan = BatteryCalc.buildChargePlan(
            batteries: _localBatteries,
            chargerCount: _localChargerCount,
            emptyVoltageThreshold: _emptyVoltage,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
            children: [
              // Threshold Configuration Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Voltage Thresholds', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _thresholdField('Empty', _emptyVoltage, (v) {
                           setState(() => _emptyVoltage = v);
                           _autoSave();
                        })),
                        const SizedBox(width: 12),
                        Expanded(child: _thresholdField('Okay', _okayVoltage, (v) {
                           setState(() => _okayVoltage = v);
                           _autoSave();
                        })),
                        const SizedBox(width: 12),
                        Expanded(child: _thresholdField('Full', _fullVoltage, (v) {
                           setState(() => _fullVoltage = v);
                           _autoSave();
                        })),
                      ],
                    )
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Dynamic Charging Plan Section
              if (plan.plannedBatteries > 0)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                           Icon(Icons.bolt, color: theme.colorScheme.primary),
                           const SizedBox(width: 8),
                           Text(
                             'Charging Plan (${plan.plannedBatteries} needed)',
                             style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                           ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        children: List.generate(plan.batches.length, (i) {
                          final batch = plan.batches[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                              border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.primary,
                                  ),
                                  child: Text(
                                    '${i + 1}', 
                                    style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: batch.map((b) {
                                      final isPriority = b.priority > 0;
                                      return Chip(
                                        padding: const EdgeInsets.all(4),
                                        label: Text(b.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        avatar: isPriority 
                                          ? CircleAvatar(
                                              backgroundColor: Colors.transparent,
                                              child: Icon(Icons.star, size: 16, color: _getPriorityColor(b.priority)),
                                            )
                                          : null,
                                        backgroundColor: theme.colorScheme.surface,
                                        side: BorderSide(
                                          color: isPriority ? _getPriorityColor(b.priority) : theme.dividerColor,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),

              // Header for Battery List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  children: [
                    Text(
                      'All Batteries',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Icon(Icons.sort, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Individual Battery Cards
              if (_localBatteries.isEmpty)
                 const Center(
                   child: Padding(
                     padding: EdgeInsets.all(24.0),
                     child: Text('No batteries defined in Setup page.'),
                   ),
                 )
              else
                ..._localBatteries.map((b) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: _getVoltageColor(b.voltage), width: 1.5),
                    ),
                    color: _getVoltageColor(b.voltage).withOpacity(0.08),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          // Priority Selector
                          PopupMenuButton<int>(
                            icon: Icon(
                              b.priority > 0 ? Icons.star : Icons.star_border,
                              color: b.priority > 0 ? _getPriorityColor(b.priority) : theme.disabledColor,
                            ),
                            tooltip: 'Set Priority (1-5)',
                            onSelected: (val) => _setPriority(b.label, val),
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 5, child: Text('5 - Critical', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                              const PopupMenuItem(value: 4, child: Text('4 - Very High', style: TextStyle(color: Colors.deepOrange))),
                              const PopupMenuItem(value: 3, child: Text('3 - High', style: TextStyle(color: Colors.amber))),
                              const PopupMenuItem(value: 2, child: Text('2 - Normal', style: TextStyle(color: Colors.lightGreen))),
                              const PopupMenuItem(value: 1, child: Text('1 - Low', style: TextStyle(color: Colors.blueGrey))),
                              const PopupMenuDivider(),
                              const PopupMenuItem(value: 0, child: Text('None (Reset)')),
                            ],
                          ),
                          
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.label, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                if (b.priority > 0)
                                   Text(_getPriorityLabel(b.priority), style: TextStyle(fontSize: 10, color: _getPriorityColor(b.priority), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),

                          // Voltage Input Field
                          SizedBox(
                            width: 90,
                            child: TextFormField(
                              key: ValueKey(b.label), 
                              initialValue: b.voltage?.toString() ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                hintText: '--.-',
                                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                isDense: true,
                                filled: true,
                                fillColor: theme.colorScheme.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (val) {
                                final v = double.tryParse(val.replaceAll(',', '.'));
                                _setBatteryVoltage(b.label, v);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('V', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
  
  /// Helper widget to build individual threshold input fields.
  Widget _thresholdField(String label, double value, Function(double) onChanged) {
    return TextFormField(
      key: ValueKey('threshold_$label'), 
      initialValue: value.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (val) {
        final v = double.tryParse(val.replaceAll(',', '.'));
        if(v != null) {
          onChanged(v);
        }
      },
    );
  }
}
