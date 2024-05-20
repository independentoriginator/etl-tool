create or replace function ${mainSchemaName}.trf_publish_pgpro_scheduler_job_monitoring_event()
returns trigger
language plpgsql
as $$
declare
	l_event record;
begin
	for l_event in (			
		with
			scheduled_task as (
				select
					id
					, target_job_id
				from
					${mainSchemaName}.v_scheduled_task t
				where
					scheduler_type_name = 'pgpro_scheduler'
			)
		select 
			scheduled_task.id as scheduled_task_id
			, case
				when l.message ilike 'max instances limit reached%' then 'warning'
				else 'failure'
			end as status_name
			, l.message
		from
			new l
		join scheduled_task 
			on scheduled_task.target_job_id = l.cron
	)
	loop 
		call
			${mainSchemaName}.p_publish_scheduled_task_monitoring_event(
				i_scheduled_task_id => l_event.scheduled_task_id
				, i_event_type_name => 'launch'
				, i_event_status_name => l_event.status_name
				, i_process_uuid => ${mainSchemaName}.f_generate_uuid()
				, i_event_message => l_event.message
			)
		;
	end loop
	;
	return
		null
	;
end
$$;

comment on function trf_publish_pgpro_scheduler_job_monitoring_event(
) is 'Сервисы мониторинга. Планировщик заданий pgpro_scheduler. Триггерная функция для события "После вставки"'
;