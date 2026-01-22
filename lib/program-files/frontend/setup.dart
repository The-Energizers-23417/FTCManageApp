// lib/program-files/frontend/setup.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' hide colorFromHex;
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';
import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/frontend/dashboard.dart';

// Uses existing FTCScout repository and models to import events automatically.
import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-calculations/team_searcher.dart';

/// Model representing a basic battery configuration.
class BatteryConfig {
  String label;

  BatteryConfig({required this.label});

  Map<String, dynamic> toMap() => {
        'label': label,
      };
}

/// Model representing a team member and their assigned roles.
class TeamMemberConfig {
  String firstName;
  Set<String> roles;

  TeamMemberConfig({
    required this.firstName,
    Set<String>? roles,
  }) : roles = roles ?? <String>{};

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'roles': roles.toList(),
      };
}

/// Model representing an FTC event.
class EventConfig {
  String name;

  EventConfig({required this.name});

  Map<String, dynamic> toMap() => {
        'name': name,
      };
}

/// Aggregated setup data stored in Firestore for a team.
class SetupData {
  final AppThemeSettings themeSettings;
  final List<BatteryConfig> batteries;
  final int chargerCount;
  final List<TeamMemberConfig> teamMembers;
  final List<EventConfig> events;
  final List<String> availableRoles;

  SetupData({
    required this.themeSettings,
    required this.batteries,
    required this.chargerCount,
    required this.teamMembers,
    required this.events,
    required this.availableRoles,
  });

  Map<String, dynamic> toMap() => {
        'themeSettings': themeSettings.toMap(),
        'batteries': batteries.map((b) => b.toMap()).toList(),
        'chargerCount': chargerCount,
        'teamMembers': teamMembers.map((m) => m.toMap()).toList(),
        'events': events.map((e) => e.toMap()).toList(),
        'availableRoles': availableRoles,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// SetupPage provides a comprehensive interface for configuring team-specific settings:
/// - Custom application theme colors.
/// - Battery inventory and charger count.
/// - Team member list and their roles.
/// - Tournament event list (with automatic import from FTCScout).
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();

  // Flag for previewing theme changes locally before saving.
  bool _previewDark = false;

  // Local color state with default values.
  Color _headerLightColor = const Color(0xFF1976D2);
  Color _headerDarkColor = const Color(0xFF0D47A1);
  Color _textLightColor = const Color(0xFF000000);
  Color _textDarkColor = const Color(0xFFFFFFFF);
  Color _headerTitleLightColor = const Color(0xFFFFFFFF);
  Color _headerTitleDarkColor = const Color(0xFFFFFFFF);

  // Lists and counters for configuration sections.
  List<BatteryConfig> _batteries = [
    BatteryConfig(label: 'B1'),
    BatteryConfig(label: 'B2'),
  ];

  int _chargerCount = 2;

  List<String> _availableRoles = [
    'Driver',
    'Human Player',
    'Programmer',
    'Coach',
    'Portfolio Maker',
    'Mechanical',
    'S&O',
    'CAD',
    'Design',
  ];

  final TextEditingController _newRoleController = TextEditingController();

  List<TeamMemberConfig> _teamMembers = [
    TeamMemberConfig(firstName: 'Driver 1', roles: {'Driver'}),
  ];

  List<EventConfig> _events = [
    EventConfig(name: 'NLHAQ'),
  ];

  // State for importing events from the API.
  int _eventSeason = 2025;
  bool _importingEvents = false;
  String? _importEventsError;

  bool _saving = false;
  bool _loadingFromDb = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadExistingSetup();
  }

  @override
  void dispose() {
    _newRoleController.dispose();
    super.dispose();
  }

  /// Fetches existing setup data from Firestore and populates the local state.
  Future<void> _loadExistingSetup() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No authenticated user found.');
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final setup = data?['setupData'] as Map<String, dynamic>?;

