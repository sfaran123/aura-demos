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
