drop trigger if exists tr_scheduled_task_invalidate_built_flag on scheduled_task;
create trigger tr_scheduled_task_invalidate_built_flag
before update 
on scheduled_task
for each row 
when (old.is_built = true)
execute function ${mainSchemaName}.trf_scheduled_task_before_update();
