// Domain screen -> login screen -> the gym module, like the AURA POS app.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/l10n.dart';
import '../integration/aura_api.dart';
import '../state/auth.dart';
import '../state/gym_store.dart';
import '../state/server_sync.dart';
import 'theme.dart';

/// Makes the [AuthController] available below the gate (settings uses it for
/// the account card and sign-out). Absent when the app runs without sign-in.
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({super.key, required AuthController auth, required super.child}) : super(notifier: auth);

  static AuthController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;
}

/// Makes the server sync available below the gate (settings shows its state
/// and a "sync now" button). Absent when the app runs without sign-in.
class SyncScope extends InheritedNotifier<GymSync> {
  const SyncScope({super.key, required GymSync sync, required super.child}) : super(notifier: sync);

  static GymSync? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SyncScope>()?.notifier;
}

/// Shows the domain or login screen until someone is signed in, then [child].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth, required this.store, required this.child});
  final AuthController auth;
  final GymStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final stage = auth.stage;
          final Widget page = switch (stage) {
            AuthStage.domain => DomainScreen(key: const ValueKey('domain'), auth: auth, store: store),
            AuthStage.login => LoginScreen(key: const ValueKey('login'), auth: auth, store: store),
            AuthStage.signedIn => KeyedSubtree(key: const ValueKey('app'), child: AuthScope(auth: auth, child: child)),
          };
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                  position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(a), child: c),
            ),
            child: page,
          );
        },
      );
}

/// Translated message for a failed call.
String authErrorText(Object error, {AuraWorkspace? workspace, String? domain, String? company}) {
  if (error is! AuraApiException) return t('משהו השתבש. נסו שוב.');
  final d = workspace?.domain ?? domain ?? '';
  final c = workspace?.company ?? company ?? '';
  return switch (error.kind) {
    AuraErrorKind.noVerifyKey => t('בגרסה הזו חסר מפתח האימות (AURA_VERIFY_KEY). פנו לצוות AURA.'),
    AuraErrorKind.companyNotFound => t('לא נמצא עסק בשם "{0}" ב-{1}', [c, d]),
    AuraErrorKind.badCredentials => t('שם משתמש או סיסמה שגויים'),
    AuraErrorKind.unreachable => t('אין חיבור ל-{0}. בדקו את האינטרנט ואת שם הדומיין.', [d]),
    AuraErrorKind.timeout => t('השרת לא ענה בזמן. נסו שוב.'),
    AuraErrorKind.server => t('שגיאת שרת ({0})', [error.detail]),
    AuraErrorKind.sessionExpired => t('החיבור פג. התחברו שוב.'),
    AuraErrorKind.forbidden => t('אין לכם הרשאה ({0})', [error.detail]),
  };
}

// ─── Domain screen ──────────────────────────────────────────────────────────

class DomainScreen extends StatefulWidget {
  const DomainScreen({super.key, required this.auth, required this.store});
  final AuthController auth;
  final GymStore store;

  @override
  State<DomainScreen> createState() => _DomainScreenState();
}

class _DomainScreenState extends State<DomainScreen> {
  final _form = GlobalKey<FormState>();
  final _domain = TextEditingController(text: AuraConfig.defaultDomain);
  final _company = TextEditingController(text: AuraConfig.defaultCompany);
  final _companyFocus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _domain.dispose();
    _company.dispose();
    _companyFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await widget.auth.connect(domain: _domain.text, company: _company.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorText(e,
          domain: AuraConfig.normalizeDomain(_domain.text), company: AuraConfig.normalizeCompany(_company.text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      store: widget.store,
      step: 0,
      title: t('חיבור לעסק'),
      subtitle: t('הזינו את הדומיין ואת שם החברה שקיבלתם מ-AURA'),
      error: _error,
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AuthField(
            key: const Key('authDomain'),
            controller: _domain,
            label: t('דומיין'),
            icon: Icons.language_rounded,
            keyboardType: TextInputType.url,
            helperText: AuraConfig.normalizeDomain(_domain.text).isEmpty
                ? null
                : t('כתובת השרת: {0}', [AuraConfig.normalizeDomain(_domain.text)]),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _companyFocus.requestFocus(),
            validator: (v) => _required(v) ?? _noAt(v),
          ),
          const SizedBox(height: 14),
          AuthField(
            key: const Key('authCompany'),
            controller: _company,
            focusNode: _companyFocus,
            label: t('שם החברה'),
            icon: Icons.storefront_outlined,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) => _required(v) ?? _noAt(v),
          ),
          const SizedBox(height: 24),
          AuthButton(
            key: const Key('authContinue'),
            label: t('המשך'),
            loading: widget.auth.busy,
            onPressed: _submit,
          ),
        ]),
      ),
    );
  }
}

