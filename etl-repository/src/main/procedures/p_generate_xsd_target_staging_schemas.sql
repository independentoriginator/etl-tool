create or replace procedure p_generate_xsd_target_staging_schemas()
language plpgsql
as $procedure$
declare 
	l_rec record;
begin
	for l_rec in (
		select
			t.*
		from 
			${mainSchemaName}.v_xsd_transformation t
		join ${mainSchemaName}.xsd_transformation xsd_transformation 
			on xsd_transformation.id = t.id
		where 
			coalesce(t.is_staging_schema_generated, false) = false
		for update of xsd_transformation
	) 
	loop
		execute format('create schema if not exists %I', l_rec.target_staging_schema);
	
		delete from 
			${mainSchemaName}.xsd_transformation_entity
		where 
			xsd_transformation_id = l_rec.id
		;
	
		insert into 
			${mainSchemaName}.xsd_transformation_entity(
				xsd_transformation_id
				, path
				, name
				, target_name
				, description
				, pkey
				, master_entity
				, master_entity_pkey
			)
		with 
			entity_table as (
				select
					coalesce(substring(x.master_entity, '.*/([^/]+)'), '') || x.name as name
					, x.path
					, x.description
					, x.pkey
					, x.master_entity
					, x.master_entity_pkey
					, substring(x.path, '(/.+)/[^/]+') as directory
				from
					ng_etl.xsd_transformation t
					, xmltable(
						'/relational_schema/table'
						passing transformed_xsd
						columns 
							name text path '@name'
							, path text path '@path'
							, description text path '@comment'
							, pkey text path '@primaryKey'
							, master_entity text path '@masterTable'
							, master_entity_pkey text path '@masterPrimaryKey'
					) x
				where 
					t.id = l_rec.id
			)
			, directory as (
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
							t.name in (
								select 
									t.name
								from 
									entity_table t
								group by 
									t.name 
								having 
									count(*) > 1
							)
					) t
				) t
			)
			, essential_path as (
				select 
					t.path
					, replace(ng_rdm.f_convert_case_snake2camel(t.target_directory_path), '/', '_')  as essential_path
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
										d.directory_path = t.directory_path
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
										d.full_path = t.full_path
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
			l_rec.id as xsd_transformation_id
			, t.path
			, t.name
			, ng_rdm.f_abbreviate_name(
				i_name => 
					coalesce(
						ep.essential_path
						, t.name
					)
				, i_adjust_to_max_length => true
			) as target_name
			, t.description
			, t.pkey
			, t.master_entity
			, t.master_entity_pkey
		from 
			entity_table t
		left join essential_path ep 
			on ep.path = t.path
		;
			
		update ${mainSchemaName}.xsd_transformation 
		set is_staging_schema_generated = true
		where id = l_rec.id
		;
	end loop;
end
$procedure$;			
