#!/bin/bash

task_name="$1"

if [ -z "$task_name" ]; then
	echo "Usage: $0 \"data-transfer-task-name\""
	exit 1
fi

pg_connection_string=$(grep -v '#.*' database-connection.txt)

if [ -z "$pg_connection_string" ]; then
	echo "Data connection string must be set at the file \"database-connection.txt\""
	exit 1
fi

echo "Connecting to ETL repository: $pg_connection_string..."

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
		ts.transfer_name
		, ts.transfer_id
		, ts.transfer_type_name
		, ts.source_type_name
		, ts.source_name
		, coalesce(ts.connection_string, 'null') as connection_string
		, coalesce(ts.container_type_name, 'null') as container_type_name
		, coalesce(case when ts.container_type_name = 'table' then ts.container end, 'null') as table_name
		, coalesce(ts.master_transfer_name, 'null') as master_transfer_name
		, coalesce(ts.master_transfer_type_name, 'null') as master_transfer_type_name
	from
		v_task_stage ts
	where 
		ts.task_name = '$task_name'
	order by 
		stage_ordinal_position
		, target_transfer_id
		, ordinal_position	
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
			transfer_name \
			transfer_id \
			transfer_type_name \
			source_type_name \
			source_name \
			connection_string \
			container_type_name \
			table_name \
			master_transfer_name \
			master_transfer_type_name \
			; do
			echo "Executing transfer: transfer_name=$transfer_name, transfer_type_name=$transfer_type_name, source_name=$source_name, source_type_name=$source_type_name"

			sql_file=
			if [[ $container_type_name = "sql" ]]; then
				sql_file=$temp_dir/sql 
				psql $pg_connection_string \
					--tuples-only \
					--no-align \
					--command="select container from v_task_stage where transfer_id = $transfer_id" \
				> $sql_file
			fi
			
			if [[ $transfer_type_name = "extraction" ]]; then
				extraction_result="$temp_dir/$transfer_type_name-$transfer_name"
			
				if [[ $source_name = "this database" ]]; then
					if [[ $container_type_name = "table" ]]; then
						psql $pg_connection_string \
							--command="\copy $table_name to '$extraction_result' with (format $exchange_file_format, header, delimiter '$exchange_file_delimiter')"
							
						if [ $? -ne 0 ]; then
							echo "$transfer_name failure"
							exit_code=1
							break
						fi						
					elif [[ $container_type_name = "sql" ]]; then
						psql $pg_connection_string \
							--file="$sql_file" \
							--no-align \
							--field-separator="$exchange_file_delimiter" \
							> $transfer_list

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
						database_file="$temp_dir/$master_transfer_type_name-$master_transfer_name"
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
				if [[ $master_transfer_type_name = "xlsx to csv" ]]; then
					load_result="$temp_dir/$transfer_type_name-$transfer_name"
					transformation_result="$temp_dir/$master_transfer_type_name-$master_transfer_name"
				
					if [[ $source_name = "this database" ]]; then
						echo todo
					elif [[ $source_type_name = "duckdb" ]]; then
						if [[ $table_name = "null" ]]; then # new tables are created
							if [[ $connection_string = "null" ]]; then # temporary db is generated
								"transfers/duckdb/load/load-csv-to-duckdb.sh" "$load_result" "$transformation_result"

								if [ $? -ne 0 ]; then
									echo "$transfer_name failure"
									exit_code=1
									break
								fi						
							fi
						fi				
					fi
				else
					echo "$source_name. $transfer_type_name: have not preceding extraction"
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

#rm -r "$temp_dir"

exit $exit_code

	
	
	
	