import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Calls the Claude API directly over HTTP (no @anthropic-ai/sdk import) —
// the npm: specifier for that package was failing to resolve inside
// Supabase's edge runtime at cold start (every invocation returned a 500
// with an "EarlyDrop" shutdown reason, meaning the isolate never finished
// booting). Raw fetch has no import to resolve, and matches how every
// other function in this project (create-razorpay-order,
// verify-razorpay-payment) already calls its external API.
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Proxies the Flutter app's "Ask AI" advisor sheet to the real Claude API.
// The API key never leaves the server — the Flutter client only ever calls
// this function via supabase.functions.invoke('ask-ai-chat', ...).
//
// The Flutter client sends its ENTIRE real package catalog with each
// request — the exact same one the Services screen itself searches over
// (every category, every tier, every screen), each entry keyed by
// "category::::name" since that's the only unique identifier that catalog
// has. The model surveys that whole list itself and picks 0-2 keys —
// ordered basic to more comprehensive, i.e. tier-wise — that genuinely fit
// what the customer described, and writes a reply explaining what's
// included and how it helps using the real feature/tagline data it was
// given. It can never invent a price or recommend a package that doesn't
// exist, because `recommended_keys` is constrained to only the keys
// present in the catalog sent for this request — and even then, the
// Flutter client re-looks-up the price/duration/features from its own
// catalog data before rendering, and opens the real screen for that exact
// category+name pair, never trusting anything the model says about them
// directly.

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = "claude-haiku-4-5-20251001";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SYSTEM_PROMPT = `You are REPERI AI, the in-app vehicle service advisor for Reperi Garage, a doorstep car servicing app. Customers describe a problem with their vehicle (or send a photo of it) and you help them understand what's going on and which real Reperi package(s) can help — like a knowledgeable service advisor, not just a Q&A bot.

TONE: warm, direct, plain language — many customers are not car-savvy or tech-savvy. Never invent or state a price or duration yourself — the app attaches the correct, live price/duration separately from its own data, so never quote a number; describe packages by what they include and how that helps instead.

WHAT TO DO WITH EVERY MESSAGE:
1. Understand the customer's concern (ask a short clarifying question first ONLY if the message is too vague to act on at all, e.g. just "something's wrong").
2. Look through the full package catalog you're given below and decide whether any package(s) genuinely help.
3. If yes, recommend 1-2 packages, ordered from more basic/essential to more comprehensive (a tier comparison, not two random packages) — pick real neighboring tiers of the same kind of service where the catalog has them (e.g. a quick check vs. a fuller package), not two unrelated services. If only one relevant package exists in the catalog, recommend just that one.
4. In your reply, explain: (a) briefly what the issue likely is, (b) for each recommended package, what it actually includes (pull directly from that package's real feature list/details given below — do not invent inclusions), and (c) how it will concretely help their specific problem. Keep it natural conversational prose, not a rigid template, but make sure the "what's included" and "how it helps" parts are both actually there.
5. Never recommend a package that isn't in the catalog below. If nothing in the catalog is relevant (pure greeting, thanks, off-topic chat), recommend nothing (empty recommended_keys) and just reply normally.
6. Always propose 2-4 short, natural follow-up questions the customer might want to ask next (e.g. clarifying their symptom further, asking about a specific package, or asking something else vehicle-related) — these appear as tappable suggestions under your reply.

If a photo is attached, actually look at it and factor in what you see.`;

function buildCatalogBlock(catalog) {
  if (!Array.isArray(catalog) || catalog.length === 0) {
    return "No catalog data is currently available — do not recommend any package this turn (empty recommended_keys).";
  }
  const lines = catalog.map((p) => {
    const features = Array.isArray(p.features) && p.features.length
      ? p.features.join(", ")
      : "(no listed features)";
    const details = p.details ? ` Details: ${p.details}` : "";
    return `- key: ${p.key} | title: ${p.title} | category: ${p.category} | price: ${p.price} | duration: ${p.duration}\n  Includes: ${features}${details}`;
  });
  return `Available Reperi packages — you may ONLY recommend keys from this exact list:\n${lines.join("\n")}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!ANTHROPIC_API_KEY) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY is not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { message, history, vehicle, imageBase64, imageMediaType, catalog } = await req.json();

    if ((!message || !String(message).trim()) && !imageBase64) {
      return new Response(
        JSON.stringify({ error: "message or imageBase64 is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const vehicleBits = [vehicle?.brand, vehicle?.model].filter(Boolean).join(" ");
    const vehicleLine = vehicleBits ? `\nThe customer's vehicle: ${vehicleBits}.` : "";

    const validKeys = Array.isArray(catalog)
      ? catalog.map((p) => p.key).filter((k) => typeof k === "string")
      : [];

    const messages = [];
    for (const turn of history ?? []) {
      if (!turn?.text || !String(turn.text).trim()) continue;
      const role = turn.role === "assistant" ? "assistant" : "user";
      messages.push({ role, content: String(turn.text) });
    }

    const userContent = [];
    if (imageBase64 && imageMediaType) {
      userContent.push({
        type: "image",
        source: { type: "base64", media_type: imageMediaType, data: imageBase64 },
      });
    }
    userContent.push({
      type: "text",
      text: message && String(message).trim()
        ? String(message).trim()
        : "What do you see in this photo of my vehicle?",
    });
    messages.push({ role: "user", content: userContent });

    const recommendedKeysSchema = validKeys.length > 0
      ? { type: "string", enum: validKeys }
      : { type: "string" };

    const anthropicResponse = await fetch(ANTHROPIC_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1536,
        system: [
          {
            type: "text",
            text: `${SYSTEM_PROMPT}${vehicleLine}\n\n${buildCatalogBlock(catalog)}`,
            cache_control: { type: "ephemeral" },
          },
        ],
        tools: [
          {
            name: "reply_to_customer",
            description: "Send the reply, package recommendations, and follow-up question suggestions back to the app.",
            strict: true,
            input_schema: {
              type: "object",
              properties: {
                reply: {
                  type: "string",
                  description: "The conversational reply to show the customer, including what any recommended package includes and how it helps.",
                },
                recommended_keys: {
                  type: "array",
                  items: recommendedKeysSchema,
                  // Anthropic's strict tool schema doesn't support
                  // minItems/maxItems on arrays — the count limit (0-2) is
                  // enforced by the system prompt and, defensively, by the
                  // Flutter client truncating the list it gets back.
                  description: "0-2 catalog keys, ordered from more basic/essential to more comprehensive (tier-wise). Empty if nothing in the catalog is relevant.",
                },
                follow_up_questions: {
                  type: "array",
                  items: { type: "string" },
                  description: "2-4 short natural follow-up questions/prompts the customer could tap to continue the conversation.",
                },
              },
              required: ["reply", "recommended_keys", "follow_up_questions"],
              additionalProperties: false,
            },
          },
        ],
        tool_choice: { type: "tool", name: "reply_to_customer" },
        messages,
      }),
    });

    const responseData = await anthropicResponse.json();

    if (!anthropicResponse.ok) {
      return new Response(
        JSON.stringify({ error: "Anthropic API error", details: responseData }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const toolUse = (responseData.content ?? []).find((b) => b.type === "tool_use");

    if (!toolUse) {
      return new Response(
        JSON.stringify({ error: "Model did not return a structured reply", details: responseData }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { reply, recommended_keys, follow_up_questions } = toolUse.input;

    return new Response(
      JSON.stringify({ reply, recommended_keys, follow_up_questions }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Unexpected error", details: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
