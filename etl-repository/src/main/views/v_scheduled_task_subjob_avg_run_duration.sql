drop view if exists v_scheduled_task_subjob_avg_run_duration;

create view v_scheduled_task_subjob_avg_run_duration
as
with 
	subjob as (
		select
			subjob.command
			, subjob.run_duration
		from 
			${stagingSchemaName}.v_pgpro_scheduler_subjob subjob 
		where 
			subjob.is_completed
			and not subjob.is_failed
	)
select 
	subjob.run_duration 
	, ${stagingSchemaName}.f_meta_view_name(
		i_meta_view_id => subjob.meta_view_id
	) as meta_view_name
	, etl_task.internal_name as etl_task_name
	, etl_transfer_chain.internal_name as etl_transfer_chain_name
from (
	select 
		avg(subjob.run_duration) as run_duration 
		, oper_obj.meta_view_id
		, oper_obj.etl_task_id
		, oper_obj.etl_transfer_chain_id
	from 
		subjob
	join lateral ${mainSchemaName}.f_parse_scheduled_task_subjob_command(
			i_command => subjob.command
		) oper_obj
		on true
	group by 
		oper_obj.meta_view_id
		, oper_obj.etl_task_id
		, oper_obj.etl_transfer_chain_id
) subjob
left join ${mainSchemaName}.task etl_task
	on etl_task.id = subjob.etl_task_id
left join ${mainSchemaName}.transfer etl_transfer_chain
	on etl_transfer_chain.id = subjob.etl_transfer_chain_id
order by 
	run_duration desc
;

comment on view v_scheduled_task_subjob_avg_run_duration is 'Подзадачи плановых заданий. Средняя длительность исполнения';
