import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFFE17C0F);
  static const Color primaryDark = Color(0xFF554B42);
  static const Color primarySoft = Color(0xFFFFF1E3);
  static const Color ink = Color(0xFF28231F);
  static const Color muted = Color(0xFF6D665F);
  static const Color subtle = Color(0xFF918A84);
  static const Color canvas = Color(0xFFF3F2F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDEEF1);
  static const Color border = Color(0xFFEEECE9);
  static const Color darkSurface = Color(0xFF554B42);
  static const Color success = Color(0xFF2E7D5B);
  static const Color successSoft = Color(0xFFEAF6F0);
  static const Color warning = Color(0xFFE17C0F);
  static const Color warningSoft = Color(0xFFFFF1E3);
}

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x242D2824), blurRadius: 18, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> navigation = [
    BoxShadow(color: Color(0x202D2824), blurRadius: 22, offset: Offset(0, -6)),
  ];
}

abstract final class AppSurfaces {
  static BoxDecoration card({
    Color color = AppColors.surface,
    double radius = 16,
    bool elevated = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: elevated ? AppShadows.card : null,
    );
  }

  static BoxDecoration placeholder({double radius = 14}) {
    return BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.canvas,
      fontFamily: 'Bubblegum Sans',
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        centerTitle: false,
        toolbarHeight: 72,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontFamily: 'Bubblegum Sans',
          fontSize: 21,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.subtle,
          elevation: 0,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Bubblegum Sans',
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: AppColors.subtle, fontSize: 14),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      dividerColor: AppColors.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurface,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'Bubblegum Sans',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
