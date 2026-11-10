import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../domain/settings.dart';
import 'checkout/checkout_screens.dart' show methodIcon;
import 'theme.dart';
import 'widgets.dart';

/// Business configuration. Every rule the counter, the link and the monthly
/// collection follow is set here.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    void set(VoidCallback f) {
      f();
      store.touch();
    }

    Widget group(String title, String hint, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionLabel(title),
            if (hint.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(hint, style: const TextStyle(fontSize: 12.5, color: Aura.muted))),
            Panel(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: Column(children: children)),
          ]),
        );

    Widget sw(String title, bool v, ValueChanged<bool> f, {String? sub, Key? key}) => SwitchListTile(
          key: key,
          title: Text(title),
          subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12.5)),
          value: v,
          onChanged: (x) => set(() => f(x)),
        );

    Widget stepper(String title, int v, ValueChanged<int> f,
            {int min = 0, int max = 99, String unit = '', int step = 1, String? sub}) =>
        ListTile(
          title: Text(title),
          subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12.5)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                onPressed: v - step >= min ? () => set(() => f(v - step)) : null,
                icon: const Icon(Icons.remove_circle_outline)),
            SizedBox(
                width: 56,
                child:
                    Text('$v$unit', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(
                onPressed: v + step <= max ? () => set(() => f(v + step)) : null,
                icon: const Icon(Icons.add_circle_outline)),
          ]),
        );

    Widget chips<T>(
            String title, List<T> values, bool Function(T) isOn, void Function(T) toggle, String Function(T) label) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in values)
                FilterChip(
                  label: Text(label(v)),
                  selected: isOn(v),
                  selectedColor: Aura.goldBg,
                  showCheckmark: true,
                  onSelected: (_) => set(() => toggle(v)),
                ),
            ]),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('הגדרות העסק')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        group('העסק', '', [
          ListTile(
            title: const Text('שם העסק'),
            subtitle: Text(s.businessName),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, 'שם העסק', s.businessName);
              if (v != null && v.trim().isNotEmpty) set(() => s.businessName = v.trim());
            },
          ),
          const ListTile(
              title: Text('סוג עסק'), subtitle: Text('חדר כושר / סטודיו'), trailing: Pill('Gym', tone: PillTone.info)),
          chips<DocType>(
              'מסמך שמופק בכל תשלום', DocType.values, (d) => s.docType == d, (d) => s.docType = d, (d) => d.label),
          stepper('מע״מ', s.vatPct.round(), (v) => s.vatPct = v.toDouble(), max: 30, unit: '%'),
        ]),
        group('אמצעי תשלום', 'מה הקבלה יכולה לקבל. אפשר להגביל גם ברמת כל מסלול.', [
          chips<PayMethod>(
              'אמצעים פעילים',
              PayMethod.values,
              (m) => s.enabledMethods.contains(m),
              (m) => s.enabledMethods.contains(m) ? s.enabledMethods.remove(m) : s.enabledMethods.add(m),
              (m) => m.label),
          stepper('מקסימום תשלומים באשראי', s.maxInstallments, (v) => s.maxInstallments = v, min: 1, max: 36),
          stepper('מקסימום שיקים', s.maxCheques, (v) => s.maxCheques = v, min: 1, max: 24),
        ]),
        group('מנוי חודשי מתחדש', 'איך גובים את החודשים שאחרי התשלום הראשון.', [
          sw('הוראת קבע בבנק', s.allowStandingOrder, (v) => s.allowStandingOrder = v,
              sub: 'חיוב חשבון בנק עם טופס הרשאה'),
          sw('גבייה ידנית כל חודש', s.allowManualMonthly, (v) => s.allowManualMonthly = v,
              key: const Key('allowManual'),
              sub: 'ללקוחות שמשלמים במזומן, בשיק או בהעברה. התשלום מופיע ב"לגבייה" כל חודש, עם תזכורות ומעקב חוב.'),
          chips<ChargeDay>(
              'יום החיוב החודשי', ChargeDay.values, (d) => s.chargeDay == d, (d) => s.chargeDay = d, (d) => d.label),
          stepper('תזכורת לפני גבייה ידנית', s.manualReminderDaysBefore, (v) => s.manualReminderDaysBefore = v,
              max: 14, unit: ' ימים'),
        ]),
        group('חיוב שנכשל וחובות', 'מה קורה כשכרטיס נדחה או שתשלום ידני לא הגיע.', [
          stepper('ניסיונות חיוב חוזרים', s.retryAttempts, (v) => s.retryAttempts = v,
              max: 8, sub: 'מרווחים: ${s.retryDays.take(s.retryAttempts).map((d) => 'יום $d').join(', ')}'),
          stepper('ימי חסד לפני חסימה', s.graceDays, (v) => s.graceDays = v, max: 30, unit: ' ימים'),
          sw('חסימת כניסה כשיש חוב', s.blockEntryWhenOverdue, (v) => s.blockEntryWhenOverdue = v,
              sub: 'אחרי ימי החסד, עד שהחוב משולם'),
          sw('תזכורת על כרטיס שעומד לפוג', s.expiringCardReminder, (v) => s.expiringCardReminder = v),
          chips<Channel>(
              'ערוצי תזכורת',
              Channel.values,
              (c) => s.reminderChannels.contains(c),
              (c) => s.reminderChannels.contains(c) ? s.reminderChannels.remove(c) : s.reminderChannels.add(c),
              (c) => c.label),
        ]),
        group('מדיניות מנויים', '', [
          stepper('הקפאה מינימלית', s.freezeMinDays, (v) => s.freezeMinDays = v, min: 1, max: 30, unit: ' ימים'),
          stepper('דמי הקפאה לחודש', s.freezeFeePerMonth.round(), (v) => s.freezeFeePerMonth = v.toDouble(),
              max: 200, step: 5, unit: ' ₪'),
          stepper('תזכורת לפני סוף מנוי', s.renewalReminderDaysBefore, (v) => s.renewalReminderDaysBefore = v,
              max: 60, unit: ' ימים'),
          sw('הצהרת בריאות חובה', s.requireHealthDeclaration, (v) => s.requireHealthDeclaration = v),
          sw('תעודת זהות חובה', s.requireIdNumber, (v) => s.requireIdNumber = v),
        ]),
        group('הרשאות צוות', '', [
          stepper('הנחה מקסימלית בקבלה', s.staffMaxDiscountPct, (v) => s.staffMaxDiscountPct = v,
              max: 50, step: 5, unit: '%'),
          sw('ויתור על דמי רישום', s.staffCanWaiveRegistration, (v) => s.staffCanWaiveRegistration = v),
        ]),
        group('לינק הרשמה וקבלות', '', [
          sw('לינק הרשמה פעיל', s.signupLinkEnabled, (v) => s.signupLinkEnabled = v),
          ListTile(
            title: const Text('כתובת הלינק'),
            subtitle: Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${s.linkSlug}.aura.link/join', textAlign: TextAlign.right)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, 'כתובת הלינק (אנגלית בלבד)', s.linkSlug, latin: true);
              if (v != null && v.trim().isNotEmpty) set(() => s.linkSlug = v.trim().toLowerCase());
            },
          ),
          chips<Channel>(
              'שליחת קבלה ללקוח',
              Channel.values,
              (c) => s.receiptChannels.contains(c),
              (c) => s.receiptChannels.contains(c) ? s.receiptChannels.remove(c) : s.receiptChannels.add(c),
              (c) => c.label),
        ]),
        const Note('ההגדרות נשמרות במכשיר בגרסת ההדגמה. בחיבור למערכת AURA הן נשמרות בשרת לכל הסניפים.'),
        const SizedBox(height: 8),
        Text('אמצעי תשלום פעילים: ${s.enabledMethods.map((m) => m.label).join(' · ')}',
            style: const TextStyle(fontSize: 12, color: Aura.muted)),
        const SizedBox(height: 4),
        Row(children: [
          for (final m in s.enabledMethods)
            Padding(padding: const EdgeInsets.only(left: 6), child: Icon(methodIcon(m), size: 18, color: Aura.muted))
        ]),
      ]),
    );
  }

  Future<String?> _askText(BuildContext context, String title, String initial, {bool latin = false}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          inputFormatters: latin ? [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]'))] : null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('שמירה')),
        ],
      ),
    );
  }
}
