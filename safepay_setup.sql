-- Safepay checkout (added 2026-09-25). Run once in Supabase > SQL Editor, AFTER plans_setup.sql,
-- and BEFORE pushing the site. Only the `safepay` edge function (service_role) writes these columns;
-- the anon key still cannot read or update mizan_leads.

alter table public.mizan_leads add column if not exists safepay_tracker text;
alter table public.mizan_leads add column if not exists paid_at timestamptz;
alter table public.mizan_leads add column if not exists paid_amount_pkr int;
alter table public.mizan_leads add column if not exists payment_method text;
