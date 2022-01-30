create or replace procedure p_execute_transfer(
	i_transfer_id ${database.defaultSchemaName}.transfer.id%type
)
language plpgsql
as $procedure$
declare 
	l_data_package_id ${stagingSchemaName}.data_package.id%type;
	l_check_date ${stagingSchemaName}.data_package.state_change_date%type;
	l_stage_rec record;
	l_extraction_command ${database.defaultSchemaName}.source.container%type;
	l_load_command ${database.defaultSchemaName}.source.container%type;
	l_temp_table_name name;
	l_column_list text;
begin
	for l_stage_rec in (
		select
			ts.*
		from 
			${database.defaultSchemaName}.v_transfer_stage ts
		where
			ts.transfer_id = i_transfer_id
		order by 
			stage_ordinal_position
			, target_operation_id
			, ordinal_position 
	) 
	loop
		if l_data_package_id is null then
			select 
				o_data_package_id, o_check_date
			into
				l_data_package_id, l_check_date
			from 
				${stagingSchemaName}.f_insert_data_package(
					i_source_name => l_stage_rec.project_name
					, i_lang_id => null
					, i_is_deletion => l_stage_rec.is_deletion
					, i_is_partial => l_stage_rec.is_partial
				)
			;
		end if;
		
		if l_stage_rec.source_type_name = 'dbms' then
			if l_stage_rec.source_name <> 'this database' then
				raise exception 'Unsupported DBMS connection type specified: %', l_stage_rec.source_name;
			end if;
		elsif l_stage_rec.source_type_name = 'extraction' and l_stage_rec.is_virtual = false then
			if l_stage_rec.container_type_name <> 'sql' then
				raise exception 'Unsupported container type specified: %', l_stage_rec.container_type_name;
			end if;
			
			l_extraction_command := l_stage_rec.container;
			
			if l_stage_rec.master_source_type_name = 'extraction' then
				if l_stage_rec.master_container_type_name <> 'sql' then
					raise exception 'Unsupported container type specified: %', l_stage_rec.master_container_type_name;
				end if;

				l_extraction_command := 
					replace(
						l_extraction_command
						, '{{master_recordset}}'
						, case 
							when l_stage_rec.is_master_source_virtual = true then
								l_stage_rec.master_container
							else
								${database.defaultSchemaName}.f_extraction_temp_table_name(
									i_transfer_id => i_transfer_id
									, i_extraction_name => l_stage_rec.master_source_name
								)::text
						end
					);
			end if;		
			
			if l_stage_rec.reexec_results then
				raise notice 'Re-executing command: %', l_extraction_command;
				if l_stage_rec.source_positional_arguments is not null then
					execute l_extraction_command into l_extraction_command using l_stage_rec.source_positional_arguments;
				else
					execute l_extraction_command into l_extraction_command;
				end if;
				if l_extraction_command is null then
					raise exception 'Re-executed command generated empty result (% %)', l_stage_rec.source_type_name, l_stage_rec.source_name;
				end if;
			end if;

			l_temp_table_name := 
				${database.defaultSchemaName}.f_extraction_temp_table_name(
					i_transfer_id => i_transfer_id
					, i_extraction_name => l_stage_rec.source_name
				);

			l_extraction_command := 
				format('
						create temporary table %I
						on commit drop
						as %s
					'
					, l_temp_table_name
					, l_extraction_command
				);
			
			raise notice 'Extraction command: %', l_extraction_command;
			
			execute l_extraction_command;
		elsif l_stage_rec.source_type_name = 'load' then
			if l_stage_rec.master_source_name is null then
				raise exception 'Load operation have not expected extraction: %', l_stage_rec.source_name;
			end if;
			
			l_temp_table_name := 
				${database.defaultSchemaName}.f_extraction_temp_table_name(
					i_transfer_id => i_transfer_id
					, i_extraction_name => l_stage_rec.master_source_name
				);
		
			if l_stage_rec.container_type_name = 'table' then
				l_column_list := (
					select 
						string_agg(c.column_name, ', ')
					from ( 
						select
							c.column_name
						from 
							information_schema.columns c
						where 
							c.table_schema = (
								select 
									nspname 
								from 
									pg_catalog.pg_namespace 
								where 
									oid = pg_my_temp_schema()
							)
							and c.table_name = l_temp_table_name
						intersect 
						select
							c.column_name
						from
							information_schema.columns c
						where 
							c.table_schema = '${stagingSchemaName}'
							and c.table_name = l_stage_rec.container
					) c			
				);
			
				l_load_command := 
					format('
							insert into 
								${stagingSchemaName}.%I(
									data_package_id 
									, data_package_rn
									, %s
								)
							select 
								%s as data_package_id
								, row_number() over() as data_package_rn
								, %s 
							from 
								%I
						'
						, l_stage_rec.container
						, l_column_list
						, l_data_package_id
						, l_column_list
						, l_temp_table_name
					);
					
				raise notice 'Load command: %', l_load_command;
				execute l_load_command;
				
				call ${stagingSchemaName}.p_apply_data_package(
					i_data_package_id => l_data_package_id
					, i_container_name => l_stage_rec.container
					, io_check_date => l_check_date
				);
				
				l_data_package_id := null;
			else
				raise exception 'Unsupported container type specified: %', l_stage_rec.container_type_name;
			end if;
		end if;		
	end loop;
	
	if l_stage_rec.transfer_id is null then
		raise exception 'Unknown transfer identifier specified: %', i_transfer_id;
	end if;
end
$procedure$;			
