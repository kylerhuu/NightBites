alter table public.orders
  add column if not exists subtotal_amount double precision,
  add column if not exists service_fee_amount double precision,
  add column if not exists charged_total_amount double precision,
  add column if not exists payment_status text,
  add column if not exists payment_transaction_id text;

update public.orders
set
  subtotal_amount = coalesce(subtotal_amount, total_amount),
  service_fee_amount = coalesce(service_fee_amount, 0),
  charged_total_amount = coalesce(charged_total_amount, total_amount),
  payment_status = coalesce(
    payment_status,
    case
      when payment_method = 'Pay at Pickup' then 'Pay on Pickup'
      else 'Authorized'
    end
  )
where
  subtotal_amount is null
  or service_fee_amount is null
  or charged_total_amount is null
  or payment_status is null;

alter table public.orders
  alter column subtotal_amount set default 0,
  alter column service_fee_amount set default 0,
  alter column charged_total_amount set default 0,
  alter column payment_status set default 'Pay on Pickup';

update public.orders
set
  subtotal_amount = 0
where subtotal_amount is null;

update public.orders
set
  service_fee_amount = 0
where service_fee_amount is null;

update public.orders
set
  charged_total_amount = 0
where charged_total_amount is null;

update public.orders
set
  payment_status = 'Pay on Pickup'
where payment_status is null;

alter table public.orders
  alter column subtotal_amount set not null,
  alter column service_fee_amount set not null,
  alter column charged_total_amount set not null,
  alter column payment_status set not null;
