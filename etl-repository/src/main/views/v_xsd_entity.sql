create or replace view v_xsd_entity
as
select 
	t.xsd_transformation_id
	, t.entity_id 
	, t.schema_name
	, t.table_name
	, t.is_table_exists
	, t.description
	, t.target_table_description
	, t.pkey
	, t.pk_columns
	, t.pk_index_name
	, case when pk_index.indexname is not null then true else false end as is_pk_index_exists
	, t.pk_constraint_name
	, t.is_pk_constraint_exists
	, t.pk_constraint_columns
	, t.master_table_name
	, t.fk_columns
	, t.ref_columns
	, t.fk_constraint_name
	, t.fk_index_name
	, t.dependency_level
	, case when fk_index.indexname is not null then true else false end as is_fk_index_exists
	, case when fk_constraint.constraint_name is not null then true else false end as is_fk_constraint_exists
from (
	select 
		e.xsd_transformation_id
		, e.id as entity_id 
		, t.target_staging_schema as schema_name
		, e.table_name
		, case when target_table.oid is not null then true else false end as is_table_exists
		, (
			coalesce(e.description, '') 
			|| case when nullif(e.description, '') is not null then ' ' else '' end
			|| e.path
			|| ' (' || t.version || ')'
		) as description
		, target_table_descr.description as target_table_description
		, e.pkey
		, pk.columns || ', _data_package_id' as pk_columns
		, left('pk_' || e.table_name, ${stagingSchemaName}.f_system_name_max_length()) as pk_index_name 
		, pk_constraint.conname as pk_constraint_name
		, case when pk_constraint.conname is not null then true else false end as is_pk_constraint_exists
		, pk_constraint_columns.columns as pk_constraint_columns
		, fk.master_table_name
		, fk.fk_columns || ', _data_package_id' as fk_columns
		, fk.ref_columns || ', _data_package_id' as ref_columns
		, 'fk_master_id' as fk_constraint_name
		, left('i_' || e.table_name, ${stagingSchemaName}.f_system_name_max_length()) as fk_index_name
		, ${mainSchemaName}.f_xsd_entity_dependency_level(
			i_xsd_transformation_id => t.id
			, i_entity_path => e.path
		) as dependency_level
	from 
		${mainSchemaName}.xsd_transformation t
	join ${mainSchemaName}.xsd_entity e
		on e.xsd_transformation_id = t.id 
	join pg_catalog.pg_namespace target_schema
		on target_schema.nspname = t.target_staging_schema
	left join pg_catalog.pg_class target_table
		on target_table.relnamespace = target_schema.oid 
		and target_table.relname = e.table_name
		and target_table.relkind in ('r'::"char", 'p'::"char")
	left join pg_catalog.pg_description target_table_descr 
		on target_table_descr.objoid = target_table.oid
		and target_table_descr.classoid = 'pg_class'::regclass
		and target_table_descr.objsubid = 0
	left join lateral (
		select 
			string_agg(a.column_name, ', ' order by a.pk_part_ord_num) as columns 
		from 
			${mainSchemaName}.v_xsd_entity_attr a
		where
			a.xsd_entity_id = e.id
			and a.is_pk_part
	) pk 
		on true		
	left join pg_catalog.pg_constraint pk_constraint
		on pk_constraint.conrelid = target_table.oid
		and pk_constraint.contype = 'p'::"char"
	left join lateral (
		select 
			string_agg(a.attname, ', ' order by pk.ord_num) as columns
		from 
			unnest(pk_constraint.conkey) with ordinality as pk(attr_num, ord_num)
		join pg_catalog.pg_attribute a
			on a.attrelid = pk_constraint.conrelid
			and a.attnum = pk.attr_num
	) pk_constraint_columns
		on true
	left join ${mainSchemaName}.xsd_entity master_entity
		on master_entity.xsd_transformation_id = e.xsd_transformation_id
		and master_entity.path = e.master_entity
	left join lateral (
		select 
			a.master_table_name
			, string_agg(a.column_name, ', ' order by a.fk_part_ord_num) as fk_columns
			, string_agg(a.fk_ref_column, ', ' order by a.fk_part_ord_num) as ref_columns
		from 
			${mainSchemaName}.v_xsd_entity_attr a
		where
			a.xsd_entity_id = e.id
			and a.is_fk_part
		group by 
			a.master_table_name
	) fk
		on true		
) t
left join pg_catalog.pg_indexes pk_index
	on pk_index.schemaname = t.schema_name
	and pk_index.tablename = t.table_name
	and pk_index.indexname = t.pk_index_name
left join pg_catalog.pg_indexes fk_index
	on fk_index.schemaname = t.schema_name
	and fk_index.tablename = t.table_name
	and fk_index.indexname = t.fk_index_name
left join information_schema.table_constraints fk_constraint
	on fk_constraint.table_schema = t.schema_name
	and fk_constraint.table_name = t.table_name
	and fk_constraint.constraint_name = t.fk_constraint_name
	and fk_constraint.constraint_type = 'FOREIGN KEY'	
;

comment on view v_xsd_entity is 'XSD-трансформация. Сущность';

grant select on ${mainSchemaName}.v_xsd_entity to ${etlUserRole};
