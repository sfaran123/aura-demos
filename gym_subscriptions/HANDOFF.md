# AURA Gym – מסמך העברה למפתח

המסמך מסביר מה בנוי, מה מדומה, ומה צריך לחבר לבאקאנד ולסליקה של AURA.

---

## 1. מצב נוכחי

| נושא | מצב |
|---|---|
| קוד | Flutter (Dart 3.6+), כ-90 קבצים. הקוד נבדק עם Flutter 3.47.9 |
| בדיקות | **88 בדיקות** (לוגיקה + מסכים), כולן עוברות. `flutter analyze` נקי |
| CI | `.github/workflows/gym-apk.yml`: analyze, test, build APK, release `gym-latest` |
| שפות | עברית (מקור), ערבית, אנגלית: `lib/src/domain/l10n_strings.dart` |
| נתונים | נשמרים כקובץ JSON במכשיר (`FileGymRepository`). **עדיין אין שרת** |
| סליקה | מדומה. אין חיבור לחברת סליקה |
| SMS / WhatsApp / מייל | מדומה. נרשם במסמך כ"נשלח", אבל שום הודעה לא יוצאת |

---

## 2. מבנה הקוד

```
lib/
  main.dart                    נקודת כניסה. כאן בוחרים repository
  src/app.dart                 AuraGymApp (עצמאי) + GymModule (להטמעה באפליקציית AURA)
  src/domain/                  Dart טהור, בלי Flutter
    models.dart                כל הישויות + toJson/fromJson  ← חוזה הנתונים
    settings.dart              BusinessSettings + סוגי עסק
    checkout.dart              חוקי תשלום: paymentProblem, subscriptionDueNow, cancelEffectiveDate…
    l10n.dart / l10n_strings   t('עברית') → ערבית/אנגלית
    help.dart / guide.dart     תוכן "?" ומדריך למשתמש
  src/state/
    gym_store.dart             כל הפעולות (פתיחת מנוי, גבייה, זיכוי…) + שמירה
    reports.dart               15 דוחות, כל אחד פונקציה טהורה GymStore → ReportData
    demo_data.dart             נתוני הדגמה (חצי שנה). לא בשימוש בגרסה מחוברת
  src/integration/             ← נקודות החיבור
    repository.dart            GymRepository: load / save / clear
    payment_gateway.dart       PaymentGateway: charge / refund (+ Mock)
    messaging.dart             MessageSender: SMS / WhatsApp / email (+ Mock)
  src/ui/                      מסכים. מדברים רק עם GymStore
test/
  domain_test.dart             לוגיקה, דוחות, זיכויים, שמירה
  app_flow_test.dart           זרימות מסך מלאות בשלוש השפות
```

**עיקרון:** המסכים לא יודעים מאיפה הנתונים מגיעים. כל שינוי עובר דרך `GymStore`. בגרסה המחוברת `GymStore` (או מחליף שלו) קורא ל-API במקום לשנות רשימות בזיכרון.

---

## 3. מה צריך לחבר

### 3.1 שרת ונתונים
- **היום:** `GymStore(repository: FileGymRepository.onDevice())` שומר snapshot מלא 0.4 שניות אחרי כל שינוי.
- **לחיבור:** להחליף בגישה מבוססת API: טעינה ראשונית ואז פעולה לכל action (טבלה 4). שמירת snapshot שלם מתאימה רק לדמו.
- **חוזה הנתונים:** `GymStore.toJson()` ו-`toJson()` של כל מודל. השדות והשמות מוכנים לשימוש כ-DTO.
- **מזהים:** היום נוצרים בצד הלקוח (`_next('c')`). בגרסה המחוברת השרת צריך להחזיר אותם.
- **ריבוי סניפים, משתמשים והרשאות:** לא קיים. `settings.staffCanRefund` ו-`staffMaxDiscountPct` מוכנים לחיבור להרשאות אמיתיות.

