create or replace procedure p_load_xml_data(
	i_xsd_transformation_id ${mainSchemaName}.xsd_transformation.id%type
	, i_data_package_external_id ${type.code}
	, i_load_date timestamp
	, i_path ${mainSchemaName}.xsd_entity.path%type
	, i_xml_data xml
)
language plpgsql
as $procedure$
declare
	l_target_staging_schema ${mainSchemaName}.xsd_transformation.target_staging_schema%type;
	l_insert_command text;
	l_delete_command text;
	l_data_package_id ${type.id};
	l_last_err_msg text;
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
begin
	select 
		t.schema_name
		, string_agg(
			format($$
				insert into %I.%I(
					_data_package_id, %s
				)
				select
					$1, %s
				from 
					xmltable(
						xmlnamespaces(
							'%s' as tns
						)
						, '%s'
						passing 
							$2
						columns 
							%s
					) t
				$$
				, t.schema_name
				, t.table_name
				, t.target_columns
				, t.src_columns
				, t.namespace
				, regexp_replace(t.path, '(/)([^/])', '\1tns:\2', 'g')
				, t.xml_table_columns
			)
			, E';\n'
			order by t.dependency_level
		) as insert_command
		, string_agg(
			format($$
				delete from %I.%I
				where _data_package_id = $1
				$$
				, t.schema_name
				, t.table_name
			)
			, E';\n'
			order by t.dependency_level desc
		) as delete_command
	into
		l_target_staging_schema
		, l_insert_command
		, l_delete_command
	from (
		select 
			e.path
			, t.target_staging_schema as schema_name
			, e.table_name
			, ${mainSchemaName}.f_xsd_entity_dependency_level(
				i_xsd_transformation_id => t.id
				, i_entity_path => e.path
			) as dependency_level
			, t.namespace
			, attr.target_columns
			, attr.src_columns
			, attr.xml_table_columns
		from 
			${mainSchemaName}.xsd_transformation t
		join ${mainSchemaName}.xsd_entity e
			on e.xsd_transformation_id = t.id 
			and (left(e.path, length(i_path)) = i_path or i_path is null) 
		join lateral (
			select 
				string_agg(quote_ident(a.column_name), ', ') as target_columns
				, string_agg('cast(nullif(t.' || quote_ident(a.column_name) || ', '''') as ' || a.column_type || ') as ' || quote_ident(a.column_name), ', ') as src_columns
				, string_agg(
					quote_ident(a.column_name) 
					|| ' text path ''' 
					|| regexp_replace(regexp_replace(a.relative_path, '(/)([^/\.@])', '\1tns:\2'), '^(\w+)$', 'tns:\1') 
					|| ''''
					, ', '
				) as xml_table_columns
			from 
				${mainSchemaName}.v_xsd_entity_attr a
			where
				a.xsd_entity_id = e.id
		) attr 
			on true
		where 
			t.id = i_xsd_transformation_id
	) t
	group by 
		t.schema_name
	;

	execute 
		format('
			select 
				id
			from
				%I._data_package	
			where
				xsd_transformation_id = $1
				and external_id = $2
			'
			, l_target_staging_schema
		)
		using 
			i_xsd_transformation_id
			, i_data_package_external_id
		into 
			l_data_package_id
	;

	if l_data_package_id is null then
		execute 
			format('
				insert into %I._data_package(
					xsd_transformation_id
					, external_id
					, load_date
				)
				values(
					$1
					, $2
					, $3
				)
				returning id
				'
				, l_target_staging_schema
			)
			using 
				i_xsd_transformation_id
				, i_data_package_external_id
				, i_load_date
			into 
				l_data_package_id
		;
	else
		-- Deleting old package data
		execute 
			l_delete_command
		using 
			l_data_package_id
		;
	end if;

	-- Loading package data
	execute 
		l_insert_command 
	using 
		l_data_package_id
		, i_xml_data
	;

exception
when others then
	get stacked diagnostics
		l_msg_text = MESSAGE_TEXT
		, l_exception_detail = PG_EXCEPTION_DETAIL
		, l_exception_hint = PG_EXCEPTION_HINT
		;
	raise exception 
		'XML data loading error: %: % (hint: %, xsd_transformation_id = %, data_package_external_id = %)'
		, l_msg_text
		, l_exception_detail
		, l_exception_hint
		, i_xsd_transformation_id
		, i_data_package_external_id
		;
end
$procedure$;			