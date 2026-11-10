# AURA Gym – subscriptions module

Flutter module for gyms: opening memberships at the counter, quick payments, split payments, monthly collection (automatic and manual), customer sign-up links, plan definitions and business settings. Hebrew, right-to-left, AURA brand.

**Download the latest APK:** [Releases → gym-latest](../../releases/tag/gym-latest) (built automatically on every push).

## What's inside

| Area | Screens |
|---|---|
| Home | KPIs (active, today's revenue, open debt), 4 actions, "needs attention" list, recent payments |
| New subscription | customer → plan (start date, discount, waive registration fee) → payment → summary → done |
| Quick payment | registered or walk-in customer → products or free amount → payment |
| Split payment | card (saved/new, installments), cash, cheques, bank transfer, link to customer – any mix that balances to the amount due |
| Monthly charge for recurring plans | saved card, new card, bank standing order, or **manual monthly collection** (cash/cheque/transfer) |
| To collect | manual monthly charges and failed card charges: mark paid (issues receipt, opens next month), send payment link, send reminder; entry blocked after grace days |
| Members | filters (active, pending, frozen, failed, ending), member card: freeze, end freeze, renew/change plan, pay, cancel (respects notice and commitment) |
| Plans | create/edit: type (recurring / term / punch card), price, months/entries/validity, commitment, cancel notice, registration fee, weekly limit, freeze days, max installments/cheques, auto-renew, cash/cheques allowed, available on link, active |
| Settings | document type, VAT, payment methods, installments, standing order, manual monthly, charge day, retries, grace days, entry blocking, reminders, freeze rules, staff permissions, sign-up link, receipt channels |
| Customer link | plan → details + health declaration + terms → card payment → active membership (previewed inside the app) |

## Code layout

```
lib/
  main.dart                 standalone app
  src/app.dart              AuraGymApp + GymModule (the widget to embed)
  src/domain/               pure Dart, no Flutter: models, pricing/split rules, settings
  src/state/gym_store.dart  in-memory store with sample data (replace with AURA API)
  src/ui/                   screens and widgets
test/
  domain_test.dart          33 unit tests for rules and store
  app_flow_test.dart        10 end-to-end widget tests of every flow
```

## Embedding in the existing AURA app

1. Copy `lib/src` into the AURA project (e.g. `lib/features/gym/`) and the Rubik fonts if the app does not have them.
2. Push the module from anywhere:
   ```dart
   Navigator.push(context, MaterialPageRoute(builder: (_) => GymModule(store: gymStore)));
   ```
   `GymModule` has its own navigator, so all its screens and sheets work inside the host app.
3. Replace the sample data: keep the public methods of `GymStore` and implement them against the AURA API
   (`addCustomer`, `savePlan`, `openSubscription`, `quickPay`, `collect`, `sendChargeLink`, `freeze`, `unfreeze`, `cancel`, `sendSignupLink`, `completeSignup`).
4. Card entry: replace `showNewCardSheet` with the processor's secure component (Z-Credit / Dangot / other) and store only the token + last 4 digits.

## Not connected yet (by design in this build)

- Data is in memory and resets when the app restarts.
- Card payments, links, WhatsApp/SMS messages and receipts are simulated; no real money moves.
- The test card button exists only in this build.

## Running locally

```
flutter pub get
flutter test
flutter run
```
