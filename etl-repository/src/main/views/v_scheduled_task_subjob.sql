drop view if exists ${stagingSchemaName}.v_scheduled_task_subjob;

create view ${stagingSchemaName}.v_scheduled_task_subjob
as
with 
	target_subjob as (
		select
			'pgpro_scheduler' as scheduler_type_name
			, t.id
			, t.command
			, t.submit_time
			, t.start_time
			, t.finish_time
			, t.run_duration 
			, t.is_completed
			, t.is_failed
			, t.is_canceled
			, t.err_descr
		from 
			${mainSchemaName}.f_pgpro_scheduler_subjob() t
	)
select
	scheduled_task_stage.scheduled_task_id
	, scheduled_task_stage.id as scheduled_task_stage_id
	, target_subjob.scheduler_type_name
	, target_subjob.id
	, target_subjob.command
	, target_subjob.submit_time
	, target_subjob.start_time
	, target_subjob.finish_time
	, target_subjob.run_duration 
	, target_subjob.is_completed
	, target_subjob.is_failed
	, target_subjob.is_canceled
	, target_subjob.err_descr
from 
	${stagingSchemaName}.scheduled_task_subjob subjob
join ${mainSchemaName}.scheduled_task_stage scheduled_task_stage
	on scheduled_task_stage.id = subjob.scheduled_task_stage_id
join ${mainSchemaName}.scheduled_task scheduled_task
	on scheduled_task.id = scheduled_task_stage.scheduled_task_id
join ${mainSchemaName}.scheduler_type scheduler_type
	on scheduler_type.id = scheduled_task.scheduler_type_id
join target_subjob
	on target_subjob.id = subjob.id
	and target_subjob.scheduler_type_name = scheduler_type.internal_name 
;

grant select on ${stagingSchemaName}.v_scheduled_task_subjob to ${etlUserRole};