        if (setup != null) {
          final theme = setup['themeSettings'] as Map<String, dynamic>?;

          if (theme != null) {
            _headerLightColor =
                colorFromHex(theme['headerLight'] as String?, _headerLightColor);
            _headerDarkColor =
                colorFromHex(theme['headerDark'] as String?, _headerDarkColor);
            _textLightColor =
                colorFromHex(theme['textLight'] as String?, _textLightColor);
            _textDarkColor =
                colorFromHex(theme['textDark'] as String?, _textDarkColor);
            _headerTitleLightColor = colorFromHex(
                theme['headerTitleLight'] as String?, _headerTitleLightColor);
            _headerTitleDarkColor = colorFromHex(
                theme['headerTitleDark'] as String?, _headerTitleDarkColor);
          }

          final rolesList = setup['availableRoles'] as List<dynamic>?;
          if (rolesList != null && rolesList.isNotEmpty) {
            _availableRoles = rolesList.map((e) => e.toString()).toList();
          }

          final batteriesList = setup['batteries'] as List<dynamic>? ?? [];
          if (batteriesList.isNotEmpty) {
            _batteries = batteriesList
                .map((e) => e as Map<String, dynamic>)
                .map((m) => BatteryConfig(label: (m['label'] ?? '') as String))
                .where((b) => b.label.trim().isNotEmpty)
                .toList();
          }

          final chargerVal = setup['chargerCount'];
          if (chargerVal is int) {
            _chargerCount = chargerVal;
          } else if (chargerVal is num) {
            _chargerCount = chargerVal.toInt();
          }

          final teamList = setup['teamMembers'] as List<dynamic>? ?? [];
          if (teamList.isNotEmpty) {
            _teamMembers = teamList
                .map((e) => e as Map<String, dynamic>)
                .map((m) {
              final name = (m['firstName'] ?? '') as String;
              final roles = (m['roles'] as List<dynamic>? ?? [])
                  .map((r) => r.toString())
                  .toSet();
              return TeamMemberConfig(firstName: name, roles: roles);
            })
                .where((m) => m.firstName.trim().isNotEmpty)
                .toList();
          }

          final eventList = setup['events'] as List<dynamic>? ?? [];
          if (eventList.isNotEmpty) {
            _events = eventList
                .map((e) => e as Map<String, dynamic>)
                .map((m) => EventConfig(name: (m['name'] ?? '') as String))
                .where((e) => e.name.trim().isNotEmpty)
                .toList();
          }

          // Immediately apply the theme globally upon successful load.
          final loadedTheme = AppThemeSettings(
            headerLight: _headerLightColor,
            headerDark: _headerDarkColor,
            textLight: _textLightColor,
            textDark: _textDarkColor,
            headerTitleLight: _headerTitleLightColor,
            headerTitleDark: _headerTitleDarkColor,
          );
          if (mounted) {
            context.read<ThemeService>().applySettings(loadedTheme);
          }
        }
      }

      setState(() {
        _loadingFromDb = false;
        _loadError = null;
      });
    } catch (e) {
      setState(() {
        _loadingFromDb = false;
        _loadError = e.toString();
      });
    }
  }

  /// Automatically fetches event participation history for the team from the FTCScout API.
  Future<void> _importEventsFromApi() async {
    setState(() {
      _importingEvents = true;
      _importEventsError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      final tnRaw = doc.data()?['teamNumber'];
      final tn = int.tryParse(tnRaw?.toString() ?? '');
      if (tn == null) {
        throw Exception(
          'Team number not set in profile (users/<uid>.teamNumber).',
        );
      }

      final data = await teamSearcherRepository.loadTeamDetail(
        teamNumber: tn,
        season: _eventSeason,
      );

      final codes = <String>{};
      for (final TeamMatchSummary m in data.matches) {
        final c = m.eventCode.trim();
        if (c.isNotEmpty) codes.add(c);
      }

      final list = codes.toList()..sort();

      if (list.isEmpty) {
        throw Exception('No events found for team $tn in season $_eventSeason.');
      }

      setState(() {
        _events = list.map((c) => EventConfig(name: c)).toList();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${list.length} events from FTCScout')),
        );
      }
    } catch (e) {
      setState(() => _importEventsError = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importingEvents = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color headerColor =
    _previewDark ? _headerDarkColor : _headerLightColor;
    final Color textColor = _previewDark ? _textDarkColor : _textLightColor;

    final ThemeData baseTheme =
    _previewDark ? ThemeData.dark() : Theme.of(context);

    const Color scaffoldBgDark = Color(0xFF121212);
    const Color surfaceDark = Color(0xFF1E1E1E);

    final ThemeData pageTheme = baseTheme.copyWith(
      brightness: _previewDark ? Brightness.dark : baseTheme.brightness,
      scaffoldBackgroundColor:
      _previewDark ? scaffoldBgDark : baseTheme.scaffoldBackgroundColor,
      colorScheme: baseTheme.colorScheme.copyWith(
        brightness:
        _previewDark ? Brightness.dark : baseTheme.colorScheme.brightness,
        surface: _previewDark ? surfaceDark : baseTheme.colorScheme.surface,
      ),
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: headerColor,
        foregroundColor:
        _previewDark ? _headerTitleDarkColor : _headerTitleLightColor,
        centerTitle: true,
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
    );

    return Theme(
      data: pageTheme,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('FTC Setup'),
          actions: [
            IconButton(
              icon: Icon(_previewDark ? Icons.dark_mode : Icons.light_mode),
              tooltip: 'Toggle theme preview',
              onPressed: () {
                setState(() {
                  _previewDark = !_previewDark;
                });
              },
            ),
          ],
        ),
        bottomNavigationBar: BottomNavBar(
          currentIndex: 0,
          onTabSelected: (index) {},
          items: const [],
        ),
        body: SafeArea(
          child: _loadingFromDb
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load settings:',
                  style: TextStyle(color: pageTheme.colorScheme.error),
                ),
                const SizedBox(height: 4),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _loadingFromDb = true;
                      _loadError = null;
                    });
                    _loadExistingSetup();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          )
              : Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth > 900
                    ? constraints.maxWidth * 0.2
                    : 16.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: textColor),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionTitle('1. Configure colors'),
                        _buildColorSection(),
                        const SizedBox(height: 16),
                        _buildSectionTitle('2. Configure batteries'),
                        _buildBatteriesSection(),
                        const SizedBox(height: 16),
                        _buildSectionTitle('3. Configure chargers'),
                        _buildChargersSection(),
                        const SizedBox(height: 16),
                        _buildSectionTitle('4. Configure roles'),
                        _buildRolesSection(),
                        const SizedBox(height: 16),
                        _buildSectionTitle('5. Configure team members'),
                        _buildTeamMembersSection(),
                        const SizedBox(height: 16),
                        _buildSectionTitle('6. Configure events'),
                        _buildEventsSection(),
                        const SizedBox(height: 24),
                        _buildSaveButton(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---------- UI SECTION BUILDERS ----------

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }

  // ------- COLOR CONFIGURATION -------

  Widget _buildColorPickerRow({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade400),
        ),
      ),
      title: Text(label),
      trailing: const Icon(Icons.color_lens),
      onTap: onTap,
    );
  }

  Widget _buildColorSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Theme colors',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildColorPickerRow(
            label: 'Header color (light theme)',
            color: _headerLightColor,
            onTap: () {
              _showColorPickerDialog(
                title: 'Select header color (light theme)',
                currentColor: _headerLightColor,
                onColorChanged: (c) => _headerLightColor = c,
              );
            },
          ),
          _buildColorPickerRow(
            label: 'Header color (dark theme)',
            color: _headerDarkColor,
            onTap: () {
              _showColorPickerDialog(
                title: 'Select header color (dark theme)',
                currentColor: _headerDarkColor,
                onColorChanged: (c) => _headerDarkColor = c,
              );
            },
          ),
          const Divider(height: 24),
          _buildColorPickerRow(
            label: 'Text color (light mode)',
            color: _textLightColor,
            onTap: () {
              _showColorPickerDialog(
                title: 'Select text color (light mode)',
                currentColor: _textLightColor,
                onColorChanged: (c) => _textLightColor = c,
              );
            },
          ),
          _buildColorPickerRow(
            label: 'Text color (dark mode)',
            color: _textDarkColor,
            onTap: () {
              _showColorPickerDialog(
                title: 'Select text color (dark mode)',
                currentColor: _textDarkColor,
                onColorChanged: (c) => _textDarkColor = c,
              );
            },
          ),
          const Divider(height: 24),
          _buildColorPickerRow(
            label: 'Header title color (light mode)',
            color: _headerTitleLightColor,
            onTap: () {
              _showColorPickerDialog(
                title: 'Select header title color (light mode)',
                currentColor: _headerTitleLightColor,
                onColorChanged: (c) => _headerTitleLightColor = c,
              );
            },
          ),
          _buildColorPickerRow(
            label: 'Header title color (dark mode)',
            color: _headerTitleDarkColor,
            onTap: () {
              _showColorPickerDialog(
                title: 'Select header title color (dark mode)',
                currentColor: _headerTitleDarkColor,
                onColorChanged: (c) => _headerTitleDarkColor = c,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Displays an interactive color selection dialog.
  Future<void> _showColorPickerDialog({
    required String title,
    required Color currentColor,
    required ValueChanged<Color> onColorChanged,
  }) async {
    Color tempColor = currentColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: tempColor,
              onColorChanged: (color) {
                tempColor = color;
                setState(() {
                  onColorChanged(color);
                });
              },
              enableAlpha: false,
              displayThumbColor: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ------- BATTERY CONFIGURATION -------

  Widget _buildBatteriesSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Number of batteries: ${_batteries.length}'),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _batteries.length,
            itemBuilder: (context, index) {
              final battery = _batteries[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: battery.label,
                        decoration: InputDecoration(
                          labelText: 'Battery label ${index + 1}',
                          hintText: 'e.g. B${index + 1}',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Label is required';
                          }
                          return null;
                        },
                        onChanged: (v) => battery.label = v.trim(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove battery',
                      onPressed: _batteries.length > 1
                          ? () {
                        setState(() {
                          _batteries.removeAt(index);
                        });
                      }
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add battery'),
              onPressed: () {
                setState(() {
                  _batteries.add(
                    BatteryConfig(label: 'B${_batteries.length + 1}'),
                  );
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ------- CHARGER CONFIGURATION -------

  Widget _buildChargersSection() {
    return _buildCard(
      child: Row(
        children: [
          const Text('Number of chargers:'),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: const ValueKey('chargerCount'),
              initialValue: _chargerCount.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g. 2',
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Enter a number';
                }
                final n = int.tryParse(val);
                if (n == null || n < 0) return 'Invalid number';
                return null;
              },
              onChanged: (val) {
                final n = int.tryParse(val);
                if (n != null && n >= 0) {
                  setState(() {
                    _chargerCount = n;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ------- ROLE CONFIGURATION -------

  Widget _buildRolesSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Custom Roles',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableRoles.map((role) {
              return Chip(
                label: Text(role),
                onDeleted: () {
                  setState(() {
                    _availableRoles.remove(role);
                    for (var member in _teamMembers) {
                      member.roles.remove(role);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newRoleController,
                  decoration: const InputDecoration(
                    labelText: 'New role name',
                    hintText: 'e.g. Scouter',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle),
                color: Theme.of(context).colorScheme.primary,
                onPressed: () {
                  final text = _newRoleController.text.trim();
                  if (text.isNotEmpty && !_availableRoles.contains(text)) {
                    setState(() {
                      _availableRoles.add(text);
                      _newRoleController.clear();
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------- TEAM MEMBER CONFIGURATION -------

  Widget _buildTeamMembersSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Number of team members: ${_teamMembers.length}'),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _teamMembers.length,
            itemBuilder: (context, index) {
              final member = _teamMembers[index];
              return Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withAlpha(77),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: member.firstName,
                              decoration: InputDecoration(
                                labelText:
                                'First name team member ${index + 1}',
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'First name is required';
                                }
                                return null;
                              },
                              onChanged: (v) => member.firstName = v.trim(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove team member',
                            onPressed: _teamMembers.length > 1
                                ? () {
                              setState(() {
                                _teamMembers.removeAt(index);
                              });
                            }
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Roles',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _availableRoles.map((role) {
                          final selected = member.roles.contains(role);
                          return FilterChip(
                            label: Text(role),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  member.roles.add(role);
                                } else {
                                  member.roles.remove(role);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add team member'),
              onPressed: () {
                setState(() {
                  _teamMembers.add(TeamMemberConfig(firstName: 'New member'));
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ------- EVENT CONFIGURATION (WITH API INTEGRATION) -------

  Widget _buildEventsSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Number of FTC events: ${_events.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),

              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withAlpha(77),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _eventSeason,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 2024, child: Text('2024')),
                      DropdownMenuItem(value: 2025, child: Text('2025')),
                      DropdownMenuItem(value: 2026, child: Text('2026')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _eventSeason = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              FilledButton.icon(
                onPressed: _importingEvents ? null : _importEventsFromApi,
                icon: _importingEvents
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.cloud_download),
                label: Text(_importingEvents ? 'Importing...' : 'Import'),
              ),
            ],
          ),

          if (_importEventsError != null) ...[
            const SizedBox(height: 8),
            Text(
              _importEventsError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],

          const SizedBox(height: 12),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _events.length,
            itemBuilder: (context, index) {
              final event = _events[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: event.name,
                        decoration: const InputDecoration(
                          labelText: 'Event name / event code',
                          hintText: 'e.g. NLHAQ',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Event name is required';
                          }
                          return null;
                        },
                        onChanged: (v) => event.name = v.trim(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove event',
                      onPressed: _events.length > 1
                          ? () {
                        setState(() {
                          _events.removeAt(index);
                        });
                      }
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add event'),
              onPressed: () {
                setState(() {
                  _events.add(EventConfig(name: 'New event'));
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ------- SAVE ACTION -------

  Widget _buildSaveButton() {
    return ElevatedButton.icon(
      icon: _saving
          ? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
          : const Icon(Icons.save),
      label: Text(
        _saving ? 'Saving...' : 'Save settings & synchronize',
      ),
      onPressed: _saving ? null : _onSavePressed,
    );
  }

  // ---------- SAVE LOGIC & NAVIGATION ----------

  Future<void> _onSavePressed() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final themeSettings = AppThemeSettings(
        headerLight: _headerLightColor,
        headerDark: _headerDarkColor,
        textLight: _textLightColor,
        textDark: _textDarkColor,
        headerTitleLight: _headerTitleLightColor,
        headerTitleDark: _headerTitleDarkColor,
      );

      final setupData = SetupData(
        themeSettings: themeSettings,
        batteries: List<BatteryConfig>.from(_batteries),
        chargerCount: _chargerCount,
        teamMembers: List<TeamMemberConfig>.from(_teamMembers),
        events: List<EventConfig>.from(_events),
        availableRoles: List<String>.from(_availableRoles),
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No authenticated user found.');
      }

      final userDoc =
      FirebaseFirestore.instance.collection('users').doc(user.uid);

      // Persist configuration to Firestore.
      await userDoc.set(
        {
          'setupData': setupData.toMap(),
        },
        SetOptions(merge: true),
      );

      // Apply the new theme globally.
      if (mounted) {
        context.read<ThemeService>().applySettings(themeSettings);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setup saved and synchronized!'),
          ),
        );

        // Redirect user to the dashboard upon completion.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const DashboardPage(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error while saving: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}
