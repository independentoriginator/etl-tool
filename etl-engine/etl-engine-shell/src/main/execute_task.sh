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

exit_code=0

script_dir="$(dirname $0)"

temp_dir="$(mktemp -d)"
echo "Used temporary directory is: $temp_dir"

transfer_list="$temp_dir/transfer-list"

echo "
	select 
		ts.transfer_name
		, ts.transfer_type_name
		, ts.source_type_name
		, ts.source_name
		, coalesce(ts.connection_string, 'null')
		, coalesce(ts.container_type_name, 'null')
		, coalesce(ts.container, 'null')
		, coalesce(ts.master_transfer_name, 'null')
		, coalesce(ts.master_transfer_type_name, 'null')
	from
		etl_schema.v_task_stage ts
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
	while IFS=$'\n\t' read -r \
		transfer_name \
		transfer_type_name \
		source_type_name \
		source_name \
		connection_string \
		container_type_name \
		container \
		master_transfer_name \
		master_transfer_type_name \
		; do
		echo "Executing transfer: transfer_type_name=$transfer_type_name, source_type_name=$source_type_name, source_name=$source_name, container_type_name=$container_type_name, container=$container, master_transfer_name=$master_transfer_name"
		
		if [[ $transfer_type_name = "extraction" ]]; then
			extraction_result="$temp_dir/$transfer_type_name-$transfer_name"
		
			if [[ $source_name = "this database" ]]; then
				if [[ $container_type_name = "table" ]]; then
					target_container=$container
				elif [[ $container_type_name = "sql" ]]; then
					target_container="("$container")"
				else
					echo "$source_name. $transfer_type_name: inappropriate container type specified: $container_type_name"
					exit_code=1
					break
				fi
				
				psql $pg_connection_string \
					--command="\copy $target_container to '$extraction_result' with (format csv, header, delimiter ';')"
					
				if [ $? -ne 0 ]; then
					echo "$transfer_name failure"
					exit_code=1
					break
				fi						
				
			elif [[ $source_type_name = "xlsx" ]]; then
				input_dir=$(eval echo "$connection_string")
				mkdir -p "$extraction_result"
				cp -r "$input_dir"/* "$extraction_result"
			fi
			
		elif [[ $transfer_type_name = "load" ]]; then
			if [[ $master_transfer_type_name = "extraction" ]]; then
				if [[ $source_name = "this database" ]]; then
					echo todo
				elif [[ $source_type_name = "duckdb" ]]; then
					echo todo
				fi
				
			elif [[ $master_transfer_type_name = "xlsx to csv" ]]; then
				load_result="$temp_dir/$transfer_type_name-$transfer_name"
				transformation_result="$temp_dir/$master_transfer_type_name-$master_transfer_name"
			
				if [[ $source_name = "this database" ]]; then
					echo todo
				elif [[ $source_type_name = "duckdb" ]]; then
					if [[ $container = "null" ]]; then # new tables are created
						if [[ $connection_string = "null" ]]; then # temporary db is generated
							"transfers/duckdb/load/load-csv-to-duckdb.sh" \
								"$load_result" \
								"$transformation_result"
								
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
				
				"transfers/xlsx/transformation/xlsx-to-csv/transform-xlsx-to-csv.sh" \
					"$extraction_result" \
					"$transformation_result"
					
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

#rm -r "$temp_dir"

exit $exit_code

	
	
	
	