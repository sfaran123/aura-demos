// Undoing a sale signed in, as the web does it (GymController):
//  - GET gym/sales/{id}/credit: what the server allows (Cancel Document mode, how
//    the money is given back, the web's Refund Card Payment and what is left).
//  - POST gym/sales/{id}/cancel: a receipt at once, a TIN by a whole-document TIC.
//  - POST gym/sales/{id}/card-refund: Z Credit refunds all or part to the card.
// Every request carries an app_uuid; a retry after no clear answer keeps it, so
// the server never refunds twice.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_gym/src/app.dart';
import 'package:aura_gym/src/domain/l10n.dart';
import 'package:aura_gym/src/domain/models.dart';
import 'package:aura_gym/src/domain/sale_credit.dart';
import 'package:aura_gym/src/integration/aura_api.dart';
import 'package:aura_gym/src/state/auth.dart';
import 'package:aura_gym/src/state/gym_store.dart';

import 'server_sync_test.dart' show serverApi, signedIn, today;
import 'support/fake_api.dart';

const creditPath = '/gym/sales/500/credit';
const cancelPath = '/gym/sales/500/cancel';
const refundPath = '/gym/sales/500/card-refund';

/// TIR-1001 (sale 500, Dana Levi, 199 by card through Z Credit, membership 5).
Map<String, Object?> options({
  bool allowed = true,
  bool cancelled = false,
  String? mode = 'document',
  List<String> methods = const ['cash', 'bank', 'card'],
  Map<String, Object?>? card = const {'amount': 199, 'refunded': 0, 'waiting': 0, 'refundable': 199},
}) =>
    {
      'data': {
        'sale_id': 500,
        'reference_no': 'TIR-1001',
        'type': 27,
        'grand_total': 199,
        'paid_amount': 199,
        'cancelled': cancelled,
        'allowed': allowed,
        'cancel_mode': mode,
        'cancel_type': mode == 'document' ? 10 : null,
        'refund_methods': methods,
        'card_refund': card,
        'membership': {'id': 5, 'active': true},
      }
    };

