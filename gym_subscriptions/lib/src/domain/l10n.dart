// Translation: the Hebrew text is the key; Arabic and English come from
// [strings]. Text not in the table falls back to Hebrew.

import 'l10n_strings.dart';

enum AppLang { he, ar, en }

extension AppLangInfo on AppLang {
  String get code => name;
  String get nativeName => switch (this) {
        AppLang.he => 'עברית',
        AppLang.ar => 'العربية',
        AppLang.en => 'English',
      };
  bool get rtl => this != AppLang.en;
}

class L10n {
  static AppLang lang = AppLang.he;
}

/// Translates [he] to the current language. `{0}`, `{1}`… are replaced by [args].
String t(String he, [List<Object?> args = const []]) {
  var s = he;
  if (L10n.lang != AppLang.he) {
    final row = strings[he];
    if (row != null) s = L10n.lang == AppLang.ar ? row.$1 : row.$2;
  }
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Re-translates a whole string that was produced by [t] in any language
/// (a seeded name, say) into the current language. Unknown text is returned as is.
String retranslate(String any) {
  if (strings.containsKey(any)) return t(any);
  for (final e in strings.entries) {
    if (e.value.$1 == any || e.value.$2 == any) return t(e.key);
  }
  return any;
}

/// Shows [s] in its own direction inside text of the other direction: an English
/// "Salams Ltd." in Hebrew text keeps its period at the end (Unicode FSI ... PDI).
String isolate(String s) => s.isEmpty ? s : '\u2068$s\u2069';
