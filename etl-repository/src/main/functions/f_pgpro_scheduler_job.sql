do $plpgsql$
begin
execute format($func$
create or replace function f_pgpro_scheduler_job(i_job_id integer = null)
returns table(
	id integer
	, name text
	, description text
	, cron_expr text
	, commands text
	, is_disabled boolean
)
language sql
as $function$
%s
$function$;			
$func$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$func_body$
	select 
		t.id
		, t.name
		, t.comments as description
		, t.rule->>'crontab' as cron_expr
		, array_to_string(t.commands, '; ') as commands
		, case when t.active then false else true end as is_disabled
	from 
		schedule.get_owned_cron() t
	where 
		t.id = i_job_id or i_job_id is null
	$func_body$
else
	$func_body$
	select 
		null::integer as id
		, null::text as name
		, null::text as description
		, null::text as cron_expr
		, null::text as commands
		, null::boolean as is_disabled
	where 
		false
	$func_body$
end
);
end
$plpgsql$;		