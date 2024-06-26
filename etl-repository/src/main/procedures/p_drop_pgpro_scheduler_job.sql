do $plpgsql$
begin
execute format($proc$
create or replace procedure p_drop_pgpro_scheduler_job(
	i_job_id ${mainSchemaName}.v_pgpro_scheduler_job.id%%type
)
language plpgsql
as $procedure$
begin
	%s
end
$procedure$;

comment on procedure p_drop_pgpro_scheduler_job(
	${mainSchemaName}.v_pgpro_scheduler_job.id%%type
) is 'Удалить плановое задание pgpro_scheduler';
$proc$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$proc_body$
		if (
			'${databaseOwner}' <> session_user 
			or exists (
				select 
					1
				from 
					pg_catalog.pg_roles
				where 
					rolname = session_user
					and not rolsuper
			)
		) 
		then
  			delete from 
  				schedule.cron
  			where 
  				id = i_job_id
  			;		
		else 
			perform 
				schedule.drop_job(
					i_job_id
				)
			;
		end if 
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