drop procedure if exists 
	p_publish_scheduled_task_monitoring_event(
		${mainSchemaName}.scheduled_task.id%type
		, ${mainSchemaName}.monitoring_event_type.internal_name%type
		, ${mainSchemaName}.monitoring_event_status.internal_name%type
		, uuid
		, text
	)
;

create or replace procedure 
	p_publish_scheduled_task_monitoring_event(
		i_scheduled_task_id ${mainSchemaName}.scheduled_task.id%type
		, i_event_type_name ${mainSchemaName}.monitoring_event_type.internal_name%type
		, i_event_status_name ${mainSchemaName}.monitoring_event_status.internal_name%type
		, i_event_message text = null
	)
language plpgsql
as $procedure$
declare 
	l_publication record;
begin
	for l_publication in (
		select 
			${mainSchemaName}.f_substitute(
				i_text => ms.event_publication_cmd_tmpl
				, i_keys => 
					array[
						'{{monitoring_service_external_id}}'
						, '{{monitoring_service_external_code}}'
						, '{{scheduled_task_external_id}}'
						, '{{scheduled_task_external_code}}'
						, '{{monitoring_event_type_code}}'
						, '{{scheduled_task_event_type_external_code}}'
						, '{{monitoring_event_status_code}}'
						, '{{monitoring_event_message}}'
					]::text[]
				, i_values => 
					array[
						ms.external_id
						, ms.external_code
						, pub.external_id
						, pub.external_code
						, coalesce((
								select
									service_event_type.external_code
								from 
									${mainSchemaName}.monitoring_service_event_type service_event_type
								join ${mainSchemaName}.monitoring_event_type event_type
									on event_type.id = service_event_type.monitoring_event_type_id
									and event_type.internal_name = i_event_type_name
								where 
									service_event_type.monitoring_service_id = pub.monitoring_service_id
							)
							, i_event_type_name
						)
						, coalesce((
								select
									scheduled_task_event_type.external_code
								from 
									${mainSchemaName}.monitoring_service_scheduled_task_event_type scheduled_task_event_type
								join ${mainSchemaName}.monitoring_event_type event_type
									on event_type.id = scheduled_task_event_type.monitoring_event_type_id
									and event_type.internal_name = i_event_type_name
								where 
									scheduled_task_event_type.monitoring_service_id = pub.monitoring_service_id
									and scheduled_task_event_type.scheduled_task_id = pub.scheduled_task_id
							)
							, i_event_type_name
						)
						, coalesce((
								select
									service_event_status.external_code
								from 
									${mainSchemaName}.monitoring_service_event_status service_event_status
								join ${mainSchemaName}.monitoring_event_status event_status
									on event_status.id = service_event_status.monitoring_event_status_id
									and event_status.internal_name = i_event_status_name
								where 
									service_event_status.monitoring_service_id = pub.monitoring_service_id
							)
							, i_event_status_name
						)
						, i_event_message
					]::text[]
			) as event_publication_cmd
		from 
			${mainSchemaName}.scheduled_task_monitor_publication pub
		join ${mainSchemaName}.monitoring_service ms
			on ms.id = pub.monitoring_service_id
		where 
			pub.scheduled_task_id = i_scheduled_task_id
			and not pub.is_disabled
	)
	loop
		execute 
			l_publication.event_publication_cmd
		;		
	end loop
	;
end
$procedure$
;			

comment on procedure p_publish_scheduled_task_monitoring_event(
	${mainSchemaName}.scheduled_task.id%type
	, ${mainSchemaName}.monitoring_event_type.internal_name%type
	, ${mainSchemaName}.monitoring_event_status.internal_name%type
	, text
) is 'Опубликовать событие в рамках мониторинга планового задания'
;
