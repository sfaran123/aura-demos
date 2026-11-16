# AURA Gym app — card APIs: what exists, and the charge that is missing

For Ashfak. The Flutter app talks only to the AURA Laravel server; the server talks to Z-Credit.
All paths are under `https://<company>.<domain>/api`, header `token: <login token>`, JSON bodies.

**Short version:** saving a card token works. A charge API for a saved token **already exists**
on the server (the POS app uses it), but the Gym app does not call it: its desk checkout only
*records* a card payment. What is left is to connect the Gym app to the existing charge, plus two
small server changes (Part 2).

---

## Part 1 — What exists today (built by Tahsin, used by the app)

### 1. Save / replace a member's card — `POST gym/members/{customer_id}/card`

```json
{ "card_number": "4580000000009435", "cvv": "123", "card_expiry_date": "08/29" }
```

Answer (200):

```json
{ "data": { "id": 1, "has_saved_card": true, "card_last4": "9435" } }
```

The server runs the web's `HomeController::checkCard` (the same check as `check-card-credentials`:
a Z-Credit J2 check, nothing is charged) and keeps the token on the customer. The app never
receives the token, only the last four digits.

Errors — an HTTP error whose `message` is one of these codes:

| `message` | Meaning |
| --- | --- |
| `card_not_valid` | Z-Credit did not approve the card |
| `card_terminal_missing` | No Z-Credit terminal in the web's general settings |
| `card_service_unreachable` | Z-Credit could not be reached |

### 2. Create a membership billed monthly by card — `POST gym/memberships`

```json
{ "customer_id": 1, "plan_id": 81, "start_date": "2026-11-15", "discount_percent": 0,
  "registration_waived": false, "recurring_method": "credit_card" }
```

The server copies the member's saved token onto the membership (`has_card_token: true` in the
answer) and its scheduler charges it from `next_payment_date`. **Nothing is charged by this call.**

### 3. Replace the card of a membership — `POST gym/memberships/{id}/card`

Same body as 1. Answer: the membership (`data`) and `failed_months` (months that failed and can
now be charged). Extra error code: `not_card_billed` (the membership is not billed by card).

### 4. Charge failed months to the membership's card — `POST gym/memberships/{id}/pay-failed-months`

```json
{ "months": ["2026-10|10", "2026-11|10"] }
```

Answer: `data` (the membership), `document` (`reference_no`, `grand_total`), `remaining_months`.
A decline is HTTP 422 with the card company's text as `message`.
**This is the only call in the app today that really charges a saved token.**

### 5. Monthly charge

Server-side scheduler. The app does not call anything.

### What only *records* a card payment (no charge)

- `POST sales/store-v2` with `paid_by_ids: "3"` and `all_receipt: "other_device"` — the POS meaning:
  "the card was charged on a separate terminal". Used by the desk checkout (new membership,
  quick pay).
- `POST gym/memberships/{id}/collect` with `"method": "card"` — the same meaning, for a failed
  month or a manual monthly payment.

Tested on 15 Nov 2026 (business `aurademo1`): new membership 70, card saved (call 1 answered 200),
sale 6020 / `TIN-81786` for 389 saved as paid by card with an empty transaction reference.
No call asked Z-Credit to charge, and no answer carried any Z-Credit data.

---

## Part 2 — The charge that already exists (POS app), and what the Gym app needs

### 2.1 The existing charge — `GET sales/call-credit-card-api`

Server: `SaleController::callCreditCardAPIForApp`. The POS app calls it from
`lib/services/zcredit_api_service.dart`:

```
GET /api/sales/call-credit-card-api
      ?amount=389
      &context=<unique string per attempt>
      &type=existing_card          (also: regular, credit = installments)
      &token=<the customer's zcredit_token>
      &no_of_payment=1
      &user_id=1
```

- `type=existing_card`: the server sends `token` to Z-Credit as the card number, so the saved card
  is charged with no pinpad.
- A negative `amount` is a refund (Z-Credit transaction type 53).
- The answer is Z-Credit's own JSON: `HasError`, `ReturnCode`, `ReturnMessage`, `ReferenceNumber`, …
  `HasError: false` = approved. `ReturnCode -50008` = cancelled on the pinpad.
