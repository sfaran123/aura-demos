// Business configuration for a gym. Every rule the counter follows is here,
// so the owner changes behaviour without a new app version.

import 'models.dart';
import 'l10n.dart';

enum ChargeDay { anniversary, firstOfMonth, tenthOfMonth }

extension ChargeDayLabel on ChargeDay {
  String get label => switch (this) {
        ChargeDay.anniversary => t('ביום ההצטרפות'),
        ChargeDay.firstOfMonth => t('ב-1 לחודש'),
        ChargeDay.tenthOfMonth => t('ב-10 לחודש'),
      };
}

enum DocType { taxInvoiceReceipt, receipt }

extension DocTypeLabel on DocType {
  String get label => switch (this) {
        DocType.taxInvoiceReceipt => t('חשבונית מס קבלה'),
        DocType.receipt => t('קבלה (עוסק פטור)'),
      };
}

enum Channel { whatsapp, sms, email }

extension ChannelLabel on Channel {
  String get label => switch (this) {
        Channel.whatsapp => 'WhatsApp',
        Channel.sms => 'SMS',
        Channel.email => t('מייל'),
      };
}

/// What kind of business uses the app. It picks a recommended set of reports;
/// the owner can still turn any report on or off.
enum BusinessType { gym, studio, crossfit, martialArts, pool, dance, beauty, clinic, classes, kids }

extension BusinessTypeInfo on BusinessType {
  String get label => switch (this) {
        BusinessType.gym => t('חדר כושר'),
        BusinessType.studio => t('סטודיו יוגה / פילאטיס'),
        BusinessType.crossfit => t('קרוספיט / אימוני כוח'),
        BusinessType.martialArts => t('אומנויות לחימה'),
        BusinessType.pool => t('בריכה / קאנטרי'),
        BusinessType.dance => t('בית ספר לריקוד'),
        BusinessType.beauty => t('קוסמטיקה / פדיקור / ציפורניים'),
        BusinessType.clinic => t('קליניקה / פיזיותרפיה'),
        BusinessType.classes => t('חוגים ושיעורים פרטיים'),
        BusinessType.kids => t('מועדון / חוגי ילדים'),
      };

  String get hint => switch (this) {
        BusinessType.gym => t('מנויים חודשיים, כרטיסיות, הקפאות וגבייה חודשית'),
        BusinessType.studio => t('מנוי לפי מספר שיעורים בשבוע וכרטיסיות'),
        BusinessType.crossfit => t('מנויים חודשיים בהתחייבות ואימונים אישיים'),
        BusinessType.martialArts => t('מנוי חודשי לחוג, הרבה תשלום במזומן ושיקים'),
        BusinessType.pool => t('מנוי עונתי או שנתי, משפחות'),
        BusinessType.dance => t('שנת לימודים בתשלומים או בשיקים'),
        BusinessType.beauty => t('סדרות טיפולים (כרטיסייה) ומנוי חודשי לטיפול קבוע'),
        BusinessType.clinic => t('סדרות טיפולים וחבילות'),
        BusinessType.classes => t('תשלום חודשי ידני, שיקים ותזכורות'),
        BusinessType.kids => t('שנת פעילות, שיקים ותשלום חודשי מההורים'),
      };

  /// Reports that matter most for this kind of business.
  Set<String> get recommendedReports {
    const all = {
      'summary', 'accountant', 'daily', 'revenue', 'forecast', 'cheques', 'deposits', 'manual', 'debts', 'failed', //
      'active', 'expiring', 'joins', 'frozen', 'links'
    };
    return switch (this) {
      BusinessType.gym || BusinessType.crossfit => all,
      BusinessType.studio || BusinessType.pool => all.difference({'cheques'}),
      BusinessType.martialArts ||
      BusinessType.classes ||
      BusinessType.kids ||
      BusinessType.dance =>
        all.difference({'deposits', 'frozen'}),
      BusinessType.beauty || BusinessType.clinic => {
          'summary',
          'accountant',
          'daily',
          'revenue',
          'forecast',
          'manual',
          'debts',
          'expiring',
          'links',
          'active'
        },
    };
  }
}

