#!/bin/bash

database_file="$1"
input_dir="$2"

if [ -z "$database_file" ] || [ -z "$input_dir" ]; then
	echo "Usage: $0 \"duckdb-file\"\"input-directory-with-csv-files\""
	exit 1
fi

echo "csv-to-duckdb load (from '$input_dir' to '$database_file')..."

exit_code=0

script_dir="$(dirname $0)"

temp_dir="$(mktemp -d)"

duckdb_script=$temp_dir/script

for input_file in "$input_dir"/*.csv; do
	filename="${input_file##*/}"
	filetitle="${filename%.*}"
	echo "create table $filetitle as select * from '$input_file';" >>"$duckdb_script"
done

if ! "$script_dir"/../duckdb -echo -init "$duckdb_script" "$database_file"
then
	echo "DuckDB data import failure"
	exit_code=1
fi

rm -r "$temp_dir"

exit $exit_code