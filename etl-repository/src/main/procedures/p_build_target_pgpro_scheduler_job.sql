do $plpgsql$
begin
execute format($proc$
create or replace procedure p_build_target_pgpro_scheduler_job(
	i_job_rec record
)
language plpgsql
as $procedure$
declare 
	l_job_id ${mainSchemaName}.v_pgpro_scheduler_job.id%%type;
	l_commands text[] := string_to_array(i_job_rec.command_string, '; ');
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
	if i_job_rec.target_job_id is null then
		l_job_id := 
			schedule.create_job(
				jsonb_build_object(
					'name', i_job_rec.job_name
					, 'comments', i_job_rec.job_description
					, 'commands', l_commands
					, 'use_same_transaction', false
					, 'cron', i_job_rec.cron_expr
					, 'run_as', '${mainSchemaName}'
				)
			);
	else
		l_job_id := i_job_rec.target_job_id;
		
		if ${mainSchemaName}.f_values_are_different(
			i_left => i_job_rec.job_description
			, i_right => i_job_rec.target_job_description
		) then
			perform 
				schedule.set_job_attribute(
					jobid => l_job_id
					, name => 'comments'::text
					, value => i_job_rec.job_description
				);
		end if;	

		if ${mainSchemaName}.f_values_are_different(
			i_left => i_job_rec.cron_expr
			, i_right => i_job_rec.target_cron_expr
		) then
			perform 
				schedule.set_job_attribute(
					jobid => l_job_id
					, name => 'cron'::text
					, value => i_job_rec.cron_expr
				);
		end if;	

		if ${mainSchemaName}.f_values_are_different(
			i_left => i_job_rec.command_string
			, i_right => i_job_rec.target_command_string
		) then
			perform 
				schedule.set_job_attribute(
					jobid => l_job_id
					, name => 'commands'::text
					, value => l_commands
				);
		end if;	
	end if;
			
	if i_job_rec.is_disabled = true and coalesce(i_job_rec.is_target_job_disabled, false) = false then
		perform 
			schedule.deactivate_job(
				jobid => l_job_id
			);
	elsif i_job_rec.is_disabled = false and coalesce(i_job_rec.is_target_job_disabled, false) = true then
		perform 
			schedule.activate_job(
				jobid => l_job_id
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
$plpgsql$;		