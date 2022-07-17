#!/bin/bash

task_name="$1"
project_name="$2"
etl_schema_name="$3"
staging_schema_name="$4"

if [ -z "$task_name" ] || [ -z "$project_name" ] || [ -z "$etl_schema_name" ] || [ -z "$staging_schema_name" ]; then
	echo "Usage: $0 \"data-transfer-task-name\" \"data-transfer-project-name\" \"etl_schema_name\" \"staging_schema_name\""
	exit 1
fi

pg_connection_string=$(grep -v '#.*' database-connection.txt)

if [ -z "$pg_connection_string" ]; then
	echo "Data connection string must be set at the file \"database-connection.txt\""
	exit 1
fi

echo "Connecting to the ETL repository: $pg_connection_string..."

# pg_password is in .pgpass file
PGPASSFILE='~/.pgpass'

exchange_file_format="csv"
exchange_file_delimiter=";"

exit_code=0

script_dir="$(dirname $0)"

temp_dir="$(mktemp -d)"
echo "Used temporary directory is: $temp_dir"

transfer_list="$temp_dir/transfer-list"

echo "
	select
		ts.project_name
		, ts.transfer_id
		, ts.transfer_name
		, ts.transfer_type_name
		, ts.is_virtual		
		, ts.source_type_name
		, ts.source_name
		, coalesce(ts.connection_string, 'null') as connection_string
		, coalesce(ts.container_type_name, 'null') as container_type_name
		, coalesce(case when ts.container_type_name = 'table' then ts.container end, 'null') as table_name
		, ts.reexec_results
		, ts.is_reexecution
		, ts.is_deletion
		, coalesce(ts.transfer_positional_arguments, 'null') as transfer_positional_arguments 
		, coalesce(ts.master_transfer_name, 'null') as master_transfer_name
		, coalesce(ts.master_transfer_type_name, 'null') as master_transfer_type_name
		, coalesce(ts.master_source_name, 'null') as master_source_name
		, coalesce(ts.master_source_type_name, 'null') as master_source_type_name
		, coalesce(ts.is_master_transfer_virtual, false) as is_master_transfer_virtual
	from
		$etl_schema_name.v_task_stage ts
	where 
		ts.project_name = '$project_name'
		and ts.task_name = '$task_name'
	order by 
		sort_order
" | \
psql $pg_connection_string \
	--tuples-only \
	--no-align \
	--field-separator=$'\t' \
	> $transfer_list
	
if [ $? -ne 0 ]; then
	echo "Unable to retrieve target data transfer list for the task specified: $task_name"
	exit_code=1
