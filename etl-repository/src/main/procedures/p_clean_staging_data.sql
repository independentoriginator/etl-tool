create or replace procedure 
	p_clean_staging_data(
		i_data_package_expiration_age_in_months integer = 3
	)
language plpgsql
as $procedure$
declare 
	l_data_package_id ${stagingSchemaName}.data_package.id%type
	;
begin
	call 
		${stagingSchemaName}.p_truncate_corrupted_unlogged_tables(
			i_schema_name => '${stagingSchemaName}'
		)
	;

	for l_data_package_id in (
		select 
			id
		from 
			${stagingSchemaName}.data_package
		where 
			${mainSchemaName}.f_months_between(
				current_date
				, create_date::date
			)::integer 
			>= i_data_package_expiration_age_in_months
	) loop
		call 
			${stagingSchemaName}.p_delete_data_package(
				i_data_package_id => l_data_package_id
			)
		;
	end loop
	;

	delete from  
		${stagingSchemaName}.materialized_view_refresh_duration
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, start_time::date
		)::integer 
		>= i_data_package_expiration_age_in_months
	;

	delete from  
		${stagingSchemaName}.matview_stat_inquiry_log
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, stat_inquiry_time::date
		)::integer 
		>= i_data_package_expiration_age_in_months
	;

	delete from  
		${stagingSchemaName}.table_stat_explicit_update_log
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, update_time::date
		)::integer 
		>= i_data_package_expiration_age_in_months
	;

	delete from  
		${stagingSchemaName}.matview_stat_explicit_update_log
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, update_time::date
		)::integer 
		>= i_data_package_expiration_age_in_months
	;
end
$procedure$
;			

comment on procedure 
	p_clean_staging_data(
		integer
	) is 'Очистка промежуточных данных'
;
