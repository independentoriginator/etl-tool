do $plpgsql$
begin
execute format($func$
create or replace function f_pgpro_scheduler_subjob(i_subjob_id bigint = null)
returns table(
	id bigint
	, command text
	, submit_time timestamptz
	, start_time timestamptz
	, finish_time timestamptz
	, run_duration interval
	, is_completed boolean
	, is_failed boolean
	, is_canceled boolean	
	, err_descr text
	, executor text
	, owner text
)
language sql
security definer
as $function$
%s
$function$;			
$func$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$func_body$
	select 
		t.id
		, t.query as command
		, t.submit_time
		, t.start_time
		, t.done_time as finish_time
		, t.done_time - t.start_time as run_duration 
		, case when t.status = 'done' or t.canceled then true else false end as is_completed
		, case
			when t.status = 'done' and not t.is_success then true 
			else false 
		end as is_failed
		, t.canceled as is_canceled
		, t.error as err_descr
		, t.run_as as executor 
		, t.owner 
	from 
		schedule.all_job_status t
	where 
		t.id = i_subjob_id or i_subjob_id is null
	$func_body$
else
	$func_body$
	select 
		null::bigint as id
		, null::text as command
		, null::timestamptz as submit_time
		, null::timestamptz as start_time
		, null::timestamptz as finish_time
		, null::interval as run_duration 
		, null::boolean as is_completed
		, null::boolean as is_failed
		, null::boolean as is_canceled
		, null::text as err_descr
		, null::text as executor 
		, null::text as owner 
	where 
		false
	$func_body$
end
);
end
$plpgsql$;		