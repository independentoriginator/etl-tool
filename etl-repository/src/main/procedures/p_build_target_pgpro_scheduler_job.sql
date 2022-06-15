do $q$
begin
execute format($proc$
create or replace procedure p_build_target_pgpro_scheduler_job(
	i_job_rec record
)
language plpgsql
as $procedure$
declare 
	l_pgpro_job_rec record;
begin
	%s
end
$procedure$;			
$proc$
, case 
	when exists (
		select 
			1
		from 
			pg_catalog.pg_extension e
		where 
			e.extname = 'pgpro_scheduler'
	) then 
	$proc_body$
	select 
		t.id
		, t.name
		, t.comments as description
		, case when t.active then false else true end as is_disabled
	into 
		l_pgpro_job_rec  
	from 
		schedule.get_owned_cron() t
	;

	if l_pgpro_job_rec.id is null then
		l_pgpro_job_rec.id := 
			schedule.create_job(
				jsonb_build_object(
					'name', i_job_rec.job_name
					, 'comments', i_job_rec.job_description
					, 'commands', i_job_rec.command_string
					, 'cron', i_job_rec.cron_expr
				)
			);
	else
		if nullif(i_job_rec.job_description, l_pgpro_job_rec.description) is not null then
			perform 
				schedule.set_job_attribute(
					jobid => l_pgpro_job_rec.id
					, name => 'comments'::text
					, value => i_job_rec.job_description
				);
		end if;	
	end if;
			
	if i_job_rec.is_disabled = true and coalesce(l_pgpro_job_rec.is_disabled, false) = false then
		perform 
			schedule.deactivate_job(
				job_id => l_pgpro_job_rec.id
			);
	elsif i_job_rec.is_disabled = false and coalesce(l_pgpro_job_rec.is_disabled, false) = true then
		perform 
			schedule.activate_job(
				job_id => l_pgpro_job_rec.id
			);
	end if;	
	$proc_body$
else
	$proc_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$proc_body$
end
);
end
$q$;						
			