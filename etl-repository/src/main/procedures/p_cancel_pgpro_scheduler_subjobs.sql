do $plpgsql$
begin
execute format($proc$
drop procedure if exists p_cancel_pgpro_scheduler_subjobs(${mainSchemaName}.scheduled_task.id%%type);

create or replace procedure p_cancel_pgpro_scheduler_subjobs(
	i_scheduled_task_id ${mainSchemaName}.scheduled_task.id%%type = null 
	, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
)
language plpgsql
as $procedure$
declare 
	l_scheduled_task_id ${mainSchemaName}.scheduled_task.id%%type := i_scheduled_task_id;
	l_job_id ${stagingSchemaName}.v_scheduled_task_subjob.id%%type;
begin
	%s
end
$procedure$;			
$proc$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$proc_body$
	if l_scheduled_task_id is null then
		select 
			t.id
		into 
			l_scheduled_task_id
		from ${mainSchemaName}.scheduled_task t
		join ${mainSchemaName}.project p
			on p.id = t.project_id
			and p.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\1')
		join ${mainSchemaName}.scheduler_type st
			on st.id = t.scheduler_type_id
			and st.internal_name = 'pgpro_scheduler'
		where 
			t.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\2')
		;
	end if;
		
	if l_scheduled_task_id is null then
		raise exception 'Unknown scheduled task specified: id = %, name = %', i_scheduled_task_id, i_scheduled_task_name;
	end if;
		
	for l_job_id in (
		select 
			subjob.id
		from 
			${stagingSchemaName}.v_scheduled_task_subjob subjob
		where 
			subjob.scheduled_task_id = l_scheduled_task_id
			and subjob.is_completed = false
	) loop
		if not schedule.cancel_job(job_id => l_job_id) then
			raise exception 'Cannot cancel the pgpro_scheduler one-time job %', l_job_id;		
		end if;
	end loop;
	$proc_body$
else
	$proc_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$proc_body$
end
);
end
$plpgsql$;							