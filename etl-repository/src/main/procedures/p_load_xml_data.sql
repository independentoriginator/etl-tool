drop procedure if exists
	p_load_xml_data(
		${mainSchemaName}.xsd_transformation.id%type
		, ${type.code}
		, timestamp
		, text[]
		, xml
		, boolean
	)
;

drop procedure if exists
	p_load_xml_data(
		${mainSchemaName}.xsd_transformation.id%type
		, ${type.code}
		, timestamp
		, text[]
		, xml
		, ${mainSchemaName}.xsd_transformation.namespace%type
		, boolean
	)
;

create or replace procedure 
	p_load_xml_data(
		i_xsd_transformation_id ${mainSchemaName}.xsd_transformation.id%type
		, i_data_package_external_id ${type.code}
		, i_load_date timestamp
		, i_path text[]
		, i_xml_data xml
		, i_namespace ${mainSchemaName}.xsd_transformation.namespace%type = null
		, i_xsd_version ${mainSchemaName}.xsd_transformation.version%type = null
		, i_aggregate_insert_instructions boolean = true
	)
language plpgsql
as $procedure$
declare
	l_target_staging_schema ${mainSchemaName}.xsd_transformation.target_staging_schema%type;
	l_insert_commands text[];
	l_delete_commands text;
	l_command text;
	l_data_package_id ${type.id};
	l_is_must_be_updated boolean;
	l_last_err_msg text;
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
	l_exception_context text;
	l_xsd_version ${mainSchemaName}.xsd_transformation.version%type;
