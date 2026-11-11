// Names of the AURA web's sales document types (ReportController::
// getSystemDocumentTypeTranslations; Hebrew as the web's ar2 language file).
// Only the customer-side types: the gym app never gets purchase or stock documents.

import 'l10n.dart';

String serverDocTypeLabel(int type) => switch (type) {
      1 => t('הזמנה'),
      2 => t('תעודת משלוח'),
      3 => t('קבלה'),
      4 => t('חשבונית עסקה'),
      5 => t('הערת החזרה'),
      7 => t('חשבונית מס'),
      8 => t('תעודת משלוח סוכן'),
      9 => t('חשבונית מס ריכוז'),
      10 => t('חשבונית זיכוי מס'),
      11 => t('חשבונית שמורה'),
      12 => t('חשבונית סוכן'),
      13 => t('קבלת תרומה'),
      27 => t('חשבונית מס/קבלה'),
      28 => t('סיבוס'),
      29 => t('וולט'),
      30 => t('הצעת מחיר'),
      32 => t('תשלום לקוח'),
      _ => t('מסמך'),
    };
