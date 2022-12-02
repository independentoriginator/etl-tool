drop procedure if exists p_wait_for_scheduled_task_subjobs_completion(
	text
	, integer
	, integer
);

create or replace procedure p_wait_for_scheduled_task_subjobs_completion(
	i_scheduled_task_name text -- 'project_internal_name.scheduled_task_internal_name'
	, i_scheduled_task_stage_ord_pos integer
	, i_timeout_in_hours integer = 8
	, i_wait_for_delay_in_seconds integer = 5	
)
language plpgsql
as $procedure$
declare 
	l_scheduled_task_stage_id ${mainSchemaName}.scheduled_task_stage.id%type;
	l_subjob_count integer;
	l_completed_count integer;
	l_failed_count integer;
	l_err_descr text;
	l_start_timestamp timestamp := clock_timestamp();
begin
	select 
		s.id
	into 
		l_scheduled_task_stage_id
	from 
		${mainSchemaName}.scheduled_task t
	join ${mainSchemaName}.project p
		on p.id = t.project_id
		and p.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\1')
	join ${mainSchemaName}.scheduled_task_stage s
		on s.scheduled_task_id = t.id
		and s.ordinal_position = i_scheduled_task_stage_ord_pos
	where
		t.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\2')
	;
	
	if l_scheduled_task_stage_id is null then
		raise exception 'Unknown scheduled task stage specified: %.%', i_scheduled_task_name, i_scheduled_task_stage_ord_pos;
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
			, string_agg(subjob.err_descr, E'\n') as err_descr 
		into 
			l_subjob_count
			, l_completed_count
			, l_failed_count
			, l_err_descr
		from 
			${stagingSchemaName}.v_scheduled_task_subjob subjob
		where 
			subjob.scheduled_task_stage_id = l_scheduled_task_stage_id
		;
		
		if l_subjob_count = 0 then
			raise warning 'Neither subjob found for the scheduled task specified: %', i_scheduled_task_name;
			exit;
		end if;

		if l_failed_count > 0 then
			raise exception E'Scheduled task % failed subjob count: %\n%', i_scheduled_task_name, l_failed_count, l_err_descr;
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
				
			