create or replace procedure p_build_target_scheduled_tasks()
language plpgsql
as $procedure$
declare 
	l_job_rec record;
begin
	for l_job_rec in (
		select
			t.*
		from 
			${mainSchemaName}.v_scheduled_task t
		join ${mainSchemaName}.scheduled_task scheduled_task 
			on scheduled_task.id = t.id
		where 
			coalesce(t.is_built, false) = false
		for update of scheduled_task
	) 
	loop
		if l_job_rec.scheduler_type_name = 'pgpro_scheduler' then
			call ${mainSchemaName}.p_build_target_pgpro_scheduler_job(
				i_job_rec => l_job_rec
			);
		else
			raise notice 'The scheduler type specified is not supported: %', l_job_rec.scheduler_type_name;
			continue;
		end if;
			
		update ${mainSchemaName}.scheduled_task 
		set is_built = true
		where id = l_job_rec.id
		;
	end loop;
end
$procedure$;			
