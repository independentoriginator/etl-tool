create or replace view ${stagingSchemaName}.v_scheduled_task_subjob
as
with 
	target_subjob as (
		select
			'pgpro_scheduler' as scheduler_type_name
			, t.id
			, t.command
			, t.start_time
			, t.finish_time
			, t.run_duration 
			, t.is_completed
			, t.is_failed
			, t.err_descr
		from 
			${stagingSchemaName}.v_pgpro_scheduler_subjob t
	)
select
	subjob.scheduled_task_id
	, target_subjob.scheduler_type_name
	, target_subjob.id
	, target_subjob.command
	, target_subjob.start_time
	, target_subjob.finish_time
	, target_subjob.run_duration 
	, target_subjob.is_completed
	, target_subjob.is_failed
	, target_subjob.err_descr
from 
	${stagingSchemaName}.scheduled_task_subjob subjob
join ${mainSchemaName}.scheduled_task scheduled_task
	on scheduled_task.id = subjob.scheduled_task_id
join ${mainSchemaName}.scheduler_type scheduler_type
	on scheduler_type.id = scheduled_task.scheduler_type_id
join target_subjob
	on target_subjob.id = subjob.id
	and target_subjob.scheduler_type_name = scheduler_type.internal_name 
;