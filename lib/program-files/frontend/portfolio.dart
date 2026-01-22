import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';
import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';

/// PortfolioPage provides a specialized interface for documenting team activities.
/// Entries can be categorized by team member and role, and are stored in Firestore for the Engineering Portfolio.
class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  final TextEditingController _descriptionController = TextEditingController();

  String? _uid;
  String? _teamLabel;

  // Master list of all team members from setup.
  List<_TeamMember> _teamMembers = [];
  // Currently selected members for a new entry.
  List<_TeamMember> _selectedMembers = [];

  // Available and selected categories/roles.
  List<String> _availableRoles = [];
  List<String> _selectedRoles = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _loadTeamData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// Loads team members and labels from the user's setupData in Firestore.
  Future<void> _loadTeamData() async {
    if (_uid == null) return;

    final doc =
    await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    if (!doc.exists) return;

    final data = doc.data();
    if (data == null) return;

    final setupData = data['setupData'];
    if (setupData is! Map<String, dynamic>) return;

    _teamLabel = setupData['label']?.toString();
    final rawMembers = setupData['teamMembers'];

    if (rawMembers is! List) return;

    final List<_TeamMember> members = [];
    for (var i = 0; i < rawMembers.length; i++) {
      final m = rawMembers[i];
      if (m is Map<String, dynamic>) {
        final firstName = (m['firstName'] ?? '').toString();
        final rolesRaw = m['roles'];
        final List<String> roles = rolesRaw is List
            ? rolesRaw.map((e) => e.toString()).toList()
            : [];

        members.add(_TeamMember(index: i, firstName: firstName, roles: roles));
      }
    }

    setState(() {
      _teamMembers = members;
    });
  }

  /// Manages the selection of team members and dynamically updates the available roles.
  void _toggleMemberSelection(_TeamMember member) {
    setState(() {
      if (_selectedMembers.any((m) => m.index == member.index)) {
        _selectedMembers.removeWhere((m) => m.index == member.index);
      } else {
        _selectedMembers.add(member);
      }

      // Rebuild the union of roles assigned to the selected members.
      final Set<String> roles = {};
      for (final m in _selectedMembers) {
        roles.addAll(m.roles);
      }
      _availableRoles = roles.toList()..sort();

      // Prune previously selected roles that are no longer available.
      _selectedRoles =
          _selectedRoles.where((r) => _availableRoles.contains(r)).toList();
    });
  }

  void _toggleRoleSelection(String role) {
    setState(() {
      if (_selectedRoles.contains(role)) {
        _selectedRoles.remove(role);
      } else {
        _selectedRoles.add(role);
      }
    });
  }

  /// Saves the new portfolio entry to Firestore.
  Future<void> _save() async {
    if (_uid == null) return;
    if (_selectedMembers.isEmpty) return;
    if (_selectedRoles.isEmpty) return;
    if (_descriptionController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();

      final memberNames =
      _selectedMembers.map((m) => m.firstName).toList(growable: false);
      final memberIndices =
      _selectedMembers.map((m) => m.index).toList(growable: false);

      final entry = {
        'memberNames': memberNames,
        'memberIndices': memberIndices,
        'roles': _selectedRoles,
        'description': _descriptionController.text.trim(),
        'timestamp': Timestamp.fromDate(now),
        'teamLabel': _teamLabel,
        'createdByUid': _uid,
      };

      // Legacy support fields for single assignee/role model.
      entry['memberName'] = memberNames.isNotEmpty ? memberNames.first : null;
      entry['role'] = _selectedRoles.isNotEmpty ? _selectedRoles.first : null;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('portfolio')
          .add(entry);

      // Reset form state upon successful save.
      _descriptionController.clear();
      setState(() {
        _selectedRoles = [];
        _selectedMembers = [];
        _availableRoles = [];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error while saving entry.')),
      );
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  String _formatDate(Timestamp ts) {
    final d = ts.toDate();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: const TopAppBar(
        title: 'Portfolio',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: const BottomNavBar(
        currentIndex: 0,
        onTabSelected: _dummyOnTabSelected,
        items: [],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Page Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Portfolio Entries',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_teamLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? theme.colorScheme.primary.withOpacity(0.2) : kPrimaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: isDark ? Colors.white24 : kPrimaryColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.groups_2_outlined, size: 16, color: theme.textTheme.bodySmall?.color),
                              const SizedBox(width: 6),
                              Text(
                                _teamLabel!,
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // New Entry Form Section
                  Card(
                    color: isDark ? theme.colorScheme.surface : theme.cardColor,
                    elevation: isDark ? 2 : 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isDark ? Colors.white12 : theme.dividerColor.withOpacity(0.6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add New Entry', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),

                          // Multi-select for Team Members.
                          Text('Team Members', style: theme.textTheme.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.3 : 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white24 : theme.dividerColor.withOpacity(0.7)),
                            ),
                            child: _teamMembers.isEmpty
                                ? Text('No team members configured in setup.', style: theme.textTheme.bodySmall?.copyWith(fontSize: 13))
                                : Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _teamMembers.map((m) {
                                final selected = _selectedMembers.any((x) => x.index == m.index);
                                return FilterChip(
                                  label: Text(m.firstName),
                                  selected: selected,
                                  onSelected: (_) => _toggleMemberSelection(m),
                                  selectedColor: theme.colorScheme.primary.withOpacity(0.35),
                                  labelStyle: theme.textTheme.bodySmall?.copyWith(color: selected ? Colors.white : theme.textTheme.bodySmall?.color),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Multi-select for Roles/Categories.
                          Text('Roles / Categories', style: theme.textTheme.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.3 : 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white24 : theme.dividerColor.withOpacity(0.7)),
                            ),
                            child: _availableRoles.isEmpty
                                ? Text('Select at least one member to choose roles.', style: theme.textTheme.bodySmall?.copyWith(fontSize: 13))
                                : Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _availableRoles.map((r) {
                                final selected = _selectedRoles.contains(r);
                                return FilterChip(
                                  label: Text(r),
                                  selected: selected,
                                  onSelected: (_) => _toggleRoleSelection(r),
                                  selectedColor: theme.colorScheme.primary.withOpacity(0.35),
                                  labelStyle: theme.textTheme.bodySmall?.copyWith(color: selected ? Colors.white : theme.textTheme.bodySmall?.color),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Description Input Field.
                          TextField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Description of activity',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),

                          // Submission Button.
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                elevation: 0,
                              ),
                              onPressed: _isSaving ? null : _save,
                              icon: _isSaving
                                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.save_outlined, size: 18),
                              label: Text(_isSaving ? 'Saving...' : 'Save Entry', style: const TextStyle(fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text('History', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  // Real-time List of Historical Entries.
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(_uid)
                        .collection('portfolio')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('No portfolio entries recorded yet.', style: theme.textTheme.bodyMedium?.copyWith(fontSize: 16)),
                        );
                      }

                      final docs = snapshot.data!.docs;

                      return Column(
                        children: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;

                          final memberNamesRaw = data['memberNames'];
                          final rolesRaw = data['roles'];

                          final List<String> memberNames = memberNamesRaw is List
                              ? memberNamesRaw.map((e) => e.toString()).toList()
                              : [if (data['memberName'] != null) data['memberName'].toString()];

                          final List<String> roles = rolesRaw is List
                              ? rolesRaw.map((e) => e.toString()).toList()
                              : [if (data['role'] != null) data['role'].toString()];

                          final description = (data['description'] ?? '') as String;
                          final timestamp = data['timestamp'] as Timestamp?;
                          final teamLabel = data['teamLabel']?.toString();

                          return _buildEntryCard(
                            theme: theme,
                            isDark: isDark,
                            memberNames: memberNames,
                            roles: roles,
                            description: description,
                            timestamp: timestamp,
                            teamLabel: teamLabel,
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds an individual history entry card.
  Widget _buildEntryCard({
    required ThemeData theme,
    required bool isDark,
    required List<String> memberNames,
    required List<String> roles,
    required String description,
    Timestamp? timestamp,
    String? teamLabel,
  }) {
    final dateLabel = timestamp != null ? _formatDate(timestamp) : 'Unknown date';
    final displayMembers = memberNames.isNotEmpty ? memberNames.join(', ') : 'Unknown';
    final displayRoles = roles.isNotEmpty ? roles.join(', ') : 'Unknown';

    final initials = memberNames.isNotEmpty && memberNames.first.isNotEmpty
        ? memberNames.first.trim()[0].toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white24 : theme.dividerColor.withOpacity(0.5)),
        boxShadow: isDark
            ? [BoxShadow(blurRadius: 10, offset: const Offset(0, 4), color: Colors.black.withOpacity(0.6))]
            : [BoxShadow(blurRadius: 6, offset: const Offset(0, 3), color: Colors.black.withOpacity(0.06))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metadata Header Row.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                  child: Text(initials, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayMembers, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.badge_outlined, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(displayRoles, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          if (teamLabel != null && teamLabel.isNotEmpty)
                            Text(teamLabel, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(dateLabel, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
              ],
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.7)),
            const SizedBox(height: 8),

            // Description of activity.
            Text(description, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

void _dummyOnTabSelected(int index) {}

/// Simple data model for a team member in the portfolio context.
class _TeamMember {
  final int index;
  final String firstName;
  final List<String> roles;

  _TeamMember({
    required this.index,
    required this.firstName,
    required this.roles,
  });
}
