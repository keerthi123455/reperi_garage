// Booking logic tests — runs the real _shared/booking.ts against an
// in-memory Postgres (PGlite) with the real migration applied.
//   deno test -A supabase/tests/booking_test.ts
import { PGlite } from "npm:@electric-sql/pglite@0.3";
import { assert, assertEquals, assertRejects } from "./asserts.ts";
import { fakeDb } from "./fakedb.ts";
import {
  ApiError, buildQuote, createIntent, finalizeIntent, loadSettings, createRazorpayOrder, rupees,
} from "../functions/_shared/booking.ts";

const MIGRATION = new URL("../migrations/20261009000000_server_catalog.sql", import.meta.url);
const STUBS = new URL("./stubs.sql", import.meta.url);

Deno.env.set("RAZORPAY_KEY_ID", "rzp_test_key");
Deno.env.set("RAZORPAY_KEY_SECRET", "secret");
let orderN = 0;
globalThis.fetch = (async () => new Response(JSON.stringify({ id: `order_${++orderN}` }), { status: 200 })) as typeof fetch;

const U = "aaaaaaaa-0000-0000-0000-000000000001"; // normal customer
const R = "aaaaaaaa-0000-0000-0000-000000000002"; // App Store review customer
const CAR = "bbbbbbbb-0000-0000-0000-000000000001";
const BIKE = "bbbbbbbb-0000-0000-0000-000000000002";
const RCAR = "bbbbbbbb-0000-0000-0000-000000000003";
const user = (id: string, email: string) => ({ id, email, phone: "", user_metadata: {} }) as any;
const normal = user(U, "someone@example.com");
const review = user(R, "AppReview@gmail.com");

async function setup() {
  const pg = new PGlite();
  await pg.exec(await Deno.readTextFile(STUBS));
  await pg.exec(await Deno.readTextFile(MIGRATION));
  await pg.exec(`
    insert into profiles (id, name, phone) values ('${U}', 'Asha', '9000000001'), ('${R}', 'Apple Reviewer', '9999999999');
    insert into vehicles (id, user_id, vehicle_type) values ('${CAR}', '${U}', 'four_wheeler'), ('${BIKE}', '${U}', 'two_wheeler'), ('${RCAR}', '${R}', 'four_wheeler');
    insert into user_addresses (user_id, name, address, latitude, longitude, is_default) values
      ('${U}', 'Home', 'Indiranagar, Bengaluru', 12.9719, 77.6412, true),
      ('${R}', 'Home', 'Indiranagar, Bengaluru', 12.9719, 77.6412, true);
    insert into fleet_pickup_requests (id, company_name, total_amount, bill_items, payment_status) values
      (7, 'Demo Fleet', 2500, '[{"name":"Brake pads","price":1800},{"name":"Labour","price":700}]', 'pending');
  `);
  const db = fakeDb(pg) as any;
  return { pg, db, settings: await loadSettings(db) };
}
const one = async (pg: PGlite, sql: string) => (await pg.query(sql)).rows[0] as any;

async function book(db: any, settings: any, u: any, input: any, paymentId: string | null = null) {
  const { intent } = await createIntent(db, u, input, settings);
  if (intent.payment_method === "online") {
    const order = await createRazorpayOrder(intent);
    await db.from("payment_intents").update({ razorpay_order_id: order.orderId }).eq("id", intent.id);
  }
  const res = await finalizeIntent(db, intent.id, intent.payment_method === "online" ? (paymentId ?? `pay_${intent.id.slice(0, 6)}`) : null, settings);
  return { intent, res };
}

Deno.test("rupees() uses Indian grouping", () => {
  assertEquals(rupees(99), "₹99");
  assertEquals(rupees(3999), "₹3,999");
  assertEquals(rupees(49999), "₹49,999");
  assertEquals(rupees(100000), "₹1,00,000");
  assertEquals(rupees(1234567), "₹12,34,567");
});

