create or replace view ${stagingSchemaName}.v_pgpro_scheduler_subjob
as
select 
	t.id
	, t.command
	, t.start_time
	, t.finish_time
	, t.run_duration 
	, t.is_completed
	, t.is_failed
	, t.err_descr
from 
	${mainSchemaName}.f_pgpro_scheduler_subjob() t
;