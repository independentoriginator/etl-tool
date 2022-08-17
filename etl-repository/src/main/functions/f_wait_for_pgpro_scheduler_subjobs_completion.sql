do $plpgsql$
begin
execute format($func$
create or replace function f_wait_for_pgpro_scheduler_subjobs_completion(
	i_scheduled_task_name ${mainSchemaName}.scheduled_task.internal_name%%type -- 'project_internal_name.scheduled_task_internal_name'
	, i_timeout_in_hours integer = 8
	, i_wait_for_delay_in_seconds integer = 5	
)
returns void
language plpgsql
as $function$
declare 
	l_scheduled_task_id ${mainSchemaName}.scheduled_task.id%%type;
	l_subjob_count integer;
	l_completed_count integer;
	l_error_count integer;
	l_start_timestamp timestamp := clock_timestamp();
begin
	%s
end
$function$;			
$func$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$func_body$
	select 
		t.id
	into 
		l_scheduled_task_id
	from 
		${mainSchemaName}.scheduled_task t
	join ${mainSchemaName}.project p
		on p.id = t.project_id
	where
		p.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\1')
		and t.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\2')
	;
	
	if l_scheduled_task_id is null then
		raise exception 'Unknown scheduled task specified: %', i_scheduled_task_name;
	end if;
	
	<<wait_for_completion>>
	loop
		select
			count(*)::integer as subjob_count
			, count(
				case when job_status.status = 'done' then 1 end
			)::integer as completed_count
			, count(
				case when not job_status.is_success then 1 end
			)::integer as error_count
		into 
			l_subjob_count
			, l_completed_count
			, l_error_count
		from 
			${stagingSchemaName}.scheduled_task_subjob subjob
		join schedule.job_status job_status
			on job_status.id = subjob.id
		where 
			subjob.scheduled_task_id = l_scheduled_task_id
		;
		
		if l_subjob_count = 0 then
			raise exception 'Neither subjob found for the scheduled task specified: %', i_scheduled_task_name;
		end if;

		if l_error_count > 0 then
			raise exception 'Scheduled task % subjob error count: %', i_scheduled_task_name, l_error_count;
		end if;
		
		if l_subjob_count - l_completed_count = 0 then 
			exit;
		end if;
		
		if extract(hours from clock_timestamp() - l_start_timestamp) >= i_timeout_in_hours then
			raise exception 'Timeout occured while waiting for the scheduled task completion: %', i_scheduled_task_name;
		end if;
			
		perform pg_sleep(i_wait_for_delay_in_seconds);
	end loop wait_for_completion;
	$func_body$
else
	$func_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$func_body$
end
);
end
$plpgsql$;						
			