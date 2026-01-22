import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Default application colors.
const Color kPrimaryColor = Color(0xFF1976D2);
const Color kBackgroundColor = Color(0xFFF5F5F5);

/// Converts a hex string (e.g., "#RRGGBB" or "#AARRGGBB") to a Flutter [Color].
Color colorFromHex(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) {
    h = 'FF$h'; // Add full opacity if missing.
  }
  if (h.length != 8) return fallback;
  try {
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Converts a Flutter [Color] to an ARGB hex string (e.g., "#FF0000FF").
String colorToHex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0')}';

/// Model representing customizable theme settings for the application.
class AppThemeSettings {
  final Color headerLight;
  final Color headerDark;
  final Color textLight;
  final Color textDark;
  final Color headerTitleLight;
  final Color headerTitleDark;

  const AppThemeSettings({
    required this.headerLight,
    required this.headerDark,
    required this.textLight,
    required this.textDark,
    required this.headerTitleLight,
    required this.headerTitleDark,
  });

  /// Returns the default theme settings.
  factory AppThemeSettings.defaults() {
    return const AppThemeSettings(
      headerLight: kPrimaryColor,
      headerDark: Color(0xFF0D47A1),
      textLight: Colors.black,
      textDark: Colors.white,
      headerTitleLight: Colors.white,
      headerTitleDark: Colors.white,
    );
  }

  /// Maps a Firestore map to an [AppThemeSettings] instance.
  factory AppThemeSettings.fromMap(Map<String, dynamic> map) {
    return AppThemeSettings(
      headerLight: colorFromHex(map['headerLight'] as String?, kPrimaryColor),
      headerDark: colorFromHex(map['headerDark'] as String?, const Color(0xFF0D47A1)),
      textLight: colorFromHex(map['textLight'] as String?, Colors.black),
      textDark: colorFromHex(map['textDark'] as String?, Colors.white),
      headerTitleLight: colorFromHex(map['headerTitleLight'] as String?, Colors.white),
      headerTitleDark: colorFromHex(map['headerTitleDark'] as String?, Colors.white),
    );
  }

  /// Converts the current settings to a map for Firestore storage.
  Map<String, dynamic> toMap() => {
    'headerLight': colorToHex(headerLight),
    'headerDark': colorToHex(headerDark),
    'textLight': colorToHex(textLight),
    'textDark': colorToHex(textDark),
    'headerTitleLight': colorToHex(headerTitleLight),
    'headerTitleDark': colorToHex(headerTitleDark),
  };

  /// Creates a copy of the settings with optional updated fields.
  AppThemeSettings copyWith({
    Color? headerLight,
    Color? headerDark,
    Color? textLight,
    Color? textDark,
    Color? headerTitleLight,
    Color? headerTitleDark,
  }) {
    return AppThemeSettings(
      headerLight: headerLight ?? this.headerLight,
      headerDark: headerDark ?? this.headerDark,
      textLight: textLight ?? this.textLight,
      textDark: textDark ?? this.textDark,
      headerTitleLight: headerTitleLight ?? this.headerTitleLight,
      headerTitleDark: headerTitleDark ?? this.headerTitleDark,
    );
  }
}

/// Service that manages the application's theme, loading preferences from Firestore.
class ThemeService extends ChangeNotifier {
  AppThemeSettings _settings = AppThemeSettings.defaults();
  ThemeMode _themeMode = ThemeMode.system;

  bool _isLoading = false;
  String? _lastError;

  ThemeService();

  AppThemeSettings get settings => _settings;
  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  ThemeData get lightTheme => _buildLightTheme(_settings);
  ThemeData get darkTheme => _buildDarkTheme(_settings);

  /// Updates the global theme mode (system/light/dark).
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  /// Manually applies new theme settings and notifies listeners.
  void applySettings(AppThemeSettings newSettings) {
    _settings = newSettings;
    _lastError = null;
    notifyListeners();
  }

  /// Fetches saved theme settings from the user's Firestore document.
  Future<void> loadFromFirestore() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final setup = data?['setupData'] as Map<String, dynamic>?;
        final themeMap = setup?['themeSettings'] as Map<String, dynamic>?;

        if (themeMap != null) {
          _settings = AppThemeSettings.fromMap(themeMap);
        } else {
          _settings = AppThemeSettings.defaults();
        }
      } else {
        _settings = AppThemeSettings.defaults();
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Builds the light theme based on current settings.
  ThemeData _buildLightTheme(AppThemeSettings s) {
    final ThemeData base = ThemeData.light();

    return base.copyWith(
      primaryColor: s.headerLight,
      scaffoldBackgroundColor: kBackgroundColor,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: s.headerLight,
        foregroundColor: s.headerTitleLight,
        centerTitle: true,
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: s.headerLight,
        onPrimary: s.headerTitleLight,
        secondary: s.headerLight,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: s.textLight,
        displayColor: s.textLight,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: TextStyle(color: s.textLight.withOpacity(0.8)),
        hintStyle: TextStyle(color: s.textLight.withOpacity(0.6)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: s.headerLight.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: s.headerLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
        backgroundColor: Colors.white,
        selectedItemColor: s.headerLight,
        unselectedItemColor: Colors.grey.shade600,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.headerLight,
          foregroundColor: s.headerTitleLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }

  /// Builds the dark theme based on current settings.
  ThemeData _buildDarkTheme(AppThemeSettings s) {
    final ThemeData base = ThemeData.dark();
    const Color scaffoldBg = Color(0xFF121212);
    const Color surfaceDark = Color(0xFF1E1E1E);

    return base.copyWith(
      primaryColor: s.headerDark,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: s.headerDark,
        foregroundColor: s.headerTitleDark,
        centerTitle: true,
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: s.headerDark,
        onPrimary: s.headerTitleDark,
        secondary: s.headerDark,
        background: scaffoldBg,
        surface: surfaceDark,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: s.textDark,
        displayColor: s.textDark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        labelStyle: TextStyle(color: s.textDark.withOpacity(0.8)),
        hintStyle: TextStyle(color: s.textDark.withOpacity(0.5)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: s.headerDark.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: s.headerDark, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
        backgroundColor: surfaceDark,
        selectedItemColor: s.headerDark,
        unselectedItemColor: Colors.grey.shade400,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.headerDark,
          foregroundColor: s.headerTitleDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        color: surfaceDark,
      ),
    );
  }
}
