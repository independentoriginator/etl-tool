create or replace view ${stagingSchemaName}.v_pgpro_scheduler_subjob
as
select 
	t.id
	, t.command
	, t.submit_time
	, t.start_time
	, t.finish_time
	, t.run_duration 
	, t.is_completed
	, t.is_failed
	, t.is_canceled
	, t.err_descr
	, t.executor
	, t.owner
from 
	${mainSchemaName}.f_pgpro_scheduler_subjob() t
;

comment on view ${stagingSchemaName}.v_pgpro_scheduler_subjob is 'Подзадачи плановых заданий pgpro_scheduler';