Deno.test("quotes are priced from the services table", async () => {
  const { db, settings } = await setup();
  const q1 = await buildQuote(db, { items: ["svc_premium_care"], pickup_drop: true }, settings);
  assertEquals([q1.subtotal, q1.pickupFeeCharged, q1.total, q1.bookingName], [3999, 100, 4099, "PREMIUM CARE"]);
  const q2 = await buildQuote(db, { items: ["wash_express"], pickup_drop: true }, settings);
  assertEquals([q2.total, q2.pickupDrop, q2.pickupMode], [299, false, "none"]); // doorstep wash: no pickup
  const q3 = await buildQuote(db, { items: ["roadside_assistance"] }, settings);
  assertEquals([q3.total, q3.pickupDrop], [499, true]); // locked pickup fee
  const q4 = await buildQuote(db, { items: ["bike_service_200", "bike_oil_change_addon"] }, settings);
  assertEquals([q4.total, q4.bookingName], [1399, "General Bike Service (126–200 CC) + Oil Change Add-on"]);
  const q5 = await buildQuote(db, { items: ["paint_addon_ceramic", "paint_addon_ppf"] }, settings);
  assertEquals([q5.total, q5.bookingName], [62998, "Paint Care Add-Ons"]);
  const q6 = await buildQuote(db, { items: ["paint_shine", "paint_addon_graphene"], pickup_drop: false }, settings);
  assertEquals([q6.total, q6.bookingName], [18998, "PAINT SHINE PACKAGE"]);
  const q7 = await buildQuote(db, { items: ["claim_assistance"] }, settings);
  assertEquals([q7.total, q7.allowCod, q7.pickupFeeCharged], [3999, false, 0]); // included pickup, no fee
});

Deno.test("quote rejects bad carts", async () => {
  const { db, settings } = await setup();
  const code = async (input: any) => {
    try { await buildQuote(db, input, settings); return "ok"; } catch (e) { return (e as ApiError).code; }
  };
  assertEquals(await code({ items: ["svc_essential", "svc_signature"] }), "one_package_only");
  assertEquals(await code({ items: ["detail_ppf_premium"] }), "service_unavailable"); // enquiry only
  assertEquals(await code({ items: ["nope"] }), "service_unavailable");
  assertEquals(await code({ items: [] }), "invalid_items");
  assertEquals(await code({ items: ["Robert'); drop table services;--"] }), "invalid_items");
  assertEquals(await code({ items: ["svc_essential", "paint_addon_ceramic"] }), "invalid_addon");
  assertEquals(await code({ items: ["svc_essential", "pollution_check"] }), "one_package_only");
});

Deno.test("price edits take effect immediately, inactive services can't be booked", async () => {
  const { pg, db, settings } = await setup();
  await pg.exec("update services set price = 4499 where key = 'svc_premium_care'");
  assertEquals((await buildQuote(db, { items: ["svc_premium_care"] }, settings)).total, 4499);
  await pg.exec("update services set active = false where key = 'svc_signature'");
  await assertRejects(() => buildQuote(db, { items: ["svc_signature"] }, settings), ApiError, "can't be booked");
});

Deno.test("online car service: server books it, rotates garage + delivery, idempotent", async () => {
  const { pg, db, settings } = await setup();
  const { intent, res } = await book(db, settings, normal, { items: ["svc_premium_care"], pickup_drop: true, vehicle_id: CAR, payment_method: "online" }, "pay_A");
  assertEquals(intent.amount, 4099);
  assertEquals(res.status, "booked");
  const b = await one(pg, `select * from bookings where id = ${res.booking_id}`);
  assertEquals([b.package_name, b.package_price, b.pickupdrop, b.payment_status, b.razorpay_payment_id], ["PREMIUM CARE", "₹3,999", "yes", "paid", "pay_A"]);
  assertEquals(b.assigned_to_admin_id, "11111111-0000-0000-0000-000000000002"); // same pick as the old count-based formula
  assertEquals(b.delivery_partner_id, 2); // 7 bookings existed → partner (7 % 2) + 1 = 2
  assertEquals([b.customer_name, b.customer_phone, b.pickup_address], ["Asha", "9000000001", "Indiranagar, Bengaluru"]);
  // confirm + webhook racing / app retrying → still exactly one booking
  const again = await finalizeIntent(db, intent.id, "pay_A", settings);
  assertEquals(again, { status: "booked", booking_table: "bookings", booking_id: res.booking_id });
  assertEquals((await one(pg, "select count(*)::int n from bookings where razorpay_payment_id = 'pay_A'")).n, 1);
});

Deno.test("doorstep washes go to washers 1/2, never a garage; COD works", async () => {
  const { pg, db, settings } = await setup();
  const w1 = await book(db, settings, normal, { items: ["wash_express"], vehicle_id: CAR, payment_method: "cod" });
  const w2 = await book(db, settings, normal, { items: ["bike_wash_quick"], vehicle_id: BIKE, payment_method: "online" });
  const a = await one(pg, `select * from bookings where id = ${w1.res.booking_id}`);
  const b = await one(pg, `select * from bookings where id = ${w2.res.booking_id}`);
  assertEquals([a.washer_id, a.assigned_to_admin_id, a.delivery_partner_id, a.pickupdrop, a.payment_status, a.razorpay_order_id], [2, null, null, null, "cod", null]);
  assertEquals([b.washer_id, b.assigned_to_admin_id, b.package_name, b.package_price], [1, null, "QUICK WASH", "₹149"]);
});

