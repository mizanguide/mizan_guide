-- Lets a day's citation sit in the middle of its own narrative instead of always landing after
-- the whole step (numbered actions included), which was breaking flow when the step text
-- referred forward to a quote ("described exactly this, below:") that then rendered after
-- content that already assumed the reader had seen it. Run once, AFTER logs_setup.sql.

alter table public.mizan_plan_days add column if not exists step_after text;

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
        'day', d.day_number, 'title', d.title, 'step', d.step, 'why', d.why, 'source', d.source,
        'step_after', d.step_after
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
      select json_agg(json_build_object('id', l.id, 'day', l.day_number, 'trigger', l.trigger, 'outcome', l.outcome, 'note', l.note, 'at', l.created_at) order by l.created_at)
      from mizan_logs l
      where l.plan_id = p.id
    ), '[]'::json)
  )
  from mizan_plans p
  where p.token = p_token and p.status in ('active', 'done');
$$;

notify pgrst, 'reload schema';
