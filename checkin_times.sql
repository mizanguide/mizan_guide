-- Adds "how many times did it happen today" to plan check-ins. Run once in Supabase SQL Editor
-- BEFORE the page that asks the question goes live (the page calls the 5-argument function).
-- Same privacy model as plans_setup.sql: the count is only readable through get_plan(token).

alter table public.mizan_checkins add column if not exists times int check (times between 0 and 99);

-- The old 4-argument version has to go, or the API cannot tell the two apart.
drop function if exists public.submit_checkin(uuid, int, text, text);

create or replace function public.submit_checkin(p_token uuid, p_day int, p_did_it text, p_note text, p_times int)
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
  if p_times is not null and (p_times < 0 or p_times > 99) then return false; end if;
  if not exists (
    select 1 from mizan_plan_days
    where plan_id = v_plan and day_number = p_day and published_at is not null and published_at <= now()
  ) then return false; end if;

  insert into mizan_checkins (plan_id, day_number, did_it, note, times)
  values (v_plan, p_day, p_did_it, left(nullif(trim(p_note), ''), 2000), p_times)
  on conflict (plan_id, day_number)
  do update set did_it = excluded.did_it, note = excluded.note, times = excluded.times, created_at = now();
  return true;
end;
$$;

revoke all on function public.submit_checkin(uuid, int, text, text, int) from public;
grant execute on function public.submit_checkin(uuid, int, text, text, int) to anon;

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
    ), '[]'::json)
  )
  from mizan_plans p
  where p.token = p_token and p.status in ('active', 'done');
$$;

notify pgrst, 'reload schema';
