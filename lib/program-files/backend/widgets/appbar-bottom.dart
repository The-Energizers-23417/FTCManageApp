import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';

/// A custom Bottom Navigation Bar that also includes a footer with credits.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.items,
    this.showFooter = true,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<BottomNavigationBarItem> items;
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeService = context.watch<ThemeService>();
    final settings = themeService.settings;

    final isDark = theme.brightness == Brightness.dark;

    // Ensure a clear background color for the bar.
    final Color barBg = theme.bottomNavigationBarTheme.backgroundColor ??
        theme.colorScheme.surface;

    final Color footerBg = isDark ? theme.scaffoldBackgroundColor : barBg;
    final Color footerText = isDark ? settings.textDark : settings.textLight;

    // If no navigation items are provided, only show the footer if enabled.
    if (items.isEmpty) {
      return showFooter
          ? SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          color: footerBg,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Using FTCScout data',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: footerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Made by: FTC team The Energizers #23417',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: footerText.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      )
          : const SizedBox.shrink();
    }

    return Material(
      color: barBg,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomNavigationBar(
              currentIndex: currentIndex,
              items: items,
              onTap: onTabSelected,

              // Enforce consistent styling from theme or defaults.
              backgroundColor: barBg,
              selectedItemColor: theme.bottomNavigationBarTheme.selectedItemColor ??
                  theme.colorScheme.primary,
              unselectedItemColor:
              theme.bottomNavigationBarTheme.unselectedItemColor ??
                  theme.colorScheme.onSurface.withValues(alpha: 0.65),
              type: BottomNavigationBarType.fixed,
              showUnselectedLabels:
              theme.bottomNavigationBarTheme.showUnselectedLabels ?? true,
            ),

            if (showFooter)
              Container(
                width: double.infinity,
                color: footerBg,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Using FTCScout data',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: footerText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Made by: FTC team The Energizers #23417',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: footerText.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
