import 'package:flutter/material.dart';
import '../domain/help.dart';
import 'help.dart';
import 'package:flutter/services.dart';

import '../domain/l10n.dart';
import '../domain/models.dart';
import '../domain/settings.dart';
import 'checkout/checkout_screens.dart' show methodIcon;
import 'guide_screen.dart';
import 'plans_screen.dart';
import 'sales_screen.dart';
import 'report_picker.dart';
import '../state/reports.dart' show allReports;
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
      appBar: AppBar(title: Text(t('הגדרות העסק')), actions: [HelpButton.topic(HelpTopic.settings)]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Panel(
          key: const Key('settingsGuide'),
          color: Aura.ink,
          borderColor: Aura.ink,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen())),
          child: Row(children: [
            const Icon(Icons.menu_book_outlined, color: Aura.goldLight),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('מדריך למשתמש'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, color: Colors.white)),
                Text(t('איך עושים כל דבר, צעד אחרי צעד'),
                    style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
              ]),
            ),
            const ForwardChevron(color: Colors.white70),
          ]),
        ),
        const SizedBox(height: 10),
        Panel(
          key: const Key('openPlans'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Aura.goldBg, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.view_list, color: Aura.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('מסלולי מנוי'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                Text(t('{0} מסלולים · עריכה והוספה', [store.plans.length]),
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              ]),
            ),
            const ForwardChevron(),
          ]),
        ),
        const SizedBox(height: 10),
        Panel(
          key: const Key('openReportPicker'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPickerScreen())),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Aura.goldBg, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.insert_chart_outlined, color: Aura.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('דוחות לעסק'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                Text(t('{0} מתוך {1} דוחות מוצגים', [s.enabledReports.length, allReports.length]),
                    style: const TextStyle(fontSize: 12.5, color: Aura.muted)),
              ]),
            ),
            const ForwardChevron(),
          ]),
        ),
        const SizedBox(height: 10),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.translate, color: Aura.muted),
              SizedBox(width: 12),
              Expanded(child: Text(t('שפה · Language · اللغة'), style: TextStyle(fontSize: 15))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in AppLang.values)
                ChoiceChip(
                  key: Key('lang-${l.code}'),
                  label: Text(l.nativeName),
                  selected: store.language == l,
                  labelStyle: TextStyle(color: store.language == l ? Colors.white : Aura.ink),
                  onSelected: (_) => store.setLanguage(l),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 4),
        group(t('העסק'), '', [
          ListTile(
            key: const Key('businessId'),
            title: Text(t('ח.פ / ע.מ')),
            subtitle: Text(s.businessId.isEmpty ? t('לא הוגדר · יודפס על כל חשבונית') : s.businessId),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, t('ח.פ / ע.מ'), s.businessId);
              if (v != null) set(() => s.businessId = v.replaceAll(RegExp(r'\D'), ''));
            },
          ),
          ListTile(
            key: const Key('openPriceList'),
            title: Text(t('מחירון')),
            subtitle: Text(t('מוצרים, שירותים ומסלולים עם המחירים')),
            trailing: const ForwardChevron(),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceListScreen())),
          ),
          ListTile(
            title: Text(t('שם העסק')),
            subtitle: Text(s.businessName),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, t('שם העסק'), s.businessName);
              if (v != null && v.trim().isNotEmpty) set(() => s.businessName = v.trim());
            },
          ),
          ListTile(
            key: const Key('businessType'),
            leading: Icon(businessIcon(s.businessType), color: Aura.gold),
            title: Text(t('סוג עסק')),
            subtitle: Text('${s.businessType.label}\n${s.businessType.hint}'),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => pickBusinessType(context),
          ),
          chips<DocType>(
              t('מסמך שמופק בכל תשלום'), DocType.values, (d) => s.docType == d, (d) => s.docType = d, (d) => d.label),
          stepper(t('מע״מ'), s.vatPct.round(), (v) => s.vatPct = v.toDouble(), max: 30, unit: '%'),
        ]),
        group(t('אמצעי תשלום'), t('מה הקבלה יכולה לקבל. אפשר להגביל גם ברמת כל מסלול.'), [
          chips<PayMethod>(
              t('אמצעים פעילים'),
              PayMethod.values,
              (m) => s.enabledMethods.contains(m),
              (m) => s.enabledMethods.contains(m) ? s.enabledMethods.remove(m) : s.enabledMethods.add(m),
              (m) => m.label),
          stepper(t('מקסימום תשלומים באשראי'), s.maxInstallments, (v) => s.maxInstallments = v, min: 1, max: 36),
          stepper(t('מקסימום שיקים'), s.maxCheques, (v) => s.maxCheques = v, min: 1, max: 24),
        ]),
        group(t('מנוי חודשי מתחדש'), t('איך גובים את החודשים שאחרי התשלום הראשון.'), [
          sw(t('הוראת קבע בבנק'), s.allowStandingOrder, (v) => s.allowStandingOrder = v,
              sub: t('חיוב חשבון בנק עם טופס הרשאה')),
          sw(t('גבייה ידנית כל חודש'), s.allowManualMonthly, (v) => s.allowManualMonthly = v,
              key: const Key('allowManual'),
              sub: t('ללקוחות שמשלמים במזומן, בשיק או בהעברה. התשלום מופיע ב"לגבייה" כל חודש, עם תזכורות ומעקב חוב.')),
          chips<ChargeDay>(
              t('יום החיוב החודשי'), ChargeDay.values, (d) => s.chargeDay == d, (d) => s.chargeDay = d, (d) => d.label),
          stepper(t('תזכורת לפני גבייה ידנית'), s.manualReminderDaysBefore, (v) => s.manualReminderDaysBefore = v,
              max: 14, unit: t(' ימים')),
        ]),
        group(t('חיוב שנכשל וחובות'), t('מה קורה כשכרטיס נדחה או שתשלום ידני לא הגיע.'), [
          stepper(t('ניסיונות חיוב חוזרים'), s.retryAttempts, (v) => s.retryAttempts = v,
              max: 8,
              sub: t('מרווחים: {0}', [
                s.retryDays.take(s.retryAttempts).map((d) => t('יום {0}', [d])).join(', ')
              ])),
          stepper(t('ימי חסד לפני חסימה'), s.graceDays, (v) => s.graceDays = v, max: 30, unit: t(' ימים')),
          sw(t('חסימת כניסה כשיש חוב'), s.blockEntryWhenOverdue, (v) => s.blockEntryWhenOverdue = v,
              sub: t('אחרי ימי החסד, עד שהחוב משולם')),
          sw(t('תזכורת על כרטיס שעומד לפוג'), s.expiringCardReminder, (v) => s.expiringCardReminder = v),
          chips<Channel>(
              t('ערוצי תזכורת'),
              Channel.values,
              (c) => s.reminderChannels.contains(c),
              (c) => s.reminderChannels.contains(c) ? s.reminderChannels.remove(c) : s.reminderChannels.add(c),
              (c) => c.label),
        ]),
        group(t('מדיניות מנויים'), '', [
          stepper(t('הקפאה מינימלית'), s.freezeMinDays, (v) => s.freezeMinDays = v, min: 1, max: 30, unit: t(' ימים')),
          stepper(t('דמי הקפאה לחודש'), s.freezeFeePerMonth.round(), (v) => s.freezeFeePerMonth = v.toDouble(),
              max: 200, step: 5, unit: ' ₪'),
          stepper(t('תזכורת לפני סוף מנוי'), s.renewalReminderDaysBefore, (v) => s.renewalReminderDaysBefore = v,
              max: 60, unit: t(' ימים')),
          sw(t('הצהרת בריאות חובה'), s.requireHealthDeclaration, (v) => s.requireHealthDeclaration = v),
          sw(t('תעודת זהות חובה'), s.requireIdNumber, (v) => s.requireIdNumber = v),
        ]),
        group(t('הרשאות צוות'), '', [
          stepper(t('הנחה מקסימלית בקבלה'), s.staffMaxDiscountPct, (v) => s.staffMaxDiscountPct = v,
              max: 50, step: 5, unit: '%'),
          sw(t('ויתור על דמי רישום'), s.staffCanWaiveRegistration, (v) => s.staffCanWaiveRegistration = v),
        ]),
        group(t('לינק הרשמה וקבלות'), '', [
          sw(t('לינק הרשמה פעיל'), s.signupLinkEnabled, (v) => s.signupLinkEnabled = v),
          ListTile(
            title: Text(t('כתובת הלינק')),
            subtitle: Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${s.linkSlug}.aura.link/join', textAlign: TextAlign.right)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, t('כתובת הלינק (אנגלית בלבד)'), s.linkSlug, latin: true);
              if (v != null && v.trim().isNotEmpty) set(() => s.linkSlug = v.trim().toLowerCase());
            },
          ),
          chips<Channel>(
              t('שליחת קבלה ללקוח'),
              Channel.values,
              (c) => s.receiptChannels.contains(c),
              (c) => s.receiptChannels.contains(c) ? s.receiptChannels.remove(c) : s.receiptChannels.add(c),
              (c) => c.label),
        ]),
        group(t('הנהלת חשבונות'), t('זיכויים ודוחות לרואה החשבון.'), [
          ListTile(
            key: const Key('accountantEmailTile'),
            title: Text(t('המייל של רואה החשבון')),
            subtitle: Text(s.accountantEmail.isEmpty ? t('לא הוגדר') : s.accountantEmail),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, t('המייל של רואה החשבון'), s.accountantEmail, latin: true);
              if (v != null) set(() => s.accountantEmail = v.trim());
            },
          ),
          sw(t('הצוות יכול להפיק זיכוי'), s.staffCanRefund, (v) => s.staffCanRefund = v,
              key: const Key('staffCanRefund'), sub: t('כבוי = רק בעל העסק (בחיבור למערכת, לפי הרשאות)')),
        ]),
        group(t('נתונים'), '', [
          ListTile(
            leading: const Icon(Icons.save_outlined, color: Aura.ok),
            title: Text(t('הנתונים נשמרים במכשיר')),
            subtitle: Text(t('כל פעולה נשמרת מיד, גם כשסוגרים את האפליקציה. בחיבור למערכת AURA הנתונים יישמרו בשרת.'),
                style: const TextStyle(fontSize: 12.5)),
          ),
          ListTile(
            key: const Key('resetDemo'),
            leading: const Icon(Icons.restart_alt, color: Aura.warn),
            title: Text(t('איפוס לנתוני הדגמה'), style: const TextStyle(color: Aura.warn)),
            subtitle: Text(t('מוחק את מה שנעשה במכשיר ומחזיר את נתוני ההדגמה'), style: const TextStyle(fontSize: 12.5)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(t('לאפס את הנתונים?')),
                  content:
                      Text(t('כל המנויים, התשלומים וההגדרות שנעשו במכשיר יימחקו ויוחלפו בנתוני ההדגמה. אי אפשר לבטל.')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('ביטול'))),
                    FilledButton(
                      key: const Key('resetConfirm'),
                      style: FilledButton.styleFrom(backgroundColor: Aura.warn),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(t('איפוס')),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                store.resetDemo();
                if (context.mounted) showDone(context, t('הנתונים אופסו לנתוני ההדגמה'));
              }
            },
          ),
        ]),
        const SizedBox(height: 8),
        Text(t('אמצעי תשלום פעילים: {0}', [s.enabledMethods.map((m) => m.label).join(' · ')]),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('ביטול'))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t('שמירה'))),
        ],
      ),
    );
  }
}
