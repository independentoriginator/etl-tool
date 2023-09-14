do $plpgsql$
begin
execute format($func$
create or replace function f_is_pgpro_scheduler_curr_transaction_succeeded()
returns boolean
language sql
as $function$
%s
$function$;		

comment on function f_is_pgpro_scheduler_curr_transaction_succeeded() is 'Признак завершения текущей транзакции pgpro_scheduler';
$func$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$func_body$
	select 
		case 
			when current_setting('schedule.transaction_state') = 'success' then true
			else false
		end
	$func_body$
else
	$func_body$
	select 
		null::boolean
	$func_body$
end
);
end
$plpgsql$;		