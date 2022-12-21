create or replace procedure p_truncate_xsd_target_staging_tables(
	i_xsd_transformation_name ${mainSchemaName}.xsd_transformation.internal_name%type
)
language plpgsql
as $procedure$
declare 
	l_rec record;
begin
	for l_rec in (
		select 
			string_agg(
				format('
					truncate table %I.%I cascade;
					'
					, t.target_staging_schema
					, t.table_name
				)
				, E'\n'
				order by dependency_level desc
			) 
			|| format('
					truncate table %I._data_package cascade;
				'
				, t.target_staging_schema
			) as command
		from (
			select distinct 
				t.target_staging_schema
				, e.table_name
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
			join pg_catalog.pg_class target_table
				on target_table.relnamespace = target_schema.oid 
				and target_table.relname = e.table_name
				and target_table.relkind in ('r'::"char", 'p'::"char")
			where 
				t.internal_name = i_xsd_transformation_name
		) t
		group by 
			t.target_staging_schema
	) loop
		execute l_rec.command; 
	end loop
	;
end
$procedure$;			
