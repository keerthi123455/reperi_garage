// Fires on Supabase Database Webhooks for:
//   bookings            (INSERT, UPDATE — wash completed)
//   booking_updates     (INSERT)
//   booking_chats       (INSERT)
//   fleet_pickup_requests (INSERT, UPDATE)
//   fleet_chat_messages (INSERT)
//
// Resolves who should be notified for each event and sends a push via
// OneSignal's REST API, targeting the same external-id scheme used by
// the Flutter app's PushNotificationService:
//   customer -> 'customer_<supabase_auth_user_id>'
//   fleet    -> 'fleet_<fleet_users.id>'
//   admin    -> 'admin'  (single fixed admin identity today)

import { createClient } from "jsr:@supabase/supabase-js@2";

const ONESIGNAL_APP_ID = "6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Record<string, unknown>;
  old_record?: Record<string, unknown> | null;
}

async function sendPush(
  externalId: string,
  title: string,
  body: string,
  data?: Record<string, unknown>,
) {
  if (!ONESIGNAL_REST_API_KEY) {
    console.error("ONESIGNAL_REST_API_KEY is not set — skipping send");
    return;
  }

  const res = await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Key ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID,
      include_aliases: { external_id: [externalId] },
      target_channel: "push",
      headings: { en: title },
      contents: { en: body },
      data: data ?? {},
    }),
  });

  const json = await res.json().catch(() => null);

  if (!res.ok || !json?.id) {
    // Not fatal for the webhook — a missing recipient (e.g. that user
    // has never opened the app / granted permission) is expected and
    // shouldn't be treated as an error, just logged for visibility.
    console.error("OneSignal send did not create a message", {
      externalId,
      status: res.status,
      response: json,
    });
  }
}

