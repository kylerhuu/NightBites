# NightBites Payments Backend

Minimal Express backend for the NightBites mobile payment flow.

## Endpoints

- `GET /health`
- `POST /api/mobile/payments/create-intent`
- `POST /api/mobile/payments/confirm`
- `POST /api/stripe/webhooks`

## Setup

1. Copy `.env.example` to `.env`
2. Fill in your Stripe values
3. Install dependencies:

```bash
cd backend
npm install
```

4. Start the server:

```bash
npm run dev
```

For simulator development, the iOS app can use:

- `PAYMENTS_API_BASE_URL = http://127.0.0.1:3000`

If env values are still placeholders, the server prints a startup warning listing what is missing.

## Current behavior

- creates Stripe PaymentIntents
- supports a truck-to-connected-account map through `TRUCK_STRIPE_ACCOUNT_MAP`
- uses `service_fee_amount_cents` as `application_fee_amount` for destination charges when a connected account exists
- confirms by retrieving the PaymentIntent and returning its current status
- webhook route is ready for you to extend with order syncing, fulfillment changes, and refunds

## What you still need to provide

- real Stripe secret key
- real webhook secret
- Apple Pay merchant identifier
- actual truck connected account IDs once Connect onboarding exists
