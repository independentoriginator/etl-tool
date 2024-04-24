do $plpgsql$
begin
	drop function if exists f_pgpro_scheduler_job(integer) cascade;

execute format($func$
create or replace function f_pgpro_scheduler_job(i_job_id integer = null)
returns table(
	id integer
	, name text
	, description text
	, cron_expr text
	, commands text
	, use_same_transaction boolean
	, run_as text
	, onrollback text
	, max_run_time interval
	, next_time_statement text
	, last_start_available interval
	, is_disabled boolean
)
language sql
security definer
as $function$
%s
$function$;		

comment on function f_pgpro_scheduler_job(integer) is 'Плановые задания pgpro_scheduler';
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
		, t.use_same_transaction
		, t.run_as
		, t.onrollback
		, t.max_run_time
		, t.next_time_statement
		, t.last_start_available
		, case when t.active then false else true end as is_disabled
	from 
		schedule.get_owned_cron() t
	where 
		'${databaseOwner}' = session_user		
		and (t.id = i_job_id or i_job_id is null)
	union all
	select 
		t.id
		, t.name
		, t.comments as description
		, t.rule->>'crontab' as cron_expr
		, array_to_string(t.do_sql, '; ') as commands
		, t.same_transaction as use_same_transaction
		, t.executor as run_as
		, t.onrollback_statement as onrollback
		, t.max_run_time
		, t.next_time_statement
		, t.postpone as last_start_available
		, case when t.active then false else true end as is_disabled
	from 
		schedule.cron t
	where 
		'${databaseOwner}' <> session_user		
		and (t.id = i_job_id or i_job_id is null)
	$func_body$
else
	$func_body$
	select 
		null::integer as id
		, null::text as name
		, null::text as description
		, null::text as cron_expr
		, null::text as commands
		, null::boolean as use_same_transaction
		, null::text as run_as
		, null::text as onrollback
		, null::interval as max_run_time
		, null::text as next_time_statement
		, null::interval as last_start_available
		, null::boolean as is_disabled
	where 
		false
	$func_body$
end
);
end
$plpgsql$;		