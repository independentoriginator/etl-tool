create or replace function f_scheduled_task_last_execution_date(
	i_scheduled_task_name ${mainSchemaName}.v_scheduled_task.scheduled_task_name%type
)
returns timestamptz
language sql
security definer
stable
parallel safe
as $function$
select 
	case t.scheduler_type_name
		when 'pgpro_scheduler' then (
			select 
				log.started
			from 
				${mainSchemaName}.f_pgpro_scheduler_job_log(
					i_job_name => t.job_name
				) log
			where 
				log.status = 'done'
			order by 
				log.started desc
			limit 1					
		)
	end
from 
	${mainSchemaName}.v_scheduled_task t
where
	t.scheduled_task_name = i_scheduled_task_name
$function$;		