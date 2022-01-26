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
	join ${database.defaultSchemaName}.transfer_stage ts on ts.transfer_id = t.id
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
	, st.internal_name as source_type_name
	, s.internal_name as source_name
	, ct.internal_name as container_type_name
	, s.container
    , ts.operation_id
	, pst.internal_name as master_source_type_name
    , ps.internal_name as master_source_name
	, ct.internal_name as master_container_type_name
	, s.container as master_container    
    , ts.preceding_operation_id
	, ts.ordinal_position
from 
	transfer_stage ts
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
	
;