import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';

/// A custom Top App Bar used across the application for consistent branding and navigation.
class TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showThemeToggle;
  final bool showLogout;
  final bool showBackButton;
  final List<Widget>? actions;

  const TopAppBar({
    super.key,
    required this.title,
    this.showThemeToggle = true,
    this.showLogout = true,
    this.showBackButton = true,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// Toggles between light and dark theme modes via ThemeService.
  void _toggleTheme(BuildContext context) {
    final themeService = context.read<ThemeService>();

    if (themeService.themeMode == ThemeMode.dark) {
      themeService.setThemeMode(ThemeMode.light);
    } else {
      themeService.setThemeMode(ThemeMode.dark);
    }
  }

  /// Navigates the user back to the login screen and clears the navigation stack.
  void _logout(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if the back button should be shown and if there is a page to go back to.
    final bool canGoBack = showBackButton && Navigator.canPop(context);

    return AppBar(
      automaticallyImplyLeading: false, // Custom leading management.
      leadingWidth: 90, // Allocates enough space for both back button and logo.
      leading: Row(
        children: [
          if (canGoBack)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),

          // Tapping the logo returns the user to the dashboard.
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
            },
            child: Padding(
              padding: EdgeInsets.only(left: canGoBack ? 0 : 12.0),
              child: Image.asset(
                'files/images/logo.png',
                fit: BoxFit.contain,
                height: 32,
              ),
            ),
          ),
        ],
      ),

      title: Text(title),
      centerTitle: true,

      actions: [
        if (actions != null) ...actions!,

        if (showThemeToggle)
          IconButton(
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => _toggleTheme(context),
          ),

        if (showLogout)
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
      ],
    );
  }
}
