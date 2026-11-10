// Business configuration for a gym. Every rule the counter follows is here,
// so the owner changes behaviour without a new app version.

import 'models.dart';

enum ChargeDay { anniversary, firstOfMonth, tenthOfMonth }

extension ChargeDayLabel on ChargeDay {
  String get label => switch (this) {
        ChargeDay.anniversary => 'ביום ההצטרפות',
        ChargeDay.firstOfMonth => 'ב-1 לחודש',
        ChargeDay.tenthOfMonth => 'ב-10 לחודש',
      };
}

enum DocType { taxInvoiceReceipt, receipt }

extension DocTypeLabel on DocType {
  String get label => switch (this) {
        DocType.taxInvoiceReceipt => 'חשבונית מס קבלה',
        DocType.receipt => 'קבלה (עוסק פטור)',
      };
}

enum Channel { whatsapp, sms, email }

extension ChannelLabel on Channel {
  String get label => switch (this) {
        Channel.whatsapp => 'WhatsApp',
        Channel.sms => 'SMS',
        Channel.email => 'מייל',
      };
}

class BusinessSettings {
  // Business
  String businessName = 'Fit Club';
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

  /// Discount steps the counter may offer.
  List<int> discountSteps() => [0, 5, 10, 15, 20, 25, 30, 40, 50].where((d) => d <= staffMaxDiscountPct).toList();
}
