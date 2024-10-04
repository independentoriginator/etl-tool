drop procedure if exists 
	p_clean_xsd_target_staging_tables(
		${mainSchemaName}.xsd_transformation.internal_name%type
		, boolean
	)
;

create or replace procedure 
	p_clean_xsd_target_staging_tables(
		i_xsd_transformation_name ${mainSchemaName}.xsd_transformation.internal_name%type
		, i_iteration_row_limit integer = 10
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
	)
language plpgsql
as $procedure$
declare 
	l_command_list_query text := (
		select 
			string_agg(
				format(
					$sql$
					select
						format(
							'delete from %I._data_package where id = any(%%L)'
							, array_agg(t.data_package_id)
						)
					from (						
						select  
							dp.id as data_package_id
							, ((row_number() over () - 1) / %s) + 1 as bucket_num
						from 
							%I._data_package dp 
						where 
							dp.xsd_transformation_id = %s
					) t
					group by 
						t.bucket_num
					$sql$
					, t.target_staging_schema
					, i_iteration_row_limit
					, t.target_staging_schema
					, t.id
				)
				, E'\nunion all'
			)
		from 
			${mainSchemaName}.xsd_transformation t
		where 
			t.internal_name = i_xsd_transformation_name
			and t.is_disabled = true
	)
	;
begin
	call 
		${stagingSchemaName}.p_execute_in_parallel(
			i_command_list_query => l_command_list_query
			, i_context_id => '${mainSchemaName}.p_clean_xsd_target_staging_tables'::regproc
			, i_max_worker_processes => i_max_worker_processes
			, i_polling_interval => i_polling_interval
			, i_max_run_time => i_max_run_time
			, i_application_name => '${project_internal_name}'
		)
	;
end
$procedure$
;

comment on procedure 
	p_clean_xsd_target_staging_tables(
		${mainSchemaName}.xsd_transformation.internal_name%type
		, integer
		, integer
		, interval
		, interval
	) 
	is 'XSD. Очистка целевых промежуточных таблиц'
;
