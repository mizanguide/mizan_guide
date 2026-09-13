-- Logging through the day. Run once in Supabase SQL Editor, AFTER checkin_times.sql, and BEFORE
-- the page with the "Log a moment" button goes live. Same privacy model as the rest: RLS on, no
-- policies, reachable only through token-gated functions.

create table if not exists public.mizan_logs (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.mizan_plans(id) on delete cascade,
  day_number int not null,
  trigger text check (trigger in ('bored', 'stressed', 'lonely', 'tired', 'saw', 'other')),
  outcome text not null check (outcome in ('held', 'happened')),
  created_at timestamptz not null default now()
);
create index if not exists mizan_logs_plan_day on public.mizan_logs (plan_id, day_number);
alter table public.mizan_logs enable row level security;

-- A moment belongs to the open day: the latest published day, or the day after it once that day
-- has been closed with a check-in (a log made after "End my day" counts toward tomorrow).
create or replace function public.log_moment(p_token uuid, p_trigger text, p_outcome text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan uuid;
  v_total int;
  v_day int;
  v_id uuid;
  v_at timestamptz;
begin
  select id, total_days into v_plan, v_total from mizan_plans where token = p_token and status = 'active';
  if v_plan is null then return null; end if;
  if p_outcome not in ('held', 'happened') then return null; end if;
  if p_trigger is not null and p_trigger not in ('bored', 'stressed', 'lonely', 'tired', 'saw', 'other') then return null; end if;

  select max(day_number) into v_day from mizan_plan_days
  where plan_id = v_plan and published_at is not null and published_at <= now();
  if v_day is null then return null; end if;
  if exists (select 1 from mizan_checkins where plan_id = v_plan and day_number = v_day) then
    if v_day >= v_total then return null; end if;
    v_day := v_day + 1;
  end if;
  if (select count(*) from mizan_logs where plan_id = v_plan and day_number = v_day) >= 100 then return null; end if;

  insert into mizan_logs (plan_id, day_number, trigger, outcome)
  values (v_plan, v_day, p_trigger, p_outcome)
  returning id, created_at into v_id, v_at;
  return json_build_object('id', v_id, 'day', v_day, 'at', v_at);
end;
$$;

-- Undo a mis-tap. Only while that day is still open (no check-in yet).
create or replace function public.remove_log(p_token uuid, p_id uuid)
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
  delete from mizan_logs l
  where l.id = p_id and l.plan_id = v_plan
    and not exists (select 1 from mizan_checkins c where c.plan_id = v_plan and c.day_number = l.day_number);
  return found;
end;
$$;

revoke all on function public.log_moment(uuid, text, text) from public;
grant execute on function public.log_moment(uuid, text, text) to anon;
revoke all on function public.remove_log(uuid, uuid) from public;
grant execute on function public.remove_log(uuid, uuid) to anon;

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
      select json_agg(json_build_object('day', c.day_number, 'did_it', c.did_it, 'times', c.times) order by c.day_number)
      from mizan_checkins c
      where c.plan_id = p.id
    ), '[]'::json),
    'logs', coalesce((
      select json_agg(json_build_object('id', l.id, 'day', l.day_number, 'trigger', l.trigger, 'outcome', l.outcome, 'at', l.created_at) order by l.created_at)
      from mizan_logs l
      where l.plan_id = p.id
    ), '[]'::json)
  )
  from mizan_plans p
  where p.token = p_token and p.status in ('active', 'done');
$$;

notify pgrst, 'reload schema';
