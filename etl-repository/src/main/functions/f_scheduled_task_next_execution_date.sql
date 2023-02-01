create or replace function f_scheduled_task_next_execution_date(
	i_scheduled_task_name ${mainSchemaName}.v_scheduled_task.scheduled_task_name%type
)
returns timestamptz
language sql
stable
parallel safe
as $function$
select 
	ts
from 
	${mainSchemaName}.v_scheduled_task t
join lateral ${mainSchemaName}.f_cron_expr_timestamps(
		i_cron_expr => t.cron_expr 
		, i_time_from => current_timestamp
		, i_time_to => 
			case 
				when t.scheduler_type_name = 'pgpro_scheduler' and not ${mainSchemaName}.f_is_pgpro_scheduler_curr_transaction_succeeded() then
					current_timestamp + make_interval(mins => t.retry_interval_in_minutes)
				else null 
			end
	) ts
	on true
where
	t.scheduled_task_name = i_scheduled_task_name
order by 
	1
limit 1
$function$;		