create or replace view v_xsd_entity_attr
as
with recursive
	entity_attr as (
		select 
			a.xsd_entity_id as entity_id
			, a.xsd_entity_id as slave_entity_id
			, false as has_master_pkey
			, a.path
			, a.path as relative_path
			, ${mainSchemaName}.f_xsd_path_nesting_level(i_path => e.path) as slave_entity_nesting_level
			, a.column_name::varchar as column_name
			, case 
				when strpos(',' || e.pkey || ',', ',' || a.name || ',') > 0 then false
				else coalesce(a.nullable, true)
			end as nullable			
		from 
			${mainSchemaName}.xsd_entity_attr a
		join ${mainSchemaName}.xsd_entity e
			on e.id = a.xsd_entity_id
		union all
		select 
			master_entity_attr.entity_id 
			, master_entity_attr.slave_entity_id
			, master_entity_attr.has_master_pkey
			, master_entity_attr.path
			, repeat(
				'../'
				, master_entity_attr.entity_nesting_level
			) || master_entity_attr.path as relative_path
			, master_entity_attr.slave_entity_nesting_level
			, left(
				repeat(
					'_'
					, master_entity_attr.entity_nesting_level			
				) || master_entity_attr.column_name
				, ${stagingSchemaName}.f_system_name_max_length()
			) as column_name 
			, master_entity_attr.nullable
		from (
			select 
				master_entity.id as entity_id
				, t.slave_entity_id
				, case when master_entity.pkey is not null then true else false end as has_master_pkey
				, t.slave_entity_nesting_level
				, (
					t.slave_entity_nesting_level 
					- ${mainSchemaName}.f_xsd_path_nesting_level(i_path => master_entity.path)
				) as entity_nesting_level
				, master_entity_attr.path
				, master_entity_attr.column_name
				, case 
					when strpos(',' || master_entity.pkey || ',', ',' || master_entity_attr.name || ',') > 0 then false
					else coalesce(master_entity_attr.nullable, true)
				end as nullable				
			from (
					select distinct
						entity_id
						, slave_entity_id
						, slave_entity_nesting_level
					from 
						entity_attr
					where 
						has_master_pkey = false
			) t
			join ${mainSchemaName}.xsd_entity e
				on e.id = t.entity_id
			join ${mainSchemaName}.xsd_entity master_entity
				on master_entity.xsd_transformation_id = e.xsd_transformation_id
				and master_entity.path = e.master_entity
			left join lateral (
				select
					ltrim(pk.attr_name) as attr_name
				from 
					unnest(string_to_array(master_entity.pkey, ',')) as pk(attr_name)
			) master_entity_pk
				on true
			join ${mainSchemaName}.xsd_entity_attr master_entity_attr
				on master_entity_attr.xsd_entity_id = master_entity.id
				and (master_entity_attr.name = master_entity_pk.attr_name or master_entity_pk.attr_name is null)
		) master_entity_attr
	)	
select 
	e.xsd_transformation_id
	, entity_attr.slave_entity_id as xsd_entity_id
	, entity_attr.entity_id as master_entity_id
	, t.target_staging_schema as schema_name
	, e.table_name
	, entity_attr.path
	, entity_attr.relative_path
	, entity_attr.column_name
	, case
		when target_column.attname is not null then true
		else false
	end as is_target_column_exists 
	, (
		case 
			when entity_attr.slave_entity_id <> entity_attr.entity_id then
				coalesce(coalesce(master_entity.description, master_entity.name) || ': ', '') 
			else ''
		end
		|| coalesce(a.description, '') 
		|| case when nullif(a.description, '') is not null then ' ' else '' end
		|| case 
			when entity_attr.slave_entity_id <> entity_attr.entity_id then
				' (' || entity_attr.relative_path || ')'
			else ''
		end
	) as description
	, target_column_descr.description target_column_description
	, ${mainSchemaName}.f_xsd_entity_attr_column_type(a) as column_type	
	, pg_catalog.format_type(target_column.atttypid, target_column.atttypmod) as target_column_type			
	, case 
		when not coalesce(entity_attr.nullable, true) 
			and (t.is_notnull_constraints_applied or pk.ord_num is not null)
		then false
		else true
	end as nullable
	, target_column.attnotnull as is_notnull_constraint_exists
	, case 
		when pk.ord_num is not null then true 
		else false 
	end as is_pk_part
	, pk.ord_num as pk_part_ord_num
	, case when fk.ord_num is not null then true else false end as is_fk_part
	, fk.ord_num as fk_part_ord_num
	, case 
		when entity_attr.slave_entity_id <> entity_attr.entity_id then
			master_entity.table_name
	end as master_table_name
	, case when fk.ord_num is not null then a.column_name end as fk_ref_column
	, a.is_multivalued
	, a.type
	, a.max_length
	, a.total_digits
	, a.fraction_digits
from 
	entity_attr 
join ${mainSchemaName}.xsd_entity_attr a 
	on a.xsd_entity_id = entity_attr.entity_id
	and a.path = entity_attr.path
join ${mainSchemaName}.xsd_entity e 
	on e.id = entity_attr.slave_entity_id
join ${mainSchemaName}.xsd_entity master_entity 
	on master_entity.id = entity_attr.entity_id
join ${mainSchemaName}.xsd_transformation t
	on t.id = e.xsd_transformation_id 
join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = t.target_staging_schema
left join pg_catalog.pg_class target_table
	on target_table.relnamespace = target_schema.oid 
	and target_table.relname = e.table_name
	and target_table.relkind in ('r'::"char", 'p'::"char")
left join pg_catalog.pg_attribute target_column
	on target_column.attrelid = target_table.oid
	and target_column.attname = entity_attr.column_name
	and target_column.attisdropped = false
left join pg_catalog.pg_description target_column_descr
	on target_column_descr.objoid = target_table.oid
	and target_column_descr.classoid = 'pg_class'::regclass
	and target_column_descr.objsubid = target_column.attnum
left join lateral (
	select 
		case when master_entity.id = e.id and e.master_entity is null then pk.ord_num end as ord_num
	from (
		select
			ltrim(pk.attr_name) as attr_name 
			, pk.ord_num
		from 
			unnest(string_to_array(e.pkey, ',')) with ordinality as pk(attr_name, ord_num)
	) pk
	where 
		pk.attr_name = a.name
) pk 
	on true		
left join lateral (
	select 
		case when master_entity.id <> e.id and master_entity.master_entity is null then pk.ord_num end as ord_num
	from (
		select
			ltrim(pk.attr_name) as attr_name 
			, pk.ord_num
		from 
			unnest(string_to_array(master_entity.pkey, ',')) with ordinality as pk(attr_name, ord_num)
	) pk
	where 
		pk.attr_name = a.name
) fk 
	on true		
;

comment on view v_xsd_entity_attr is 'XSD-трансформация. Атрибут сущности';

grant select on ${mainSchemaName}.v_xsd_entity_attr to ${etlUserRole};