### 3.2 סליקת אשראי
- **הזנת כרטיס:** `ui/checkout/card_sheet.dart` הוא מקום-שומר לשדה המאובטח (Hosted Fields / iframe) של חברת הסליקה. **האפליקציה לא שומרת ולא מעבירה מספר כרטיס.** מהסולק צריך לקבל `token` ו-4 ספרות אחרונות בלבד (PCI-DSS).
- **שמירת token:** `Customer.savedCardLast4` מוצג למשתמש. ה-token עצמו צריך להישמר רק בשרת.
- **ממשק:** `PaymentGateway` (`charge` עם תשלומים, `refund` לפי `transactionId`). כל `PaymentLine` של אשראי מחזיק `transactionId`, שהוא בסיס להחזר.
- **חיוב חודשי אוטומטי:** צריך job בשרת שמחייב את `Charge` עם `status=due` ו-`manual=false` בתאריך שלהם.
  - אם החיוב נכשל: `status=failed` ו-`attempts++`.
  - ניסיונות חוזרים לפי `settings.retryDays` / `retryAttempts`.
  - חסימת כניסה אחרי `graceDays`. החוק כבר קיים ב-`GymStore.entryBlocked`.
- **הוראת קבע בבנק:** `RecurringMethod.standingOrder` מוגדר. צריך ממשק מס"ב או מה שהבנק מספק.
- **לינק לתשלום:** `SignupLink`. היום זרימת הלקוח (`ui/links.dart` → `CustomerLinkFlow`) מוצגת בתוך האפליקציה. בפועל צריך דף ווב ציבורי. השלבים `opened / details / signed / paid / failed` צריכים להגיע ב-push או ב-websocket, ו-`linkStage()` מקבל אותם.

### 3.3 מסמכים חשבונאיים (חובה רגולטורית)
- **מספור:** מספר מסמך חייב להיות רץ, ייחודי ובלי חורים. היום הוא נוצר בצד הלקוח (`_receiptNo`). **בגרסה מחוברת רק השרת מקצה מספרים.**
- **אי-שינוי:** מסמך שהופק לא נמחק ולא משתנה. ביטול נעשה רק בחשבונית זיכוי (`GymStore.credit`), כבר עכשיו.
- **סוג מסמך:** `DocType.taxInvoiceReceipt` (חשבונית מס קבלה) או `receipt` (עוסק פטור). ח.פ/ע.מ נמצא ב-`settings.businessId` ומודפס על המסמך.
- **PDF:** צריך להפיק PDF חתום לכל מסמך בשרת, ולשלוח לינק אליו ב-SMS, ב-WhatsApp או במייל (`MessageSender`).
- **חשבוניות ישראל (מספר הקצאה):**
  - מ-1.6.2026 חשבונית מעל **5,000 ₪ לפני מע״מ** ללקוח עסקי צריכה מספר הקצאה מרשות המסים.
  - השדה `Receipt.allocationNumber` קיים, והדוח לרואה חשבון מסמן חשבוניות מעל הסף.
  - **חסר:** שדה "לקוח עסקי / ח.פ לקוח" ב-`Customer`, ובקשת המספר מה-API של רשות המסים.
  - הסף מוגדר ב-`allocationThreshold` בקובץ `reports.dart`.
- **מבנה אחיד (BKMVDATA / INI.TXT):** אם התוכנה תירשם כתוכנה להנהלת חשבונות, צריך ייצוא במבנה אחיד לפי הוראות רשות המסים. זה לא קיים, והמקום הנכון לבנות אותו הוא השרת.
- **ייצוא לרואה חשבון:** היום הדוח מועתק כ-CSV ללוח. צריך קובץ Excel/PDF במייל ל-`settings.accountantEmail`.

### 3.4 הודעות
`MessageSender.send(channel, to, text, receiptPdfUrl)` משמש לקבלות, לתזכורות גבייה (`remind`), ללינקים (`sendChargeLink`, `sendSignupLink`) ולתזכורת חידוש. **הודעות WhatsApp עסקיות דורשות תבניות מאושרות מראש.**

---

## 4. פעולות ← endpoints מוצעים

