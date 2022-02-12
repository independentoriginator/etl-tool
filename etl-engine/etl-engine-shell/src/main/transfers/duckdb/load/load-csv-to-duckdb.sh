#!/bin/bash

database_file="$1"
input_dir="$2"

if [ -z "$database_file" ] || [ -z "$input_dir" ]; then
	echo "Usage: $0 \"duckdb-file\" \"input-directory-with-csv-files\""
	exit 1
fi

echo "CSV-to-DuckDB load (from '$input_dir' to '$database_file')..."

exit_code=0

script_dir="$(dirname $0)"

temp_dir="$(mktemp -d)"

duckdb_script=$temp_dir/script

file_count=0

for input_file in "$input_dir"/*.csv; do
	filename="${input_file##*/}"
	filetitle="${filename%.*}"
	echo "create table $filetitle as select * from '$input_file';" >>"$duckdb_script"
	(( file_count++ ))	
done

echo ".exit 0" >>"$duckdb_script"

"$script_dir"/../duckdb "$database_file" ".read \"$duckdb_script\""

if [ $? -ne 0 ]; then
	echo "DuckDB data import failure"
	exit_code=1
else
	echo "CSV file loaded count: $file_count"
fi

rm -r "$temp_dir"

exit $exit_code