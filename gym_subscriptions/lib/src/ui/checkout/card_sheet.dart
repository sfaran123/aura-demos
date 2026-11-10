import 'package:flutter/material.dart';

import '../theme.dart';

/// Placeholder for the card processor's secure input (iframe / SDK).
/// The app never sees the card number; the processor returns a token and the
/// last four digits. In this build a test card is used.
Future<String?> showNewCardSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => const _CardSheet(),
  );
}

class _CardSheet extends StatefulWidget {
  const _CardSheet();
  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  bool filled = false;

  Widget _field(String hint, String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
            color: Aura.paper, borderRadius: BorderRadius.circular(10), border: Border.all(color: Aura.line)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(filled ? value : hint, style: TextStyle(color: filled ? Aura.ink : Aura.muted, fontSize: 15)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('כרטיס חדש', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14), border: Border.all(color: Aura.goldLight, width: 1.5)),
          child: Column(children: [
            const Row(children: [
              Icon(Icons.lock_outline, size: 16, color: Aura.muted),
              SizedBox(width: 6),
              Expanded(child: Text('שדה מאובטח של חברת הסליקה', style: TextStyle(fontSize: 12, color: Aura.muted))),
              Text('PCI', style: TextStyle(fontSize: 12, color: Aura.muted)),
            ]),
            const SizedBox(height: 10),
            _field('מספר כרטיס', '4580 •••• •••• 1111'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _field('MM/YY', '09/28')),
              const SizedBox(width: 8),
              Expanded(child: _field('CVV', '•••')),
            ]),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('fillTestCard'),
              onPressed: () => setState(() => filled = true),
              child: const Text('גרסת בדיקה: מילוי כרטיס בדיקה'),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        const Text(
          'בחיבור לחברת הסליקה, ההקלדה נעשית ברכיב המאובטח שלה והמערכת מקבלת רק טוקן וארבע ספרות אחרונות.',
          style: TextStyle(fontSize: 13, color: Aura.muted, height: 1.45),
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('saveCard'),
          onPressed: filled ? () => Navigator.pop(context, '1111') : null,
          child: const Text('שמירת הכרטיס'),
        ),
      ]),
    );
  }
}
