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
	l_command text := '';
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
		l_command := 
			l_command 
			|| case when length(l_command) > 0 then '; ' else '' end
			|| format('schedule.cancel_job(job_id => %s)', l_job_id)
		;
	end loop;

	if length(l_command) > 0 then
		if schedule.submit_job(l_command) is null then
			raise exception 'Cannot create one-time pgpro_scheduler job';		
		end if;
	end if;
	$proc_body$
else
	$proc_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$proc_body$
end
);
end
$plpgsql$;							