void main() {
  setUp(() => L10n.lang = AppLang.en);

  group('the server\'s answers', () {
    test('options', () {
      final o = SaleCreditOptions.fromJson(options()['data'] as Map);
      expect((o.saleId, o.reference, o.total, o.cancelMode), (500, 'TIR-1001', 199.0, 'document'));
      expect(o.refundMethods, [PayMethod.cash, PayMethod.bank, PayMethod.card]);
      expect((o.cardRefund!.refundable, o.canRefundCard, o.canCancel), (199.0, true, true));
      expect((o.membershipId, o.membershipActive), ('5', true));

      final done = SaleCreditOptions.fromJson(options(cancelled: true, mode: null, card: null)['data'] as Map);
      expect((done.canCancel, done.canRefundCard), (false, false));
      final used = SaleCreditOptions.fromJson(
          options(card: {'amount': 199, 'refunded': 199, 'waiting': 0, 'refundable': 0})['data'] as Map);
      expect(used.canRefundCard, isFalse, reason: 'all of the card payment was refunded');
      final notAllowed = SaleCreditOptions.fromJson(options(allowed: false)['data'] as Map);
      expect((notAllowed.canCancel, notAllowed.canRefundCard), (false, false));
    });

    test('errors in the desk\'s words', () {
      expect(saleCreditError('HTTP 409: already_cancelled')!.message, 'The document is already cancelled');
      expect(saleCreditError('HTTP 409: cannot_cancel')!.message, 'This document cannot be cancelled');
      expect(saleCreditError('HTTP 422: amount_too_high')!.message, 'The amount is more than can be refunded');
      expect(saleCreditError('HTTP 422: refund_declined: Card blocked')!.message,
          'Z Credit did not approve the refund: Card blocked');
      final unknown = saleCreditError('HTTP 409: refund_unknown')!;
      expect((unknown.unknown, unknown.message.contains('Check in Z Credit')), (true, true));
      expect(saleCreditError('HTTP 500: Server Error'), isNull);
    });
  });

  group('signed in, a sale from the sales list', () {
    Future<void> tapKey(WidgetTester t, String key) async {
      await t.ensureVisible(find.byKey(Key(key)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key(key)));
      await t.pumpAndSettle();
    }

    Future<GymStore> openCredit(WidgetTester t, FakeApi api) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final store = GymStore(clock: () => today);
      await t.pumpWidget(AuraGymApp(store: store, auth: AuthController(storage: signedIn(), api: api)));
      await t.pumpAndSettle();
      await tapKey(t, 'homeSales');
      await tapKey(t, 'sale-500');
      await tapKey(t, 'creditReceipt');
      return store;
    }

    List<Map<String, Object?>> sent(FakeApi api, String path) => [
          for (final p in api.posts)
            if (p.$1 == path) p.$2
        ];

    testWidgets('cancel the document: a whole TIC, the money back in cash, the membership too', (t) async {
      final api = serverApi()..responses[creditPath] = options();
      api.postHandlers[cancelPath] = (b) => {
            'data': {
              'sale': {'id': 500, 'reference_no': 'TIR-1001', 'cancelled': true},
              'document': {'id': 900, 'reference_no': 'TIC-90003', 'type': 10, 'grand_total': -199},
              'receipt': {'id': 901, 'reference_no': 'R-50007', 'grand_total': -199},
            }
          };
      await openCredit(t, api);
      expect(find.byKey(const Key('creditMode-card')), findsOneWidget, reason: 'paid by card through Z Credit');
      await tapKey(t, 'creditMode-cancel');
      expect(find.byKey(const Key('creditTotal')), findsOneWidget);
      expect(find.byKey(const Key('creditAmount')), findsNothing, reason: 'the web cancels the whole document');
      expect(find.text('Refund on the terminal'), findsOneWidget);

      await tapKey(t, 'refund-cash');
      expect(find.text('Write a reason'), findsOneWidget);
      await t.enterText(find.byKey(const Key('creditReason')), 'Double charge');
      await t.pumpAndSettle();
      await tapKey(t, 'creditCancelSub');
      await tapKey(t, 'creditConfirm');
      expect(find.byKey(const Key('creditConfirmDialog')), findsOneWidget);
      expect(find.text('Cancel TIR-1001?'), findsOneWidget);
      await tapKey(t, 'creditConfirmYes');

      final body = sent(api, cancelPath).single;
      expect(body['method'], 'cash');
      expect(body['reason'], 'Double charge');
      expect(body['cancel_membership'], isTrue);
      expect(body['app_uuid'], isA<String>());
      expect(find.text('TIR-1001 cancelled · Credit invoice TIC-90003 · Minus receipt R-50007'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('GET /gym/sales?')).length, greaterThan(1),
          reason: 'everything is loaded again');
    });

    testWidgets('refund to the card: part of the amount, confirmed first', (t) async {
      final api = serverApi()..responses[creditPath] = options();
      api.postHandlers[refundPath] = (b) => {
            'data': {'sale_id': 500, 'amount': 50, 'tic': 'TIC-90004', 'receipt': 'R-50006'}
          };
      await openCredit(t, api);
      expect(find.text('Refund to card · ${money(199)}'), findsOneWidget, reason: 'all that is left, by default');
      await t.enterText(find.byKey(const Key('creditAmount')), '250');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('creditProblem')), findsOneWidget);
      await t.enterText(find.byKey(const Key('creditAmount')), '50');
      await t.enterText(find.byKey(const Key('creditReason')), 'Wrong price');
      await t.pumpAndSettle();
      await tapKey(t, 'creditConfirm');
      expect(find.text('Refund ${money(50)} to the card?'), findsOneWidget);
      await tapKey(t, 'creditConfirmYes');

      final body = sent(api, refundPath).single;
      expect((body['amount'], body['reason'], body['cancel_membership']), (50.0, 'Wrong price', false));
      expect(find.text('${money(50)} refunded to the card · Credit invoice TIC-90004 · Minus receipt R-50006'),
          findsOneWidget);
    });

    testWidgets('declined: nothing refunded, the next try is a new one; no clear answer: the same key', (t) async {
      final api = serverApi()
        ..responses[creditPath] = options()
        ..postErrors[refundPath] = AuraApiException(AuraErrorKind.server, 'HTTP 422: refund_declined: Card blocked');
      await openCredit(t, api);
      await t.enterText(find.byKey(const Key('creditReason')), 'Wrong price');
      await t.pumpAndSettle();
      await tapKey(t, 'creditConfirm');
      await tapKey(t, 'creditConfirmYes');
      expect(find.text('The refund was not made'), findsOneWidget);
      expect(find.text('Z Credit did not approve the refund: Card blocked'), findsOneWidget);
      await tapKey(t, 'cardProblemOk');

      api.postErrors[refundPath] = AuraApiException(AuraErrorKind.server, 'HTTP 409: refund_unknown');
      await tapKey(t, 'creditConfirm');
      await tapKey(t, 'creditConfirmYes');
      expect(find.text('Unknown whether the refund was made'), findsOneWidget);
      await tapKey(t, 'cardProblemOk');
      await tapKey(t, 'creditConfirm');
      await tapKey(t, 'creditConfirmYes');
      await tapKey(t, 'cardProblemOk');

      final keys = [for (final b in sent(api, refundPath)) b['app_uuid']];
      expect(keys.length, 3);
      expect(keys[1], isNot(keys[0]), reason: 'declined: nothing happened, a new try');
      expect(keys[2], keys[1], reason: 'no clear answer: the same key, never refunded twice');
      expect(find.byKey(const Key('creditConfirm')), findsOneWidget, reason: 'the sheet stays open');
    });

    testWidgets('not allowed, already cancelled, or a receipt cancelled at once', (t) async {
      final api = serverApi()..responses[creditPath] = options(allowed: false, mode: null, card: null);
      await openCredit(t, api);
      expect(find.text("You don't have permission to cancel documents"), findsOneWidget);
      expect(api.posts.where((p) => p.$1.startsWith('/gym/sales/500/')), isEmpty);
      await tapKey(t, 'cardProblemOk');

      api.responses[creditPath] = options(cancelled: true, mode: null, card: null);
      await tapKey(t, 'sale-500');
      await tapKey(t, 'creditReceipt');
      expect(find.text('The document is already cancelled'), findsOneWidget);
      await tapKey(t, 'cardProblemOk');

      // A receipt (exempt dealer): cancelled at once, no refund method; a minus receipt is issued.
      api.responses[creditPath] = options(mode: 'direct', methods: const [], card: null);
      api.postHandlers[cancelPath] = (b) => {
            'data': {
              'sale': {'id': 500, 'reference_no': 'TIR-1001', 'cancelled': true},
              'document': null,
              'receipt': 'R-50008',
            }
          };
      await tapKey(t, 'sale-500');
      await tapKey(t, 'creditReceipt');
      expect(find.byKey(const Key('creditMode-card')), findsNothing);
      expect(find.text('The receipt is cancelled and a minus receipt is issued for the whole amount.'), findsWidgets);
      await t.enterText(find.byKey(const Key('creditReason')), 'Mistake');
      await t.pumpAndSettle();
      await tapKey(t, 'creditConfirm');
      await tapKey(t, 'creditConfirmYes');
      expect(sent(api, cancelPath).single.containsKey('method'), isFalse);
      expect(find.text('TIR-1001 cancelled · Minus receipt R-50008'), findsOneWidget);
    });
  });
}
