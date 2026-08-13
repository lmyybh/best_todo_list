import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const accent = Color(0xFF26777A);

  static ThemeData light() {
    const background = Color(0xFFF7F6F2);
    const surface = Colors.white;
    const text = Color(0xFF242522);
    const muted = Color(0xFF62655F);
    const border = Color(0xFFDADBD4);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamilyFallback: const <String>['PingFang SC', 'Helvetica Neue'],
      dividerColor: border,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: const Color(0xFF292A27),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        AppColors(
          sidebar: Color(0xFFEFEEE9),
          muted: muted,
          faint: Color(0xFF858981),
          border: border,
          borderSoft: Color(0xFFE8E8E2),
          surfaceHover: Color(0xFFFAF9F6),
          accentSoft: Color(0xFFE0EFED),
          completion: Color(0xFF4F7D68),
          danger: Color(0xFFC45D4E),
          dangerSoft: Color(0xFFF8E9E4),
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
    required this.completion,
    required this.danger,
    required this.dangerSoft,
  });

  final Color sidebar;
  final Color muted;
  final Color faint;
  final Color border;
  final Color borderSoft;
  final Color surfaceHover;
  final Color accentSoft;
  final Color completion;
  final Color danger;
  final Color dangerSoft;

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
    Color? completion,
    Color? danger,
    Color? dangerSoft,
  }) => AppColors(
    sidebar: sidebar ?? this.sidebar,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    border: border ?? this.border,
    borderSoft: borderSoft ?? this.borderSoft,
    surfaceHover: surfaceHover ?? this.surfaceHover,
    accentSoft: accentSoft ?? this.accentSoft,
    completion: completion ?? this.completion,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
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
      completion: Color.lerp(completion, other.completion, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
    );
  }
}
