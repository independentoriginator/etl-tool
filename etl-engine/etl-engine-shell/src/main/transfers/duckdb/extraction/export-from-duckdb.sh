#!/bin/bash

database_file="$1"
table_name="$2"
sql_file="$3"
output_file="$4"
output_format="$5"
output_delimiter="$6"
output_with_header="$7"

if [[ -z "$database_file" ]] || [[ -z "$output_file" ]] || ([[ -z "$table_name" ]] && [[ -z "$sql_file" ]]); then
	echo "Usage: $0 \"duckdb-file\" \"table_name\" \"sql_file\" \"output_file\" \"output_format\" \"output_delimiter\" \"output_with_header\""
	exit 1
fi

echo "DuckDB export (from '$database_file' to '$output_file')..."

exit_code=0

script_dir="$(dirname $0)"

if [ -z "$output_format" ]; then
	output_format=csv
fi

if [ -z "$output_delimiter" ]; then
	output_delimiter=";"
fi

if [ ! -z $table_name ] && [ $table_name != "null" ]; then
	if [ -z "$output_with_header" ]; then
		output_with_header=true
	fi

	"$script_dir"/../duckdb \
		-echo \
		"$database_file" \
		"copy $table_name to '$output_file' with (format $output_format, delimiter '$output_delimiter', header $output_with_header);" \
		".quit 0"
	
	if [ $? -ne 0 ]; then
		echo "DuckDB data export failure"
		exit_code=1
	fi
else
	if [ "$output_with_header" = "false" ]; then
		output_with_header=noheader
	else
		output_with_header=header
	fi
	
	"$script_dir"/../duckdb \
		-$output_format \
		-$output_with_header \
		-separator $output_delimiter \
		"$database_file" \
		".read \"$sql_file\"" \
		".quit 0" \
		> "$output_file"
		
	if [ $? -ne 0 ]; then
		echo "DuckDB data export failure"
		exit_code=1
	fi
fi

exit $exit_code