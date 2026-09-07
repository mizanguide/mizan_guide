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
