create or replace view v_transfer_stage
as
with recursive transfer_stage as (
	select 
		ts.transfer_id
        , ts.operation_id
        , s.master_id as preceding_operation_id
		, ts.ordinal_position
	from 
		${database.defaultSchemaName}.transfer t
	join ${database.defaultSchemaName}.transfer_stage ts on ts.transfer_id = t.id and ts.is_disabled = false
	join ${database.defaultSchemaName}.source s on s.id = ts.operation_id
	union all
	select
		ts.transfer_id
		, preceding_operation.id as operation_id
        , preceding_operation.master_id as preceding_operation_id
        , ts.ordinal_position - 1 as ordinal_position 
	from 
		transfer_stage ts
	join ${database.defaultSchemaName}.source preceding_operation
		on preceding_operation.id = ts.preceding_operation_id
)
select
	ts.transfer_id
	, p.internal_name as project_name
	, t.is_deletion
	, t.is_partial
	, st.internal_name as source_type_name
	, s.internal_name as source_name
	, ct.internal_name as container_type_name
	, s.container
    , ts.operation_id
	, pst.internal_name as master_source_type_name
    , ps.internal_name as master_source_name
	, pct.internal_name as master_container_type_name
	, ps.container as master_container    
    , ts.preceding_operation_id
	, ts.ordinal_position
	, s.reexec_results
	, params.positional_arguments as source_positional_arguments
	, s.is_virtual
	, ps.is_virtual as is_master_source_virtual
from 
	transfer_stage ts
join ${database.defaultSchemaName}.transfer t 
	on t.id = ts.transfer_id
join ${database.defaultSchemaName}.project p
	on p.id = t.project_id
join ${database.defaultSchemaName}.source s 
	on s.id = ts.operation_id
join ${database.defaultSchemaName}.source_type st 
	on st.id = s.source_type_id
left join ${database.defaultSchemaName}.container_type ct 
	on ct.id = s.container_type_id
left join ${database.defaultSchemaName}.source ps 
	on ps.id = ts.preceding_operation_id
left join ${database.defaultSchemaName}.source_type pst 
	on pst.id = ps.source_type_id
left join ${database.defaultSchemaName}.container_type pct 
	on pct.id = ps.container_type_id
left join lateral (
	select 
		string_agg(sp.param_value, ', ' order by sp.ordinal_position) as positional_arguments
	from 
		${database.defaultSchemaName}.source_param sp
	where 
		sp.source_id = s.id
		and sp.is_disabled = false
) params on true
	
;