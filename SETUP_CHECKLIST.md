# Setup Checklist

Do these in order.

## App

Already done in code:

- local `PAYMENTS_API_BASE_URL` points to `http://127.0.0.1:3000`
- digital payments are still off by default
- app is ready for Stripe-style checkout

You still need to fill in later:

- `STRIPE_PUBLISHABLE_KEY` in [Info.plist](/Users/kylerhu/NightBites/Info.plist)
- `STRIPE_MERCHANT_IDENTIFIER` in [Info.plist](/Users/kylerhu/NightBites/Info.plist)
- `ENABLE_DIGITAL_PAYMENTS = true` in [Info.plist](/Users/kylerhu/NightBites/Info.plist)

## Backend

1. Copy:

```bash
cd /Users/kylerhu/NightBites/backend
cp .env.example .env
```

2. Install packages:

```bash
npm install
```

3. Put these in `backend/.env`:

- `STRIPE_SECRET_KEY=sk_test_...`
- `STRIPE_WEBHOOK_SECRET=whsec_...`
- `STRIPE_MERCHANT_IDENTIFIER=merchant.com.your.app`

4. Start backend:

```bash
npm run dev
```

5. Check:

- [http://127.0.0.1:3000/health](http://127.0.0.1:3000/health)

## Supabase

Run the migration:

- [20260224_add_order_payment_columns.sql](/Users/kylerhu/NightBites/supabase/migrations/20260224_add_order_payment_columns.sql)

## Stripe / Apple

Still external:

- create Stripe account
- enable Connect
- create Apple Pay merchant ID
- install Stripe iOS SDK package in Xcode

## Final code step after that

Replace the placeholder presenter logic in:

- [StripePaymentPresenter.swift](/Users/kylerhu/NightBites/NightBites/Services/StripePaymentPresenter.swift)