Deno.test("App Store review account keeps its fixed demo partners", async () => {
  const { pg, db, settings } = await setup();
  const s = await book(db, settings, review, { items: ["svc_essential"], pickup_drop: true, vehicle_id: RCAR, payment_method: "online" });
  const w = await book(db, settings, review, { items: ["wash_premium"], vehicle_id: RCAR, payment_method: "online" });
  const bw = await book(db, settings, review, { items: ["bike_wash_premium"], vehicle_id: RCAR, payment_method: "online" });
  const r = await book(db, settings, review, { items: ["roadside_assistance"], payment_method: "online", options: { label: "Dead Battery" } });
  const m = await book(db, settings, review, { items: ["monthly_wash_suv"], vehicle_id: RCAR, payment_method: "online" });
  const sb = await one(pg, `select * from bookings where id = ${s.res.booking_id}`);
  assertEquals([sb.assigned_to_admin_id, sb.delivery_partner_id], ["11111111-0000-0000-0000-000000000006", 4]);
  assertEquals((await one(pg, `select washer_id from bookings where id = ${w.res.booking_id}`)).washer_id, 3);
  assertEquals((await one(pg, `select washer_id from bookings where id = ${bw.res.booking_id}`)).washer_id, 3);
  const rb = await one(pg, `select * from bookings where id = ${r.res.booking_id}`);
  assertEquals([rb.assigned_to_admin_id, rb.delivery_partner_id, rb.package_name], ["11111111-0000-0000-0000-000000000006", null, "Roadside Assistance - Dead Battery"]);
  assertEquals((await one(pg, `select washer_id from monthlywash_table where id = ${m.res.booking_id}`)).washer_id, 3);
  // switching review mode off in app_settings sends them through the normal rotation
  await pg.exec("update app_settings set value = 'false' where key = 'review_override_enabled'");
  const off = await loadSettings(db);
  const n = await book(db, off, review, { items: ["wash_premium"], vehicle_id: RCAR, payment_method: "online" });
  assert((await one(pg, `select washer_id from bookings where id = ${n.res.booking_id}`)).washer_id !== 3);
});

Deno.test("roadside, bike, pollution, inspection, claim, monthly wash land in the right tables", async () => {
  const { pg, db, settings } = await setup();
  const r = await book(db, settings, normal, { items: ["roadside_assistance"], payment_method: "cod", options: { label: "Flat Tyre" } });
  const rb = await one(pg, `select * from bookings where id = ${r.res.booking_id}`);
  assertEquals([rb.package_name, rb.package_price, rb.pickupdrop, rb.delivery_partner_id, rb.vehicle_id], ["Roadside Assistance - Flat Tyre", "₹399", "yes", null, null]);
  assertEquals(rb.assigned_to_admin_id, "11111111-0000-0000-0000-000000000004"); // emergency_service

  const bk = await book(db, settings, normal, { items: ["bike_service_350", "bike_oil_change_addon"], vehicle_id: BIKE, payment_method: "online" });
  const bb = await one(pg, `select * from bookings where id = ${bk.res.booking_id}`);
  assertEquals([bb.assigned_to_admin_id, bb.package_price, bb.pickupdrop], ["11111111-0000-0000-0000-000000000003", "₹1,899", "no"]);

  const p = await book(db, settings, normal, { items: ["pollution_check"], vehicle_id: CAR, payment_method: "cod" });
  const pb = await one(pg, `select * from pollution_booking where id = ${p.res.booking_id}`);
  assertEquals([pb.price, pb.razorpay_order_id, pb.delivery_partner_id, pb.pickupdrop, pb.status], ["₹299", "COD", 3, "yes", "booked"]);

  const tomorrow = new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10);
  const i = await book(db, settings, normal, { items: ["inspection_suv"], vehicle_id: CAR, payment_method: "online",
    options: { inspection: { condition: "Used", slot_date: tomorrow, slot_time: "10:00 AM - 12:00 PM" } } });
  const ib = await one(pg, `select * from inspection_booking where id = ${i.res.booking_id}`);
  assertEquals([ib.vehicle_type, ib.package_price, ib.vehicle_condition, ib.delivery_partner_id], ["SUV", "₹1,599", "Used", 3]);

  const docs = { description: "Rear door dent", rc: "rc-copies/claim-1700000000-abcdef-rc.pdf", license: "driving-licenses/claim-1700000000-abcdef-license.pdf",
    aadhaar: "aadhaar/claim-1700000000-abcdef-aadhaar.pdf", pan: "pan/claim-1700000000-abcdef-pan.pdf",
    insurance: "insurance-copies/claim-1700000000-abcdef-insurance.pdf", photo: "damage-photos/claim-1700000000-abcdef-damage.jpg" };
  const c = await book(db, settings, normal, { items: ["claim_assistance"], vehicle_id: CAR, payment_method: "online", options: { claim: docs } });
  const cb = await one(pg, `select * from claim_table where id = ${c.res.booking_id}`);
  assertEquals([cb.assigned_to_admin_id, cb.delivery_partner_id, cb.package_price, cb.claim_status, cb.rc_copy_url], ["1bcf9d81-6625-4c01-ac23-f0c237462eb7", 3, "₹3,999", "submitted", docs.rc]);

  const m = await book(db, settings, normal, { items: ["monthly_wash_bike"], vehicle_id: BIKE, payment_method: "online" });
  const mb = await one(pg, `select * from monthlywash_table where id = ${m.res.booking_id}`);
  assertEquals([mb.plan_type, Number(mb.price), mb.status, mb.washer_id, mb.plan_title], ["bike", 499, "active", null, "Monthly Wash Plan - Bike"]);
});