begin
	select 
		t.schema_name
		, array_agg(
			format($$
				insert into 
					%I.%I(
						_data_package_id
						, %s
					)
				select
					$1
					, %s
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
				, coalesce(i_namespace, t.namespace)
				, regexp_replace(t.path, '(/)([^/])', '\1tns:\2', 'g')
				, t.xml_table_columns
			)
			order by 
				t.dependency_level
		) as insert_commands
		, string_agg(
			format($$
				delete from 
					%I.%I
				where 
					_data_package_id = $1
				$$
				, t.schema_name
				, t.table_name
			)
			, E';\n'
			order by 
				t.dependency_level desc
		) as delete_commands
		, coalesce(i_xsd_version, t.version)
	into
		l_target_staging_schema
		, l_insert_commands
		, l_delete_commands
		, l_xsd_version
	from (
		with 
			path_prefix as (
				select 
					path.directory
				from 
					unnest(i_path) as path(directory)
			)
		select 
			t.path
			, t.schema_name
			, t.table_name
			, t.dependency_level
			, t.namespace
			, t.version
			, attr.target_columns
			, attr.src_columns
			, attr.xml_table_columns
		from (			
			select 
				e.id as entity_id
				, e.path
				, t.target_staging_schema as schema_name
				, e.table_name
				, ${mainSchemaName}.f_xsd_entity_dependency_level(
					i_xsd_transformation_id => t.id
					, i_entity_path => e.path
				) as dependency_level
				, t.namespace
				, t.version
				, (
					i_xsd_version is not null 
					and ${mainSchemaName}.f_values_are_different(
						i_left => t.version
						, i_right => i_xsd_version
					)
				) as is_compatibility_mode
			from 
				${mainSchemaName}.xsd_transformation t
			join ${mainSchemaName}.xsd_entity e
				on e.xsd_transformation_id = t.id
			where 
				t.id = i_xsd_transformation_id
				and (
					exists (
						select 
							1
						from 
							path_prefix
						where
							path_prefix.directory = left(e.path, length(path_prefix.directory))
					)
					or i_path is null
				)
		) t
		join lateral (
			select 
				string_agg(quote_ident(a.column_name), ', ') as target_columns
				, string_agg(
					case 
						when not a.is_multivalued then
							case 
								when t.is_compatibility_mode then
									format(
										E'${mainSchemaName}.f_try_cast('
										'\n	i_in =>'
										'\n		nullif('
										'\n			%s'
										'\n			, '''''
										'\n		)'
										'\n	, i_out => null::%s'
										'\n) as %s' 
										, case 
											when a.type = 'xs:string' and a.max_length > 0 then
												format(
													'${mainSchemaName}.f_truncate_string(i_str => t.%s, i_max_length => %s)'
													, quote_ident(a.column_name)
													, a.max_length
												)
											else 
												't.' || quote_ident(a.column_name)
										end
										, a.column_type
										, quote_ident(a.column_name)
									)
								else 
									format(
										'cast(nullif(t.%s, '''') as %s) as %s' 
										, quote_ident(a.column_name)
										, a.column_type
										, quote_ident(a.column_name)
									)
							end
						else
							quote_ident(a.column_name)
					end
					, ', '
				) as src_columns
				, string_agg(
					quote_ident(a.column_name)
					|| ' ' || case when not a.is_multivalued then 'text' else 'xml' end
					|| ' path ''' 
					|| regexp_replace(regexp_replace(a.relative_path, '(/)([^/\.@])', '\1tns:\2'), '^(\w+)$', 'tns:\1')
					|| case when a.is_multivalued then '[1]' else '' end -- Annoying temporary workaround solution because of XPath 1.0 limitations					
					|| ''''
					, ', '
				) as xml_table_columns
			from 
				${mainSchemaName}.v_xsd_entity_attr a
			where
				a.xsd_entity_id = t.entity_id
		) attr 
			on true
	) t
	group by 
		t.schema_name
		, t.version
	;

	execute 
		format('
			select 
				id
				, (xsd_transformation_id <> $1) as is_must_be_updated 
			from
				%I._data_package	
			where
				external_id = $2
			'
			, l_target_staging_schema
		)
		using 
			i_xsd_transformation_id
			, i_data_package_external_id
		into 
			l_data_package_id
			, l_is_must_be_updated
	;

	if l_data_package_id is null then
		execute 
			format('
				insert into 
					%I._data_package(
						xsd_transformation_id
						, xsd_version
						, external_id
						, load_date
					)
				values(
					$1
					, $2
					, $3
					, $4
				)
				returning 
					id
				'
				, l_target_staging_schema
			)
			using 
				i_xsd_transformation_id
				, l_xsd_version
				, i_data_package_external_id
				, i_load_date
			into 
				l_data_package_id
		;
	else
		if l_is_must_be_updated then
			execute 
				format('
					update
						%I._data_package
					set
						xsd_transformation_id = $2
						, xsd_version = $3
					where 
						id = $1
					'
					, l_target_staging_schema
				)
				using 
					l_data_package_id
					, i_xsd_transformation_id
					, l_xsd_version
			;
		end if
		;
	
		-- Deleting old package data
		execute 
			l_delete_commands
		using 
			l_data_package_id
		;
	end if;

	-- Loading package data
	if i_aggregate_insert_instructions then
		execute 
			array_to_string(l_insert_commands, E';\n')
		using 
			l_data_package_id
			, i_xml_data
		;
	else
		foreach l_command in array l_insert_commands loop
			-- raise notice '%', l_command;
			execute 
				l_command
			using 
				l_data_package_id
				, i_xml_data
			;
		end loop
		;
	end if
	;

exception
when others then
	get stacked diagnostics
		l_msg_text = MESSAGE_TEXT
		, l_exception_detail = PG_EXCEPTION_DETAIL
		, l_exception_hint = PG_EXCEPTION_HINT
		, l_exception_context = PG_EXCEPTION_CONTEXT
	;
	raise exception 
		E'XML data loading error: %:\n%\n(hint: %,\nxsd_transformation_id = %,\ndata_package_external_id = %,\ncontext=%)'
		, l_msg_text
		, l_exception_detail
		, l_exception_hint
		, i_xsd_transformation_id
		, i_data_package_external_id
		, l_exception_context
	;
end
$procedure$
;	

comment on procedure 
	p_load_xml_data(
		${mainSchemaName}.xsd_transformation.id%type
		, ${type.code}
		, timestamp
		, text[]
		, xml
		, ${mainSchemaName}.xsd_transformation.namespace%type
		, ${mainSchemaName}.xsd_transformation.version%type
		, boolean
	) 
	is 'Загрузка XML-данных'
;
