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
| Members | filters for every status with counts (active, awaiting payment, debt, failed charge, frozen, ending, being cancelled, ended), member card: freeze, end freeze, renew/change plan, pay, cancel (respects notice and commitment) |
| Plans (Settings → plans) | create/edit: type (recurring / term / punch card), price, months/entries/validity, commitment, cancel notice, registration fee, weekly limit, freeze days, max installments/cheques, auto-renew, cash/cheques allowed, available on link, active, **last month paid upfront** (join pays first + last month; cancellation needs a month's notice and the last month is not charged) |
| Settings | document type, VAT, payment methods, installments, standing order, manual monthly, charge day, retries, grace days, entry blocking, reminders, freeze rules, staff permissions, sign-up link, receipt channels |
| Reports (tab) | 15 reports, each two taps away, grouped: Money (revenue, 30-day forecast, cheques to clear, last-month deposits), Collection & debt (**monthly manual collection** – who still owes cash/cheque/transfer this month, debts and arrears, failed charges), Members (active and MRR, ending and renewals, joins/cancellations and churn, frozen), Links (funnel). Period chips, KPI tiles, copy to Excel |
| Sent links (live) | every payment/sign-up link with its stage – sent, opened, filled details, signed, paid, failed – filters by stage, and a live timeline that updates as the customer moves on (with a built-in live demo) |
| Business summary | one report for the whole business vs the previous period: revenue, joins/cancellations, collection rate, open debt, link conversion, 6-month trend, best sellers, what needs attention |
| Collect from reports | debts, failed charges and manual collection rows have a "Collect" button (cash / card / cheque / transfer / link / reminder) |
| Sales & invoices | every invoice-receipt with search, period / sale-type / method filters, totals with VAT, open and resend |
| Price list | desk products and services (add / edit / remove) and plan prices |
| Receipts | receipt view (with VAT split and company number), send by SMS / WhatsApp / email after every payment |
| Cheques & transfers | cheque number, bank, branch, account and first date (consecutive monthly cheques); transfer reference, bank and date – required before confirming |
| Business type | gym, studio, CrossFit, martial arts, pool, dance, beauty/pedicure, clinic, classes, kids club – each with a recommended report set; reports can be turned on/off per business |
| Help & guide | "?" on every screen (why it helps, what you get) and a searchable user guide with numbered steps and "take me there" |
| Credit notes | full or partial credit for any document (refund to card / cash / transfer, reason required); original stays unchanged; a fully credited monthly payment returns to "To collect"; option to cancel the membership |
| Customer history | member card shows total paid, open balance and every document |
| Accountant | monthly package (VAT summary, document journal with numbering check, receipts by method, cheques, credits, allocation-number alerts) and daily cash close; send to the accountant's email |
| Data | saved on the device (JSON) after every change; reset to demo data in Settings |
| Languages | Hebrew, Arabic and English (Settings → language); RTL/LTR switch, Cairo font for Arabic |
| Customer link | plan → details + health declaration + terms → card payment → active membership (previewed inside the app) |

For connecting the backend and card processing, see **[HANDOFF.md](HANDOFF.md)**.

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

In the browser (local testing only). The AURA server does not allow calls from
web pages (no CORS headers), so Chrome has to be started with that check off;
Flutter opens a separate Chrome window with its own temporary profile:

```
flutter run -d chrome --dart-define-from-file=dart_defines.json --web-browser-flag=--disable-web-security
```

Sign-in and data are kept in the browser's localStorage.

## Test APK from GitHub

Every push that touches `gym_subscriptions/` builds an APK and publishes it as the
`gym-latest` release. No secret is needed: sign-in works without one. If the optional
repository secret `AURA_VERIFY_KEY` is set, the domain screen also checks that the
business exists before showing the login screen.

The workflow file is not on the default branch, so GitHub shows no "Run workflow"
button. To build again without a code change, open the last run under Actions and
press "Re-run all jobs".
