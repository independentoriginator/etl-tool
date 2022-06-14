create or replace function trf_scheduled_task_stage_after_update()
returns trigger
language plpgsql
as $$
begin
	update ${mainSchemaName}.scheduled_task
	set is_built = false
	where id = coalesce(new.scheduled_task_id, old.scheduled_task_id)
	;
		
	return null;
end
$$;			
