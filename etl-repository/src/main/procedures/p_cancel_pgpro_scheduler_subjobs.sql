do $plpgsql$
begin
execute format($proc$
create or replace procedure p_cancel_pgpro_scheduler_subjobs(
	i_scheduled_task_id ${mainSchemaName}.scheduled_task.id%%type 
)
language plpgsql
as $procedure$
declare 
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
	for l_job_id in (
		select 
			subjob.id
		from 
			${stagingSchemaName}.v_scheduled_task_subjob subjob
		where 
			subjob.scheduled_task_id = i_scheduled_task_id
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