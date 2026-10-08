# Server-driven prices, packages & assignments

From app version **2.2.0**, package names, prices, features and **who every
booking is assigned to** live in Supabase, not in the app. You change them in
the Supabase dashboard and every customer sees the change within ~5 minutes,
with no app update and no App Store / Play Store review.

```
App ──quote / create / confirm──▶ booking-api (Edge Function)
                                     │  reads services, pools, overrides
                                     │  creates the Razorpay order for ITS price
                                     │  after payment: inserts the booking
                                     ▼  + assigns garage / delivery / washer
                            bookings · pollution_booking · inspection_booking
                            claim_table · monthlywash_table · fleet_pickup_requests
Razorpay ──webhook──▶ razorpay-webhook  (backup: books it even if the phone dies)
```

The app **never sends a price**. A modified app can't pay ₹1 for a ₹3,999
service, and a payment can't end up without a booking.

---

## 1. Deploy (once)

> Ship build 18 to Apple first. Deploy this as the next release (2.2.0).
> Old app versions keep working: nothing they use was removed.

1. **Database.** In Supabase, go to SQL Editor and run
   `supabase/migrations/20261009000000_server_catalog.sql`
   (or run `supabase db push`). It's safe to run twice.
2. **Check the seeded routing.** In Table Editor:
   - `assignment_pool_members`: check the garages in `garage_four_wheeler`,
     `garage_two_wheeler` and `garage_any`. They were copied from the `admin`
     table exactly as today's rotation picks them, so if the
     `appreview@gmail.com` admin has a vehicle label it will be in the normal
     rotation too (same as today). Untick `active` to take it out.
   - `review_overrides`: there should be 3 rows (admin, delivery, washer)
     for `appreview@gmail.com`. If one is missing, that demo account didn't
     exist yet; add the row by hand.
3. **Edge Functions.**
   ```bash
   supabase functions deploy booking-api razorpay-webhook
   supabase secrets set RAZORPAY_WEBHOOK_SECRET=<any long random string>
   ```
   `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` are already set (the old
   functions use them). `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are
   provided automatically.
4. **Razorpay webhook.** In Razorpay Dashboard, go to Settings → Webhooks → Add:
   - URL: `https://rmvxqjyoqfinbrpubsvp.supabase.co/functions/v1/razorpay-webhook`
   - Secret: the same `RAZORPAY_WEBHOOK_SECRET`
   - Events: `payment.captured`, `order.paid`
5. **App.** Bump `pubspec.yaml` to `2.2.0+<next build>`, build, and test (section 4).

---

## 2. Everyday changes (no app update)

| I want to… | Do this in Table Editor |
|---|---|
| Change a price | `services` → `price` (whole rupees, e.g. `3999`) |
| Rename a package | `services` → `name` (what customers see) **and** `booking_name` (what garages see on bookings; empty = same as name) |
| Edit what's included | `services` → `features` (JSON list of strings) |
| Hide a package everywhere | `services` → `active` = false |
| Mark "Most Popular" | `services` → `popular` = true |
| Change the pickup & drop fee | `app_settings` → `pickup_drop_fee` |
| Turn App Store review routing off | `app_settings` → `review_override_enabled` = `false` |
| Change garages per rotation (3 → 5) | `assignment_pools` → `batch_size` |
| Add a garage to the car rotation | `assignment_pool_members` → new row: `pool_key` = `garage_four_wheeler`, `member_ref` = the admin's `id` |
| Pause a garage / delivery partner / washer | `assignment_pool_members` → `active` = false |
| Send claims to another garage | `assignment_pool_members` for `garage_claims` |
| Auto-assign washers to monthly plans | add washers to the `washers_subscriptions` pool |
| Change the serviceable area | `app_settings` → `service_area` (`lat`, `lng`, `radius_km`) |

### How a booking is routed
Each `services` row says who gets it:

| Column | Meaning |
|---|---|
| `admin_pool` | garage pool. `garage_{vehicle}` = the booked vehicle's type (`garage_four_wheeler` / `garage_two_wheeler`, or `garage_any`) |
| `delivery_pool` | used only when the booking has pickup & drop |
| `washer_pool` | doorstep washes |
| `pickup_mode` | `optional` (customer chooses, +fee) · `none` · `included` (always, no fee) · `locked` (always, fee charged, e.g. Roadside) |
| `allow_cod` | shows "Cash on Pickup" |
| `booking_table` | where the booking is saved |
| `bookable` | `false` = display/enquiry only (Detailing Studio, Fleet Management) |

Rotation: member = `(counter ÷ batch_size) mod active members`, counted
atomically in the database, so two simultaneous bookings never collide.

---

## 3. What's still in the app (by design)
Layout, colours, icons, comparison tables, checklists and "Why choose us"
sections are visual and stay in code. The **package data shown in them**
(names, prices, taglines, features, badges, add-ons) comes from `services`.
A new row with a matching `screens` value shows up on that screen
automatically.

---

## 4. Test checklist (2.2.0)
- [ ] Every package screen opens and shows today's prices.
- [ ] Change one price in `services`, reopen the app (or wait 5 min): the new price shows **and** is charged.
- [ ] Car service + pickup → booking has garage (3-each rotation) + delivery partner.
- [ ] Car Express/Premium wash & bike washes → washer 1/2, no garage, no pickup option.
- [ ] Roadside → emergency_service, fee included, no delivery partner.
- [ ] Pollution / inspection / claim → delivery partner 3; claim → claims garage.
- [ ] Monthly plan → `monthlywash_table`, 30 days.
- [ ] Paint package + add-ons and bike service + oil change → itemised bill.
- [ ] Fleet "Pay Now" → request marked paid.
- [ ] appreview@gmail.com → review garage / delivery / washer.
- [ ] Turn off wifi right after paying → "Payment received… RETRY" → booking saved once.
- [ ] Cash on Pickup works where allowed (not claims / fleet).

---

### Automated tests
`deno test -A supabase/tests/booking_test.ts` runs the real booking code against an
in-memory Postgres with the migration applied (pricing, every booking table,
rotation, review routing, idempotent retries, fleet payments).

## 5. Later (once everyone is on 2.2.0+)
- Delete the old `create-razorpay-order` / `verify-razorpay-payment` functions
  (old apps still use them, so they can't be removed yet).
- Revoke client INSERT on `bookings`, `claim_table`, `pollution_booking`,
  `inspection_booking`, `monthlywash_table`. Only booking-api needs to
  write them now.
- Old app versions still assign with the old count-based rotation, so the
  rotation may be slightly uneven until they update.