/** " for Wed 22 Oct, 11:00 AM – 01:00 PM" — empty when no slot was picked. */
function slotText(record: Record<string, unknown>): string {
  const date = record.slot_date ? String(record.slot_date).slice(0, 10) : "";
  const time = record.slot_time ? String(record.slot_time) : "";
  if (!date) return "";
  const d = new Date(`${date}T00:00:00Z`);
  const day = Number.isNaN(d.getTime())
    ? date
    : d.toLocaleDateString("en-IN", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" });
  return ` for ${day}${time ? `, ${time}` : ""}`;
}

/** What the slot means for the customer, by kind. */
function slotHint(record: Record<string, unknown>): string {
  switch (String(record.slot_mode ?? "")) {
    case "pickup": return " We'll pick up your car then.";
    case "garage_drop": return " Please drop your car at the garage in that window.";
    case "doorstep": return " We'll come to you then.";
    default: return "";
  }
}

Deno.serve(async (req) => {
  try {
    const payload = (await req.json()) as WebhookPayload;
    const { type, table, record, old_record } = payload;

    switch (table) {
      // ── New booking: notify admin + confirm to the customer ──
      case "bookings": {
        if (type === "INSERT") {
          const packageName = String(record.package_name ?? "your service");
          const when = slotText(record);
          await Promise.all([
            sendPush(
              "admin",
              "New booking",
              `${packageName}${when} — a new booking just came in.`,
              { type: "booking", bookingId: record.id },
            ),
            record.user_id
              ? sendPush(
                  `customer_${record.user_id}`,
                  "Booking confirmed",
                  `Your booking for ${packageName}${when} was placed successfully.${slotHint(record)}`,
                  { type: "booking", bookingId: record.id },
                )
              : Promise.resolve(),
          ]);
        } else if (type === "UPDATE") {
          // Doorstep wash marked done from the washer dashboard.
          const nowDone =
            record.washer_id &&
            String(record.booking_status ?? "") === "Completed" &&
            String(old_record?.booking_status ?? "") !== "Completed";
          if (nowDone && record.user_id) {
            await sendPush(
              `customer_${record.user_id}`,
              "Wash complete!",
              `Your ${String(record.package_name ?? "wash")} is done. Thanks for choosing Reperi!`,
              { type: "booking", bookingId: record.id },
            );
          }
        }
        break;
      }

      // ── Apartment offer washes (₹1 / ₹199 / ₹999) ──
      // New: notify admin, confirm to the customer, alert the assigned washer.
      // Marked Completed by the washer: tell the customer it's done.
      case "offer_bookings": {
        const packageName = String(record.package_name ?? "your wash");
        const apartment = String(record.pickup_address_name ?? "the apartment");
        const data = { type: "offer_booking", bookingId: record.id };
        const when = slotText(record);

        if (type === "INSERT") {
          await Promise.all([
            sendPush(
              "admin",
              "New offer booking",
              `${packageName} at ${apartment}${when} — a new offer booking just came in.`,
              data,
            ),
            record.user_id
              ? sendPush(
                  `customer_${record.user_id}`,
                  "Booking confirmed",
                  `Your ${packageName} at ${apartment} is booked${when}.`,
                  data,
                )
              : Promise.resolve(),
            record.washer_id
              ? sendPush(
                  `washer_${record.washer_id}`,
                  "New wash assigned",
                  `${packageName} at ${apartment}${when}. Open your dashboard for details.`,
                  data,
                )
              : Promise.resolve(),
          ]);
        } else if (type === "UPDATE") {
          const nowDone =
            String(record.booking_status ?? "") === "Completed" &&
            String(old_record?.booking_status ?? "") !== "Completed";
          if (nowDone && record.user_id) {
            await sendPush(
              `customer_${record.user_id}`,
              "Wash complete!",
              `Your ${packageName} at ${apartment} is done. Thanks for choosing Reperi!`,
              data,
            );
          }
        }
        break;
      }

      // ── Admin posts a progress update on a booking: notify the customer ──
      case "booking_updates": {
        if (type === "INSERT") {
          const { data: booking } = await supabaseAdmin
            .from("bookings")
            .select("user_id, package_name")
            .eq("id", record.booking_id as string)
            .single();

          if (booking?.user_id) {
            const stage = String(record.stage ?? "");
            const isDone = stage === "Delivered";
            await sendPush(
              `customer_${booking.user_id}`,
              isDone ? "Booking complete!" : "Booking update",
              isDone
                ? `Your ${booking.package_name} service is complete and ready.`
                : `${stage}: ${booking.package_name}`,
              { type: "booking", bookingId: record.booking_id },
            );
          }
        }
        break;
      }

      // ── Consumer <-> Admin chat: notify whichever side didn't send it ──
      case "booking_chats": {
        if (type === "INSERT") {
          const message = String(record.message ?? "");
          if (record.sender === "consumer") {
            await sendPush("admin", "New message", message, {
              type: "booking_chat",
              bookingId: record.booking_id,
            });
          } else if (record.sender === "admin") {
            const { data: booking } = await supabaseAdmin
              .from("bookings")
              .select("user_id")
              .eq("id", record.booking_id as string)
              .single();

            if (booking?.user_id) {
              await sendPush(
                `customer_${booking.user_id}`,
                "New message from garage",
                message,
                { type: "booking_chat", bookingId: record.booking_id },
              );
            }
          }
        }
        break;
      }

      // ── New fleet pickup request: notify admin; status change: notify fleet ──
      case "fleet_pickup_requests": {
        if (type === "INSERT") {
          const companyName = String(
            record.company_name ?? "A fleet operator",
          );
          await sendPush(
            "admin",
            "New fleet pickup request",
            `${companyName} submitted a new pickup request.`,
            { type: "fleet_request", requestId: record.id },
          );
        } else if (type === "UPDATE") {
          const statusChanged =
            old_record && record.status !== old_record.status;

          if (statusChanged && record.fleet_user_id) {
            await sendPush(
              `fleet_${record.fleet_user_id}`,
              "Request update",
              `Your pickup request is now: ${record.status}.`,
              { type: "fleet_request", requestId: record.id },
            );
          }
        }
        break;
      }

      // ── Fleet <-> Admin chat: notify whichever side didn't send it ──
      case "fleet_chat_messages": {
        if (type === "INSERT") {
          const message = String(record.message ?? "");
          if (record.sender_type === "fleet") {
            await sendPush("admin", "New fleet message", message, {
              type: "fleet_chat",
              requestId: record.request_id,
            });
          } else if (record.sender_type === "admin") {
            const { data: reqRow } = await supabaseAdmin
              .from("fleet_pickup_requests")
              .select("fleet_user_id")
              .eq("id", record.request_id as string)
              .single();

            if (reqRow?.fleet_user_id) {
              await sendPush(
                `fleet_${reqRow.fleet_user_id}`,
                "New message from garage",
                message,
                { type: "fleet_chat", requestId: record.request_id },
              );
            }
          }
        }
        break;
      }

      // ── ReperiResolve: problem photos/video → your team sends a price ──
      // New request → admin. Price typed in → customer. Price accepted → admin.
      case "resolve_requests": {
        const car = String(record.vehicle_label ?? "a car");
        const cats = Array.isArray(record.categories) ? (record.categories as string[]).join(", ") : "";
        const what = cats || String(record.description ?? "").slice(0, 80) || "photos / video";
        const data = { type: "resolve_request", requestId: record.id };

        if (type === "INSERT") {
          await Promise.all([
            sendPush("admin", "New ReperiResolve request", `${car}: ${what}. Send them a price.`, data),
            record.user_id
              ? sendPush(
                  `customer_${record.user_id}`,
                  "Request received",
                  "We're looking at your problem and will send you a fixed price soon.",
                  data,
                )
              : Promise.resolve(),
          ]);
        } else if (type === "UPDATE") {
          // New price, or the price note / photo changed.
          const priced =
            record.quoted_price != null &&
            (String(record.quoted_price) !== String(old_record?.quoted_price ?? "") ||
              String(record.quote_note ?? "") !== String(old_record?.quote_note ?? "") ||
              String(record.quote_image_path ?? "") !== String(old_record?.quote_image_path ?? ""));
          const accepted =
            record.status === "Accepted" && old_record?.status !== "Accepted";
          if (priced && record.user_id) {
            await sendPush(
              `customer_${record.user_id}`,
              "Your price is ready",
              `₹${record.quoted_price} to fix ${what.toLowerCase()} on your ${car}. Tap to accept.`,
              data,
            );
          }
          if (accepted) {
            const who = [record.customer_name, record.customer_phone].filter(Boolean).join(" · ");
            await sendPush(
              "admin",
              "ReperiResolve price accepted",
              `${who || "Customer"} accepted ₹${record.quoted_price} for ${car}. Call to schedule.`,
              data,
            );
          }
        }
        break;
      }

      default:
        console.log("Unhandled table in webhook payload:", table);
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("notify-on-db-change error:", err);
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});