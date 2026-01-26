import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// A page for configuring robot hardware ports (Motors, Servos, Sensors).
/// Data is persisted to Firestore and can be exported as Java code for FTC SDK.
class RobotConfigPage extends StatefulWidget {
  const RobotConfigPage({super.key});

  @override
  State<RobotConfigPage> createState() => _RobotConfigPageState();
}

class _RobotConfigPageState extends State<RobotConfigPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  bool _loading = true;
  
  /// Notifier to track saving status without rebuilding the entire form.
  final ValueNotifier<bool> _isSavingNotifier = ValueNotifier<bool>(false);
  
  Map<String, dynamic> _config = {};
  
  // Timer for auto-saving (debouncing)
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _isSavingNotifier.dispose();
    super.dispose();
  }

  /// Triggers a delayed auto-save when data changes.
  /// Removed setState to prevent UI lag during typing.
  void _onDataChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    
    _isSavingNotifier.value = true;
    
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _saveConfig(silent: true);
    });
  }

  /// Loads the existing configuration from Firestore.
  Future<void> _loadConfig() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()?['robotConfig'] as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _config = _mergeWithDefault(data ?? _defaultConfig());
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _config = _defaultConfig();
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Merges saved configuration with the default schema to ensure no missing keys.
  Map<String, dynamic> _mergeWithDefault(Map<String, dynamic> saved) {
    final def = _defaultConfig();
    for (var hubKey in def.keys) {
      if (!saved.containsKey(hubKey)) {
        saved[hubKey] = def[hubKey];
      } else {
        for (var portKey in def[hubKey].keys) {
          if (!saved[hubKey].containsKey(portKey)) {
            saved[hubKey][portKey] = def[hubKey][portKey];
          } else if (saved[hubKey][portKey] is List && def[hubKey][portKey] is List) {
            if ((saved[hubKey][portKey] as List).length < (def[hubKey][portKey] as List).length) {
              final newList = List<String>.from(saved[hubKey][portKey]);
              while (newList.length < (def[hubKey][portKey] as List).length) {
                newList.add('');
              }
              saved[hubKey][portKey] = newList;
            }
          }
        }
      }
    }
    return saved;
  }

  /// Defines the default hardware structure for Control and Expansion Hubs.
  Map<String, dynamic> _defaultConfig() {
    return {
      'hub0': {
        'motors': List.filled(4, ''),
        'servos': List.filled(6, ''),
        'digital': List.filled(8, ''),
        'analog': List.filled(4, ''),
        'i2c': List.filled(4, ''),
        'imu': 'Internal BHI260AP',
      },
      'hub1': {
        'motors': List.filled(4, ''),
        'servos': List.filled(6, ''),
        'digital': List.filled(8, ''),
        'analog': List.filled(4, ''),
        'i2c': List.filled(4, ''),
      },
    };
  }

  /// Saves the current configuration to Firestore.
  Future<void> _saveConfig({bool silent = false}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    _isSavingNotifier.value = true;

    try {
      await _db.collection('users').doc(user.uid).set({
        'robotConfig': _config,
      }, SetOptions(merge: true));

      _isSavingNotifier.value = false;
      
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved!'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      _isSavingNotifier.value = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  /// Generates a Java class (RobotHardware.java) based on the configured ports.
  String _generateJavaCode() {
    StringBuffer buffer = StringBuffer();
    buffer.writeln("package org.firstinspires.ftc.teamcode;");
    buffer.writeln();
    buffer.writeln("import com.qualcomm.robotcore.hardware.DcMotor;");
    buffer.writeln("import com.qualcomm.robotcore.hardware.Servo;");
    buffer.writeln("import com.qualcomm.robotcore.hardware.DigitalChannel;");
    buffer.writeln("import com.qualcomm.robotcore.hardware.AnalogInput;");
    buffer.writeln("import com.qualcomm.robotcore.hardware.HardwareMap;");
    buffer.writeln("import com.qualcomm.robotcore.hardware.IMU;");
    buffer.writeln();
    buffer.writeln("/**");
    buffer.writeln(" * Hardware definition class for the robot.");
    buffer.writeln(" * Generated via FTC Manage App.");
    buffer.writeln(" */");
    buffer.writeln("public class RobotHardware {");
    
    // Hub 0 - Control Hub
    buffer.writeln("    // Hub 0 - Control Hub");
    _generateDeclarations(buffer, 'hub0');
    buffer.writeln("    public IMU imu;");
    buffer.writeln();

    // Hub 1 - Expansion Hub
    buffer.writeln("    // Hub 1 - Expansion Hub");
    _generateDeclarations(buffer, 'hub1');
    buffer.writeln();

    buffer.writeln("    public void init(HardwareMap hwMap) {");
    
    // Initialize components
    _generateInit(buffer, 'hub0');
    buffer.writeln("        imu = hwMap.get(IMU.class, \"imu\");");
    buffer.writeln();
    _generateInit(buffer, 'hub1');
    
    buffer.writeln("    }");
    buffer.writeln("}");
    
    return buffer.toString();
  }

  void _generateDeclarations(StringBuffer buffer, String hubKey) {
    _addDecl(buffer, hubKey, 'motors', 'DcMotor');
    _addDecl(buffer, hubKey, 'servos', 'Servo');
    _addDecl(buffer, hubKey, 'digital', 'DigitalChannel');
    _addDecl(buffer, hubKey, 'analog', 'AnalogInput');
    _addDecl(buffer, hubKey, 'i2c', 'Object'); 
  }

  void _addDecl(StringBuffer buffer, String hubKey, String typeKey, String className) {
    List<dynamic> ports = _config[hubKey][typeKey];
    for (int i = 0; i < ports.length; i++) {
      if (ports[i].toString().trim().isNotEmpty) {
        String varName = _sanitize(ports[i].toString());
        buffer.writeln("    public $className $varName; // Port $i");
      }
    }
  }

  void _generateInit(StringBuffer buffer, String hubKey) {
    _addInit(buffer, hubKey, 'motors', 'DcMotor');
    _addInit(buffer, hubKey, 'servos', 'Servo');
    _addInit(buffer, hubKey, 'digital', 'DigitalChannel');
    _addInit(buffer, hubKey, 'analog', 'AnalogInput');
  }

  void _addInit(StringBuffer buffer, String hubKey, String typeKey, String className) {
    List<dynamic> ports = _config[hubKey][typeKey];
    for (int i = 0; i < ports.length; i++) {
      if (ports[i].toString().trim().isNotEmpty) {
        String varName = _sanitize(ports[i].toString());
        buffer.writeln("        $varName = hwMap.get($className.class, \"$varName\");");
      }
    }
  }

  String _sanitize(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  void _showExportDialog() {
    String javaCode = _generateJavaCode();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Java Export (RobotHardware.java)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  javaCode,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: javaCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text("Copy Code"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TopAppBar(
        title: "Robot Configuration",
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isSavingNotifier,
            builder: (context, isSaving, child) {
              if (isSaving) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                );
              }
              return const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Icon(Icons.cloud_done, size: 20, color: Colors.white70),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: "Export Java Code",
            onPressed: _showExportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: "Manual Save",
            onPressed: () => _saveConfig(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (i) {},
        items: const [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      _buildHubSection('Control Hub (Hub 0)', 'hub0', isControlHub: true),
                      const SizedBox(height: 16),
                      _buildHubSection('Expansion Hub (Hub 1)', 'hub1', isControlHub: false),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHubSection(String title, String hubKey, {required bool isControlHub}) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            _buildPortTypeSection(hubKey, 'motors', 'DC Motors', Icons.settings_input_component, 4),
            _buildPortTypeSection(hubKey, 'servos', 'Servos', Icons.precision_manufacturing, 6),
            _buildPortTypeSection(hubKey, 'digital', 'Digital I/O', Icons.electrical_services, 8),
            _buildPortTypeSection(hubKey, 'analog', 'Analog Input', Icons.linear_scale, 4),
            _buildPortTypeSection(hubKey, 'i2c', 'I2C Ports', Icons.alt_route, 4),
            if (isControlHub) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.explore, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text('Internal IMU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _config[hubKey]['imu'],
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (val) {
                  _config[hubKey]['imu'] = val;
                  _onDataChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPortTypeSection(String hubKey, String typeKey, String label, IconData icon, int count) {
    List<TableRow> rows = [];
    for (int i = 0; i < count; i += 2) {
      rows.add(
        TableRow(
          children: [
            _buildInputField(hubKey, typeKey, i),
            if (i + 1 < count)
              _buildInputField(hubKey, typeKey, i + 1)
            else
              const SizedBox.shrink(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: rows,
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(String hubKey, String typeKey, int index) {
    final List<dynamic> ports = _config[hubKey][typeKey];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Port $index',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: ports[index],
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onChanged: (val) {
              _config[hubKey][typeKey][index] = val;
              _onDataChanged();
            },
          ),
        ],
      ),
    );
  }
}
