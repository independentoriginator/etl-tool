do $plpgsql$
begin
execute format($proc$
create or replace procedure p_clean_pgpro_scheduler_log(
	i_record_expiration_age_in_months integer = 3
)
language plpgsql
as $procedure$
begin
	%s
end
$procedure$;	

comment on procedure p_clean_pgpro_scheduler_log(
	integer
) is 'Очистка журнала исполнения планировщика заданий pgpro_scheduler';
$proc$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$proc_body$
	delete from 
		schedule.log
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, start_at::date
		)::integer >= i_record_expiration_age_in_months
	;
	
	delete from 
		schedule.at_jobs_done
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, submit_time::date
		)::integer >= i_record_expiration_age_in_months
	;

	delete from 
		schedule.at_jobs_process
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, submit_time::date
		)::integer >= i_record_expiration_age_in_months
	;

	delete from 
		schedule.at_jobs_submitted
	where 
		${mainSchemaName}.f_months_between(
			current_date
			, submit_time::date
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