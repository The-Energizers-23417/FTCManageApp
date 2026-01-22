import 'package:flutter/material.dart';

/// DashboardTile is a custom widget used on the home screen to navigate to different app modules.
/// It features hover effects, custom icons, and a 'Coming Soon' overlay for pending features.
class DashboardTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool comingSoon;

  const DashboardTile({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.comingSoon = false,
  });

  @override
  State<DashboardTile> createState() => _DashboardTileState();
}

class _DashboardTileState extends State<DashboardTile> {
  // Track hover state for visual feedback on desktop/web.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool enabled = !widget.comingSoon && widget.onTap != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: AnimatedPhysicalModel(
          duration: const Duration(milliseconds: 150),
          // Increase elevation when hovered to create a "lift" effect.
          elevation: _hovered && enabled ? 12 : 6,
          color: theme.colorScheme.surface,
          shadowColor: Colors.black.withAlpha(77),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          shape: BoxShape.rectangle,
          child: Opacity(
            // Fade out disabled or pending tiles.
            opacity: enabled ? 1.0 : 0.5,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.dividerColor.withAlpha(enabled ? 255 : 100),
                    ),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, size: 40),
                          const SizedBox(height: 10),
                          Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Indicator for features not yet available.
                if (widget.comingSoon)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'SOON',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
