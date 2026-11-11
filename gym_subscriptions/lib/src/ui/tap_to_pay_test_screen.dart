// Settings > Tap to Pay: checks the Dejavoo Tap to Pay SDK on this phone before it is
// used for real payments: which SDK build is in the app, registering the device, and a
// small test sale. Every attempt's report can be copied (for Dejavoo / support).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/l10n.dart';
import '../integration/tap_to_pay_service.dart';
import 'theme.dart';
import 'widgets.dart';

class TapToPayTestScreen extends StatefulWidget {
  const TapToPayTestScreen({super.key});

  @override
  State<TapToPayTestScreen> createState() => _TapToPayTestScreenState();
}

class _TapToPayTestScreenState extends State<TapToPayTestScreen> {
  final _service = TapToPayService.instance;
  String _env = '…';
  bool _available = false;
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final env = await _service.environment();
    final available = await _service.isAvailable();
    if (mounted) {
      setState(() {
        _env = env;
        _available = available;
      });
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    var ok = false;
    String result;
    try {
      result = await action();
      ok = true;
    } on TopPaymentException catch (e) {
      result = e.isCancelled ? t('בוטל') : '${e.code}: ${e.message}';
    } catch (e) {
      result = '$e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = ok;
      _result = result;
    });
  }

  Future<String> _register() async {
    final s = await _service.registerDevice();
    return t('המכשיר נרשם · session …{0}', [s.sessionKey.length > 4 ? s.sessionKey.substring(s.sessionKey.length - 4) : s.sessionKey]);
  }

  Future<String> _sale() async {
    final r = await _service.sale(amount: 1);
    final raw = r.raw;
    final card = [raw['card_type'], raw['last_4_digits']].where((x) => x != null && '$x'.isNotEmpty).join(' ');
    return '${r.approved ? t('אושר') : t('נדחה')} · ${raw['response_code'] ?? ''} ${raw['message'] ?? ''}'
        '${card.isEmpty ? '' : ' · $card'}';
  }

  @override
  Widget build(BuildContext context) {
    final tpn = (_service.userTpn ?? '').trim();
    final reports = PaymentDiagnostics.recent;
    return Scaffold(
      appBar: AppBar(title: const Text('Tap to Pay')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        SummaryBox(rows: [
          (t('גרסת SDK'), switch (_env) {
            'sandbox' => t('בדיקות (Sandbox)'),
            'prod' => t('אמיתי (Prod)'),
            'none' => t('לא כלול באפליקציה'),
            _ => _env,
          }),
          ('TPN', tpn.isNotEmpty ? tpn : (_env == 'prod' ? t('לא הוגדר למשתמש') : t('ברירת מחדל של Sandbox'))),
        ]),
        const SizedBox(height: 10),
        if (!_available)
          Note(t('האפליקציה נבנתה בלי ה-SDK של Tap to Pay (חסרים פרטי הגישה של Dejavoo בזמן הבנייה).'), warn: true),
        if (_env == 'prod')
          Note(t('גרסה אמיתית: בדיקה תחייב את הכרטיס ב-1 ₪.'), warn: true),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('topRegister'),
          onPressed: _busy || !_available ? null : () => _run(_register),
          icon: const Icon(Icons.app_registration),
          label: Text(t('רישום המכשיר')),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('topSale'),
          style: FilledButton.styleFrom(backgroundColor: Aura.goldLight, foregroundColor: Aura.ink),
          onPressed: _busy || !_available ? null : () => _run(_sale),
          icon: const Icon(Icons.contactless),
          label: Text(t('עסקת בדיקה · 1 ₪')),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_result != null) ...[const SizedBox(height: 12), Note(_result!, warn: !_ok)],
        const SizedBox(height: 16),
        SectionLabel(t('דוחות אחרונים')),
        if (reports.isEmpty) Text(t('אין עדיין'), style: const TextStyle(color: Aura.muted)),
        for (final r in reports)
          Card(
            child: ListTile(
              title: Text('${r.operation} · ${r.outcome.name}'),
              subtitle: Text('${r.id} · ${r.code} ${r.message}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: t('העתקת הדוח'),
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.toText()));
                  showDone(context, t('הדוח {0} הועתק', [r.id]));
                },
              ),
            ),
          ),
      ]),
    );
  }
}
