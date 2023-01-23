drop procedure p_truncate_xsd_target_staging_tables(
	${mainSchemaName}.xsd_transformation.internal_name%type
);

create or replace procedure p_clean_xsd_target_staging_tables(
	i_xsd_transformation_name ${mainSchemaName}.xsd_transformation.internal_name%type
	, i_perform_truncation boolean = false
)
language plpgsql
as $procedure$
declare 
	l_rec record;
begin
	for l_rec in (
		select 
			string_agg(
				case 	
					when i_perform_truncation then
						format('
							truncate table %I.%I cascade;
							'
							, t.target_staging_schema
							, t.table_name
						)
					else
						format('
							delete from %I.%I 
							where _data_package_id in ( 
								select 
									id 
								from 
									%I._data_package 	
								where 
									xsd_transformation_id = any(%L)
							);
							'
							, t.target_staging_schema
							, t.table_name
							, t.target_staging_schema
							, t.xsd_transformation_ids
						)
				end					
				, E'\n'
				order by dependency_level desc
			) 
			|| case 	
				when i_perform_truncation then
					format('
						truncate table %I._data_package cascade;
						'
						, t.target_staging_schema
					)
				else
					format('
						delete from 
							%I._data_package 
						where 
							xsd_transformation_id = any(%L);
						'
						, t.target_staging_schema
						, t.xsd_transformation_ids
					)
			end as command
		from (
			select 
				t.target_staging_schema
				, t.table_name
				, t.dependency_level
				, array_agg(t.xsd_transformation_id) as xsd_transformation_ids
			from (
				select  
					t.id as xsd_transformation_id
					, t.target_staging_schema
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
					and t.is_disabled = true -- cleaning non-actual data
			) t
			group by 
				t.target_staging_schema
				, t.table_name
				, t.dependency_level			
		) t
		group by 
			t.target_staging_schema
			, t.xsd_transformation_ids
	) loop
		execute l_rec.command; 
	end loop
	;
end
$procedure$;			
