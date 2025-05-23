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
	l_direct_modification_mode boolean := (
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
	;
begin
	%s
end
$procedure$;

comment on procedure p_build_target_pgpro_scheduler_job(
	record
) is 'Генерация целевых плановых заданий pgpro_scheduler';
$proc$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$proc_body$
	if i_job_rec.target_job_id is null then
		if l_direct_modification_mode then
  			insert into 
  				schedule.cron(
  					node
  					, rule
  					, do_sql
  					, owner
  					, executor
  					, name
  					, comments
  					, max_run_time
  					, same_transaction
  					, onrollback_statement
  					, next_time_statement
  					, postpone
  				)
  			values (
  				schedule.nodename()
  				, schedule._get_cron_from_attrs(
					params => 
						jsonb_build_object(
							'cron'::text
							, i_job_rec.cron_expr
						)
					, prev => null
				)
  				, l_commands
  				, '${databaseOwner}'
  				, i_job_rec.task_session_user
  				, i_job_rec.job_name
  				, i_job_rec.job_description
  				, i_job_rec.max_run_time
  				, i_job_rec.is_task_used_single_transaction
  				, i_job_rec.on_err_cmd
  				, i_job_rec.next_start_time_calc_sttmnt
  				, i_job_rec.delayed_start_timeout
  			)
  			returning 
  				id 
  			into 
  				l_job_id
  			;	
  		else
			l_job_id := 
				schedule.create_job(
					jsonb_build_object(
						'name', i_job_rec.job_name
						, 'comments', i_job_rec.job_description
						, 'commands', l_commands
						, 'use_same_transaction', i_job_rec.is_task_used_single_transaction
						, 'cron', i_job_rec.cron_expr
						, 'run_as', i_job_rec.task_session_user
						, 'onrollback', i_job_rec.on_err_cmd
						, 'max_run_time', i_job_rec.max_run_time
						, 'last_start_available', i_job_rec.delayed_start_timeout
						, 'next_time_statement', i_job_rec.next_start_time_calc_sttmnt
					)
				);
		end if;
	else
		l_job_id := i_job_rec.target_job_id;
	
		if l_direct_modification_mode then
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.job_description
				, i_right => i_job_rec.target_job_description
			) 
			then
				update
					schedule.cron
				set
					comments = i_job_rec.job_description
				where 	
					id = l_job_id
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.cron_expr
				, i_right => i_job_rec.target_cron_expr
			) 
			then
				update
					schedule.cron
				set
					rule =
						schedule._get_cron_from_attrs(
							params => 
								jsonb_build_object(
									'cron'::text
									, i_job_rec.cron_expr
								)
							, prev => rule
						)
				where 	
					id = l_job_id
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.command_string
				, i_right => i_job_rec.target_command_string
			) 
			then
				update
					schedule.cron
				set
					do_sql = l_commands
				where 	
					id = l_job_id
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.is_task_used_single_transaction
				, i_right => i_job_rec.is_target_task_used_single_transaction
			) 
			then
				update
					schedule.cron
				set
					same_transaction = i_job_rec.is_task_used_single_transaction
				where 	
					id = l_job_id
				;
			end if
			;	
	
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.task_session_user
				, i_right => i_job_rec.target_task_session_user
			) 
			then
				update
					schedule.cron
				set
					executor = i_job_rec.task_session_user
				where 	
					id = l_job_id
				;
			end if
			;	
	
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.on_err_cmd
				, i_right => i_job_rec.target_on_err_cmd
			) 
			then
				update
					schedule.cron
				set
					onrollback_statement = i_job_rec.on_err_cmd
				where 	
					id = l_job_id
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.max_run_time
				, i_right => i_job_rec.target_max_run_time
			) 
			then
				update
					schedule.cron
				set
					max_run_time = i_job_rec.max_run_time
				where 	
					id = l_job_id
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.delayed_start_timeout
				, i_right => i_job_rec.target_delayed_start_timeout
			) 
			then
				update
					schedule.cron
				set
					postpone = i_job_rec.delayed_start_timeout::text
				where 	
					id = l_job_id
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.next_start_time_calc_sttmnt
				, i_right => i_job_rec.target_next_start_time_calc_sttmnt
			) 
			then
				update
					schedule.cron
				set
					next_time_statement = i_job_rec.next_start_time_calc_sttmnt
				where 	
					id = l_job_id
				;
			end if
			;
		else
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.job_description
				, i_right => i_job_rec.target_job_description
			) 
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'comments'::text
						, value => i_job_rec.job_description
					)
				;
			end if
			;	
	
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.cron_expr
				, i_right => i_job_rec.target_cron_expr
			) 
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'cron'::text
						, value => i_job_rec.cron_expr
					)
				;
			end if
			;	
	
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.command_string
				, i_right => i_job_rec.target_command_string
			) 
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'commands'::text
						, value => l_commands
					)
				;
			end if
			;	
	
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.is_task_used_single_transaction
				, i_right => i_job_rec.is_target_task_used_single_transaction
			) 
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'use_same_transaction'::text
						, value => i_job_rec.is_task_used_single_transaction
					)
				;
			end if
			;	
	
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.task_session_user
				, i_right => i_job_rec.target_task_session_user
			) 
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'run_as'::text
						, value => i_job_rec.task_session_user
					)
				;
			end if;	
	
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.on_err_cmd
				, i_right => i_job_rec.target_on_err_cmd
			) then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'onrollback'::text
						, value => i_job_rec.on_err_cmd
					)
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.max_run_time
				, i_right => i_job_rec.target_max_run_time
			) 
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'max_run_time'::text
						, value => i_job_rec.max_run_time::text
					)
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.delayed_start_timeout
				, i_right => i_job_rec.target_delayed_start_timeout
			)
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'last_start_available'::text
						, value => i_job_rec.delayed_start_timeout::text
					)
				;
			end if
			;	
		
			if ${mainSchemaName}.f_values_are_different(
				i_left => i_job_rec.next_start_time_calc_sttmnt
				, i_right => i_job_rec.target_next_start_time_calc_sttmnt
			) 
			then
				perform 
					schedule.set_job_attribute(
						jobid => l_job_id
						, name => 'next_time_statement'::text
						, value => i_job_rec.next_start_time_calc_sttmnt
					)
				;
			end if
			;
		end if
		;
	end if
	;
		
	if i_job_rec.is_disabled = true and coalesce(i_job_rec.is_target_job_disabled, false) = false then
		if l_direct_modification_mode then
			update
				schedule.cron
			set
				active = false
			where 	
				id = l_job_id
				and active
			;
		else			
			perform 
				schedule.deactivate_job(
					jobid => l_job_id
				)
			;
		end if
		;
	elsif i_job_rec.is_disabled = false and coalesce(i_job_rec.is_target_job_disabled, false) = true then
		if l_direct_modification_mode then
			update
				schedule.cron
			set
				active = true
			where 	
				id = l_job_id
				and active = false
			;
		else			
			perform 
				schedule.activate_job(
					jobid => l_job_id
				)
			;
		end if
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