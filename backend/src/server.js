const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const Stripe = require("stripe");

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 3000);
const clientOrigin = process.env.CLIENT_ORIGIN || "*";
const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
const stripeMerchantIdentifier = process.env.STRIPE_MERCHANT_IDENTIFIER || null;

const stripe = stripeSecretKey ? new Stripe(stripeSecretKey) : null;
printStartupWarnings();

app.use(cors({ origin: clientOrigin === "*" ? true : clientOrigin }));
app.use((req, res, next) => {
  if (req.originalUrl === "/api/stripe/webhooks") {
    next();
    return;
  }
  express.json()(req, res, next);
});

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    stripe_configured: Boolean(stripeSecretKey),
    webhook_configured: Boolean(stripeWebhookSecret),
  });
});

app.post("/api/mobile/payments/create-intent", async (req, res) => {
  const validationError = validateCreateIntentRequest(req.body);
  if (validationError) {
    res.status(400).json({ error: validationError });
    return;
  }

  if (!stripe) {
    res.status(500).json({ error: "Stripe is not configured on this backend." });
    return;
  }

  const {
    method,
    subtotal_amount_cents,
    service_fee_amount_cents,
    amount_cents,
    currency,
    order_reference,
    truck_id,
  } = req.body;

  try {
    const connectedAccountID = connectedAccountForTruck(truck_id);
    const params = {
      amount: amount_cents,
      currency: (currency || "usd").toLowerCase(),
      automatic_payment_methods: { enabled: true },
      metadata: {
        order_reference,
        truck_id,
        method,
        subtotal_amount_cents: String(subtotal_amount_cents),
        service_fee_amount_cents: String(service_fee_amount_cents),
      },
    };

    if (connectedAccountID) {
      params.application_fee_amount = Math.max(Number(service_fee_amount_cents) || 0, 0);
      params.transfer_data = { destination: connectedAccountID };
    }

    const paymentIntent = await stripe.paymentIntents.create(params);

    checkoutCache.set(paymentIntent.id, {
      checkout_id: paymentIntent.id,
      order_reference,
      truck_id,
      connected_account_id: connectedAccountID || null,
    });

    res.json({
      checkout_id: paymentIntent.id,
      processor: "stripe",
      payment_method: method,
      subtotal_amount_cents,
      service_fee_amount_cents,
      amount_cents,
      currency: params.currency.toUpperCase(),
      order_reference,
      client_secret: paymentIntent.client_secret,
      customer_ephemeral_key: null,
      customer_id: null,
      merchant_display_name: "NightBites",
      merchant_country_code: "US",
      apple_pay_merchant_identifier: stripeMerchantIdentifier,
    });
  } catch (error) {
    res.status(500).json({
      error: "Failed to create Stripe PaymentIntent.",
      details: error.message,
    });
  }
});

app.post("/api/mobile/payments/confirm", express.json(), async (req, res) => {
  const { checkout_id, order_reference } = req.body || {};
  if (!checkout_id || !order_reference) {
    res.status(400).json({ error: "checkout_id and order_reference are required." });
    return;
  }

  if (!stripe) {
    res.status(500).json({ error: "Stripe is not configured on this backend." });
    return;
  }

  try {
    const paymentIntent = await stripe.paymentIntents.retrieve(checkout_id);
    const status = normalizeStripeStatus(paymentIntent.status);
    res.json({
      status,
      transaction_id: latestChargeID(paymentIntent),
      message: null,
    });
  } catch (error) {
    res.status(500).json({
      error: "Failed to confirm Stripe PaymentIntent.",
      details: error.message,
    });
  }
});

app.post(
  "/api/stripe/webhooks",
  express.raw({ type: "application/json" }),
  (req, res) => {
    if (!stripe || !stripeWebhookSecret) {
      res.status(500).json({ error: "Stripe webhook secret is not configured." });
      return;
    }

    const signature = req.headers["stripe-signature"];
    if (!signature) {
      res.status(400).json({ error: "Missing stripe-signature header." });
      return;
    }

    try {
      const event = stripe.webhooks.constructEvent(req.body, signature, stripeWebhookSecret);

      switch (event.type) {
        case "payment_intent.succeeded":
        case "payment_intent.payment_failed":
        case "charge.refunded":
          break;
        default:
          break;
      }

      res.json({ received: true });
    } catch (error) {
      res.status(400).json({
        error: "Webhook signature verification failed.",
        details: error.message,
      });
    }
  }
);

app.listen(port, () => {
  console.log(`NightBites payments backend listening on http://127.0.0.1:${port}`);
});

function printStartupWarnings() {
  const missing = [];
  if (!stripeSecretKey || stripeSecretKey === "sk_test_replace_me") {
    missing.push("STRIPE_SECRET_KEY");
  }
  if (!stripeWebhookSecret || stripeWebhookSecret === "whsec_replace_me") {
    missing.push("STRIPE_WEBHOOK_SECRET");
  }
  if (!stripeMerchantIdentifier || stripeMerchantIdentifier === "merchant.com.nightbites.app") {
    missing.push("STRIPE_MERCHANT_IDENTIFIER");
  }

  if (missing.length > 0) {
    console.warn(
      `[payments-backend] Missing or placeholder env vars: ${missing.join(", ")}`
    );
  }
}

function validateCreateIntentRequest(body) {
  if (!body || typeof body !== "object") {
    return "Request body is required.";
  }

  const required = [
    "method",
    "subtotal_amount_cents",
    "service_fee_amount_cents",
    "amount_cents",
    "currency",
    "order_reference",
    "truck_id",
  ];

  for (const key of required) {
    if (body[key] === undefined || body[key] === null || body[key] === "") {
      return `${key} is required.`;
    }
  }

  if (!Number.isInteger(body.amount_cents) || body.amount_cents <= 0) {
    return "amount_cents must be a positive integer.";
  }

  if (!Number.isInteger(body.subtotal_amount_cents) || body.subtotal_amount_cents < 0) {
    return "subtotal_amount_cents must be a non-negative integer.";
  }

  if (!Number.isInteger(body.service_fee_amount_cents) || body.service_fee_amount_cents < 0) {
    return "service_fee_amount_cents must be a non-negative integer.";
  }

  return null;
}

function connectedAccountForTruck(truckID) {
  const raw = process.env.TRUCK_STRIPE_ACCOUNT_MAP || "{}";
  try {
    const parsed = JSON.parse(raw);
    return parsed[truckID] || null;
  } catch {
    return null;
  }
}

function normalizeStripeStatus(status) {
  switch (status) {
    case "requires_capture":
      return "authorized";
    case "succeeded":
      return "succeeded";
    case "processing":
    case "requires_action":
    case "requires_payment_method":
      return "requires_action";
    default:
      return "failed";
  }
}

function latestChargeID(paymentIntent) {
  const latestCharge = paymentIntent.latest_charge;
  return typeof latestCharge === "string" ? latestCharge : latestCharge?.id || null;
}
