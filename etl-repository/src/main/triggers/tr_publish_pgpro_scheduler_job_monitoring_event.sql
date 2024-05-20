do $plpgsql$
begin
	if ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'	
	) 
	then
		execute 
			format(
				E'create or replace trigger tr_%s_monitoring_event_pub'
				'\nafter insert'
				'\non schedule.log'
				'\nfor each row'
				'\n-- only unstarted jobs are processed'
				'\nwhen ('
				'\n	not new.status' 
				'\n	and ('
				'\n		new.started is null'
				'\n		or date_trunc(''second'', new.finished) - date_trunc(''second'', new.started) = ''0 second''::interval'
				'\n	)'
				'\n)'
				'\nexecute function ${mainSchemaName}.trf_publish_pgpro_scheduler_job_monitoring_event()'
				'\n;'
				, ${stagingSchemaName}.f_valid_system_name(
					i_raw_name => '${project_internal_name}'
					, i_is_considered_as_whole_name	=> false
				)
			)
		;
	end if
	;
end
$plpgsql$
;			