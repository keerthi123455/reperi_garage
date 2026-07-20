// Fires on Supabase Database Webhooks for:
//   bookings            (INSERT)
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

Deno.serve(async (req) => {
  try {
    const payload = (await req.json()) as WebhookPayload;
    const { type, table, record, old_record } = payload;

    switch (table) {
      // ── New booking: notify admin + confirm to the customer ──
      case "bookings": {
        if (type === "INSERT") {
          const packageName = String(record.package_name ?? "your service");
          await Promise.all([
            sendPush(
              "admin",
              "New booking",
              `${packageName} — a new booking just came in.`,
              { type: "booking", bookingId: record.id },
            ),
            record.user_id
              ? sendPush(
                  `customer_${record.user_id}`,
                  "Booking confirmed",
                  `Your booking for ${packageName} was placed successfully.`,
                  { type: "booking", bookingId: record.id },
                )
              : Promise.resolve(),
          ]);
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