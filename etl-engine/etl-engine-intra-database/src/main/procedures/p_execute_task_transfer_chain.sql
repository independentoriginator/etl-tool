create or replace procedure p_execute_task_transfer_chain(
	i_task_id ${mainSchemaName}.task.id%type
	, i_transfer_chain_id ${mainSchemaName}.transfer.id%type
)
language plpgsql
as $procedure$
declare 
	l_stage_rec record;
	l_command ${mainSchemaName}.transfer.container%type;
	l_temp_table_name name;
	l_positional_arguments text[];
	l_n_arg integer;
	l_data_package_id ${stagingSchemaName}.data_package.id%type; 
	l_check_date ${stagingSchemaName}.data_package.state_change_date%type;
	l_insert_columns text;
	l_select_columns text;
begin
	for l_stage_rec in (
		select
			ts.*
		from 
			${mainSchemaName}.v_task_stage ts
		where 
			ts.task_id = i_task_id
			and ts.transfer_chain_id = i_transfer_chain_id
			and ts.is_virtual = false
		order by 
			sort_order
	) 
	loop
		if l_stage_rec.is_reexecution = false then
			raise notice 
				'Executing the transfer: transfer_name=%, transfer_type_name=%, source_name=%, source_type_name=%'
				, l_stage_rec.transfer_name
				, l_stage_rec.transfer_type_name
				, l_stage_rec.source_name
				, l_stage_rec.source_type_name
				;				 			
		end if;
	
		case l_stage_rec.transfer_type_name
			when 'extraction' then
				
				case l_stage_rec.container_type_name 
					when 'table' then
						l_command := 
							format(
								'select * from %I' 
								, l_stage_rec.container
							);
					else 
						l_command := l_stage_rec.container;
				end case;	
				
				raise notice 'l_command=%', l_command;			
			
				if l_stage_rec.master_transfer_name is not null then
					if l_stage_rec.is_master_transfer_virtual then
						l_command :=  
							replace(
								l_command
								, '{{master_recordset}}'
								, case 
									when l_stage_rec.master_container_type_name = 'table' then 
										format(
											'select * from %I' 
											, l_stage_rec.master_container
										)
									else 
										l_stage_rec.master_container
								end
							);
					elsif l_stage_rec.reexec_results and l_stage_rec.is_reexecution then
						l_temp_table_name := 
							${mainSchemaName}.f_extraction_temp_table_name(
								i_task_id => i_task_id
								, i_transfer_name => l_stage_rec.master_transfer_name
								, i_is_for_reexec => true
							)::text
							;
						l_command :=  
							replace(
								l_command
								, '{{master_recordset}}'
								, format(
									$$select string_agg(%s, '') from %I$$
									, (
										select
											string_agg('coalesce(' || c.column_name || ', '''')', '||')
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
									)
									, l_temp_table_name
								)
							);
						execute l_command into l_command;							
					else
						l_command :=  
							replace(
								l_command
								, '{{master_recordset}}'
								, ${mainSchemaName}.f_extraction_temp_table_name(
									i_task_id => i_task_id
									, i_transfer_name => l_stage_rec.master_transfer_name
									, i_is_for_reexec => false
								)::text
							);
					end if;

					raise notice 'l_command=%', l_command;
				end if;
					
				if l_stage_rec.transfer_positional_arguments is not null then 
					l_positional_arguments := string_to_array(l_stage_rec.transfer_positional_arguments, ',');
					
					for l_n_arg in array_lower(l_positional_arguments, 1) .. array_upper(l_positional_arguments, 1)  loop
						l_command := replace(l_command, '$' || l_n_arg::varchar,  quote_nullable(l_positional_arguments[l_n_arg]));
					end loop;
				end if; 

				l_temp_table_name := 
					${mainSchemaName}.f_extraction_temp_table_name(
						i_task_id => i_task_id
						, i_transfer_name => l_stage_rec.transfer_name
						, i_is_for_reexec => case when l_stage_rec.reexec_results and not l_stage_rec.is_reexecution then true else false end 
					);
					
				case l_stage_rec.source_type_name
					when 'postgresql' then
			
						l_command := 
							format('
									create temporary table %I
									on commit drop
									as %s
								'
								, l_temp_table_name
								, l_command
							);
						
						raise notice 'Extraction command: %', l_command;
						
						execute l_command;
						
					else
						raise warning 'Unsupported source type specified: %', l_stage_rec.source_type_name;
				end case;
			
			when 'load' then
				if l_stage_rec.master_transfer_name is null then
					raise exception '%. %: have not expected preceding extraction or transformation', l_stage_rec.source_name, l_stage_rec.transfer_type_name;
				end if;
				
				l_temp_table_name := 
					${mainSchemaName}.f_extraction_temp_table_name(
						i_task_id => i_task_id
						, i_transfer_name => l_stage_rec.master_transfer_name
					);
				
				if l_stage_rec.source_name = 'this database' then
					
					select 
						o_data_package_id
						, o_check_date
					into
						l_data_package_id
						, l_check_date
					from 
						${stagingSchemaName}.f_insert_data_package(
							i_type_name => l_stage_rec.container
							, i_source_name => l_stage_rec.project_name
							, i_is_deletion => l_stage_rec.is_deletion
						)
					;
				
					select 
						string_agg(src_col.column_name, ', ')
						, string_agg(src_col.column_name || '::' || dest_col.data_type || ' as ' || dest_col.column_name, ', ')
					into 
						l_insert_columns
						, l_select_columns
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
					) src_col
					join (
						select
							c.column_name
							, c.data_type
						from
							information_schema.columns c
						where 
							c.table_schema = '${stagingSchemaName}'
							and c.table_name = l_stage_rec.container			
					) dest_col
					on dest_col.column_name = src_col.column_name								
					;	
					
					l_command := 
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
							;
							'
							, l_stage_rec.container
							, l_insert_columns
							, l_data_package_id
							, l_select_columns
							, l_temp_table_name
						);
						
					raise notice 'Load command: %', l_command;
						
					execute l_command;
					
					call ${stagingSchemaName}.p_process_data_package(
						i_data_package_id => l_data_package_id
						, i_entity_name => l_stage_rec.container
						, io_check_date => l_check_date
					);
				
				end if;
				
			when 'execution' then
			
				if l_stage_rec.source_name = 'this database' then
					l_command := l_stage_rec.container;
					
					raise notice 'Execution command: %', l_command;
					
					execute l_command;
				else
					raise warning 'Unsupported source type specified: %', l_stage_rec.source_type_name;
				end if;
		
			else
				raise warning 'Unsupported transfer type specified: %', l_stage_rec.transfer_type_name;
		end case;	

	end loop;
	
	if l_stage_rec.transfer_id is null then
		raise exception 'Unknown "transfer task" and/or "transfer chain" are specified: task_id = %, transfer_chain_id = %', i_task_id, i_transfer_chain_id;
	end if;
end
$procedure$;			
