drop procedure if exists 
	p_execute_task_transfer_chain(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer.id%type
	)
;

drop procedure if exists 
	p_execute_task_transfer_chain(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer.id%type
		, text
		, text
		, integer
		, integer
		, integer
		, timestamptz
	)
;

drop procedure if exists 
	p_execute_task_transfer_chain(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer.id%type
		, boolean
		, text
		, text
		, integer
		, integer
		, integer
		, timestamptz
	)
;

drop procedure if exists 
	p_execute_task_transfer_chain(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer.id%type
		, text
		, bigint
		, boolean
		, text
		, text
		, integer
		, integer
		, integer
		, timestamptz
	)
;

drop procedure if exists 
	p_execute_task_transfer_chain(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer.id%type
		, text
		, ${mainSchemaName}.transfer.id%type
		, boolean
		, text
		, text
		, integer
		, integer
		, integer
		, timestamptz
	)
;

drop procedure if exists 
	p_execute_task_transfer_chain(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer.id%type
		, text
		, ${mainSchemaName}.transfer.id%type
		, boolean
		, text
		, text
		, integer
		, integer
		, interval
		, interval
		, timestamptz
	) 
;

create or replace procedure 
	p_execute_task_transfer_chain(
		i_task_id ${mainSchemaName}.task.id%type
		, i_transfer_chain_id ${mainSchemaName}.transfer.id%type
		, i_chunk_id text = null
		, i_chunked_sequence_id ${mainSchemaName}.transfer.id%type = null
		, i_process_chunks_in_single_transaction boolean = false
		, i_is_deletion_stage boolean = null
		, i_scheduler_type_name text = null
		, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
		, i_scheduled_task_stage_ord_pos integer = 0
		, i_max_worker_processes integer = 1
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
		, i_last_execution_date timestamptz = null
	)
language plpgsql
as $procedure$
declare 
	l_stage_rec record;
	l_env_variable_names text[] := 
		array[
			'{{scheduler_type_name}}'
			, '{{scheduled_task_name}}'
			, '{{scheduled_task_stage_ord_pos}}'
			, '{{thread_max_count}}'
			, '{{max_worker_processes}}'
			, '{{max_run_time}}'
			, '{{wait_for_delay_in_seconds}}'
			, '{{polling_interval}}'
			, '{{last_execution_date}}'
		]::text[];
	l_env_variable_values text[] := 
		array[
			i_scheduler_type_name
			, i_scheduled_task_name
			, i_scheduled_task_stage_ord_pos::text
			, i_max_worker_processes::text
			, i_max_worker_processes::text
			, i_max_run_time::text
			, extract(epoch from i_polling_interval)::integer::text
			, i_polling_interval::text
			, i_last_execution_date::text
		]::text[];
	l_command ${mainSchemaName}.transfer.container%type;
	l_temp_table_name name;
	l_positional_arguments text[];
	l_n_arg integer;
	l_data_package_id ${stagingSchemaName}.data_package.id%type; 
	l_check_date ${stagingSchemaName}.data_package.state_change_date%type;
	l_insert_columns text;
	l_select_columns text;
	l_chunk_id text;
	l_processed_chunked_sequences ${type.id}[];
