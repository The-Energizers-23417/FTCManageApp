// lib/program-files/frontend/resource_hub.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// ResourceHubPage provides an integrated PDF viewer for competition manuals and resources.
/// Features include keyword searching, page navigation, and keyboard shortcuts.
class ResourceHubPage extends StatefulWidget {
  const ResourceHubPage({super.key});

  @override
  State<ResourceHubPage> createState() => _ResourceHubPageState();
}

class _ResourceHubPageState extends State<ResourceHubPage> {
  // Path to the primary competition manual PDF asset.
  static const String _pdfAssetPath = 'files/resources/DECODE_Competition_Manual_TU18.pdf';

  final PdfViewerController _pdfController = PdfViewerController();

  PdfDocument? _doc;
  int _pageCount = 1;

  // Visual state for the current page number.
  int _page = 1;

  // Controllers for direct page navigation input.
  final TextEditingController _pageController = TextEditingController(text: '1');
  final FocusNode _pageFocus = FocusNode();

  // Document loading and search state.
  bool _openingDoc = true;
  String? _openError;

  bool _searching = false;
  String? _lastQuery;
  
  // Cache for page text to improve subsequent search performance.
  final Map<int, String> _pageTextCache = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Load localized user theme settings.
      context.read<ThemeService>().loadFromFirestore();
      await _openDocument();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  /// Attempts to open the PDF document from application assets.
  Future<void> _openDocument() async {
    setState(() {
      _openingDoc = true;
      _openError = null;
    });

    try {
      final doc = await PdfDocument.openAsset(_pdfAssetPath);
      final count = doc.pages.length;
      setState(() {
        _doc = doc;
        _pageCount = count <= 0 ? 1 : count;
        _openingDoc = false;
      });
    } catch (e) {
      setState(() {
        _openingDoc = false;
        _openError = e.toString();
      });
    }
  }

