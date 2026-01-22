// lib/program-files/frontend/team_searcher.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

import 'package:ftcmanageapp/program-files/backend/api-ftcscout-rest/api-connection/api_global.dart';
import 'package:ftcmanageapp/program-files/frontend/team_detail.dart';

const int kCurrentSeason = 2025; // Decode season

/// Page to search FTC teams via FTCScout REST API.
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
  List<dynamic> _teams = [];

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
      final result = await ftcScoutApi.searchTeams(
        // ✅ Region removed
        limit: _limit,
        searchText: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );

      if (result is List) {
        setState(() {
          _teams = result;
        });
      } else {
        setState(() {
          _errorMessage = 'Unexpected response format from API.';
        });
      }
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
            Text('Team search', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search text',
                hintText: 'Team number, name, city...',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _searchTeams(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Alleen limit veld over (rechts uitgelijnd)
                const Spacer(),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    initialValue: _limit.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Limit',
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
                label: const Text('Search teams'),
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
          child: Text(
            _errorMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_teams.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            'No teams loaded.\nUse the search form above.',
            style: theme.textTheme.bodyMedium,
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

          if (team is! Map) return const SizedBox.shrink();

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

          final subtitleParts = <String>[];
          if (nameFull != null && nameFull.toString().isNotEmpty) {
            subtitleParts.add(nameFull.toString());
          }
          if (nameShort != null &&
              nameShort.toString().isNotEmpty &&
              nameShort != nameFull) {
            subtitleParts.add('($nameShort)');
          }
          final subtitle = subtitleParts.join(' ');

          final locationParts = <String>[];
          if (city.toString().isNotEmpty) locationParts.add(city.toString());
          if (country.toString().isNotEmpty) {
            locationParts.add(country.toString());
          }
          final location =
          locationParts.isEmpty ? null : locationParts.join(', ');

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  (number ?? '?').toString(),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              title: Text(title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle.isNotEmpty) Text(subtitle),
                  if (region.toString().isNotEmpty)
                    Text(
                      'Region: $region',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (location != null && location.isNotEmpty)
                    Text(
                      'Location: $location',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
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
    // Zorgt dat theme updates door ThemeService ook deze pagina rebuilden
    context.watch<ThemeService>();

    return Scaffold(
      appBar: const TopAppBar(
        title: 'Team searcher',
        showThemeToggle: true,
        showLogout: true,
      ),
      // Alleen FTCScout-footer in de bottom bar
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
