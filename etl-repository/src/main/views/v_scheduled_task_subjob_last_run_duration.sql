drop view if exists v_scheduled_task_subjob_last_run_duration;

create view v_scheduled_task_subjob_last_run_duration
as
with 
	subjob as (
		select
			st.scheduled_task_name
			, subjob.command
			, subjob.run_duration
			, subjob.submit_time
		from 
			${mainSchemaName}.v_scheduled_task st
		join ${stagingSchemaName}.v_scheduled_task_subjob subjob 
			on subjob.scheduled_task_id = st.id
			and subjob.is_completed
			and not subjob.is_failed
	)
select 
	subjob.scheduled_task_name
	, subjob.run_duration
	, subjob.submit_time
	, ${stagingSchemaName}.f_meta_view_name(
		i_meta_view_id => oper_obj.meta_view_id
	) as meta_view_name
	, etl_task.internal_name as etl_task_name
	, etl_transfer_chain.internal_name as etl_transfer_chain_name
from 
	subjob
join lateral ${mainSchemaName}.f_parse_scheduled_task_subjob_command(
		i_command => subjob.command
	) oper_obj
	on true
left join ${mainSchemaName}.task etl_task
	on etl_task.id = oper_obj.etl_task_id
left join ${mainSchemaName}.transfer etl_transfer_chain
	on etl_transfer_chain.id = oper_obj.etl_transfer_chain_id
order by 
	run_duration desc
;

comment on view v_scheduled_task_subjob_last_run_duration is 'Подзадачи плановых заданий. Последняя длительность исполнения';
