-- Run this once in Supabase: Project > SQL Editor > New query > paste all > Run.
-- Creates the table the landing page form writes to, and locks it down so the
-- public anon key (the one embedded in index.html) can only INSERT rows, never
-- read, update, or delete them. Only you, logged into the Supabase dashboard,
-- can see submissions (dashboard access uses your own login, not this policy).

create table if not exists public.mizan_leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  instagram text not null,
  email text,
  struggle text,
  timing text,
  duration text,
  tried text,
  more text,
  source_path text
);

alter table public.mizan_leads enable row level security;

create policy "anon can insert leads"
  on public.mizan_leads
  for insert
  to anon
  with check (true);

-- No select/update/delete policy for anon or authenticated on purpose.
-- To view submissions: Supabase dashboard > Table Editor > mizan_leads.

-- Analytics events (page views, section views, form start/submit, outbound clicks).
-- Different policy on purpose: this table carries NO personal content (no struggle text,
-- no instagram handle, no email), just event names and counts, so unlike mizan_leads it's
-- safe to let the public anon key both insert AND read. That means Claude can query real
-- funnel numbers directly via the anon key without needing a screenshot or a service_role
-- key, while mizan_leads (which holds people's private disclosures) stays insert-only.

create table if not exists public.mizan_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  event_type text not null,
  source_path text,
  referrer text,
  meta jsonb
);

alter table public.mizan_events enable row level security;

create policy "anon can insert events"
  on public.mizan_events
  for insert
  to anon
  with check (true);

create policy "anon can read events"
  on public.mizan_events
  for select
  to anon
  using (true);
