import 'package:flutter/material.dart';
import '../domain/help.dart';
import 'help.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import 'theme.dart';
import 'widgets.dart';
import '../domain/l10n.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('מסלולי מנוי')), actions: [HelpButton.topic(HelpTopic.plans)]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newPlan'),
        heroTag: 'newPlanFab',
        backgroundColor: Aura.ink,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PlanEditor(
                  plan: SubscriptionPlan(id: '', name: '', kind: PlanKind.recurring, price: 0, freezeDaysPerYear: 14))),
        ),
        icon: const Icon(Icons.add),
        label: Text(t('מסלול חדש')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
        Note(t(t(
            'כל מסלול נשמר כמוצר שמסומן כמנוי. שינוי כאן משפיע על מנויים חדשים ועל לינק ההרשמה. מנויים קיימים שומרים על התנאים שלהם.'))),
        const SizedBox(height: 12),
        for (final p in store.plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PlanCard(
              key: Key('editPlan-${p.id}'),
              plan: p,
              showKind: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanEditor(plan: p.copy()))),
            ),
          ),
      ]),
    );
  }
}

class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, required this.plan});
  final SubscriptionPlan plan;
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final SubscriptionPlan p = widget.plan;
  String? error;

  Widget _num(String key, String label, num value, ValueChanged<num> onChanged,
      {String? suffix, String? hint, bool decimal = false}) {
    return TextFormField(
      key: Key('pe-$key'),
      initialValue: value == 0 && hint != null ? '' : (decimal ? _fmt(value.toDouble()) : '$value'),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))],
      decoration: InputDecoration(labelText: label, suffixText: suffix, hintText: hint),
      onChanged: (v) => onChanged(decimal ? (double.tryParse(v) ?? 0) : (int.tryParse(v) ?? 0)),
    );
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Widget _grid(List<Widget> c) => LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final x in c) SizedBox(width: w, child: x)]);
      });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final isNew = p.id.isEmpty;
    return FlowScaffold(
      title: isNew ? t('מסלול חדש') : t('עריכת מסלול'),
      help: HelpTopic.planEditor,
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 6), child: Text(error!, style: const TextStyle(color: Aura.warn))),
        FilledButton(
          key: const Key('savePlan'),
          onPressed: () {
            if (p.isRecurring) {
              p.maxInstallments = 1;
              p.autoRenew = true;
            }
            final e = p.validate();
            if (e != null) return setState(() => error = e);
            final saved = store.savePlan(p);
            Navigator.pop(context, saved);
            showDone(context, t('המסלול "{0}" נשמר', [p.name]));
          },
          child: Text(t('שמירת המסלול')),
        ),
      ]),
      children: [
        TextFormField(
          key: const Key('pe-name'),
          initialValue: p.name,
          decoration: InputDecoration(labelText: t('שם המסלול'), hintText: t('לדוגמה: חודשי סטודנטים')),
          onChanged: (v) => p.name = v,
        ),
        SegmentedButton<PlanKind>(
          segments: [for (final k in PlanKind.values) ButtonSegment(value: k, label: Text(k.short))],
          selected: {p.kind},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => p.kind = s.first),
        ),
        Text(
          switch (p.kind) {
            PlanKind.recurring => t('חיוב אוטומטי כל חודש עד ביטול. מתאים למנוי "חודשי ללא הגבלה".'),
            PlanKind.term => t('משלמים מראש על תקופה קבועה (3, 6, 12 חודשים), אפשר בתשלומים או בשיקים.'),
            PlanKind.punch => t('מספר כניסות קבוע עם תוקף. כל כניסה מורידה אחת.'),
          },
          style: const TextStyle(fontSize: 13, color: Aura.muted),
        ),
        SectionLabel(t('מחיר ומשך')),
        _grid([
          _num('price', p.isRecurring ? t('מחיר לחודש') : t('מחיר כולל'), p.price, (v) => p.price = v.toDouble(),
              suffix: '₪', decimal: true),
          if (p.kind == PlanKind.term) _num('months', t('משך בחודשים'), p.months, (v) => p.months = v.toInt()),
          if (p.kind == PlanKind.punch) _num('entries', t('מספר כניסות'), p.entries, (v) => p.entries = v.toInt()),
          if (p.kind == PlanKind.punch)
            _num('valid', t('תוקף בחודשים'), p.validMonths, (v) => p.validMonths = v.toInt()),
          if (p.isRecurring)
            _num('commit', t('התחייבות בחודשים'), p.commitMonths, (v) => p.commitMonths = v.toInt(),
                hint: t('0 = בלי')),
          if (p.isRecurring)
            _num('notice', t('הודעת ביטול מראש'), p.cancelNoticeDays, (v) => p.cancelNoticeDays = v.toInt(),
                suffix: t('ימים')),
          _num('reg', t('דמי רישום'), p.registrationFee, (v) => p.registrationFee = v.toDouble(),
              suffix: '₪', hint: '0', decimal: true),
        ]),
        SectionLabel(t('שימוש')),
        _grid([
          _num('limit', t('כניסות בשבוע'), p.weeklyLimit, (v) => p.weeklyLimit = v.toInt(), hint: t('ללא הגבלה')),
          _num('freeze', t('ימי הקפאה בשנה'), p.freezeDaysPerYear, (v) => p.freezeDaysPerYear = v.toInt(), hint: '0'),
        ]),
        SectionLabel(t('תשלום')),
        _grid([
          if (!p.isRecurring)
            _num('inst', t('מקס׳ תשלומים באשראי'), p.maxInstallments,
                (v) => p.maxInstallments = v.toInt() < 1 ? 1 : v.toInt()),
          _num('chq', t('מקס׳ שיקים'), p.maxCheques, (v) => p.maxCheques = v.toInt(), hint: '0'),
        ]),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(children: [
            if (p.kind == PlanKind.term)
              SwitchListTile(
                title: Text(t('חידוש אוטומטי בסוף התקופה')),
                subtitle: Text(t('אם כבוי, נשלחת ללקוח תזכורת לחידוש')),
                value: p.autoRenew,
                onChanged: (v) => setState(() => p.autoRenew = v),
              ),
            if (p.isRecurring)
              SwitchListTile(
                key: const Key('pe-prepay'),
                title: Text(t('תשלום מראש על החודש האחרון')),
                subtitle:
                    Text(t('בהצטרפות משלמים חודש ראשון + חודש אחרון. ביטול בהודעה של חודש, והחודש האחרון לא מחויב')),
                value: p.prepayLastMonth,
                onChanged: (v) => setState(() {
                  p.prepayLastMonth = v;
                  if (v && p.cancelNoticeDays < 30) p.cancelNoticeDays = 30;
                }),
              ),
            SwitchListTile(
              title: Text(t('מותר מזומן')),
              subtitle: Text(p.isRecurring ? t('בתשלום הראשון ובגבייה ידנית חודשית') : t('בתשלום בקבלה')),
              value: p.allowCash,
              onChanged: (v) => setState(() => p.allowCash = v),
            ),
            SwitchListTile(
              title: Text(t('מותר שיקים')),
              value: p.allowCheques,
              onChanged: (v) => setState(() => p.allowCheques = v),
            ),
            SwitchListTile(
              title: Text(t('זמין בלינק ההרשמה')),
              subtitle: Text(t('הלקוח יכול לבחור אותו לבד')),
              value: p.onlineSignup,
              onChanged: (v) => setState(() => p.onlineSignup = v),
            ),
            SwitchListTile(
              title: Text(t('מסלול פעיל')),
              subtitle: Text(t('כבוי = לא מוצג בפתיחת מנוי חדש')),
              value: p.active,
              onChanged: (v) => setState(() => p.active = v),
            ),
          ]),
        ),
      ],
    );
  }
}
