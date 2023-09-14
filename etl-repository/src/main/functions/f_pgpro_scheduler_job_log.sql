do $plpgsql$
begin
execute format($func$
create or replace function f_pgpro_scheduler_job_log(
	i_job_id integer = null
	, i_job_name text = null
)
returns table(
	job_id integer
	, job_name text
	, scheduled_at timestamptz
	, started timestamptz
	, finished timestamptz
	, run_duration interval
	, status text
	, message text
)
language sql
security definer
as $function$
%s
$function$;			

comment on function f_pgpro_scheduler_job_log(
	integer
	, text
) is 'Журнал исполнения планировщика заданий pgpro_scheduler';
$func$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$func_body$
	select 
		t.cron as job_id
		, t.name as job_name
		, t.scheduled_at
		, t.started
		, t.finished
		, t.finished - t.started as run_duration		
		, t.status::text as status
		, t.message
	from 
		schedule.get_log() t
	where 
		(t.cron = i_job_id or i_job_id is null)
		and (t.name = i_job_name or i_job_name is null)
	$func_body$
else
	$func_body$
	select 
		null::integer as job_id
		, null::text as job_name
		, null::timestamptz as scheduled_at
		, null::timestamptz as started
		, null::timestamptz as finished
		, null::interval as run_duration		
		, null::text as status
		, null::text as message
	where 
		false
	$func_body$
end
);
end
$plpgsql$;		