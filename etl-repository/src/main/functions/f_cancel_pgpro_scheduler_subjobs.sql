do $plpgsql$
begin
execute format($func$
drop procedure if exists p_cancel_pgpro_scheduler_subjobs(
	${mainSchemaName}.scheduled_task.id%%type
	, text
);

create or replace function f_cancel_pgpro_scheduler_subjobs(
	i_scheduled_task_id ${mainSchemaName}.scheduled_task.id%%type = null 
	, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
	, i_scheduled_task_stage_id ${mainSchemaName}.scheduled_task_stage.id%%type = null 
)
returns void
language plpgsql
as $function$
declare 
	l_scheduled_task_id ${mainSchemaName}.scheduled_task.id%%type := i_scheduled_task_id;
	l_job_id ${stagingSchemaName}.v_scheduled_task_subjob.id%%type;
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
	if l_scheduled_task_id is null then
		if i_scheduled_task_stage_id is null then
			l_scheduled_task_id := 
				${mainSchemaName}.f_scheduled_task_id(
					i_scheduled_task_name => i_scheduled_task_name
				);
		else
			select 
				t.scheduled_task_id
			into 
				l_scheduled_task_id
			from 
				${mainSchemaName}.scheduled_task_stage t
			where 
				t.id = i_scheduled_task_stage_id
			;
		end if;
	end if;
		
	if l_scheduled_task_id is null then
		raise exception 
			'Unknown scheduled task specified: id = %, name = %, stage = %'
			, i_scheduled_task_id
			, i_scheduled_task_name
			, i_scheduled_task_stage_id
		;
	end if;
		
	for l_job_id in (
		select 
			subjob.id
		from 
			${stagingSchemaName}.v_scheduled_task_subjob subjob
		where 
			subjob.scheduled_task_id = l_scheduled_task_id
			and (subjob.scheduled_task_stage_id = i_scheduled_task_stage_id or i_scheduled_task_stage_id is null)
			and subjob.is_completed = false
	) loop
		if not schedule.cancel_job(job_id => l_job_id) then
			raise exception 'Cannot cancel the pgpro_scheduler one-time job %', l_job_id;		
		end if;
	end loop;
	$func_body$
else
	$func_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$func_body$
end
);
end
$plpgsql$;							