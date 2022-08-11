do $plpgsql$
begin
execute format($view$
create or replace view v_pgpro_scheduler_job_log
as
%s
$view$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$view_query$
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
	$view_query$
else
	$view_query$
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
	$view_query$
end
);
end
$plpgsql$;						
			