// ─── Login screen ───────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.store});
  final AuthController auth;
  final GymStore store;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await widget.auth.signIn(name: _name.text, password: _password.text);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorText(e, workspace: widget.auth.workspace));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.auth.workspace;
    return AuthLayout(
      store: widget.store,
      step: 1,
      title: t('ברוכים הבאים'),
      subtitle: t('התחברו עם שם המשתמש והסיסמה של AURA'),
      error: _error ?? (widget.auth.sessionExpired ? t('החיבור פג. התחברו שוב.') : null),
      header: ws == null
          ? null
          : _WorkspaceChip(
              workspace: ws,
              onChange: widget.auth.busy ? null : widget.auth.changeWorkspace,
            ),
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AuthField(
              key: const Key('authUser'),
              controller: _name,
              label: t('שם משתמש'),
              icon: Icons.person_outline_rounded,
              autofillHints: const [AutofillHints.username],
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              validator: (v) => _required(v) ?? _noAt(v),
            ),
            const SizedBox(height: 14),
            AuthField(
              key: const Key('authPassword'),
              controller: _password,
              focusNode: _passwordFocus,
              label: t('סיסמה'),
              icon: Icons.lock_outline_rounded,
              obscureText: _hidden,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              validator: (v) => (v == null || v.isEmpty) ? t('שדה חובה') : null,
              suffix: IconButton(
                tooltip: _hidden ? t('הצגת הסיסמה') : t('הסתרת הסיסמה'),
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 20, color: Aura.muted),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            const SizedBox(height: 24),
            AuthButton(
              key: const Key('authSignIn'),
              label: t('כניסה'),
              loading: widget.auth.busy,
              onPressed: _submit,
            ),
          ]),
        ),
      ),
    );
  }
}

String? _required(String? v) => (v == null || v.trim().isEmpty) ? t('שדה חובה') : null;

/// The POS signs in with the username and the company id, never an email.
String? _noAt(String? v) => (v != null && v.contains('@')) ? t('בלי @ – שם בלבד, לא אימייל') : null;

class _WorkspaceChip extends StatelessWidget {
  const _WorkspaceChip({required this.workspace, required this.onChange});
  final AuraWorkspace workspace;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: Aura.goldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Aura.gold.withValues(alpha: .25)),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.storefront_outlined, size: 18, color: Aura.gold),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(workspace.company,
                key: const Key('authWorkspace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            Text(workspace.domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 12, color: Aura.muted)),
          ]),
        ),
        TextButton(
          key: const Key('authChangeWorkspace'),
          onPressed: onChange,
          style: TextButton.styleFrom(foregroundColor: Aura.gold),
          child: Text(t('שינוי'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Shared layout ──────────────────────────────────────────────────────────

/// Dark branded background, brand mark, and a white card with the form.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.store,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
    this.header,
    this.error,
  });

  final GymStore store;

  /// 0 = business, 1 = sign in.
  final int step;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? header;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Aura.ink,
        body: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _BackdropPainter())),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - 32)),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        // Room for the language switch pinned at the top.
                        SizedBox(height: box.maxHeight > 700 ? 64 : 48),
                        const _Brand(),
                        SizedBox(height: box.maxHeight > 700 ? 36 : 24),
                        _card(),
                        const SizedBox(height: 22),
                        Text('Powered by AURA Tech',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                                fontSize: 12, letterSpacing: .4, color: Colors.white.withValues(alpha: .38))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: _LanguageSwitch(store: store)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .28), blurRadius: 40, offset: const Offset(0, 18)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Steps(step: step),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.15)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 14, color: Aura.muted, height: 1.35)),
          if (header != null) ...[const SizedBox(height: 18), header!],
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: error == null
                ? const SizedBox(width: double.infinity, height: 22)
                : Padding(padding: const EdgeInsets.only(top: 18, bottom: 18), child: _ErrorBanner(error!)),
          ),
          child,
        ]),
      );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Aura.goldLight, Aura.gold],
          ),
          boxShadow: [BoxShadow(color: Aura.gold.withValues(alpha: .45), blurRadius: 28, offset: const Offset(0, 10))],
        ),
        child: const Icon(Icons.fitness_center_rounded, size: 38, color: Aura.ink),
      ),
      const SizedBox(height: 18),
      // The brand name reads left to right in every language.
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('AURA',
              style: TextStyle(
                  fontFamily: 'Rubik', fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 6, color: Colors.white)),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('GYM',
                style: TextStyle(
                    fontFamily: 'Rubik',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 7,
                    color: Aura.goldLight.withValues(alpha: .95))),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Text(t('מנויים, תשלומים וגבייה – במקום אחד'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: .62))),
    ]);
  }
}

