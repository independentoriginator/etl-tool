create or replace view v_task_stage
as
with recursive task_stage as (
	select 
		ts.task_id
        , ts.transfer_id
        , tr.master_id as preceding_transfer_id
        , ts.transfer_id as target_transfer_id
		, coalesce(ts.ordinal_position, 0) as ordinal_position
		, coalesce(ts.ordinal_position, 0) as stage_ordinal_position
	from 
		${database.defaultSchemaName}.task t
	join ${database.defaultSchemaName}.task_stage ts on ts.task_id = t.id and ts.is_disabled = false
	join ${database.defaultSchemaName}.transfer tr on tr.id = ts.transfer_id
	union all
	select
		ts.task_id
		, preceding_transfer.id as transfer_id
        , preceding_transfer.master_id as preceding_transfer_id
        , ts.target_transfer_id
        , ts.ordinal_position - 1 as ordinal_position
        , ts.stage_ordinal_position
	from 
		task_stage ts
	join ${database.defaultSchemaName}.transfer preceding_transfer
		on preceding_transfer.id = ts.preceding_transfer_id
)
select
	ts.task_id
	, t.internal_name as task_name
    , ts.transfer_id
	, tr.internal_name as transfer_name
	, trt.internal_name as transfer_type_name
	, st.internal_name as source_type_name
	, s.internal_name as source_name
	, s.connection_string
	, s.user_name
	, s.user_password
	, ct.internal_name as container_type_name
	, tr.container
	, tr.is_virtual
	, tr.reexec_results
	, ts.ordinal_position
	, ts.target_transfer_id
	, ts.stage_ordinal_position
	, params.positional_arguments as source_positional_arguments
    , ts.preceding_transfer_id
	, ptr.internal_name as master_transfer_name
	, ptrt.internal_name as master_transfer_type_name
    , ps.internal_name as master_source_name
	, pst.internal_name as master_source_type_name
	, pct.internal_name as master_container_type_name
	, ptr.container as master_container    
	, ptr.is_virtual as is_master_transfer_virtual
from 
	task_stage ts
join ${database.defaultSchemaName}.task t 
	on t.id = ts.task_id
join ${database.defaultSchemaName}.transfer tr 
	on tr.id = ts.transfer_id
join ${database.defaultSchemaName}.transfer_type trt 
	on trt.id = tr.type_id
join ${database.defaultSchemaName}.source s 
	on s.id = tr.source_id
join ${database.defaultSchemaName}.source_type st 
	on st.id = s.source_type_id
left join ${database.defaultSchemaName}.container_type ct 
	on ct.id = tr.container_type_id
left join ${database.defaultSchemaName}.transfer ptr 
	on ptr.id = ts.preceding_transfer_id
left join ${database.defaultSchemaName}.transfer_type ptrt 
	on ptrt.id = ptr.type_id
left join ${database.defaultSchemaName}.source ps 
	on ps.id = ptr.source_id
left join ${database.defaultSchemaName}.source_type pst 
	on pst.id = ps.source_type_id
left join ${database.defaultSchemaName}.container_type pct 
	on pct.id = ptr.container_type_id
left join lateral (
	select 
		string_agg(tp.param_value, ', ' order by tp.ordinal_position) as positional_arguments
	from 
		${database.defaultSchemaName}.transfer_param tp
	where 
		tp.transfer_id = ts.transfer_id
		and tp.is_disabled = false
) params on true
;