- The POS app then saves the sale with `sales/store-v2`, putting that answer as the `receipt` of
  the card payment row (instead of `"other_device"`).
- The POS app reads the token from the customer it loaded (`zcredit_token` on the customer object).

### 2.1.1 BUG found on 15 Nov 2026 — `existing_card` with one payment is refused

The Gym app now calls this API. A real test (business `aurademo1`, card ending 9435, 389 ₪):

```
GET /api/sales/call-credit-card-api?amount=389&context=<uuid>&type=existing_card&token=<token>&no_of_payment=1&user_id=1

-> 200 { "HasError": true, "ReturnCode": 404, "ReturnMessage": "לא הוזן שדה מספר תשלומים",
         "Card4Digits": "9435", "CardName": "מסטרקארד רגיל", "ReferenceNumber": 112007298,
         "ApprovalNumber": "",
         "IntOt_JSON": { "ashStatus": "404", "amount": "38900", "tranType": "01",
                         "creditTerms": "6", "noPayments": "0", "firstPayment": "0", ... } }
```

Z-Credit found the token (card name and digits came back), but the transaction was sent with
`creditTerms: 6` ("credit" deal) and `noPayments: 0`, so it answers "number of payments field
was not entered". Nothing was charged.

**Fix needed in `SaleController::callCreditCardAPIForApp` for `type=existing_card`:**

- `no_of_payment = 1` → a regular deal: `CreditType = 1`, no payments fields.
- `no_of_payment > 1` → installments: `CreditType = 8` with `NumberOfPayments`,
  `FirstPaymentSum`, `OtherPaymentsSum` (or `CreditType = 6` with `NumberOfPayments` if the
  business really wants a "credit" deal — that is a different product for the cardholder).

Today the app's value of `no_of_payment` does not seem to reach Z-Credit at all (it sent 1, Z-Credit
shows 0).

### 2.2 What the Gym app will do (app side, no new endpoint needed)

At the desk, for a card payment with the member's saved card:

1. `GET sales/call-credit-card-api` with `type=existing_card` and the member's token.
2. Declined or failed: show Z-Credit's `ReturnMessage`, save nothing.
3. Approved: `POST sales/store-v2` with Z-Credit's answer as the payment's receipt, then
   `gym/memberships/{id}/link-sale` as today.

### 2.3 What the app needs from the server for that

1. **The token, or a way not to need it.** `gym/members` answers only `has_saved_card` and
   `card_last4`. Either add `zcredit_token` there (as the POS customer list has), or — better —
   let `call-credit-card-api` accept `customer_id` (and `subscription_id`) and look the token up on
   the server, so the token never leaves it.
2. **No double charge.** `context` is unique per attempt today. If the app's answer is lost and it
   retries, a second charge is possible. Please make the server refuse a second approved charge
   for the same `app_uuid` / sale.
3. **Use POST** for the charge if possible: a GET puts the token and amount in access logs.

### 2.4 Still missing on the server

- Collecting a failed month or a manual monthly payment with the saved card:
  `gym/memberships/{id}/collect` with `"method": "card"` only records it. It could take the
  Z-Credit answer as a receipt the same way, or charge on the server (`"method": "saved_card"`).
- A refund that also issues the credit document for a gym sale.

---

## Part 3 — Two security points found while tracing

1. `POST login` answers the whole user row, including the Z-Credit terminal number, the terminal
   password, the pinpad track data and the AnyDesk id. A phone app must not receive these: please
   return only what the app uses (`id`, `name`, `email`, `company_name`, `role_id`, `warehouse_id`,
   `biller_id`, and the token).
2. If the web calls `check-card-credentials` with `card_number` and `cvv` in the URL query, they end
   up in server and proxy access logs. They should be sent in a POST body.

The app sends the card number and CVV to the AURA server (calls 1 and 3). That puts the server in
PCI DSS scope; Z-Credit's hosted fields / iframe would remove that. Not urgent for a test, worth
deciding before customers.
