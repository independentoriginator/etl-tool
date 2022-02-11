#!/bin/bash

input_dir="$1"
result_dir="$2"

if [ -z "$input_dir" ] || [ -z "$result_dir" ]; then
	echo "Usage: $0 \"input-directory-with-xlsx-or-zip-files\" \"result-directory-for-output-csv-files\""
	exit 1
fi

echo "xlsx-to-csv transformation (from '$input_dir' to '$result_dir')..."

csv_delimiter=";"

script_dir="$(dirname $0)"

function transform_xlsx_to_csv {
	result=0
	
	xlsx_file="$1"
	xlsx_filename=$(basename "$xlsx_file")
	xlsx_file_id="$2"
	result_csv_dir="$3"
	gen_csv_header="$4"
	source_archive_file="$5"
	csv_delimiter="$6"
	
	file_content_dir="$(mktemp -d)"

	unzip -q "$xlsx_file" -d "$file_content_dir"
	
	if [ $? -ne 0 ]
	then
		echo "Could not unpack the file '$xlsx_filename'" >&2
		result=1
	else
		java -cp "$script_dir/xslt/saxon-he-10.5.jar" net.sf.saxon.Transform \
			-s:"$file_content_dir/xl/workbook.xml" \
			-xsl:"$script_dir/xslt/xlsx2cell-list.xsl" \
			-o:"$result_csv_dir/cells.csv" \
			sourceFileName="$xlsx_filename" \
			sourceFileId="$xlsx_file_id" \
			sourceArchiveName="$source_archive_file" \
			withHeader="$gen_csv_header" \
			delimiter="$csv_delimiter"
		
		if [ $? -ne 0 ]
		then
			echo "Could not transform the file '$xlsx_filename'" >&2
			result=1
		else
			echo "The file '$xlsx_filename' is transformed successfully" 
		fi
	fi
		
	rm -r "$file_content_dir"

	return $result
}

exit_code=0

temp_dir="$(mktemp -d)"
echo "Used temporary directory is: $temp_dir"

xlsx_file_count=0
processed_file_count=0
skipped_file_count=0

gen_csv_header="true"

shopt -s globstar nullglob dotglob

for input_file in "$input_dir"/**/*; do
	if [ -d "$input_file" ]; then
		continue
	fi

	input_filename="${input_file##*/}" 
	input_file_ext="${input_filename##*.}"
	input_file_ext="${input_file_ext,,}" # to lower case
	
	if [ $input_file_ext = "zip" ]; then
		echo "Processing archive file: $input_filename..."
		
		arc_file_dir="$(mktemp -d)"
	
		unzip -q "$input_file" -d "$arc_file_dir"
		if [ $? -ne 0 ]
		then
			echo "Could not unpack the file $input_filename" >&2
			exit_code=1
			break
		else
			for unpacked_file in "$arc_file_dir"/**/*; do
				if [ -d "$unpacked_file" ]; then
					continue
				fi
			
				file_name="${unpacked_file##*/}"
				file_ext="${file_name##*.}"
				
				if [ $file_ext = "xlsx" ]; then
					result_csv_dir="$temp_dir/result$xlsx_file_count"
					(( xlsx_file_count++ ))
					
					if [ $xlsx_file_count -gt 1 ]; then
						gen_csv_header="false"
					fi
	
					transform_xlsx_to_csv "$unpacked_file" "$xlsx_file_count" "$result_csv_dir" "$gen_csv_header" "$input_filename" "$csv_delimiter"
					if [ $? -ne 0 ]; then
						exit_code=1
						break
					fi
					
					(( processed_file_count++ ))
				else
					echo "The file '$file_name' cannot be processed. Only *.xlsx files are expected."
					(( skipped_file_count++ ))
				fi
			done
		fi
		
	elif [ $input_file_ext = "xlsx" ]; then
		result_csv_dir="$temp_dir/result$xlsx_file_count"
		(( xlsx_file_count++ ))
		
		if [ $xlsx_file_count -gt 1 ]; then
			gen_csv_header="false"
		fi
		
		transform_xlsx_to_csv "$input_file" "$xlsx_file_count" "$result_csv_dir" "$gen_csv_header" "$input_filename" "$csv_delimiter"
		if [ $? -ne 0 ]; then
			exit_code=1
			break
		fi
		
		(( processed_file_count++ ))
	else
		echo "The file '$input_filename' is skipped. Only *.zip or *.xlsx input files are expected."
		(( skipped_file_count++ ))
	fi	
	
done

if [ $processed_file_count -gt 0 ]; then
	mkdir "$temp_dir/result"
	cat $temp_dir/result*/books.csv > $temp_dir/result/books.csv
	cat $temp_dir/result*/sheets.csv > $temp_dir/result/sheets.csv
	cat $temp_dir/result*/cells.csv > $temp_dir/result/cells.csv
	mkdir -p "$result_dir"
	mv -f "$temp_dir/result"/* "$result_dir"
fi

echo "File processed count: $processed_file_count"
echo "File skipped count: $skipped_file_count"

rm -r "$temp_dir"

exit $exit_code
