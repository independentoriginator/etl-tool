create or replace procedure p_generate_xsd_target_staging_table_columns(
	i_xsd_entity_id ${mainSchemaName}.xsd_entity.id%type
)
language plpgsql
as $procedure$
declare 
	l_column_rec record;
begin
	for l_column_rec in (
		select 
			t.target_staging_schema as schema_name
			, e.table_name
			, a.column_name
			, case when target_column.attname is null then false else true end as is_target_column_exists 
			, a.description
			, target_column_descr.description target_column_description
			, ${mainSchemaName}.f_xsd_entity_attr_column_type(a) as column_type	
			, pg_catalog.format_type(target_column.atttypid, target_column.atttypmod) as target_column_type			
			, case 
				when strpos(',' || e.pkey, a.name) > 0 then false
				else coalesce(a.nullable, true)
			end as nullable
			, target_column.attnotnull as is_notnull_constraint_exists
		from 
			${mainSchemaName}.xsd_entity e
		join ${mainSchemaName}.xsd_entity_attr a
			on a.xsd_entity_id = e.id
		join ${mainSchemaName}.xsd_transformation t
			on t.id = e.xsd_transformation_id 
		join pg_catalog.pg_namespace target_schema
			on target_schema.nspname = t.target_staging_schema
		join pg_catalog.pg_class target_table
			on target_table.relnamespace = target_schema.oid 
			and target_table.relname = e.table_name
			and target_table.relkind in ('r'::"char", 'p'::"char")
		left join pg_catalog.pg_attribute target_column
			on target_column.attrelid = target_table.oid
			and target_column.attname = a.column_name
			and target_column.attisdropped = false
		left join pg_catalog.pg_description target_column_descr
			on target_column_descr.objoid = target_table.oid
			and target_column_descr.classoid = 'pg_class'::regclass
			and target_column_descr.objsubid = target_column.attnum
		where 
			e.id = i_xsd_entity_id
	) 
	loop
		if not l_column_rec.is_target_column_exists then
			execute format('
				alter table %I.%I 
					add column %I %s %snull 
				'
				, l_column_rec.schema_name
				, l_column_rec.table_name
				, l_column_rec.column_name
				, l_column_rec.column_type
				, case when l_column_rec.nullable then '' else 'not ' end
			);
		else
			if l_column_rec.column_type <> l_column_rec.target_column_type then
				execute format('
					alter table %I.%I 
						alter column %I set data type %s
					'
					, l_column_rec.schema_name
					, l_column_rec.table_name
					, l_column_rec.column_name
					, l_column_rec.column_type
				);
			end if;		
		
			if not l_column_rec.nullable and not l_column_rec.is_notnull_constraint_exists then
				execute format('
					alter table %I.%I 
						alter column %I set not null
					'
					, l_column_rec.schema_name
					, l_column_rec.table_name
					, l_column_rec.column_name
				);
			elsif l_column_rec.nullable and l_column_rec.is_notnull_constraint_exists then
				execute format('
					alter table %I.%I 
						alter column %I drop not null
					'
					, l_column_rec.schema_name
					, l_column_rec.table_name
					, l_column_rec.column_name
				);
			end if;
		end if;
	
		if ${mainSchemaName}.f_values_are_different(l_column_rec.description, l_column_rec.target_column_description) then
			execute format('
				comment on column %I.%I.%I is $comment$%s$comment$
				'
				, l_column_rec.schema_name
				, l_column_rec.table_name
				, l_column_rec.column_name
				, l_column_rec.description
			);
		end if;
	end loop;
end
$procedure$;			
