-- Mizan daily plans. Run once: Supabase > SQL Editor > New query > paste all > Run.
--
-- Privacy model, deliberately stricter than mizan_events: all three tables have RLS on and NO
-- policies, so the public anon key embedded in the site cannot read or write any of them
-- directly. The plan page only ever talks to two functions below, and both require the plan's
-- secret token. Nobody can list plans, guess another person's plan, or read anyone's notes.
-- Writing the days themselves happens only with the service_role key, from Anas's machine.

create table if not exists public.mizan_plans (
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),
  label text not null,
  status text not null default 'pending_payment'
    check (status in ('pending_payment', 'active', 'paused', 'done')),
  total_days int not null default 14,
  started_on date,
  created_at timestamptz not null default now()
);

create table if not exists public.mizan_plan_days (
  plan_id uuid not null references public.mizan_plans(id) on delete cascade,
  day_number int not null check (day_number between 1 and 90),
  title text not null,
  step text not null,
  why text,
  source text,
  published_at timestamptz,
  primary key (plan_id, day_number)
);

create table if not exists public.mizan_checkins (
  plan_id uuid not null references public.mizan_plans(id) on delete cascade,
  day_number int not null,
  did_it text not null check (did_it in ('done', 'partly', 'not_yet')),
  note text,
  created_at timestamptz not null default now(),
  primary key (plan_id, day_number)
);

alter table public.mizan_plans enable row level security;
alter table public.mizan_plan_days enable row level security;
alter table public.mizan_checkins enable row level security;

-- Returns null unless the plan is active or done, so a plan waiting on payment shows the
-- "starts once payment is confirmed" state and nothing else. Only published days come back,
-- and check-ins come back without their notes.
create or replace function public.get_plan(p_token uuid)
returns json
language sql
security definer
set search_path = public
stable
as $$
  select json_build_object(
    'ref', left(p.id::text, 8),
    'status', p.status,
    'total_days', p.total_days,
    'started_on', p.started_on,
    'days', coalesce((
      select json_agg(json_build_object(
        'day', d.day_number, 'title', d.title, 'step', d.step, 'why', d.why, 'source', d.source
      ) order by d.day_number)
      from mizan_plan_days d
      where d.plan_id = p.id and d.published_at is not null and d.published_at <= now()
    ), '[]'::json),
    'checkins', coalesce((
      select json_agg(json_build_object('day', c.day_number, 'did_it', c.did_it) order by c.day_number)
      from mizan_checkins c
      where c.plan_id = p.id
    ), '[]'::json)
  )
  from mizan_plans p
  where p.token = p_token and p.status in ('active', 'done');
$$;

create or replace function public.submit_checkin(p_token uuid, p_day int, p_did_it text, p_note text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan uuid;
begin
  select id into v_plan from mizan_plans where token = p_token and status = 'active';
  if v_plan is null then return false; end if;
  if p_did_it not in ('done', 'partly', 'not_yet') then return false; end if;
  if not exists (
    select 1 from mizan_plan_days
    where plan_id = v_plan and day_number = p_day and published_at is not null and published_at <= now()
  ) then return false; end if;

  insert into mizan_checkins (plan_id, day_number, did_it, note)
  values (v_plan, p_day, p_did_it, left(nullif(trim(p_note), ''), 2000))
  on conflict (plan_id, day_number)
  do update set did_it = excluded.did_it, note = excluded.note, created_at = now();
  return true;
end;
$$;

revoke all on function public.get_plan(uuid) from public;
grant execute on function public.get_plan(uuid) to anon;
revoke all on function public.submit_checkin(uuid, int, text, text) from public;
grant execute on function public.submit_checkin(uuid, int, text, text) to anon;

-- ---------------------------------------------------------------------------------------------
-- Hard payment wall. Each quiz submission carries a short reference code (MZ-XXXXX) that the
-- payer writes in the bank transfer remarks. Payment details are NOT in this public file or the
-- site's code: they live in mizan_settings (no policies, unreadable directly) and are returned
-- only to someone holding the reference code of a real submission.

alter table public.mizan_leads add column if not exists ref text unique;
alter table public.mizan_leads add column if not exists payment_status text not null default 'unpaid';

create table if not exists public.mizan_settings (
  key text primary key,
  value jsonb not null
);
alter table public.mizan_settings enable row level security;

create or replace function public.get_payment_details(p_ref text)
returns json
language sql
security definer
set search_path = public
stable
as $$
  select s.value::json
  from mizan_settings s
  where s.key = 'payment'
    and exists (select 1 from mizan_leads l where l.ref = p_ref);
$$;

-- The page can only move a lead to "claimed" (I've sent it) or "wants_card" (outside Pakistan).
-- Only Anas, with the service_role key, ever marks a lead "paid".
create or replace function public.set_lead_payment(p_ref text, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('claimed', 'wants_card') then return false; end if;
  update mizan_leads set payment_status = p_status
  where ref = p_ref and payment_status in ('unpaid', 'claimed', 'wants_card');
  return found;
end;
$$;

revoke all on function public.get_payment_details(text) from public;
grant execute on function public.get_payment_details(text) to anon;
revoke all on function public.set_lead_payment(text, text) from public;
grant execute on function public.set_lead_payment(text, text) to anon;

-- New columns and functions are invisible to the API until its schema cache reloads.
notify pgrst, 'reload schema';

-- Later migration, 2026-09-13: the check-in also records how many times it happened that day,
-- and submit_checkin / get_plan carry the count. See checkin_times.sql, which must be run after
-- everything above (it replaces the 4-argument submit_checkin with a 5-argument one).
