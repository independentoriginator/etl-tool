do $plpgsql$
begin
execute format($view$
create or replace view ${stagingSchemaName}.v_pgpro_scheduler_subjob
as
%s
$view$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$view_query$
	select 
		t.id
		, t.query as command
		, t.start_time
		, t.done_time as finish_time
		, t.done_time - t.start_time as run_duration 
		, case when t.status = 'done' or t.canceled then true else false end as is_completed
		, case
			when t.canceled then true
			when t.status = 'done' and not t.is_success then true 
			else false 
		end as is_failed
	from 
		schedule.job_status t
	$view_query$
else
	$view_query$
	select 
		null::bigint as id
		, null::text as command
		, null::timestamptz as start_time
		, null::timestamptz as finish_time
		, null::timestamptz as run_duration 
		, null::boolean as is_completed
		, null::boolean as is_failed
	where 
		false
	$view_query$
end
);
end
$plpgsql$;						
			