create or replace function f_scheduled_task_id(
	i_scheduled_task_name ${mainSchemaName}.v_scheduled_task.scheduled_task_name%type
)
returns ${mainSchemaName}.scheduled_task.id%type
language sql
stable
parallel safe
as $function$
select 
	t.id
from 
	${mainSchemaName}.scheduled_task t
join ${mainSchemaName}.project p
	on p.id = t.project_id
	and p.internal_name = regexp_replace(i_scheduled_task_name, '(?:(.+?)\.(.+)){1,1}', '\1')
where 
	t.internal_name = regexp_replace(i_scheduled_task_name, '(?:(.+?)\.(.+)){1,1}', '\2')
$function$;		

comment on function f_scheduled_task_id(
	${mainSchemaName}.v_scheduled_task.scheduled_task_name%type
) is 'Идентификатор планового задания';