Deno.test("create refuses what the app used to let through", async () => {
  const { pg, db, settings } = await setup();
  const code = async (u: any, input: any) => {
    try { await createIntent(db, u, input, settings); return "ok"; } catch (e) { return (e as ApiError).code; }
  };
  assertEquals(await code(null, { items: ["svc_essential"], vehicle_id: CAR }), "sign_in_required");
  assertEquals(await code(normal, { items: ["svc_essential"], vehicle_id: RCAR }), "invalid_vehicle"); // someone else's car
  assertEquals(await code(normal, { items: ["svc_essential"] }), "vehicle_required");
  assertEquals(await code(normal, { items: ["claim_assistance"], vehicle_id: CAR, payment_method: "cod", options: { claim: {} } }), "cod_not_allowed");
  assertEquals(await code(normal, { items: ["claim_assistance"], vehicle_id: CAR, options: { claim: { description: "x", rc: "../../etc/passwd" } } }), "invalid_options");
  assertEquals(await code(normal, { items: ["inspection_ev"], vehicle_id: CAR, options: { inspection: { condition: "New", slot_date: "2020-01-01", slot_time: "x" } } }), "invalid_options");
  await pg.exec(`update user_addresses set latitude = 28.61, longitude = 77.20 where user_id = '${U}'`); // Delhi
  assertEquals(await code(normal, { items: ["svc_essential"], vehicle_id: CAR }), "out_of_service_area");
  await pg.exec(`delete from user_addresses where user_id = '${U}'`);
  assertEquals(await code(normal, { items: ["svc_essential"], vehicle_id: CAR }), "address_required");
});

Deno.test("fleet Pay Now is priced from the request, not the app", async () => {
  const { pg, db, settings } = await setup();
  const q = await buildQuote(db, { fleet_request_id: "7" }, settings);
  assertEquals([q.total, q.lines.length, q.allowCod], [2500, 2, false]);
  const { res } = await book(db, settings, null, { fleet_request_id: "7", payment_method: "online" }, "pay_F");
  assertEquals(res.status, "booked");
  const f = await one(pg, "select * from fleet_pickup_requests where id = 7");
  assertEquals([f.payment_status, f.razorpay_payment_id], ["paid", "pay_F"]);
  await assertRejects(() => buildQuote(db, { fleet_request_id: "7" }, settings), ApiError, "already paid");
});

Deno.test("a failed save can be retried without charging again", async () => {
  const { pg, db, settings } = await setup();
  const { intent } = await createIntent(db, normal, { items: ["svc_essential"], vehicle_id: CAR, payment_method: "online" }, settings);
  await db.from("payment_intents").update({ razorpay_order_id: "order_fail" }).eq("id", intent.id);
  await pg.exec("alter table bookings rename to bookings_tmp"); // simulate an outage
  await assertRejects(() => finalizeIntent(db, intent.id, "pay_X", settings), ApiError, "payment went through");
  assertEquals((await one(pg, `select status from payment_intents where id = '${intent.id}'`)).status, "failed");
  await pg.exec("alter table bookings_tmp rename to bookings");
  const ok = await finalizeIntent(db, intent.id, "pay_X", settings);
  assertEquals(ok.status, "booked");
  assertEquals((await one(pg, "select count(*)::int n from bookings where razorpay_payment_id = 'pay_X'")).n, 1);
});
