# Backend work the app is waiting for

For Tahsin. Two areas changed in the app and need the server: **check-in (visits)** and the
**collection list**. The app already calls the endpoints below; where one is missing (HTTP 404)
it falls back as described, so nothing breaks before the server is ready.

All paths are under `/api`, with the usual `token` header.

---

## 1. Check-in (new "Check-in" tab)

What the desk does: finds a member by name or the last digits of the phone, touches the row, and
the visit is recorded. A punch card loses one entry. A visit recorded by mistake can be taken back
(from the confirmation, from today's list, or from the member card) and the entry comes back.

Until the server has these endpoints the app keeps visits **on the device only**: another device
and the web do not see them, and `entries_remaining` on the server does not change.

### 1.1 Record a visit — `POST gym/memberships/{id}/visits`

Body:

```json
{ "force": false }
```

`force: true` means the desk decided to let in a member the rules stop (see 1.4). Please save the
flag on the visit so it can be reported.

Answer:

```json
{
  "data": { "id": 41, "subscription_id": 6, "customer_id": 8, "created_at": "2026-11-11 09:31:00" },
  "entries_remaining": 6
}
```

- For a punch card: take one entry off and answer the new `entries_remaining`.
- For a membership without entries: `entries_remaining: null`.
- Any HTTP error other than 404 is shown to the desk and nothing is recorded in the app.

### 1.2 Take a visit back — `POST gym/visits/{id}/cancel`

Body: `{}`. Answer:

```json
{ "entries_remaining": 7 }
```

A punch card gets its entry back. Please soft-delete (keep who cancelled and when).

### 1.3 List visits — `GET gym/visits?from=YYYY-MM-DD`

The app asks for the last 60 days on every sync (today's list, the weekly limit, the member's
history). Cancelled visits are not in the list.

```json
{
  "data": [
    { "id": 70, "subscription_id": 6, "customer_id": 8, "created_at": "2026-11-11 07:15:00" }
  ]
}
```

If this becomes large, add paging as in `gym/sales` (`page`, `last_page`) and tell me.

### 1.4 The rules (the app applies them; the server should too when `force` is false)

Blocked — not recorded unless `force`:

| Case | App message |
| --- | --- |
| No running membership | No membership / The membership has ended |
| Status `frozen` | The membership is frozen until … |
| Status `awaiting_payment` | The membership is waiting for payment |
| End date passed | The membership ended on … |
| Punch card with 0 entries | The punch card is used up |
| `weekly_entry_limit` reached (week starts on **Sunday**) | All N of this week's visits are used |
| A payment overdue past the grace days, when the business blocks entry | Entry blocked: a payment is overdue |

Recorded with a warning: last entry on the card, an open payment, a membership ending within 7 days.

A member with several running memberships: the desk picks the membership, so the visit always
arrives with the membership id in the path.

A second visit on the same day is allowed (the app asks the desk first).

### 1.5 Not built in the app yet (tell me if you want them in the same round)

- A visit recorded for an earlier time ("forgot to record yesterday"): `created_at` in the POST body.
- Changing the entries of a punch card by hand (a free entry, a correction).
- An attendance report: members who did not come for 30 days, busy hours.

---

## 2. Collection list ("To collect")

Decided with the business owner: the list holds **only** (a) monthly card charges that failed and
(b) monthly payments in manual collection. No tax invoice-receipts / unpaid membership documents.

What the app does today on its own, so you know what you will see:

- Drops `kind: "unpaid_invoice"` from `gym/dashboard` `debts` and takes their amounts off `open_debt`.
- Shows one row per failed **month**, not one per try: the tries of a month (same `month_key`,
  else the same calendar month) are grouped; the row opens the list of tries.
- Counts as debt only failed charges of the **last 3 months** of memberships that are **not**
  cancelled or ended. Older ones go to a folded "Old debts" section, outside the totals.
  A business that worked for years on the web otherwise shows a meaningless total.
- One row per member when several months failed.

### 2.1 What I need from the server

1. `gym/dashboard`: `debts` with only `failed_charge` and `manual_due`, and `open_debt` as their
   sum. Best: one item per failed month (not per try), with `subscription_id` and `date`.
   The app's total is exact only if `debts` is the **full** list behind `open_debt`.
2. `gym/memberships` → `failed_payments`: keep `month_key` on every item, and if possible send the
   tries of a month as a list (`date`, `message`) so the app can show each try. Today the app
   shows whatever items it gets.
3. **Write off a failed month** ("do not collect"): e.g. `POST gym/memberships/{id}/failed-payments/{month_key}/dismiss`
   with an optional `reason`. The month leaves `failed_payments` and the dashboard.
4. **One-time clean-up for a business that joins**: dismiss every failed charge before a date the
   owner picks, e.g. `POST gym/failed-payments/dismiss-before` `{ "date": "2026-08-01" }`.

When 1 is done I will remove the app-side filtering of `unpaid_invoice`; the 3-month window stays
until 3 and 4 exist.

---

## 3. Small things to know

- The bottom bar has a new second tab, so the tab numbers moved: Home 0, Check-in 1, Members 2,
  To collect 3, Reports 4, Settings 5.
- Sign-out keeps the visits that exist only on the device (the same business signs in again);
  a different business signing in removes them.
- Tests: `flutter test` — 246 passing. The check-in tests are in `test/checkin_test.dart` and show
  the exact requests and answers the app expects.

---

## 4. Cancel and refund: the documents that must be made (owner's rule, 16 Nov 2026)

- **Cancelling a receipt** (exempt dealer, type 3): a **minus receipt** for the whole amount must be
  issued. Today `POST gym/sales/{id}/cancel` answers `cancel_mode: "direct"` with `document: null`
  and no minus receipt.
- **Cancelling a tax invoice-receipt**: a **credit invoice (TIC)** for the whole document **and a
  minus receipt** for the money given back (cash, transfer or terminal).
- **Refund to the card** (`POST gym/sales/{id}/card-refund`): Z Credit refund, then a **TIC and a
  minus receipt**. Reported on 16 Nov: a card refund from the app left no TIC and no minus receipt.

What the app reads from the answer, so it can show the numbers to the desk:

```json
{ "data": { "document": { "reference_no": "TIC-90003" },   // or "tic": "TIC-90003"
            "receipt":  { "reference_no": "R-50007" } } }   // or "receipt": "R-50007" / "minus_receipt"
```

When a document that must exist is missing from the answer, the app now tells the desk
("the server did not return a minus receipt / a credit invoice. Check in AURA") instead of
saying everything is done.

## 5. Other things the app now sends or expects

- `POST gym/memberships/{id}/collect` may carry `card_receipt` (Z Credit's answer) and `app_uuid`
  when the desk collected with the member's saved card: the app first charges with
  `POST gym/card-charges` (same `app_uuid`), then records the payment. Please save the receipt on
  the payment and link the charge to the document (`gym/card-charges/link` is called after).
- `POST gym/members/{id}` `{ name, phone_number, tax_no, email }`: edit a customer. If it does not
  exist yet the app says so and changes nothing.
- Draft sales: `gym/sales` rows and `gym/dashboard` `recent_payments` should carry `sale_status`
  (3 = POS draft, 5 = ERP draft) or `is_draft`; the app leaves drafts out of the sales list and of
  "recent payments". Best: do not send drafts at all, and leave them out of `revenue_today`.
- Products and prices: the owner wants to manage them from the app. There is no endpoint, so
  signed in the price list is read-only (an edit there used to be lost at the next sync, and a
  sale could go out with a price the server does not have). Needed: create / update / deactivate
  a product (`gym/products`, `gym/products/{id}`), as `gym/plans` does for plans.

---

## 6. Cards and debts: three tasks built in the app (18 Nov 2026)

The app side is done and tested against a fake server (`test/cards_and_debts_test.dart` shows the
exact requests and answers). Every new endpoint is optional for the app: on HTTP 404 it falls back
or tells the desk "not available on the server yet", so nothing breaks before you build it.

Rule for all of them: **the app never keeps a card number or CVV**. It sends them once to the
server, the server gets a Z Credit token and keeps only the token. Answers carry `last4`, `brand`,
`expiry` only.

### 6.1 Several saved cards per customer

`gym/members` rows (and every answer below) may carry:

```json
"cards": [
  { "id": 11, "last4": "4815", "brand": "Visa", "expiry": "08/27", "is_default": true },
  { "id": 12, "last4": "2222", "brand": "Mastercard", "expiry": "01/29", "is_default": false }
]
```

Without `cards` the app shows the one card of `has_saved_card` / `card_last4`, as today.

| Action | Request | Answer |
| --- | --- | --- |
| Add a card (the others stay) | `POST gym/members/{id}/cards` `{card_number, cvv, card_expiry_date, make_default}` | `{ "data": { "cards": [...] } }` |
| Set the default | `POST gym/members/{id}/cards/{card}/default` `{}` | same |
| Remove | `POST gym/members/{id}/cards/{card}/delete` `{}` | same (`cards` may be empty) |
| Remove the single card (old model) | `POST gym/members/{id}/card/delete` `{}` | same |

- Errors as the existing card endpoint: `card_not_valid`, `card_terminal_missing`,
  `card_service_unreachable`.
- **Recurring charges go to the default card.** Today a membership keeps its own token
  (`gym/memberships/{id}/card`); please decide whether the membership follows the customer's
  default or keeps its own, and tell me. Optional: when the default fails, try the next card.
- The app asks the desk to confirm before removing the last card of a customer with an active
  card-billed membership; the server may also refuse with a code if you prefer.
- `POST gym/card-charges` gets an optional `card_id` (which saved card to charge). The app sends it
  only when the server listed cards with ids. Without it: the default card.

### 6.2 A debt paid with a new card (the saved card is not changed)

1. `POST gym/card-charges/new-card`
   `{customer_id, amount, payments, app_uuid, card_number, cvv, card_expiry_date}`
   → `{ "receipt": "<Z Credit answer>", "card_last4": "1111" }`.
   Charge through Z Credit, keep the token **with the charge** (not on the customer). The same
   `app_uuid` again must never charge twice. Errors as `gym/card-charges`
   (`card_declined: <Z Credit text>`, `charge_unknown`, …): the app shows the text, records
   nothing, keeps the debt open and lets the desk try another card.
2. The app then records the payment as today (`collect` / `collect-months` with `card_receipt` and
   `app_uuid`) and calls `gym/card-charges/link`.
3. The desk is asked "save this card?". On yes:
   `POST gym/card-charges/save-card` `{app_uuid, make_default: false}` → `{ "data": { "cards": [...] } }`.
   The token of that charge becomes a saved card; the default does not change (unless there was none).

A separate path on purpose: an older server that ignored the card fields on `gym/card-charges`
would charge the saved card instead.

**Log of attempts.** Please log every card charge try (success or not) and return them, newest
first: `GET gym/members/{id}/card-charges` →
`{ "data": [ { "created_at", "amount", "payments", "card_last4", "status": "success|failed", "message" } ] }`.
The customer page shows the list when it is not empty.

### 6.3 Several unpaid months in one payment

The customer page and the collection list let the desk tick months, see the total and pay once.

`POST gym/memberships/{id}/collect-months`

```json
{
  "method": "cash",               // cash | card | cheque | bank (+ the same detail fields as collect)
  "amount": 358.2,
  "months": [
    { "month_key": "2026-09|10", "amount": 179.1 },   // or "due_date": "2026-09-10" for a manual month
    { "month_key": "2026-10|10", "amount": 179.1 }
  ],
  "card_receipt": "...", "app_uuid": "..."            // when a card was charged from the app
}
```

→ `{ "document": { "reference_no": "TIR-…", "grand_total": 358.2 } }`: **one** document with a
line per month, all the months cleared, or nothing at all when it fails.

- A card: the app charges **once** for the whole amount first (`gym/card-charges` or
  `…/new-card`), and only then calls this. A charge that fails records nothing.
- Without this endpoint (404) the app records each month with `collect` (one document per month),
  with the same `card_receipt` on each and the `app_uuid` on the first only.
- Failed months of a card-billed membership, default card, one payment: the app still uses your
  `pay-failed-months`, as before.
- Not built: a partial payment applied to the oldest month first. Tell me if you want it.

### 6.4 Found live on 2026-11-19 (card charged, payment not recorded)

- `POST gym/memberships/{id}/collect-months` answers **405** today (a GET route matches the path),
  not 404. The app now treats 405 like 404 and falls back to `collect` per month.
- Before that fix, one real charge was left without a document: customer 54, membership 17,
  354 (3 months x 118, 4 payments), `gym/card-charges` `app_uuid`
  `8835cc93-c3d5-461a-bf87-1eae21771b55`, 2026-11-19 06:30:47. Please either record the three
  months (2026-08, 2026-09, 2026-10) against that charge or cancel the charge.
- While that charge is unlinked, every new `gym/card-charges` for the customer answers
  `409 already_charged`. Please return the open charge in that answer
  (`app_uuid`, `amount`, `receipt`), so the app can finish recording it instead of only blocking.

### 6.5 Urgent, found live on 2026-11-19: one document for several months

The business wants **one tax invoice-receipt** when several unpaid months are paid together, with
**a line per month that says what it is** (for example "Monthly plan · 05/2026 · 375").

- `POST gym/memberships/{id}/collect-months` (section 6.3) is the endpoint for that. It answers 405
  today. Each item of `months` now also carries `description` (plan name and month): please use it
  as the line's text on the document.
- The app asks first whether the endpoint exists by posting `{"months": []}`: please answer that
  with a 422 (validation), not 404/405, and record nothing.
- Until it exists the app warns that a document per month will be made, and the desk can cancel.

Data to repair by hand (the app cannot do it):

- Membership 16 (customer 48): on 2026-11-19 the app recorded six months by bank transfer
  (reference 34941, bank 12) as six documents, the last one TIN-80449 (id 1470). The owner deleted
  those documents on the web. The failed months `2026-05|53` … `2026-10|53` are cleared and
  `payments_done` went up by six: please put those six months back as unpaid (or record them
  on one document of 2250), so the owner can pay them once with one document.
