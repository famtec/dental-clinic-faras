# Engineering Audit — Token-Based Activation Flow & Commercial Paywall
**Repository:** dental_project · **Domain:** https://dental-clinic-faras.onrender.com
**Scope:** `main.py` (`/api/activate`, `/api/auth/*`, `/api/patients`, `/api/appointments`, `/api/finance/*`, `/api/prescriptions/*`, `/api/inventory/*`), `models.py`, `database.py`, and `frontend_web/{index,login,register,appointments,finance,inventory,patient_record,contact_developer}.html`
**Date:** 2026-08-22
**Verdict: NOT ready for commercial deployment as-is.** Three critical defects break the activation/paywall guarantee this sprint was meant to lock down. None require a rewrite — each has a small, surgical fix — but all three should land before this is called bulletproof.

---

## 1. Summary

The token-activation mechanics themselves (`/api/activate`, the `activation_keys` table, the `TEST-PREMIUM-365` style seed data) are well built and match the spec almost exactly. The failure is not in the activation endpoint — it's in what happens *around* it: one real code bug breaks the entire Google-login path, and the server never actually checks activation status on the routes that hold the data being sold. As it stands, a `pending_activation` account — or anyone who simply knows a doctor's email — can read and write patient, appointment, financial, and prescription records without ever entering a code. That is the opposite of a monetization gate.

| # | Finding | Severity | Location |
|---|---|---|---|
| 1 | Google-login handler reads the wrong JSON keys — breaks the paywall gate *and* every API call for Google-authenticated users | **Critical** | `frontend_web/login.html:268-269` |
| 2 | Core money-making routes never check `tier` / `is_active` — only `/api/inventory/*` is actually gated server-side | **Critical** | `main.py` (`get_current_doctor_user`, all `/api/patients`, `/api/appointments`, `/api/finance/*`, `/api/prescriptions/*` routes) |
| 3 | `POST /api/patients` has no enforced authentication at all — a failed auth check is silently swallowed | **Critical** | `main.py:747-757` |
| 4 | Direct-URL bypass block on 4 of 5 sub-pages is a race condition, not a hard gate | **High** | `appointments.html:884`, `finance.html:462`, `inventory.html:437`, `patient_record.html:3416` |
| 5 | `/api/activate` failure handling discards the server's real error reason | **Medium** | `index.html:1018-1036` |

Confirmed clean: no duplicate route decorators anywhere in `main.py`; every `<script>` block across the eight audited HTML files has balanced backticks (no truncated template literals); `main.py` parses without a `SyntaxError` (`ast.parse` + `py_compile`); doctor-name branding is live and consistent across all five dashboard pages. Details below.

---

## 2. Critical findings

### 2.1 Google login stores the tier/email under the wrong keys — the paywall never engages for Google users, and every subsequent API call breaks

`frontend_web/login.html` has two separate login handlers. The email/password handler (line 333-334) is correct:

```js
localStorage.setItem("user_email", data.email || emailInput.value.trim());
localStorage.setItem("user_tier", data.tier || "standard");
```

This matches what `POST /api/auth/login` actually returns (`{"status": "success", "email": ..., "tier": ...}`, `main.py:590-594`).

The Google OAuth handler (`handleCredentialResponse`, line 268-269) does not:

```js
localStorage.setItem("user_email", data.user_email);
localStorage.setItem("user_tier", data.user_tier); // سيخزن pending_activation أو premium
```

`POST /api/auth/google` responds with the `LoginResponse` model (`main.py:414-419`), whose fields are `email` and `tier` — there is no `user_email` or `user_tier` key anywhere in that payload (verified in `main.py:668-674`). `data.user_email` and `data.user_tier` are therefore always `undefined`, and `localStorage.setItem` stringifies that to the literal text `"undefined"`.

The consequences cascade through the whole app:

- **The paywall never shows for a brand-new Google signup.** A first-time Google user is created server-side with `tier="pending_activation"` (`main.py:636`), but the client stores the string `"undefined"` instead. Since `"undefined" !== "pending_activation"`, the lock screen in `index.html:974` never triggers — this is a direct failure of Sprint requirement #2, specifically for the Google-login path.
- **Every API call after Google login sends a broken auth header.** `doctorEmail` is computed as `localStorage.getItem('user_email') || 'fareshalawi17@gmail.com'` (`index.html:257`) — but `"undefined"` is a non-empty truthy string, so the fallback never kicks in. Every subsequent request carries `X-Doctor-Email: undefined`, which resolves to no user in `get_current_doctor_user` (`main.py:461-480`) and 401s. This breaks the app for *every* Google-authenticated doctor, not just unactivated ones — including a legitimately paying premium doctor who happens to sign in with Google instead of email/password.
- **`doctor_name` is never stored for Google logins at all** (the handler doesn't set it, unlike the email/password path at line 220), even though the backend already returns it (`main.py:670`). Every Google-login doctor sees the generic fallback branding text forever, regardless of the branding logic audited in §4 being correct.

**Fix:** in `handleCredentialResponse`, change to `data.email`, `data.tier`, and add `localStorage.setItem('doctor_name', data.doctor_name || '')`.

### 2.2 The paywall is not enforced server-side on the routes that hold the paid content

Requirement #2 asks specifically for a "bulletproof" gate. The gate that exists is 100% client-side. `get_current_doctor_user` (`main.py:461-480`) — the dependency used by `/api/patients` (GET/POST), `/api/appointments`, `/api/finance/*`, `/api/prescriptions/*`, and the x-ray/archive routes — only checks that a `User` row exists with the given email. It never checks `tier`, never checks `is_active`, and never calls `ensure_user_subscription_is_active`.

`ensure_user_subscription_is_active` and the tier check do exist in the codebase — but they're only wired into `require_premium_user_by_email` (`main.py:442-458`), which gates exclusively the `/api/inventory/*` routes (`main.py:1625, 1656, 1679, 1721`). Patients, appointments, finance, and prescriptions — the actual clinical/financial core of the product — have no server-side activation check whatsoever.

Practically: any account that exists in the `users` table — including a `pending_activation` Google signup that never paid, or an account whose `subscription_expires_at` has lapsed — can call these endpoints directly (curl, browser devtools, Postman, or simply disabling JavaScript) and get full, unrestricted read/write access to every patient's record, every appointment, every financial transaction, and every prescription. The DOM-wipe lock screen only stops someone using the rendered page; it stops nothing that talks to the API directly. This is the difference between "the button is grayed out" and "the door is locked" — right now it's the former.

**Fix:** add a tier/subscription check (reuse `ensure_user_subscription_is_active`, or a lighter `require_active_user_by_email` that also rejects `tier == "pending_activation"`) as a dependency on every patients/appointments/finance/prescriptions/archive route, not just inventory.

### 2.3 `POST /api/patients` doesn't actually require authentication

Compounding 2.2: `create_patient` (`main.py:740-771`) calls `get_current_doctor_user` inside a `try/except HTTPException`, and on failure just sets `current_user = None` and **keeps going** — it creates the patient anyway, falling back to whatever `doctor_name`/`doctor_email` was in the request body:

```python
try:
    current_user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)
except HTTPException:
    current_user = None
...
if not resolved_doctor_name:
    resolved_doctor_name = (patient.doctor_email or doctor_email or "").strip().lower()
```

A request with no auth header at all, and no matching user, still succeeds — the caller just types whatever doctor name they want into the JSON body and a patient record is created under that name. This is a genuinely unauthenticated write endpoint sitting behind what's supposed to be a paid gate, and it also lets one tenant plant records under another doctor's name (data is scoped by `doctor_name` string matching, not a real foreign key to the authenticated user).

**Fix:** if `get_current_doctor_user` raises, `create_patient` should raise too (401), not silently degrade to an anonymous write.

---

## 3. High: the direct-URL bypass block on 4 of 5 sub-pages is a race, not a wall

Requirement #2 explicitly asks whether un-activated direct-URL requests to `appointments.html`, `finance.html`, `inventory.html`, and `patient_record.html` are "strictly routed back" before anything renders. `index.html` does this correctly: it synchronously overwrites `document.body.innerHTML` with the lock screen at parse time (`index.html:974-1008`), *and* the `DOMContentLoaded` handler explicitly skips `fetchPatients()` when the tier is pending (`index.html:1041`). Nothing protected ever fetches or renders.

The other four pages use a different, weaker pattern — a bare redirect placed at the very bottom of the script:

```js
window.addEventListener('DOMContentLoaded', async () => { await Promise.all([loadAppointments(), ...]); });
...
if (localStorage.getItem("user_tier") === "pending_activation") {
    window.location.href = "index.html";
}
```

(`appointments.html:880-886`, mirrored in `finance.html:452-464`, `inventory.html:422-439`, `patient_record.html:3407-3418`.)

Two problems: first, `window.location.href = ...` schedules a navigation, it doesn't halt execution — the `DOMContentLoaded` listener registered earlier in the same script still fires (usually in the same tick, since the redirect guard runs *after* the listener is already registered) and kicks off `loadAppointments()`, `loadFinanceLedger()`, `loadInventoryItems()`, or `loadPatientRecord()` before the browser has actually navigated away. Second, unlike `index.html`, there's no DOM wipe and no gating condition on the fetch calls themselves — the guard's only job is the redirect, so if the redirect loses the race (slow network waking a cold Render instance, a heavier page like the 163&nbsp;KB `patient_record.html`, etc.) the protected data has already been requested and can render. This is exactly the scenario requirement #2 asks to be "aggressively" blocked, and on these four pages it isn't — it's best-effort.

**Fix:** move the tier check to the top of each script (mirroring `index.html`'s pattern), gate the `DOMContentLoaded` data-loading calls on it, and treat the redirect as a fallback rather than the only mechanism. This is a frontend-only mitigation, though — §2.2 means the real fix has to happen server-side regardless, since a redirect can't stop a direct API call.

---

## 4. Medium: activation failures don't surface the real reason

`activateClinicAccount()` (`index.html:1011-1037`) doesn't check `res.ok` before parsing JSON, and only branches on `data.status === "success"`. Every failure path — wrong code, already-used code, no matching user account, or a genuine 500 from the DB — collapses into one generic alert ("كود التفعيل غير صحيح أو مستخدم مسبقاً"), even though `/api/activate` already returns a specific, correct `detail` message for each case (`main.py:1939, 1948, 1963, 1988`). Not a security issue, but it throws away diagnostic information the backend is already producing, which will make support/debugging harder once this is live with real customers.

**Fix:** branch on `res.ok`, and show `data.detail` (falling back to the generic message only if `detail` is missing).

---

## 5. Confirmed correct / clean

- **`/api/activate` core logic** (`main.py:1933-1988`): input validation, DB lookup against `models.ActivationKey` (not a hardcoded list — good, avoids the typo-prone duplicated-list anti-pattern), `is_used` check, `target_tier` derivation (duration ≥ 365 days or a `PREMIUM`/`VIP` substring → `premium`, else `standard`), user lookup, and the actual `tier`/`subscription_expires_at`/`is_active` update are all correct and wrapped in `try/except` with `db.rollback()` on failure. `TEST-PREMIUM-365` is genuinely seeded at 365 days (`main.py:58`) and correctly resolves to `premium`.
- **Doctor-name branding** is live and consistent on `index.html`, `appointments.html`, `finance.html`, `inventory.html`, `patient_record.html`, and `contact_developer.html`, reading `localStorage.getItem('doctor_name') || localStorage.getItem('user_name')` with a shared fallback string. (Note: because of §2.1, this binding is currently silently starved for any doctor who only ever logs in via Google — fixing 2.1 fixes this too, no separate change needed.)
- **Code hygiene**: no duplicate `@app.get/post/put/delete` decorators anywhere in `main.py`; all `<script>` blocks in the eight audited HTML files have an even number of un-escaped backticks (no truncated template literals); `main.py` parses cleanly under both `ast.parse` and `py_compile` — no stray Arabic comment fragments breaking the runtime were found.
- **Out of scope, not audited**: `chart.html` and `qr.html` were not part of the five pages named in this sprint's brief and were not staged/reviewed here — if either of them renders patient or financial data, they should get the same server-side check from §2.2 and a look at whether they need the same client-side gate as §3.

---

## 6. Recommended fix order

1. Fix the `login.html` Google-handler key mismatch (§2.1) — one-line change, unblocks the entire Google-auth path.
2. Add a real tier/subscription dependency to every patients/appointments/finance/prescriptions/archive route (§2.2) — this is the actual monetization gate; everything else is decoration until this lands.
3. Make `create_patient` fail closed instead of open when auth resolution fails (§2.3).
4. Bring `appointments.html`/`finance.html`/`inventory.html`/`patient_record.html`'s bypass guard up to `index.html`'s standard (§3) — belt-and-suspenders once #2 is server-enforced.
5. Surface real `/api/activate` error details in the UI (§4) — low priority, whenever convenient.

None of this requires touching the schema or rearchitecting the activation table — it's a small, well-scoped punch list. Once items 1–3 are in, the "bulletproof commercial paywall" claim will actually be true; right now it describes the UI, not the system.
