create or replace procedure p_wait_for_scheduled_task_subjobs_completion(
	i_scheduled_task_name text -- 'project_internal_name.scheduled_task_internal_name'
	, i_timeout_in_hours integer = 8
	, i_wait_for_delay_in_seconds integer = 5	
)
language plpgsql
as $procedure$
declare 
	l_scheduled_task_id ${mainSchemaName}.scheduled_task.id%type;
	l_subjob_count integer;
	l_completed_count integer;
	l_failed_count integer;
	l_start_timestamp timestamp := clock_timestamp();
begin
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
				case when subjob.is_completed then 1 end
			)::integer as completed_count
			, count(
				case when subjob.is_failed then 1 end
			)::integer as failed_count
		into 
			l_subjob_count
			, l_completed_count
			, l_failed_count
		from 
			${stagingSchemaName}.v_scheduled_task_subjob subjob
		where 
			subjob.scheduled_task_id = l_scheduled_task_id
		;
		
		if l_subjob_count = 0 then
			raise notice 'Neither subjob found for the scheduled task specified: %', i_scheduled_task_name;
			exit;
		end if;

		if l_failed_count > 0 then
			raise exception 'Scheduled task % failed subjob count: %', i_scheduled_task_name, l_failed_count;
		end if;
		
		if l_subjob_count - l_completed_count = 0 then 
			exit;
		end if;
		
		if extract(hours from clock_timestamp() - l_start_timestamp) >= i_timeout_in_hours then
			raise exception 'Timeout occured while waiting for the scheduled task completion: %', i_scheduled_task_name;
		end if;
			
		perform pg_sleep(i_wait_for_delay_in_seconds);
	end loop wait_for_completion;
end
$procedure$;
				
			