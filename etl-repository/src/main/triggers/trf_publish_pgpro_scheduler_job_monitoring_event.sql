create or replace function ${mainSchemaName}.trf_publish_pgpro_scheduler_job_monitoring_event()
returns trigger
language plpgsql
as $$
declare
	l_event record;
	l_exception_descr text;
begin
	for l_event in (
		select
			t.id as scheduled_task_id
			, case
				when new.message ilike 'max instances limit reached%' then 'warning'
				else 'failure'
			end as status_name
			, new.message
		from
			${mainSchemaName}.v_scheduled_task t
		where
			t.target_job_id = new.cron
			and t.scheduler_type_name = 'pgpro_scheduler'
	)
	loop 
		call
			${mainSchemaName}.p_publish_scheduled_task_monitoring_event(
				i_scheduled_task_id => l_event.scheduled_task_id
				, i_event_type_name => 'launch'
				, i_event_status_name => l_event.status_name
				, i_event_message => l_event.message
			)
		;
	end loop
	;
	return
		new
	;
exception
when others then
	get stacked diagnostics
		l_exception_descr = MESSAGE_TEXT
	;

	new.message := 
		concat_ws(
			E'\n'
			, new.message
			, l_exception_descr
		)
	;

	return
		new
	;
end
$$;

comment on function trf_publish_pgpro_scheduler_job_monitoring_event(
) is 'Сервисы мониторинга. Планировщик заданий pgpro_scheduler. Триггерная функция для события "После вставки"'
;