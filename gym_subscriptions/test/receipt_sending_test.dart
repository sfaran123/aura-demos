// Sending a sale's document to the customer, signed in: the AURA server sends it,
// with the same endpoints the POS app calls.
//  - SMS: POST sales/send-invoice-by-sms {id, mobile (local 05…), type: short}.
//  - Email: POST sales/send-invoice-via-mail {sale_id, emails: '[{"value": …}]'}.
// Offered on a sale opened from the sales list and on the screen after a payment.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/receipt_sending.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'server_sync_test.dart' show members, serverApi, signedIn, today;
import 'support/fake_api.dart';

const smsPath = '/sales/send-invoice-by-sms';
const mailPath = '/sales/send-invoice-via-mail';

void main() {
  setUp(() => L10n.lang = AppLang.en);

  group('the SMS endpoint', () {
    test('the phone goes in the local form the web expects', () {
      expect(localPhoneNumber('050-1234567'), '0501234567');
      expect(localPhoneNumber('+972 50 123 4567'), '0501234567');
      expect(localPhoneNumber('972501234567'), '0501234567');
      expect(localPhoneNumber('501234567'), '0501234567');
    });

    test('its answer: JSON (the web today) or plain text (older servers)', () {
      expect(smsAnswer({'success': true, 'message': 'SMS sent successfully', 'units': 2}).ok, isTrue);
      expect(smsAnswer('SMS sent successfully').ok, isTrue);
      expect(smsAnswer('Succeeded').ok, isTrue, reason: "SMS4Free's own text, passed through");
      expect(smsAnswer('SMS sent successfully<div class="phpdebugbar">…</div>').ok, isTrue);

      final failed = smsAnswer({'success': false, 'message': 'Invalid recipient'});
      expect((failed.ok, failed.message), (false, 'Invalid recipient'), reason: "the provider's reason is shown");
      final notSetUp = smsAnswer({'success': false, 'message': 'Please set up the SMS setting first!', 'showSetupBtn': true});
      expect(notSetUp.ok, isFalse);
      expect(notSetUp.message, contains('not set up for this branch'));
      expect(smsAnswer(null).message, 'The SMS was not sent. Try again.');
      expect(smsAnswer('<html>error</html>').message, 'The SMS was not sent. Try again.');
    });
  });

  group('signed in, a sale from the sales list', () {
    Future<void> tapKey(WidgetTester t, String key) async {
      await t.ensureVisible(find.byKey(Key(key)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key(key)));
      await t.pumpAndSettle();
    }

    /// Opens TIR-1001 (sale 500, Dana Levi, 050-1234567).
    Future<(FakeApi, GymStore)> openSale(WidgetTester t, FakeApi api) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final store = GymStore(clock: () => today);
      await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: api)));
      await t.pumpAndSettle();
      await tapKey(t, 'homeSales');
      await tapKey(t, 'sale-500');
      return (api, store);
    }

    Map<String, Object?> sent(FakeApi api, String path) => api.posts.lastWhere((p) => p.$1 == path).$2;

    testWidgets('SMS to the member\'s phone: the server sends a link to the document', (t) async {
      final (api, store) = await openSale(
          t, serverApi()..postHandlers[smsPath] = (_) => {'success': true, 'message': 'SMS sent successfully', 'units': 2});
      expect(find.byKey(const Key('sendWhatsapp')), findsNothing, reason: 'no WhatsApp sending on the server');
      expect(t.widget<TextField>(find.byKey(const Key('sendPhone'))).controller!.text, '050-1234567');

      await tapKey(t, 'sendSms');
      expect(sent(api, smsPath), {'id': 500, 'mobile': '0501234567', 'type': 'short'});
      expect(find.text('Receipt sent by SMS to 050-1234567'), findsOneWidget);
      expect(find.text('Sent by SMS · 050-1234567'), findsOneWidget);
      expect(store.receipts.firstWhere((r) => r.saleId == 500).sent.single.$2, '050-1234567');
    });

    testWidgets('another number can be typed; a wrong one is not sent', (t) async {
      final (api, _) = await openSale(t, serverApi()..postHandlers[smsPath] = (_) => {'success': true});
      await t.enterText(find.byKey(const Key('sendPhone')), '123');
      await tapKey(t, 'sendSms');
      expect(find.text("The phone number isn't valid"), findsOneWidget);
      expect(api.posts.where((p) => p.$1 == smsPath), isEmpty);

      await t.enterText(find.byKey(const Key('sendPhone')), '052-7654321');
      await tapKey(t, 'sendSms');
      expect(sent(api, smsPath)['mobile'], '0527654321');
    });

    testWidgets('the provider refuses: its reason, nothing marked as sent', (t) async {
      await openSale(t, serverApi()..postHandlers[smsPath] = (_) => {'success': false, 'message': 'Not enough credit'});
      await tapKey(t, 'sendSms');
      expect(find.text('Not enough credit'), findsOneWidget);
      expect(find.textContaining('Sent by'), findsNothing);
    });

    testWidgets('no SMS account on the branch: says where to set it up', (t) async {
      await openSale(
          t,
          serverApi()
            ..postHandlers[smsPath] =
                (_) => {'success': false, 'message': 'Please set up the SMS setting first!', 'showSetupBtn': true});
      await tapKey(t, 'sendSms');
      expect(find.text('SMS sending is not set up for this branch in AURA (branch settings).'), findsOneWidget);
    });

    testWidgets('the server cannot be reached: the usual connection message', (t) async {
      await openSale(t, serverApi()..postErrors[smsPath] = AuraApiException(AuraErrorKind.unreachable));
      await tapKey(t, 'sendSms');
      expect(find.textContaining('Sent by'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('email: the member\'s address from the server, the PDF sent by the web', (t) async {
      final withEmail = jsonDecode(jsonEncode(members)) as Map<String, Object?>;
      ((withEmail['data'] as List)[1] as Map)['email'] = 'dana@example.com';
      final (api, _) = await openSale(
          t,
          serverApi()
            ..responses['/gym/members'] = withEmail
            ..postHandlers[mailPath] = (_) => true);
      expect(t.widget<TextField>(find.byKey(const Key('sendEmail'))).controller!.text, 'dana@example.com');

      await tapKey(t, 'sendEmailGo');
      final body = sent(api, mailPath);
      expect(body['sale_id'], 500);
      expect(jsonDecode(body['emails'] as String), [
        {'value': 'dana@example.com'}
      ]);
      expect(find.text('Receipt sent by Email to dana@example.com'), findsOneWidget);
    });

    testWidgets('email: a wrong address is not sent; a server error is shown', (t) async {
      final (api, _) = await openSale(
          t, serverApi()..postErrors[mailPath] = AuraApiException(AuraErrorKind.server, 'HTTP 500'));
      await tapKey(t, 'sendEmailGo');
      expect(find.text("The email address isn't valid"), findsOneWidget, reason: 'Dana has no email on the server');
      expect(api.posts.where((p) => p.$1 == mailPath), isEmpty);

      await t.enterText(find.byKey(const Key('sendEmail')), 'dana@example.com');
      await tapKey(t, 'sendEmailGo');
      expect(api.posts.where((p) => p.$1 == mailPath), hasLength(1));
      expect(find.textContaining('Sent by'), findsNothing);
    });
  });
}