/// "Business · Sign in" progress.
class _Steps extends StatelessWidget {
  const _Steps({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, String label) {
      final done = i < step, current = i == step;
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 4,
            decoration: BoxDecoration(
              color: done || current ? Aura.gold : Aura.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.circle,
                size: done ? 15 : 7, color: done || current ? Aura.gold : Aura.line),
            SizedBox(width: done ? 5 : 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                      color: current ? Aura.ink : Aura.muted)),
            ),
          ]),
        ]),
      );
    }

    return Row(children: [item(0, t('העסק')), const SizedBox(width: 10), item(1, t('התחברות'))]);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('authError'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Aura.warnBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Aura.warn.withValues(alpha: .18)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, size: 20, color: Aura.warn),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13.5, color: Aura.warn, height: 1.35))),
        ]),
      );
}

class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({required this.store});
  final GymStore store;

  static const _short = {AppLang.he: 'עב', AppLang.ar: 'ع', AppLang.en: 'EN'};

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final l in AppLang.values)
          Semantics(
            button: true,
            selected: store.language == l,
            label: l.nativeName,
            child: GestureDetector(
              key: Key('authLang-${l.code}'),
              onTap: () => store.setLanguage(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                // Fixed height: with `alignment` set, the chip would otherwise
                // grow to the whole screen and block taps below it.
                height: 32,
                constraints: const BoxConstraints(minWidth: 40),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: store.language == l ? Aura.goldLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(_short[l]!,
                    style: TextStyle(
                      fontFamily: 'Rubik',
                      fontFamilyFallback: const ['Cairo'],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: store.language == l ? Aura.ink : Colors.white.withValues(alpha: .75),
                    )),
              ),
            ),
          ),
      ]),
    );
  }
}

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: !obscureText && keyboardType != TextInputType.url,
      // Usernames, domains and passwords are typed left to right.
      textDirection: TextDirection.ltr,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Aura.muted),
        floatingLabelStyle: const TextStyle(color: Aura.gold, fontWeight: FontWeight.w600),
        prefixIcon: Icon(icon, size: 21),
        prefixIconColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.focused) ? Aura.gold : Aura.muted),
        suffixIcon: suffix,
        helperText: helperText,
        helperStyle: const TextStyle(color: Aura.muted, fontSize: 12.5),
        filled: true,
        fillColor: Aura.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        focusedBorder: border(Aura.gold, 1.6),
        errorBorder: border(Aura.warn.withValues(alpha: .6)),
        focusedErrorBorder: border(Aura.warn, 1.6),
      ),
    );
  }
}

class AuthButton extends StatelessWidget {
  const AuthButton({super.key, required this.label, required this.loading, required this.onPressed});
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: Aura.ink,
        disabledBackgroundColor: Aura.ink.withValues(alpha: .85),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: loading
            ? const SizedBox(
                key: ValueKey('spin'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Aura.goldLight),
              )
            : Row(key: const ValueKey('label'), mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: const TextStyle(color: Colors.white)),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_rounded, size: 20, color: Aura.goldLight),
              ]),
      ),
    );
  }
}

/// Soft gold glow, a large ring and fine diagonal lines on the dark background.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16253A), Aura.ink, Color(0xFF0B121C)],
          stops: [0, .55, 1],
        ).createShader(rect),
    );

    final glowCenter = Offset(size.width * .85, size.height * .08);
    canvas.drawCircle(
      glowCenter,
      size.shortestSide * .9,
      Paint()
        ..shader = RadialGradient(colors: [
          Aura.goldLight.withValues(alpha: .20),
          Aura.goldLight.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: glowCenter, radius: size.shortestSide * .9)),
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Aura.goldLight.withValues(alpha: .10);
    final ringCenter = Offset(size.width * .05, size.height * .2);
    canvas.drawCircle(ringCenter, size.shortestSide * .42, ring);
    canvas.drawCircle(ringCenter, size.shortestSide * .30, ring..color = Colors.white.withValues(alpha: .05));

    final line = Paint()
      ..color = Colors.white.withValues(alpha: .028)
      ..strokeWidth = 1;
    const gap = 26.0;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
