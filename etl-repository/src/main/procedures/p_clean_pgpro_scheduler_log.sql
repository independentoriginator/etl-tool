do $plpgsql$
begin
execute format($proc$
create or replace procedure p_clean_pgpro_scheduler_log(
	i_record_expiration_age_in_months integer
)
language plpgsql
as $procedure$
begin
	%s
end
$procedure$;			
$proc$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$proc_body$
	perform schedule.onlysuperuser();
	
	delete from 
		schedule.log
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, start_at::date
		)::integer >= i_record_expiration_age_in_months
	;
	$proc_body$
else
	$proc_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$proc_body$
end
);
end
$plpgsql$;						
			