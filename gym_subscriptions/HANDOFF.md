# AURA Gym – developer handoff

The full backend integration spec (architecture, JSON contract, endpoints, card processing, billing job, fiscal documents and Israeli tax rules, messaging, public links, roles, reports, open decisions, go-live checklist) is here:

**AURA Gym – Backend Integration Spec:** https://claude.ai/artifact/5YDdxxyVEeAsUGpRTggRzX

## Short version

| Area | Today | Backend must provide |
|---|---|---|
| Data | JSON snapshot on the device (`FileGymRepository`) | Database + REST API, server-assigned IDs |
| Card payments | Mocked | Processor hosted fields, tokens, charges, installments, refunds, webhooks |
| Monthly auto-charges | Scheduled in the app, never charged | Daily job: charge, retry per `settings.retryDays`, mark failures, entry-block flag |
| Document numbers | Assigned by the app | Server only, gap-free, in the same transaction as the document |
| Receipts / credit notes | On screen only | Stored, signed PDF per document; credit notes never change the original |
| SMS / WhatsApp / email | Logged as "sent" | Real providers behind `MessageSender` |
| Sign-up / payment link | Previewed inside the app | Public mobile web page + stage events to the app |
| Tax Authority | Large invoices flagged in the accountant report | Allocation numbers (B2B, > 5,000 ₪ before VAT from 1.6.2026); unified-format export if registered |
| Users / branches | None | Login, roles, server-side permissions, audit log, branchId |

## Code map

```
lib/main.dart                         entry point; choose the repository here
lib/src/app.dart                      AuraGymApp (standalone) + GymModule (embed in the AURA app)
lib/src/domain/models.dart            entities + toJson/fromJson = the JSON contract
lib/src/domain/checkout.dart          payment rules (amount due, split validation, cancellation date, ID/phone)
lib/src/domain/settings.dart          BusinessSettings, business types
lib/src/state/gym_store.dart          every action -> one endpoint each
lib/src/state/reports.dart            15 reports (pure functions)
lib/src/state/demo_data.dart          demo data - remove in production
lib/src/integration/repository.dart   GymRepository (load/save/clear)
lib/src/integration/payment_gateway.dart  PaymentGateway (charge/refund) + mock
lib/src/integration/messaging.dart    MessageSender + mock
test/                                 88 tests (logic + full screen flows in 3 languages)
```

## Run

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

`android/` is not committed: CI generates it with `flutter create` (see `.github/workflows/gym-apk.yml`, step "Generate the Android project"). Run the same command locally.
