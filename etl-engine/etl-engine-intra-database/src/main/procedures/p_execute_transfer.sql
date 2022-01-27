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
			ordinal_position 
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
		elsif l_stage_rec.source_type_name = 'extraction' then
			if l_stage_rec.container_type_name <> 'sql' then
				raise exception 'Unsupported container type specified: %', l_stage_rec.container_type_name;
			end if;
			
			l_extraction_command := 
				format('
						create temporary table t_%I
						as %s
					'
					, l_stage_rec.source_name
					, l_stage_rec.container
				);
			
			if l_stage_rec.master_source_type_name = 'extraction' then
				if l_stage_rec.master_container_type_name <> 'sql' then
					raise exception 'Unsupported container type specified: %', l_stage_rec.master_container_type_name;
				end if;

				l_extraction_command := replace(l_extraction_command, '{{master_recordset}}', 't_' || l_stage_rec.master_source_name);
			end if;		
			
			raise notice 'Extraction command: %', l_extraction_command;
			
			execute l_extraction_command;
		elsif l_stage_rec.source_type_name = 'load' then
			l_temp_table_name := 't_' || l_stage_rec.master_source_name;
			l_column_list := (
				select 
					string_agg(c.column_name, ', ' order by c.ordinal_position)
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
			);
		
			if l_stage_rec.container_type_name = 'table' then
				l_load_command := 
					format('
							insert into %I.%I(data_package_id, %s)
							select %s, %s from %I
						'
						, '${stagingSchemaName}'
						, l_stage_rec.container
						, l_column_list
						, l_data_package_id
						, l_column_list
						, l_temp_table_name
					);
			else
				raise exception 'Unsupported container type specified: %', l_stage_rec.container_type_name;
			end if;
			
			raise notice 'Load command: %', l_load_command;
			execute l_load_command;
			
			call ${stagingSchemaName}.p_apply_data_package(
				i_data_package_id => l_data_package_id
				, io_check_date => l_check_date
			);
		end if;		
	end loop;
	
	if l_data_package_id is null then
		raise exception 'Unknown transfer identifier specified: %', i_transfer_id;
	end if;
end
$procedure$;			
