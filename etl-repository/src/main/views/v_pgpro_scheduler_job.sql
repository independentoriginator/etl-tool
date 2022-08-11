do $plpgsql$
begin
execute format($view$
create or replace view v_pgpro_scheduler_job
as
%s
$view$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$view_query$
	select 
		t.id
		, t.name
		, t.comments as description
		, t.rule->>'crontab' as cron_expr
		, array_to_string(t.commands, '; ') as commands
		, case when t.active then false else true end as is_disabled
	from 
		schedule.get_owned_cron() t
	$view_query$
else
	$view_query$
	select 
		null::integer as id
		, null::text as name
		, null::text as description
		, null::text as cron_expr
		, null::text as commands
		, null::boolean as is_disabled
	where 
		false
	$view_query$
end
);
end
$plpgsql$;						
			