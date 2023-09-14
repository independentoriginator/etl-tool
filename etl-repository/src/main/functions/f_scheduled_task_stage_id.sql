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
	${mainSchemaName}.scheduled_task t
join ${mainSchemaName}.project p
	on p.id = t.project_id
	and p.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\1')
join ${mainSchemaName}.scheduled_task_stage s
	on s.scheduled_task_id = t.id
	and s.ordinal_position = i_scheduled_task_stage_ord_pos
where
	t.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\2')
$function$;	

comment on function f_scheduled_task_stage_id(
	${mainSchemaName}.v_scheduled_task.scheduled_task_name%type
	, integer
) is 'Идентификатор этапа планового задания';