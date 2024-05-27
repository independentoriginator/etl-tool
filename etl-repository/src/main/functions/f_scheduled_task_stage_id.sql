create or replace function f_scheduled_task_stage_id(
	i_scheduled_task_name ${mainSchemaName}.v_scheduled_task.scheduled_task_name%type
	, i_scheduled_task_stage_ord_pos integer
)
returns ${mainSchemaName}.scheduled_task_stage.id%type
language sql
stable
parallel safe
as $function$
select 
	s.id
from 
	${mainSchemaName}.scheduled_task_stage s
where
	s.scheduled_task_id = 
		${mainSchemaName}.f_scheduled_task_id(
			i_scheduled_task_name => i_scheduled_task_name
		)
	and s.ordinal_position = i_scheduled_task_stage_ord_pos
$function$;	

comment on function f_scheduled_task_stage_id(
	${mainSchemaName}.v_scheduled_task.scheduled_task_name%type
	, integer
) is 'Идентификатор этапа планового задания';