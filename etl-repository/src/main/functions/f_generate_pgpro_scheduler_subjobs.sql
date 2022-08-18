do $plpgsql$
begin
execute format($func$
create or replace function f_generate_pgpro_scheduler_subjobs(
	i_scheduled_task_id ${mainSchemaName}.scheduled_task.id%%type 
	, i_iteration_number ${stagingSchemaName}.scheduled_task_subjob.iteration_number%%type
	, i_commands text[]
)
returns void
language plpgsql
as $function$
declare 
	l_subjob_id ${type.id};
	l_prev_iteration_subjobs ${type.id}[];
	l_command text;
begin
	%s
end
$function$;			
$func$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$func_body$
	if i_iteration_number = 0 then
		delete from 
			${stagingSchemaName}.scheduled_task_subjob
		where 
			scheduled_task_id = i_scheduled_task_id
		;
	elsif i_iteration_number > 0 then 
		select 
			array_agg(id)
		into
			l_prev_iteration_subjobs
		from 
			${stagingSchemaName}.scheduled_task_subjob
		where 
			scheduled_task_id = i_scheduled_task_id
			and iteration_number = i_iteration_number - 1
		;
	else
		raise exception 'Invalid iteration number specified: %', i_iteration_number;
	end if;
	
	foreach l_command in array i_commands loop
		l_subjob_id := 
			schedule.submit_job(
				query => l_command
				, depends_on => l_prev_iteration_subjobs
			);
		
		if l_subjob_id is null then
			raise exception 'Cannot create one-time pgpro_scheduler job';
		end if;
		
		insert into ${stagingSchemaName}.scheduled_task_subjob(
			id
			, scheduled_task_id
			, iteration_number
		)
		values(
			l_subjob_id
			, i_scheduled_task_id
			, i_iteration_number
		);
	end loop;	
	$func_body$
else
	$func_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$func_body$
end
);
end
$plpgsql$;						
			