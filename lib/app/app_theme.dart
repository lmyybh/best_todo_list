import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const accent = Color(0xFF157F85);
  static const darkAccent = Color(0xFF65BDC0);

  static ThemeData light() => _theme(
    brightness: Brightness.light,
    background: const Color(0xFFFCFBF8),
    surface: Colors.white,
    sidebar: const Color(0xFFF3F1EC),
    text: const Color(0xFF20201E),
    muted: const Color(0xFF696863),
    faint: const Color(0xFF98958E),
    border: const Color(0xFFDFDDD6),
    borderSoft: const Color(0xFFEBE9E3),
    surfaceHover: const Color(0xFFF8F7F3),
    accentColor: accent,
  );

  static ThemeData dark() => _theme(
    brightness: Brightness.dark,
    background: const Color(0xFF20211F),
    surface: const Color(0xFF292A27),
    sidebar: const Color(0xFF252623),
    text: const Color(0xFFF1EFE8),
    muted: const Color(0xFFB3B0A8),
    faint: const Color(0xFF85827B),
    border: const Color(0xFF3E3F3B),
    borderSoft: const Color(0xFF333430),
    surfaceHover: const Color(0xFF30312E),
    accentColor: darkAccent,
  );

  static ThemeData _theme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color sidebar,
    required Color text,
    required Color muted,
    required Color faint,
    required Color border,
    required Color borderSoft,
    required Color surfaceHover,
    required Color accentColor,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamilyFallback: const <String>['PingFang SC', 'Helvetica Neue'],
      dividerColor: border,
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: text, displayColor: text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: brightness == Brightness.light
              ? const Color(0xFF292A27)
              : const Color(0xFFF1EFE8),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: brightness == Brightness.light ? Colors.white : Colors.black,
          fontSize: 12,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        AppColors(
          sidebar: sidebar,
          muted: muted,
          faint: faint,
          border: border,
          borderSoft: borderSoft,
          surfaceHover: surfaceHover,
          accentSoft: brightness == Brightness.light
              ? const Color(0xFFDFF0EF)
              : const Color(0xFF223F3F),
          danger: brightness == Brightness.light
              ? const Color(0xFFC75B4F)
              : const Color(0xFFEF8C7D),
        ),
      ],
    );
  }
}

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.sidebar,
    required this.muted,
    required this.faint,
    required this.border,
    required this.borderSoft,
    required this.surfaceHover,
    required this.accentSoft,
    required this.danger,
  });

  final Color sidebar;
  final Color muted;
  final Color faint;
  final Color border;
  final Color borderSoft;
  final Color surfaceHover;
  final Color accentSoft;
  final Color danger;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? sidebar,
    Color? muted,
    Color? faint,
    Color? border,
    Color? borderSoft,
    Color? surfaceHover,
    Color? accentSoft,
    Color? danger,
  }) => AppColors(
    sidebar: sidebar ?? this.sidebar,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    border: border ?? this.border,
    borderSoft: borderSoft ?? this.borderSoft,
    surfaceHover: surfaceHover ?? this.surfaceHover,
    accentSoft: accentSoft ?? this.accentSoft,
    danger: danger ?? this.danger,
  );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
