// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color primaryGreen = Color(0xFF00A884);
  static const Color darkGreen = Color(0xFF008069);
  static const Color lightGreen = Color(0xFF25D366);
  static const Color accentTeal = Color(0xFF00BCD4);

  // Dark theme backgrounds
  static const Color bgPrimary = Color(0xFF111B21);
  static const Color bgSecondary = Color(0xFF1C2B33);
  static const Color bgCard = Color(0xFF202C33);
  static const Color bgElevated = Color(0xFF2A3942);

  // Text colors
  static const Color textPrimary = Color(0xFFE9EDEF);
  static const Color textSecondary = Color(0xFF8696A0);
  static const Color textTertiary = Color(0xFF566B78);

  // Status colors
  static const Color onlineColor = Color(0xFF25D366);
  static const Color offlineColor = Color(0xFF8696A0);
  static const Color awayColor = Color(0xFFFFD700);

  // Divider
  static const Color dividerColor = Color(0xFF2A3942);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: lightGreen,
        surface: bgCard,
        background: bgPrimary,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onBackground: textPrimary,
      ),
      textTheme: GoogleFonts.nunitoTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          displaySmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          headlineSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
          titleSmall: TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: textPrimary),
          bodyMedium: TextStyle(color: textSecondary),
          bodySmall: TextStyle(color: textTertiary),
          labelLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgSecondary,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(color: textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgSecondary,
        selectedItemColor: primaryGreen,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      dividerTheme: const DividerThemeData(color: dividerColor, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgElevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGreen, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return primaryGreen;
          return textSecondary;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return primaryGreen.withOpacity(0.4);
          return bgElevated;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryGreen),
      chipTheme: ChipThemeData(
        backgroundColor: bgElevated,
        labelStyle: const TextStyle(color: textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