| פעולה ב-`GymStore` | מה היא עושה | endpoint מוצע |
|---|---|---|
| `addCustomer` | לקוח חדש | `POST /customers` |
| `savePlan` | מסלול חדש/עריכה | `PUT /plans/{id}` |
| `saveItem` / `removeItem` | מחירון | `PUT/DELETE /items/{id}` |
| `openSubscription` | מנוי + חיוב ראשון + קבלה + חיוב חודשי הבא | `POST /subscriptions` |
| `quickPay` | מכירה מהירה + קבלה | `POST /sales` |
| `collect` | גביית חיוב חודשי (מזומן/שיק/העברה/אשראי) | `POST /charges/{id}/collect` |
| `credit` | חשבונית זיכוי + החזר + ביטול מנוי אופציונלי | `POST /documents/{no}/credit` |
| `freeze` / `unfreeze` | הקפאה | `POST /subscriptions/{id}/freeze` |
| `cancel` | ביטול לפי הודעה מוקדמת/התחייבות/חודש מראש | `POST /subscriptions/{id}/cancel` |
| `sendSignupLink` / `sendChargeLink` | לינק הרשמה/תשלום | `POST /links` |
| `linkStage` | עדכון שלב לינק (מהשרת) | push / websocket |
| `completeSignup` | הלקוח סיים בלינק | webhook מהסולק → שרת |
| `remind` | תזכורת גבייה | `POST /charges/{id}/remind` |
| `sendReceipt` | שליחת מסמך | `POST /documents/{no}/send` |
| דוחות (`reports.dart`) | מחושבים מהנתונים | אפשר להשאיר בלקוח, או לחשב בשרת לנתונים גדולים |

**חוקים עסקיים שצריך לשמור** (חלקם עם בדיקות):
- `checkout.dart`: חישוב סכום לתשלום (כולל דמי רישום והחודש האחרון מראש), תנאי תשלום מפוצל, מועד ביטול לפי התחייבות והודעה, ת"ז, טלפון.
- `GymStore._schedule`: לא מתזמנים חיוב אחרי תאריך הביטול. החודש האחרון של מנוי "חודש אחרון מראש" מסומן `covered`.
- `GymStore.cancel`: אם שולם חודש אחרון מראש, הוא תמיד החודש האחרון.
- `GymStore.credit`: זיכוי מלא על תשלום חודשי מחזיר את החיוב ל"לגבייה". אין זיכוי מעבר ליתרה. אין זיכוי על זיכוי.

---

## 5. הרצה ובדיקות

```bash
flutter pub get
flutter analyze
flutter test                 # 88 בדיקות
flutter run                  # או: flutter build apk --release
```
- **תיקיית android/:** לא נשמרת ב-repo. ה-CI מייצר אותה עם `flutter create`. כדי לעבוד מקומית מריצים את אותה פקודה (בשלב "Generate the Android project" בקובץ ה-workflow).
- **נתוני הדגמה:** הגדרות ← "איפוס לנתוני הדגמה" מחזיר אותם.
- **הטמעה באפליקציית AURA:** משתמשים ב-`GymModule(store: …)` בתוך ה-route שלכם. אין צורך ב-`AuraGymApp`.

---

## 6. פתוח, להחלטת בעל העסק / המפתח

1. **סליקה:** איזו חברת סליקה? צריך את ה-SDK או ה-API שלה ל-Hosted Fields, ל-token, לתשלומים ולהחזרים.
2. **ספק הודעות:** איזה ספק SMS ואיזה חשבון WhatsApp Business?
3. **רשות המסים:** האם התוכנה תירשם כתוכנה להנהלת חשבונות (מבנה אחיד)? ומי מבקש מספרי הקצאה: המערכת הזו או מערכת הנהלת החשבונות הקיימת?
4. **כניסה למועדון:** חיבור לבקר כניסה או ברקוד. החוק `entryBlocked` כבר קיים.
5. **הרשאות:** אילו פעולות מותרות לעובד ואילו רק לבעלים (זיכוי, הנחה, ויתור על דמי רישום, איפוס)?
6. **ריבוי סניפים:** האם נתונים, מחירון ומסלולים משותפים או נפרדים לכל סניף?