class BusinessSettings {
  // Business
  String businessName = 'Fit Club';

  /// Company / dealer number printed on every invoice. Empty until the owner sets it.
  String businessId = '';
  BusinessType businessType = BusinessType.gym;

  /// Reports shown in the reports tab for this business.
  Set<String> enabledReports = BusinessType.gym.recommendedReports;
  DocType docType = DocType.taxInvoiceReceipt;
  double vatPct = 18;

  // Payment methods
  Set<PayMethod> enabledMethods = {...PayMethod.values};
  int maxInstallments = 12;
  int maxCheques = 12;
  bool allowStandingOrder = true;

  /// Recurring plan paid by hand every month (cash, cheque, transfer or link).
  bool allowManualMonthly = true;

  // Membership policy
  bool requireHealthDeclaration = true;
  bool requireIdNumber = false;
  int freezeMinDays = 7;
  double freezeFeePerMonth = 0;
  int staffMaxDiscountPct = 20;
  bool staffCanWaiveRegistration = true;

  // Recurring billing and collection
  ChargeDay chargeDay = ChargeDay.anniversary;
  int retryAttempts = 3;
  List<int> retryDays = [1, 4, 11];
  int graceDays = 7;
  bool blockEntryWhenOverdue = true;
  int manualReminderDaysBefore = 2;
  int renewalReminderDaysBefore = 14;
  bool expiringCardReminder = true;

  // Customer sign-up link
  bool signupLinkEnabled = true;
  String linkSlug = 'fitclub';

  // Messages
  Set<Channel> receiptChannels = {Channel.whatsapp};
  Set<Channel> reminderChannels = {Channel.whatsapp, Channel.sms};

  /// Where the monthly accountant package is sent.
  String accountantEmail = '';

  /// Staff may issue credit notes (refunds). Off = owner only, in the real app.
  bool staffCanRefund = true;

  /// Sign-up fee: this product (from the AURA price list) is added to a new membership's sale.
  /// Null = no sign-up fee line.
  String? registrationFeeProductId;

  /// Discount steps the counter may offer.
  List<int> discountSteps() => [0, 5, 10, 15, 20, 25, 30, 40, 50].where((d) => d <= staffMaxDiscountPct).toList();

  Map<String, Object?> toJson() => {
        'businessName': businessName,
        'businessId': businessId,
        'businessType': businessType.name,
        'enabledReports': enabledReports.toList(),
        'docType': docType.name,
        'vatPct': vatPct,
        'enabledMethods': [for (final m in enabledMethods) m.name],
        'maxInstallments': maxInstallments,
        'maxCheques': maxCheques,
        'allowStandingOrder': allowStandingOrder,
        'allowManualMonthly': allowManualMonthly,
        'requireHealthDeclaration': requireHealthDeclaration,
        'requireIdNumber': requireIdNumber,
        'freezeMinDays': freezeMinDays,
        'freezeFeePerMonth': freezeFeePerMonth,
        'staffMaxDiscountPct': staffMaxDiscountPct,
        'staffCanWaiveRegistration': staffCanWaiveRegistration,
        'chargeDay': chargeDay.name,
        'retryAttempts': retryAttempts,
        'retryDays': retryDays,
        'graceDays': graceDays,
        'blockEntryWhenOverdue': blockEntryWhenOverdue,
        'manualReminderDaysBefore': manualReminderDaysBefore,
        'renewalReminderDaysBefore': renewalReminderDaysBefore,
        'expiringCardReminder': expiringCardReminder,
        'signupLinkEnabled': signupLinkEnabled,
        'linkSlug': linkSlug,
        'receiptChannels': [for (final c in receiptChannels) c.name],
        'reminderChannels': [for (final c in reminderChannels) c.name],
        'accountantEmail': accountantEmail,
        'staffCanRefund': staffCanRefund,
        if (registrationFeeProductId != null) 'registrationFeeProductId': registrationFeeProductId,
      };

