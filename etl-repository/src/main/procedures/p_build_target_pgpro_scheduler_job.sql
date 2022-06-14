create or replace procedure p_build_target_pgpro_scheduler_job(
	i_job_rec record
)
language plpgsql
as $procedure$
declare 
	l_job_id integer := i_job_rec.target_id;
begin
	if i_job_rec.is_job_exists = false then
		l_job_id := 
			schedule.create_job(
				jsonb_build_object(
					'name', i_job_rec.job_name
					, 'comments', i_job_rec.job_description
					, 'commands', i_job_rec.command_string
					, 'cron', i_job_rec.cron_expr
				)
			);
	else
		if nullif(i_job_rec.job_description, i_job_rec.target_description) is not null then
			perform 
				schedule.set_job_attribute(
					jobid => l_job_id
					, name => 'comments'::text
					, value => i_job_rec.job_description
				);
		end if;	
	end if;
			
	if i_job_rec.is_disabled = true and coalesce(i_job_rec.is_disabled, false) = false then
		perform 
			schedule.deactivate_job(
				job_id => l_job_id
			);
	elsif i_job_rec.is_disabled = false and coalesce(i_job_rec.is_disabled, false) = true then
		perform 
			schedule.activate_job(
				job_id => l_job_id
			);
	end if;	
end
$procedure$;			
