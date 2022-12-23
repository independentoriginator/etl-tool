create or replace procedure p_generate_xsd_target_staging_tables(
	i_xsd_transformation_id ${mainSchemaName}.xsd_transformation.id%type
)
language plpgsql
as $procedure$
declare 
	l_table_rec record;
	l_column text;
	l_is_etl_role_used boolean := case when length('${etlUserRole}') > 0 then true else false end;
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
			, t.is_pk_index_exists
			, t.pk_constraint_name
			, t.is_pk_constraint_exists
			, t.pk_constraint_columns
			, t.master_table_name
			, t.fk_columns
			, t.ref_columns
			, t.fk_constraint_name
			, t.fk_index_name
		from 
			${mainSchemaName}.v_xsd_entity t
		where
			t.xsd_transformation_id = i_xsd_transformation_id
		order by 
			dependency_level
	) 
	loop
		if not l_table_rec.is_table_exists then
			raise notice 'Creating table %...', l_table_rec.table_name;
			execute format('
				create table %I.%I(
					_data_package_id ${type.id} not null references %I._data_package(id)
				);

				create index i_%s$data_package_id on %I.%I(_data_package_id);
				'
				, l_table_rec.schema_name
				, l_table_rec.table_name
				, l_table_rec.schema_name
				, l_table_rec.table_name
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
	
		if l_table_rec.pk_columns is null
			or ${mainSchemaName}.f_values_are_different(l_table_rec.pk_columns, l_table_rec.pk_constraint_columns)
		then
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

		call ${mainSchemaName}.p_generate_xsd_target_staging_table_columns(
			i_xsd_entity_id => l_table_rec.entity_id
		);
	
		if l_table_rec.pk_columns is not null then
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
		end if;
	
		if l_table_rec.fk_columns is not null then
			if not exists (
				select 
					1
				from 
					pg_catalog.pg_indexes fk_index	
				where
					fk_index.schemaname = l_table_rec.schema_name
					and fk_index.tablename = l_table_rec.table_name
					and fk_index.indexname = l_table_rec.fk_index_name			
			) then
				execute format('
					create index %I on %I.%I (
						%s
					)'
					, l_table_rec.fk_index_name 
					, l_table_rec.schema_name
					, l_table_rec.table_name 
					, l_table_rec.fk_columns
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
					and fk_constraint.constraint_name = l_table_rec.fk_constraint_name
					and fk_constraint.constraint_type = 'FOREIGN KEY'	
			) then
				execute format('
					alter table %I.%I
						add constraint %I foreign key (%s) references %I.%I(%s) 
					'
					, l_table_rec.schema_name
					, l_table_rec.table_name 
					, l_table_rec.fk_constraint_name
					, l_table_rec.fk_columns
					, l_table_rec.schema_name
					, l_table_rec.master_table_name 
					, l_table_rec.ref_columns
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
					and fk_index.indexname = l_table_rec.fk_index_name			
			) then
				execute format('
					drop index %I.%I
					'
					, l_table_rec.schema_name
					, l_table_rec.fk_index_name 
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
					and fk_constraint.constraint_name = l_table_rec.fk_constraint_name
					and fk_constraint.constraint_type = 'FOREIGN KEY'	
			) then
				execute format('
					alter table %I.%I
						drop constraint %I 
					'
					, l_table_rec.schema_name
					, l_table_rec.table_name 
					, l_table_rec.fk_constraint_name
				);
			end if;
		end if;

		-- ETL user role permissions
		if l_is_etl_role_used
		then
			execute	
				format(
					'grant select, insert, update, delete, truncate on %I.%I to ${etlUserRole}'
					, l_table_rec.schema_name
					, l_table_rec.table_name
				);
		end if;
		
	end loop;
end
$procedure$;			