else	
	if [ ! -s $transfer_list ]; then
		echo "Unknown task specified: $task_name"
		exit_code=1
	else
		while IFS=$'\n\t' read -r \
			project_name \
			transfer_id \
			transfer_name \
			transfer_type_name \
			is_virtual \
			source_type_name \
			source_name \
			connection_string \
			container_type_name \
			table_name \
			reexec_results \
			is_reexecution \
			is_deletion \
			transfer_positional_arguments \
			master_transfer_name \
			master_transfer_type_name \
			master_source_name \
			master_source_type_name \
			is_master_transfer_virtual \
			; do
			
			if [[ $is_reexecution = "f" ]]; then			
				echo "Executing transfer: transfer_name=$transfer_name, transfer_type_name=$transfer_type_name, source_name=$source_name, source_type_name=$source_type_name, is_virtual=$is_virtual"
			fi

			sql_file=
			if [[ $container_type_name = "sql" ]]; then
				sql_file=$temp_dir/sql-$transfer_type_name-$transfer_name 
				psql $pg_connection_string \
					--tuples-only \
					--no-align \
					--command="select container from $etl_schema_name.v_task_stage where transfer_id = $transfer_id and is_reexecution = false" \
				> $sql_file
			fi
			
			if [[ $transfer_type_name = "extraction" ]] \
				&& [[ ! -z $master_transfer_name ]] \
				&& [[ $master_transfer_name != "null" ]] \
				&& [[ $is_master_transfer_virtual = "t" ]]; then
					master_query=$temp_dir/sql-$master_transfer_type_name-$master_transfer_name
					singleline_sql=$(tr '\n' ' ' < $master_query)
					# Replacing {{master_recordset}} with the master sql file contents
					sed --in-place "s/{{master_recordset}}/$singleline_sql/" $sql_file
			fi
			
			if [[ $is_virtual = "t" ]]; then
				continue
			fi
			
			if [[ ! -z $transfer_positional_arguments ]] && [[ $transfer_positional_arguments != "null" ]]; then
				IFS="," read -r -a arg_arr <<< $transfer_positional_arguments 
				arg_pos=0
				for arg_value in "${arg_arr[@]}"; do
					(( arg_pos++ ))
					sed --in-place "s/\$$arg_pos/'$arg_value'/" $sql_file
				done				
			fi
			
			if [[ $source_name = "this database" ]]; then
				connection_string=$pg_connection_string
			fi
			
			if [[ $transfer_type_name = "extraction" ]]; then
				extraction_result="$temp_dir/$transfer_type_name-$transfer_name"
				
				if [[ $reexec_results = "t" ]] && [[ $is_reexecution = "f" ]]; then
					extraction_result=$extraction_result"-for-reexec"
				fi
				
				if [[ $source_type_name = "postgresql" ]]; then
					if [[ $container_type_name = "table" ]]; then
						psql $connection_string \
							--command="\copy $table_name to '$extraction_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')"
							
						if [ $? -ne 0 ]; then
							echo "$transfer_name failure"
							exit_code=1
							break
						fi						
					elif [[ $container_type_name = "sql" ]]; then
						if [[ ! -z $master_transfer_name ]] \
							&& [[ $master_transfer_name != "null" ]] \
							&& [[ $is_master_transfer_virtual = "f" ]]; then
							# {{master_recordset}} substitution
							master_transfer_result="$temp_dir/$master_transfer_type_name-$master_transfer_name"
							export_script=$temp_dir/script
							if [[ $reexec_results = "t" ]] && [[ $is_reexecution = "t" ]]; then
								singleline_sql=$(tr '\n' ' ' < $master_transfer_result"-for-reexec")
								echo "\copy ($singleline_sql) to '$extraction_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')" > $export_script
							else
								temp_table_name="tmp_$master_transfer_name"
								table_header=$(head -n 1 $master_transfer_result)
								echo "create temporary table \"$temp_table_name\"(\""${table_header//$exchange_file_delimiter/'" text,"'}"\" text) on commit drop;" > $export_script
								echo "\copy \"$temp_table_name\" from '$master_transfer_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')" >> $export_script
								# Replacing {{master_recordset}} with the temporary table name of the master extraction
								sed --in-place "s/{{master_recordset}}/\"$temp_table_name\"/g" $sql_file
								singleline_sql=$(tr '\n' ' ' < $sql_file)
								echo "\copy ($singleline_sql) to '$extraction_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')" >> $export_script
							fi

							psql $connection_string \
								--single-transaction \
								--command="\set ON_ERROR_STOP true" \
								--file="$export_script"
						else
							if [[ $reexec_results = "t" ]] && [[ $is_reexecution = "f" ]]; then
								psql $connection_string \
									--file=$sql_file \
									--tuples-only \
									--no-align \
								> $extraction_result
							else
								singleline_sql=$(tr '\n' ' ' < $sql_file)
								psql $connection_string \
									--command="\copy ($singleline_sql) to '$extraction_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')"
							fi
						fi
						
						if [ $? -ne 0 ]; then
							echo "$transfer_name failure"
							exit_code=1
							break
						fi						
					else
						echo "$source_name. $transfer_type_name: inappropriate container type specified: $container_type_name"
						exit_code=1
						break
					fi
					
				elif [[ $source_type_name = "duckdb" ]]; then
					if [[ $connection_string = "null" ]]; then # temporary db is used
						database_file="$temp_dir/$master_source_name"
					else
						database_file="$connection_string"
					fi
					
					"transfers/duckdb/extraction/export-from-duckdb.sh" "$database_file" "$table_name" "$sql_file" "$extraction_result" "$exchange_file_format" "$exchange_file_delimiter" "true"
						 
					if [ $? -ne 0 ]; then
						echo "$transfer_name failure"
						exit_code=1
						break
					fi						
					
				elif [[ $source_type_name = "xlsx" ]]; then
					input_dir=$(eval echo "$connection_string")
					mkdir -p "$extraction_result"
					cp -r "$input_dir"/* "$extraction_result"
					
				else
					echo "$source_name. $transfer_type_name: unsupported source type specified: $source_type_name"
					exit_code=1
					break
				fi
				
			elif [[ $transfer_type_name = "load" ]]; then
				if [[ ! -z $master_transfer_type_name ]] && [[ $master_transfer_type_name != "null" ]]; then
					master_transfer_result="$temp_dir/$master_transfer_type_name-$master_transfer_name"
				
					if [[ $source_type_name = "postgresql" ]]; then
						if [[ $master_source_type_name = "folder" ]]; then
							echo todo
							
						else
							table_header=$(head -n 1 $master_transfer_result)
						
							if [[ $table_name = "null" ]]; then # new table is created
								target_table_name="$master_transfer_name"
								create_table_command="create table \"$target_table_name\"("${table_header//$exchange_file_delimiter/' text,'}" text);"
		
								psql $connection_string \
									--single-transaction \
									--command="\set ON_ERROR_STOP true" \
									--command="$create_table_command"
									--command="\copy $target_table_name from '$master_transfer_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')"
							else
								table_columns="${table_header//$exchange_file_delimiter/','}"
						
								if [[ $source_name = "this database" ]]; then
									temp_table_name="tmp_$master_transfer_name"
									create_table_command="create temporary table \"$temp_table_name\"("${table_header//$exchange_file_delimiter/' text,'}" text) on commit drop;"

									psql $connection_string \
										--single-transaction \
										--command="\set ON_ERROR_STOP true" \
										--command="$create_table_command" \
										--command="\copy \"$temp_table_name\" from '$master_transfer_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')" \
										--command="
											do \$target_data_import\$
											declare 
												l_data_package_id $staging_schema_name.data_package.id%type; 
												l_check_date $staging_schema_name.data_package.state_change_date%type;
												l_insert_columns text;
												l_select_columns text;
											begin
												select 
													o_data_package_id
													, o_check_date
												into
													l_data_package_id
													, l_check_date
												from 
													$staging_schema_name.f_insert_data_package(
														i_type_name => '$table_name'
														, i_source_name => '$project_name'
														, i_is_deletion => '$is_deletion'::boolean
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
														and c.table_name = '$temp_table_name'
												) src_col
												join (
													select
														c.column_name
														, c.data_type
													from
														information_schema.columns c
													where 
														c.table_schema = '$staging_schema_name'
														and c.table_name = '$table_name'			
												) dest_col
												on dest_col.column_name = src_col.column_name								
												;	
												
												execute format('
													insert into 
														$staging_schema_name.$table_name(
															data_package_id 
															, data_package_rn
															, %s
														)
													select 
														%s as data_package_id
														, row_number() over() as data_package_rn
														, %s 
													from 
														\"$temp_table_name\"
													;
													'
													, l_insert_columns
													, l_data_package_id
													, l_select_columns
												);
												
												call $staging_schema_name.p_process_data_package(
													i_data_package_id => l_data_package_id
													, i_entity_name => '$table_name'
													, io_check_date => l_check_date
												);
											end
											\$target_data_import\$;
										"								
								else							
									psql $connection_string \
										--command="\copy $table_name($table_columns) from '$master_transfer_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')"
								fi
							fi
							
							if [ $? -ne 0 ]; then
								echo "$transfer_name failure"
								exit_code=1
								break
							fi
						fi						
						
					elif [[ $source_type_name = "duckdb" ]]; then
						if [[ $master_source_type_name = "folder" ]]; then
							if [[ $table_name = "null" ]]; then # new tables are created
								if [[ $connection_string = "null" ]]; then # temporary db is generated
									"transfers/duckdb/load/load-csv-to-duckdb.sh" "$temp_dir/$source_name" "$master_transfer_result"
	
									if [ $? -ne 0 ]; then
										echo "$transfer_name failure"
										exit_code=1
										break
									fi						
								fi
							fi
						fi				
					fi
				else
					echo "$source_name. $transfer_type_name: have not expected preceding extraction or transformation"
					exit_code=1
					break
				fi
				
			elif [[ $transfer_type_name = "execution" ]]; then
				
				if [[ $source_type_name = "postgresql" ]]; then
					psql $connection_string \
						--file=$sql_file 
						
					if [ $? -ne 0 ]; then
						echo "$transfer_name failure"
						exit_code=1
						break
					fi						
				else
					echo "$source_name. $transfer_type_name: unsupported source type specified: $source_type_name"
					exit_code=1
					break
				fi
				
			elif [[ $transfer_type_name = "xlsx to csv" ]]; then
				if [[ $master_transfer_type_name = "extraction" ]]; then
					extraction_result="$temp_dir/$master_transfer_type_name-$master_transfer_name"
					transformation_result="$temp_dir/$transfer_type_name-$transfer_name"
					
					"transfers/xlsx/transformation/xlsx-to-csv/transform-xlsx-to-csv.sh" "$extraction_result" "$transformation_result"
						
					if [ $? -ne 0 ]; then
						echo "$transfer_name failure"
						exit_code=1
						break
					fi						
				else
					echo "$source_name. $transfer_type_name: have not preceding extraction"
					exit_code=1
					break
				fi
				
			fi
				
		done < $transfer_list
	fi
fi

rm -r "$temp_dir"

exit $exit_code

	
	
	
	