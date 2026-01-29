// lib/program-files/frontend/team_searcher.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/backlog_api/team_searcher.dart';
import 'package:ftcmanageapp/program-files/frontend/team_detail.dart';

const int kCurrentSeason = 2025; // Decode season

/// Page to search FTC teams via improved repository with ranking and fuzzy fallback.
class TeamSearcherPage extends StatefulWidget {
  const TeamSearcherPage({super.key});

  @override
  State<TeamSearcherPage> createState() => _TeamSearcherPageState();
}

class _TeamSearcherPageState extends State<TeamSearcherPage> {
  final TextEditingController _searchController = TextEditingController();

  int _limit = 25;

  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _teams = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchTeams() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _teams = [];
    });

    try {
      // Use the repository instead of direct API call to benefit from ranking logic
      final result = await teamSearcherRepository.searchTeams(
        _searchController.text.trim(),
      );

      setState(() {
        // Apply limit locally if repository returns more
        _teams = result.take(_limit).toList();
        if (_teams.isEmpty && _searchController.text.isNotEmpty) {
          _errorMessage = "No teams found. Try a different name or number.";
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSearchForm(ThemeData theme) {
    final textTheme = theme.textTheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Smart Team Search', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Search by number, name, or city. Typos are handled automatically.', 
              style: textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search query',
                hintText: 'Team number of name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    })
                  : null,
              ),
              onSubmitted: (_) => _searchTeams(),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    initialValue: _limit.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Max results',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        setState(() {
                          _limit = parsed;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _searchTeams,
                icon: const Icon(Icons.search),
                label: const Text('Find Teams'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamList(ThemeData theme) {
    if (_isLoading) {
      return const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 48, color: theme.disabledColor),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_teams.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            'Enter a team name or number to begin.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: _teams.length,
        itemBuilder: (context, index) {
          final team = _teams[index];

          final numberRaw = team['number'] ?? team['teamNumber'];
          final int? number = numberRaw is int
              ? numberRaw
              : int.tryParse(numberRaw?.toString() ?? '');

          final nameFull = team['nameFull'] ?? team['name'] ?? '';
          final nameShort = team['nameShort'] ?? team['shortName'] ?? '';
          final region = team['region'] ?? '';
          final country = team['country'] ?? '';
          final city = team['city'] ?? '';

          final title = number != null
              ? 'Team $number'
              : (nameShort.toString().isNotEmpty
              ? nameShort.toString()
              : 'Unknown team');

          final subtitle = nameShort.toString().isNotEmpty ? nameShort.toString() : nameFull.toString();

          final locationParts = <String>[];
          if (city.toString().isNotEmpty) locationParts.add(city.toString());
          if (country.toString().isNotEmpty) {
            locationParts.add(country.toString());
          }
          final location = locationParts.isEmpty ? null : locationParts.join(', ');

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    (number ?? '?').toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle.isNotEmpty) Text(subtitle),
                  if (location != null)
                    Text(
                      location,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: number == null
                  ? null
                  : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeamDetailPage(
                      teamNumber: number,
                      teamName: nameShort.toString().isNotEmpty
                          ? nameShort.toString()
                          : nameFull.toString(),
                      season: kCurrentSeason,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    context.watch<ThemeService>();

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Team Searcher',
        showThemeToggle: true,
        showLogout: true,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            _buildSearchForm(theme),
            _buildTeamList(theme),
          ],
        ),
      ),
    );
  }
}
