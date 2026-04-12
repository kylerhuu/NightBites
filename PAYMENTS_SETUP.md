# Payments Setup

NightBites is now scaffolded for a Stripe-style mobile checkout flow:

1. App requests a checkout session from the backend.
2. Backend creates a Stripe PaymentIntent for the truck/platform payout flow.
3. App confirms the prepared checkout session.
4. Order is created with payment metadata.

## Recommended stack

- Stripe Connect
- Stripe PaymentIntents
- Stripe iOS SDK / PaymentSheet
- Apple Pay through Stripe

## Required app config

Add these Info.plist values before enabling digital payments:

- `ENABLE_DIGITAL_PAYMENTS` = `true`
- `STRIPE_PUBLISHABLE_KEY`
- `STRIPE_MERCHANT_IDENTIFIER`
- `PAYMENTS_API_BASE_URL`

## Current app status

The app is now prepared up to the point where external setup is required:

- truck-level payment settings exist in the owner UI
- checkout uses a Stripe-style `create-intent` then `confirm` flow
- orders store payment method, status, and transaction ID
- a compile-safe `StripePaymentCheckoutPresenter` seam exists in the app

What is still intentionally blocked by external setup:

- installing the Stripe iOS package
- wiring real PaymentSheet presentation from a live view controller / scene
- Apple Pay merchant setup in Apple Developer
- backend Stripe PaymentIntent + webhook implementation
- running the remote orders table migration if your Supabase schema is already live

## Expected backend endpoints

### `POST /api/mobile/payments/create-intent`

Request body:

```json
{
  "method": "Card",
  "amount_cents": 1798,
  "currency": "USD",
  "order_reference": "uuid",
  "merchant_identifier": "merchant.com.example"
}
```

Response body:

```json
{
  "checkout_id": "pi_123",
  "processor": "stripe",
  "payment_method": "Card",
  "amount_cents": 1798,
  "currency": "USD",
  "order_reference": "uuid",
  "client_secret": "pi_secret_123",
  "customer_ephemeral_key": "ephkey_123",
  "customer_id": "cus_123",
  "merchant_display_name": "NightBites",
  "merchant_country_code": "US",
  "apple_pay_merchant_identifier": "merchant.com.example"
}
```

### `POST /api/mobile/payments/confirm`

Request body:

```json
{
  "checkout_id": "pi_123",
  "order_reference": "uuid"
}
```

Response body:

```json
{
  "status": "authorized",
  "transaction_id": "ch_123",
  "message": null
}
```

Supported `status` values currently expected by the app:

- `authorized`
- `succeeded`
- `paid`
- `requires_action`
- any other value is treated as failed

## Owner-side expectations

Owner settings in the app now gate digital payments using:

- online payments enabled
- Apple Pay enabled
- payout account status: `Not Connected`, `Setup Pending`, `Connected`

Digital methods only appear to students when:

- digital payments are enabled globally
- the truck has online payments enabled
- payout setup status is `Connected`

## What still needs to be implemented

- run the SQL migration in:
  - [20260224_add_order_payment_columns.sql](/Users/kylerhu/NightBites/supabase/migrations/20260224_add_order_payment_columns.sql)
- Stripe Connect onboarding for trucks
- real Stripe PaymentIntent creation on the backend
- Stripe webhook handling for payment success/failure/refunds
- Stripe iOS SDK package installation in the project
- replacing placeholder checkout presentation with real PaymentSheet / Apple Pay presentation

## Next code step after your external setup

Once you have the Stripe package installed and credentials configured, replace the placeholder logic inside:

- `[StripePaymentPresenter.swift](/Users/kylerhu/NightBites/NightBites/Services/StripePaymentPresenter.swift)`

That presenter is where PaymentSheet and Apple Pay UI should actually be shown.
