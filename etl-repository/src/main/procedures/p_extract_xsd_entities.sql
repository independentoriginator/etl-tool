create or replace procedure p_extract_xsd_entities(
	i_xsd_transformation_id ${mainSchemaName}.xsd_transformation.id%type
)
language plpgsql
as $procedure$
begin
	delete from 
		${mainSchemaName}.xsd_entity_attr
	where 
		xsd_entity_id in (
			select 
				id
			from 
				${mainSchemaName}.xsd_entity
			where 
				xsd_transformation_id = i_xsd_transformation_id
		)
	;
	
	delete from 
		${mainSchemaName}.xsd_entity
	where 
		xsd_transformation_id = i_xsd_transformation_id
	;
	
	insert into 
		${mainSchemaName}.xsd_entity(
			xsd_transformation_id
			, path
			, name
			, table_name
			, description
			, pkey
			, master_entity
		)
	with 
		entity_table as (
			select
				t.xsd_transformation_id
				, t.name
				, lower(t.name) as lc_name
				, t.path
				, t.description
				, t.pkey
				, t.master_entity
				, t.directory
			from (
				select
					t.id as xsd_transformation_id
					, coalesce(substring(x.master_entity, '.*/([^/]+)'), '') || x.name as name
					, x.path
					, x.description
					, x.pkey
					, x.master_entity
					, substring(x.path, '(/.+)/[^/]+') as directory
				from
					${mainSchemaName}.xsd_transformation t
					, xmltable(
						xmlnamespaces(t.namespace as tns)
						, '/tns:relational_schema/tns:table'
						passing transformed_xsd
						columns 
							name text path '@name'
							, path text path '@path'
							, description text path '@comment'
							, pkey text path '@primaryKey'
							, master_entity text path '@masterTable'
					) x
				where 
					t.id = i_xsd_transformation_id
			) t
		)
		, directory as (
			select 
				t.path
				, t.name
				, t.directory
				, t.directory_level
				, t.master_entity
				, t.directory_path  
				, lower(t.directory_path) as lc_directory_path
				, t.full_path
				, lower(t.full_path) as lc_full_path
			from (
				select 
					t.path
					, t.name
					, t.directory
					, t.directory_level
					, t.master_entity
					, t.directory || '/' || t.name as directory_path  
					, (
						select 
							string_agg( 
								dir.directory
								, '/'
								order by dir.directory_level desc
							) 
						from 
							unnest(t.full_path) with ordinality as dir(directory, directory_level)
					) || '/' || t.name as full_path
				from (	
					select 
						t.path
						, t.name
						, t.directory
						, t.directory_level
						, t.master_entity
						, t.name || '/' || t.directory as directory_path  
						, array_agg(
							t.directory
						) over(
							partition by 
								t.path
							order by 
								t.directory_level desc	
						) as full_path
					from (
						select 
							t.path
							, t.name
							, t.master_entity
							, dir[1] as directory
							, ordinality as directory_level
						from 
							entity_table t
						join lateral 
							regexp_matches(
								t.directory
								, '/([^/]+)'
								, 'g'
							) with ordinality as dir on true
						where 
							exists (
								select 
									1
								from 
									entity_table
								where 
									entity_table.lc_name = t.lc_name
									and entity_table.path <> t.path
							)
					) t
				) t
			) t
		)
		, essential_path as (
			select 
				t.path
				, t.target_directory_path
				, replace(
					${stagingSchemaName}.f_convert_case_snake2camel(
						t.target_directory_path
					)
					, '/'
					, '_'
				)  as essential_path
			from (
				select 
					t.path
					, t.directory
					, t.directory_level
					, case 
						when t.is_directory_path_unique then t.directory_path
						when t.is_full_path_unique then t.full_path
					end as target_directory_path				
					, t.directory_path
					, t.full_path
					, t.is_directory_path_unique
					, t.is_full_path_unique
					, row_number() over(
						partition by
							t.path
						order by 
							t.is_directory_path_unique desc
							, t.is_full_path_unique desc
							, t.directory_level desc
					) as rn
				from (
					select 
						t.path
						, t.name
						, t.master_entity
						, t.directory
						, t.directory_level
						, t.directory_path
						, t.full_path
						, case 
							when exists (
								select 
									1
								from 
									directory d
								where 	
									d.lc_directory_path = t.lc_directory_path
									and d.path <> t.path
							)
							then false
							else true
						end is_directory_path_unique
						, case 
							when exists (
								select 
									1
								from 
									directory d
								where 	
									d.lc_full_path = t.lc_full_path
									and d.path <> t.path
							)
							then false
							else true
						end is_full_path_unique
					from 
						directory t	
				) t
				where 
					t.is_directory_path_unique 
					or t.is_full_path_unique				
			) t
			where 
				t.rn = 1
		)
	select
		t.xsd_transformation_id
		, t.path
		, t.name
		, lower(
			${stagingSchemaName}.f_abbreviate_name(
				i_name => 
					coalesce(
						ep.essential_path
						, t.name
					)
				, i_adjust_to_max_length => true
			)
		) as table_name
		, nullif(t.description, '') as description
		, nullif(t.pkey, '') as pkey
		, nullif(t.master_entity, '') as master_entity
	from 
		entity_table t
	left join essential_path ep 
		on ep.path = t.path
	;
end
$procedure$;			
