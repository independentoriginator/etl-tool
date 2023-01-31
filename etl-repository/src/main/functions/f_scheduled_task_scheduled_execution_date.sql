create or replace function f_scheduled_task_scheduled_execution_date(
	i_scheduled_task ${mainSchemaName}.v_scheduled_task%type
)
returns timestamptz
language sql
stable
parallel safe
as $function$
select 
	to_timestamp(
		extract(year from current_date)::varchar
		|| 
	)

	cron_expr_minutes varchar(63) NULL,
	cron_expr_hours varchar(63) NULL,
	cron_expr_dom varchar(63) NULL,
	cron_expr_month varchar(63) NULL,
	cron_expr_dow varchar(63) NULL,

	case 
		when t.scheduler_type_name = 'pgpro_scheduler' and not ${mainSchemaName}.f_is_pgpro_scheduler_curr_transaction_succeeded() then
			now() + make_interval(minutes => t.retry_interval_in_minutes)
		else
	end
	
	, t.retry_interval_in_minutes
	, t.retry_max_count
	
from 
	${mainSchemaName}.v_scheduled_task t
where
	t.scheduled_task_name = i_scheduled_task_name
$function$;		