  /// Handles navigation changes from the bottom bar.
  void _onTabSelected(int index) {
    if (index == 0) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
      return;
    }
    // Staying on current page (Resources).
    if (index == 1) return;
  }

  /// Navigates the viewer to a specific page number.
  void _goToPage(int page) {
    final p = page.clamp(1, _pageCount);
    setState(() {
      _page = p;
      _pageController.text = p.toString();
    });

    _pdfController.goToPage(pageNumber: p);
  }

  void _prev() => _goToPage(_page - 1);
  void _next() => _goToPage(_page + 1);
  void _start() => _goToPage(1);

  /// Opens an interactive dialog for manual page number entry.
  Future<void> _openGoToPageDialog() async {
    final controller = TextEditingController(text: _page.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Go to page'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Page number',
              hintText: 'e.g. 12',
              prefixIcon: Icon(Icons.find_in_page),
            ),
            onSubmitted: (_) {
              final n = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(n);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final n = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(n);
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Go'),
            ),
          ],
        );
      },
    );

    if (result != null) _goToPage(result);
  }

  // ---------- PDF KEYWORD SEARCH ----------

  /// Opens the search overlay dialog.
  Future<void> _openSearchDialog() async {
    if (_doc == null) {
      _snack('PDF not ready yet.');
      return;
    }

    final queryController = TextEditingController(text: _lastQuery ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Search in PDF'),
          content: TextField(
            controller: queryController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Keyword',
              hintText: 'Type a word or phrase...',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) async {
              Navigator.of(context).pop();
              final q = queryController.text.trim();
              if (q.isNotEmpty) {
                await _searchAndShowResults(q);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                final q = queryController.text.trim();
                if (q.isNotEmpty) {
                  await _searchAndShowResults(q);
                }
              },
              icon: const Icon(Icons.manage_search),
              label: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  /// Retrieves and caches text content for a specific page.
  Future<String?> _getPageText(int pageNumber) async {
    final cached = _pageTextCache[pageNumber];
    if (cached != null) return cached;

    final doc = _doc;
    if (doc == null) return null;
    if (pageNumber < 1 || pageNumber > doc.pages.length) return null;

    final page = doc.pages[pageNumber - 1];
    final raw = await page.loadText();
    final text = raw?.fullText;
    if (text != null) {
      _pageTextCache[pageNumber] = text;
    }
    return text;
  }

  /// Scans the PDF for matches and displays result snippets in a list.
  Future<void> _searchAndShowResults(String query) async {
    final doc = _doc;
    if (doc == null) return;

    setState(() {
      _searching = true;
      _lastQuery = query;
    });

    try {
      final qLower = query.toLowerCase();
      final results = <_SearchHit>[];
      int pagesWithText = 0;

      // Limit results to maintain responsiveness.
      const int maxHits = 60;

      for (int p = 1; p <= _pageCount; p++) {
        final text = await _getPageText(p);
        if (text == null) continue;

        final t = text.trim();
        if (t.isEmpty) continue;

        pagesWithText++;

        final lower = t.toLowerCase();
        int idx = 0;

        // Extract occurrences with surrounding context snippets.
        while (true) {
          final found = lower.indexOf(qLower, idx);
          if (found < 0) break;

          final start = (found - 45).clamp(0, t.length);
          final end = (found + qLower.length + 45).clamp(0, t.length);
          final snippet = t.substring(start, end).replaceAll('\n', ' ');

          results.add(_SearchHit(page: p, snippet: snippet, matchIndex: found));

          if (results.length >= maxHits) break;
          idx = found + qLower.length;
        }

        if (results.length >= maxHits) break;
      }

      if (!mounted) return;

      setState(() => _searching = false);

      if (pagesWithText == 0) {
        _snack('No searchable text found in this PDF.');
        return;
      }

      if (results.isEmpty) {
        _snack('No results for "$query".');
        return;
      }

      // Display results list to the user.
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Results for "$query"'),
            content: SizedBox(
              width: 520,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (context, i) {
                  final r = results[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      child: Text(
                        '${r.page}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    title: Text('Page ${r.page}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      r.snippet,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _goToPage(r.page);
                    },
                  );
                },
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      _snack('Search failed: $e');
    }
  }

  // Keyboard shortcut handlers.
  void _handleCtrlF() => _openSearchDialog();
  void _handleCtrlG() {
    _pageFocus.requestFocus();
    _pageController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _pageController.text.length,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Register custom keyboard shortcuts.
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): const _CtrlFIntent(),
      const SingleActivator(LogicalKeyboardKey.keyG, control: true): const _CtrlGIntent(),
    };

    final actions = <Type, Action<Intent>>{
      _CtrlFIntent: CallbackAction<_CtrlFIntent>(onInvoke: (_) {
        _handleCtrlF();
        return null;
      }),
      _CtrlGIntent: CallbackAction<_CtrlGIntent>(onInvoke: (_) {
        _handleCtrlG();
        return null;
      }),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: const TopAppBar(
              title: 'Resource Hub',
              showThemeToggle: true,
              showLogout: true,
            ),
            bottomNavigationBar: BottomNavBar(
              currentIndex: 1,
              onTabSelected: _onTabSelected,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_rounded),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.menu_book_rounded),
                  label: 'Resources',
                ),
              ],
              showFooter: false,
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isPhone = constraints.maxWidth < 650;

                  if (_openingDoc) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_openError != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Could not open PDF:',
                              style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(_openError!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _openDocument,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.all(isPhone ? 12 : 16),
                    child: Column(
                      children: [
                        _headerCard(theme, isPhone),
                        const SizedBox(height: 12),
                        _controlsCard(theme, isPhone),
                        const SizedBox(height: 12),

                        // Main PDF Rendering Card
                        Expanded(
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            elevation: 2,
                            child: Stack(
                              children: [
                                PdfViewer.asset(
                                  _pdfAssetPath,
                                  controller: _pdfController,
                                ),
                                // Searching Indicator
                                if (_searching)
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.10),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          SizedBox(width: 10),
                                          Text('Searching...'),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the top card displaying document info.
  Widget _headerCard(ThemeData theme, bool isPhone) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isPhone ? 12 : 16),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: isPhone ? 28 : 34,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resource Hub',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'DECODE Competition Manual (TU18)',
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.first_page_rounded),
              label: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }

  /// Card containing buttons and input for PDF navigation and searching.
  Widget _controlsCard(ThemeData theme, bool isPhone) {
    final rowGap = isPhone ? 8.0 : 12.0;

    final goButton = FilledButton(
      onPressed: () {
        final n = int.tryParse(_pageController.text.trim());
        if (n != null) {
          _goToPage(n);
        } else {
          _snack('Please enter a valid page number.');
        }
      },
      child: const Text('Go'),
    );

    final prevButton = OutlinedButton.icon(
      onPressed: _prev,
      icon: const Icon(Icons.chevron_left),
      label: const Text('Prev'),
    );

    final nextButton = OutlinedButton.icon(
      onPressed: _next,
      icon: const Icon(Icons.chevron_right),
      label: const Text('Next'),
    );

    final searchButton = OutlinedButton.icon(
      onPressed: _openSearchDialog,
      icon: const Icon(Icons.search),
      label: Text(isPhone ? 'Search' : 'Search (Ctrl+F)'),
    );

    final goDialogButton = OutlinedButton.icon(
      onPressed: _openGoToPageDialog,
      icon: const Icon(Icons.find_in_page),
      label: Text(isPhone ? 'Page' : 'Go (Ctrl+G)'),
    );

    final pageChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Page: $_page / $_pageCount',
        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isPhone ? 12 : 14),
        child: isPhone
            ? Column(
          children: [
            Row(
              children: [
                Expanded(child: searchButton),
                const SizedBox(width: 10),
                Expanded(child: goDialogButton),
              ],
            ),
            SizedBox(height: rowGap),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pageController,
                    focusNode: _pageFocus,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Go to page',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    onSubmitted: (_) => goButton.onPressed?.call(),
                  ),
                ),
                const SizedBox(width: 10),
                goButton,
              ],
            ),
            SizedBox(height: rowGap),
            Row(
              children: [
                Expanded(child: prevButton),
                const SizedBox(width: 10),
                Expanded(child: nextButton),
              ],
            ),
            SizedBox(height: rowGap),
            Row(
              children: [
                Expanded(child: pageChip),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _pageTextCache.clear());
                      _snack('Search cache cleared.');
                    },
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        )
            : Row(
          children: [
            searchButton,
            const SizedBox(width: 10),
            goDialogButton,
            const SizedBox(width: 12),
            Text(
              'Go to page:',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _pageController,
                focusNode: _pageFocus,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixText: '#  ',
                ),
                onSubmitted: (_) => goButton.onPressed?.call(),
              ),
            ),
            const SizedBox(width: 10),
            goButton,
            const SizedBox(width: 12),
            prevButton,
            const SizedBox(width: 10),
            nextButton,
            const Spacer(),
            pageChip,
          ],
        ),
      ),
    );
  }
}

/// Representation of a single search result occurrence.
class _SearchHit {
  final int page;
  final String snippet;
  final int matchIndex;

  const _SearchHit({
    required this.page,
    required this.snippet,
    required this.matchIndex,
  });
}

// ----- Keyboard Shortcut Intents -----

class _CtrlFIntent extends Intent {
  const _CtrlFIntent();
}

class _CtrlGIntent extends Intent {
  const _CtrlGIntent();
}
