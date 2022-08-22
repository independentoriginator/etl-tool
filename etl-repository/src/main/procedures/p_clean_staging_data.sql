create or replace procedure p_clean_staging_data(
	i_data_package_expiration_age_in_months integer = 3
)
language plpgsql
as $procedure$
declare 
	l_data_package_id ${stagingSchemaName}.data_package.id%type;
begin
	for l_data_package_id in (
		select 
			id
		from 
			${stagingSchemaName}.data_package
		where 
			${mainSchemaName}.f_months_between(
				current_date
				, create_date::date
			)::integer >= i_data_package_expiration_age_in_months
	) loop
		call ${stagingSchemaName}.p_delete_data_package(
			i_data_package_id => l_data_package_id
		);
	end loop;
end
$procedure$;			