begin
	<<stages>>
	for l_stage_rec in (
		select
			ts.task_id
			, ts.task_name
			, ts.project_name
			, ts.transfer_project_name
			, ts.transfer_id
			, ts.transfer_name
			, ts.transfer_type_name
			, ts.source_type_name
			, ts.source_name
			, ts.connection_string
			, ts.user_name
			, ts.user_password
			, ts.container_type_name
			, ${mainSchemaName}.f_substitute(
				i_text => ts.container
				, i_keys => l_env_variable_names
				, i_values => l_env_variable_values
			) as container
			, ts.is_virtual
			, ts.reexec_results
			, ts.is_reexecution
			, ts.is_chunking
			, ts.is_chunking_parallelizable
			, ts.is_chunked
			, ts.chunked_sequence_id
			, ts.is_deletion			
			, ts.ordinal_position
			, ts.target_transfer_id
			, ts.stage_ordinal_position
			, ts.transfer_positional_arguments
			, ts.preceding_transfer_id
			, ts.master_transfer_id
			, ts.master_transfer_name
			, ts.master_transfer_type_name
			, ts.master_source_name
			, ts.master_source_type_name
			, ts.master_container_type_name
			, ts.master_container    
			, ts.is_master_transfer_virtual
			, ts.is_master_transfer_chunked
			, ts.transfer_chain_id
			, ts.chain_order_num
			, ts.sort_order as transfer_num
		from 
			${mainSchemaName}.v_task_stage ts
		where 
			ts.task_id = i_task_id
			and ts.transfer_chain_id = i_transfer_chain_id
			and (ts.chunked_sequence_id = i_chunked_sequence_id or i_chunked_sequence_id is null)
			and (ts.is_deletion_stage = i_is_deletion_stage or i_is_deletion_stage is null)
			and ts.is_virtual = false
		order by 
			ts.sort_order
	) 
	loop
		-- Skipping previously processed chunked sequence
		if l_stage_rec.chunked_sequence_id = any(l_processed_chunked_sequences) then
			continue;
		end if;
	
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
							)
							;
					elsif l_stage_rec.reexec_results and l_stage_rec.is_reexecution then
						l_temp_table_name := 
							${mainSchemaName}.f_extraction_temp_table_name(
								i_task_id => i_task_id
								, i_transfer_id => l_stage_rec.master_transfer_id
								, i_chunk_id => case when l_stage_rec.is_master_transfer_chunked then i_chunk_id end
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
									, i_transfer_id => l_stage_rec.master_transfer_id
									, i_chunk_id => case when l_stage_rec.is_master_transfer_chunked then i_chunk_id end
									, i_is_for_reexec => false
								)::text
							);
					end if;
				end if;

				if i_chunk_id is not null then 
					l_command :=
						replace(
							l_command
							, '{{chunk_id}}'
							, i_chunk_id
						)
						;
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
						, i_transfer_id => l_stage_rec.transfer_id
						, i_chunk_id => case when l_stage_rec.is_chunked then i_chunk_id end
						, i_is_for_reexec => case when l_stage_rec.reexec_results and not l_stage_rec.is_reexecution then true else false end 
					);
					
				case l_stage_rec.source_type_name
					when 'postgresql' then

						if not l_stage_rec.is_chunking then
						
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
							raise notice 'Chunking command: %', l_command;
						
							l_processed_chunked_sequences := array_append(l_processed_chunked_sequences, l_stage_rec.transfer_id);
						
							if l_stage_rec.master_transfer_id is null 
								and (
									l_stage_rec.is_chunking_parallelizable
								 	or (
								 		i_max_worker_processes = 1
								 		and i_process_chunks_in_single_transaction = false
								 	)
								)
							then
								call 
									${stagingSchemaName}.p_execute_in_parallel(
										i_command_list_query => 
											format(
												$sql$
												select
													format($$
														call 
															${mainSchemaName}.p_execute_task_transfer_chain(
																i_task_id => %s
																, i_transfer_chain_id => %s
																, i_chunk_id => %%L
																, i_chunked_sequence_id => %s
																, i_is_deletion_stage => %L::boolean
																, i_scheduler_type_name => %L
																, i_scheduled_task_name => %L
																, i_scheduled_task_stage_ord_pos => %s
																, i_max_worker_processes => %s
																, i_polling_interval => %L
																, i_max_run_time => %L
																, i_last_execution_date => %L
															)
														$$
														, c.chunk_id
													)
												from (
													%s
												) as c(chunk_id)
												$sql$
												, i_task_id
												, i_transfer_chain_id
												, l_stage_rec.transfer_id
												, i_is_deletion_stage
												, i_scheduler_type_name
												, i_scheduled_task_name
												, i_scheduled_task_stage_ord_pos
												, i_max_worker_processes
												, i_polling_interval
												, i_max_run_time
												, i_last_execution_date
												, l_command
											)
										, i_context_id => '${mainSchemaName}.p_execute_task_transfer_chain'::regproc
										, i_operation_instance_id => -i_transfer_chain_id::integer
										, i_max_worker_processes => round(i_max_worker_processes::numeric / 2, 0)::integer
										, i_single_transaction => i_process_chunks_in_single_transaction
										, i_polling_interval => i_polling_interval
										, i_max_run_time => i_max_run_time
										, i_application_name => '${project_internal_name}'
									)
								;
							else
								<<chunking>>
								for l_chunk_id in execute l_command loop
									
									raise notice 'Extraction chunk: %', l_chunk_id;
								
									call 
										${mainSchemaName}.p_execute_task_transfer_chain(
											i_task_id => i_task_id
											, i_transfer_chain_id => i_transfer_chain_id
											, i_chunk_id => l_chunk_id
											, i_chunked_sequence_id => l_stage_rec.transfer_id
											, i_is_deletion_stage => i_is_deletion_stage
											, i_scheduler_type_name => i_scheduler_type_name
											, i_scheduled_task_name => i_scheduled_task_name
											, i_scheduled_task_stage_ord_pos => i_scheduled_task_stage_ord_pos
											, i_max_worker_processes => i_max_worker_processes
											, i_polling_interval => i_polling_interval
											, i_max_run_time => i_max_run_time
											, i_last_execution_date => i_last_execution_date
										)
									;
								
								end loop chunking
								;
							end if 
							;
						
						end if;
					else
						raise warning 'Unsupported source type specified: %', l_stage_rec.source_type_name;
				end case;
			
			when 'load' then
				if l_stage_rec.master_transfer_name is null then
					raise exception '%. %: has no expected preceding extraction or transformation', l_stage_rec.source_name, l_stage_rec.transfer_type_name;
				end if;
				
				l_temp_table_name := 
					${mainSchemaName}.f_extraction_temp_table_name(
						i_task_id => i_task_id
						, i_transfer_id => l_stage_rec.master_transfer_id
						, i_chunk_id => i_chunk_id
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
							, i_source_name => l_stage_rec.transfer_project_name
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
				
					raise notice 'Processing the data package...';
					
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

	end loop stages;
	
	if l_stage_rec.transfer_id is null then
		raise exception 'Unknown "transfer task" and/or "transfer chain" are specified: task_id = %, transfer_chain_id = %', i_task_id, i_transfer_chain_id;
	end if;
end
$procedure$;			

comment on procedure 
	p_execute_task_transfer_chain(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer.id%type
		, text
		, ${mainSchemaName}.transfer.id%type
		, boolean
		, boolean
		, text
		, text
		, integer
		, integer
		, interval
		, interval
		, timestamptz
	) 
	is 'Исполнение цепочки перемещений задачи'
;
