create or replace procedure p_generate_xsd_target_staging_tables(
	i_xsd_transformation_id ${mainSchemaName}.xsd_transformation.id%type
)
language plpgsql
as $procedure$
declare 
	l_table_rec record;
	l_column text;
begin
	for l_table_rec in (
		select 
			t.entity_id 
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
			, t.master_entity_id
			, t.master_table_name
			, t.master_entity_pk_columns
			, t.master_entity_fk_columns
			, t.fk_columns_must_be_added
			, t.master_entity_fk_constraint_name
			, t.master_entity_fk_index_name
			, t.dependency_level
		from (
			select 
				e.id as entity_id 
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
				, coalesce(pk.columns || ', data_package_external_id', '_id') as pk_columns
				, left('pk_' || e.table_name, ${stagingSchemaName}.f_system_name_max_length()) as pk_index_name 
				, pk_constraint.conname as pk_constraint_name
				, case when pk_constraint.conname is not null then true else false end as is_pk_constraint_exists
				, pk_constraint_columns.columns as pk_constraint_columns
				, master_entity.id as master_entity_id
				, master_entity.table_name as master_table_name
				, master_entity_pk.master_columns || case when master_entity_pk.master_columns <> '_id' then ', data_package_external_id' else '' end as master_entity_pk_columns
				, master_entity_pk.fk_columns || case when master_entity_pk.master_columns <> '_id' then ', data_package_external_id' else '' end as master_entity_fk_columns
				, master_entity_pk.fk_columns_must_be_added
				, 'fk_master_id' as master_entity_fk_constraint_name
				, left('i_' || e.table_name, ${stagingSchemaName}.f_system_name_max_length()) as master_entity_fk_index_name
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
					string_agg(a.column_name, ', ' order by pk.ord_num) as columns 
				from (
					select
						ltrim(pk.attr_name) as attr_name 
						, pk.ord_num
					from 
						unnest(string_to_array(e.pkey, ',')) with ordinality as pk(attr_name, ord_num)
				) pk
				join ${mainSchemaName}.xsd_entity_attr a
					on a.xsd_entity_id = e.id
					and a.name = pk.attr_name
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
					string_agg(a.master_column_name, ', ' order by a.ord_num) as master_columns 
					, string_agg(a.fk_column_name, ', ' order by a.ord_num) as fk_columns
					, array_agg(
						case 
							when target_column.attnum is null then 
								a.fk_column_name || ' ' || a.column_type || ' not null'
						end
					) as fk_columns_must_be_added 
				from (
					select 
						coalesce(a.column_name, '_id') as master_column_name
						, '_master_' || coalesce(a.column_name, 'id') as fk_column_name
						, case
							when a.column_name is null then '${type.id}'
							else ${mainSchemaName}.f_xsd_entity_attr_column_type(a)
						end as column_type
						, pk.ord_num
					from (
						select
							ltrim(pk.attr_name) as attr_name 
							, pk.ord_num
						from 
							unnest(string_to_array(coalesce(master_entity.pkey, '_id'), ',')) with ordinality as pk(attr_name, ord_num)
					) pk
					left join ${mainSchemaName}.xsd_entity_attr a
						on a.xsd_entity_id = master_entity.id
						and a.name = pk.attr_name
				) a
				left join pg_catalog.pg_attribute target_column
					on target_column.attrelid = target_table.oid
					and target_column.attname = a.fk_column_name
					and target_column.attisdropped = false
			) master_entity_pk 
				on true		
			where 
				t.id = i_xsd_transformation_id
		) t
		left join pg_catalog.pg_indexes pk_index
			on pk_index.schemaname = t.schema_name
			and pk_index.tablename = t.table_name
			and pk_index.indexname = t.pk_index_name
		order by 
			dependency_level
	) 
	loop
		if not l_table_rec.is_table_exists then
			raise notice 'Creating table %...', l_table_rec.table_name;
			execute format('
				create table %I.%I(
					data_package_external_id ${type.code} not null
				)
				'
				, l_table_rec.schema_name
				, l_table_rec.table_name
			);
		end if;
	
		if ${mainSchemaName}.f_values_are_different(l_table_rec.description, l_table_rec.target_table_description) then
			execute format('
				comment on table %I.%I is $comment$%s$comment$
				'
				, l_table_rec.schema_name
				, l_table_rec.table_name
				, l_table_rec.description
			);
		end if;
	
		call ${mainSchemaName}.p_generate_xsd_target_staging_table_columns(
			i_xsd_entity_id => l_table_rec.entity_id
		);
	
		if not l_table_rec.is_pk_constraint_exists then
			if l_table_rec.pkey is null and strpos(', ' || l_table_rec.pk_constraint_columns, l_table_rec.pk_columns) = 0 then
				execute format('
					alter table %I.%I 
						add column %s ${type.id} not null generated by default as identity
					'
					, l_table_rec.schema_name
					, l_table_rec.table_name
					, l_table_rec.pk_columns
				);
			end if;
		elsif ${mainSchemaName}.f_values_are_different(l_table_rec.pk_columns, l_table_rec.pk_constraint_columns) then
			if l_table_rec.is_pk_constraint_exists then
				execute format('
					alter table %I.%I 
						drop constraint %I cascade
					'
					, l_table_rec.schema_name
					, l_table_rec.table_name
					, l_table_rec.pk_constraint_name 
				);
				l_table_rec.is_pk_constraint_exists := false;
			end if;
		
			if l_table_rec.is_pk_index_exists then
				execute format('
					drop index if exists %I.%I
					'
					, l_table_rec.schema_name
					, l_table_rec.pk_index_name
				);
				l_table_rec.is_pk_index_exists := false;
			end if;
		end if;
	
		if not l_table_rec.is_pk_index_exists then
			execute format('
				create unique index %I on %I.%I (
					%s
				)'
				, l_table_rec.pk_index_name 
				, l_table_rec.schema_name
				, l_table_rec.table_name 
				, l_table_rec.pk_columns
			);
		end if;
	
		raise notice '%', format('
				alter table %I.%I
					add constraint %I primary key using index %I
				'
				, l_table_rec.schema_name
				, l_table_rec.table_name
				, l_table_rec.pk_index_name 
				, l_table_rec.pk_index_name				
			);
	
		if not l_table_rec.is_pk_constraint_exists then
			execute format('
				alter table %I.%I
					add constraint %I primary key using index %I
				'
				, l_table_rec.schema_name
				, l_table_rec.table_name
				, l_table_rec.pk_index_name 
				, l_table_rec.pk_index_name				
			);
		end if;
	
		raise notice '%',	l_table_rec.fk_columns_must_be_added;
		if l_table_rec.master_entity_id is not null then
			foreach l_column in array l_table_rec.fk_columns_must_be_added loop
				if l_column is not null then
					execute format('
						alter table %I.%I 
							add column %s
						'
						, l_table_rec.schema_name
						, l_table_rec.table_name
						, l_column
					);
				end if;
			end loop;
		
			if not exists (
				select 
					1
				from 
					pg_catalog.pg_indexes fk_index	
				where
					fk_index.schemaname = l_table_rec.schema_name
					and fk_index.tablename = l_table_rec.table_name
					and fk_index.indexname = l_table_rec.master_entity_fk_index_name			
			) then
				execute format('
					create index %I on %I.%I (
						%s
					)'
					, l_table_rec.master_entity_fk_index_name 
					, l_table_rec.schema_name
					, l_table_rec.table_name 
					, l_table_rec.master_entity_fk_columns
				);
			end if;
		
			if not exists (
				select 
					1
				from 
					information_schema.table_constraints fk_constraint
				where 
					fk_constraint.table_schema = l_table_rec.schema_name
					and fk_constraint.table_name = l_table_rec.table_name
					and fk_constraint.constraint_name = l_table_rec.master_entity_fk_constraint_name
					and fk_constraint.constraint_type = 'FOREIGN KEY'	
			) then
				execute format('
					alter table %I.%I
						add constraint %I foreign key (%s) references %I.%I(%s) 
					'
					, l_table_rec.schema_name
					, l_table_rec.table_name 
					, l_table_rec.master_entity_fk_constraint_name
					, l_table_rec.master_entity_fk_columns
					, l_table_rec.schema_name
					, l_table_rec.master_table_name 
					, l_table_rec.master_entity_pk_columns
				);
			end if;
		else 
			if exists (
				select 
					1
				from 
					pg_catalog.pg_indexes fk_index	
				where
					fk_index.schemaname = l_table_rec.schema_name
					and fk_index.tablename = l_table_rec.table_name
					and fk_index.indexname = l_table_rec.master_entity_fk_index_name			
			) then
				execute format('
					drop index %I.%I
					'
					, l_table_rec.schema_name
					, l_table_rec.master_entity_fk_index_name 
				);
			end if;
		
			if exists (
				select 
					1
				from 
					information_schema.table_constraints fk_constraint
				where 
					fk_constraint.table_schema = l_table_rec.schema_name
					and fk_constraint.table_name = l_table_rec.table_name
					and fk_constraint.constraint_name = l_table_rec.master_entity_fk_constraint_name
					and fk_constraint.constraint_type = 'FOREIGN KEY'	
			) then
				execute format('
					alter table %I.%I
						drop constraint %I 
					'
					, l_table_rec.schema_name
					, l_table_rec.table_name 
					, l_table_rec.master_entity_fk_constraint_name
				);
			end if;
		end if;

		-- ETL user role read permission
		if length('${etlUserRole}') > 0 
		then
			execute	
				format(
					'grant select on %I.%I to ${etlUserRole}'
					, l_table_rec.schema_name
					, l_table_rec.table_name
				);
		end if;
		
	end loop;
end
$procedure$;			
