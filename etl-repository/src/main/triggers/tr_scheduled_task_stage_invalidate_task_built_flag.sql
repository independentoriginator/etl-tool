drop trigger if exists tr_scheduled_task_stage_invalidate_task_built_flag on scheduled_task_stage;
create trigger tr_scheduled_task_stage_invalidate_task_built_flag
after insert or update or delete
on scheduled_task_stage
for each row 
execute function ${mainSchemaName}.trf_scheduled_task_stage_after_update();