  /// Reads settings saved by [toJson]; missing keys keep their defaults.
  static BusinessSettings fromJson(Map<String, dynamic> j) {
    final s = BusinessSettings();
    T? g<T>(String k) => j[k] is T ? j[k] as T : null;
    s.businessName = g<String>('businessName') ?? s.businessName;
    s.businessId = g<String>('businessId') ?? s.businessId;
    s.businessType = BusinessType.values.asNameMap()[j['businessType']] ?? s.businessType;
    if (j['enabledReports'] is List) s.enabledReports = {...(j['enabledReports'] as List).cast<String>()};
    s.docType = DocType.values.asNameMap()[j['docType']] ?? s.docType;
    s.vatPct = (g<num>('vatPct') ?? s.vatPct).toDouble();
    if (j['enabledMethods'] is List) {
      s.enabledMethods = {for (final m in j['enabledMethods'] as List) PayMethod.values.byName(m)};
    }
    s.maxInstallments = g<int>('maxInstallments') ?? s.maxInstallments;
    s.maxCheques = g<int>('maxCheques') ?? s.maxCheques;
    s.allowStandingOrder = g<bool>('allowStandingOrder') ?? s.allowStandingOrder;
    s.allowManualMonthly = g<bool>('allowManualMonthly') ?? s.allowManualMonthly;
    s.requireHealthDeclaration = g<bool>('requireHealthDeclaration') ?? s.requireHealthDeclaration;
    s.requireIdNumber = g<bool>('requireIdNumber') ?? s.requireIdNumber;
    s.freezeMinDays = g<int>('freezeMinDays') ?? s.freezeMinDays;
    s.freezeFeePerMonth = (g<num>('freezeFeePerMonth') ?? s.freezeFeePerMonth).toDouble();
    s.staffMaxDiscountPct = g<int>('staffMaxDiscountPct') ?? s.staffMaxDiscountPct;
    s.staffCanWaiveRegistration = g<bool>('staffCanWaiveRegistration') ?? s.staffCanWaiveRegistration;
    s.chargeDay = ChargeDay.values.asNameMap()[j['chargeDay']] ?? s.chargeDay;
    s.retryAttempts = g<int>('retryAttempts') ?? s.retryAttempts;
    if (j['retryDays'] is List) s.retryDays = (j['retryDays'] as List).cast<int>();
    s.graceDays = g<int>('graceDays') ?? s.graceDays;
    s.blockEntryWhenOverdue = g<bool>('blockEntryWhenOverdue') ?? s.blockEntryWhenOverdue;
    s.manualReminderDaysBefore = g<int>('manualReminderDaysBefore') ?? s.manualReminderDaysBefore;
    s.renewalReminderDaysBefore = g<int>('renewalReminderDaysBefore') ?? s.renewalReminderDaysBefore;
    s.expiringCardReminder = g<bool>('expiringCardReminder') ?? s.expiringCardReminder;
    s.signupLinkEnabled = g<bool>('signupLinkEnabled') ?? s.signupLinkEnabled;
    s.linkSlug = g<String>('linkSlug') ?? s.linkSlug;
    if (j['receiptChannels'] is List) {
      s.receiptChannels = {for (final c in j['receiptChannels'] as List) Channel.values.byName(c)};
    }
    if (j['reminderChannels'] is List) {
      s.reminderChannels = {for (final c in j['reminderChannels'] as List) Channel.values.byName(c)};
    }
    s.accountantEmail = g<String>('accountantEmail') ?? s.accountantEmail;
    s.staffCanRefund = g<bool>('staffCanRefund') ?? s.staffCanRefund;
    s.registrationFeeProductId = g<String>('registrationFeeProductId');
    return s;
  }
}
