do $plpgsql$
begin
drop function if exists f_generate_pgpro_scheduler_subjobs(
	${mainSchemaName}.scheduled_task_stage.id%type 
	, ${stagingSchemaName}.scheduled_task_subjob.iteration_number%type
	, text[]
);

execute format($func$
create or replace function f_generate_pgpro_scheduler_subjobs(
	i_scheduled_task_stage_id ${mainSchemaName}.scheduled_task_stage.id%%type 
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
			scheduled_task_stage_id = i_scheduled_task_stage_id
		;
	elsif i_iteration_number < 0 then
		raise exception 'Invalid iteration number specified: %', i_iteration_number;
	end if;

	select 
		array_agg(subjob.id)
	into
		l_prev_iteration_subjobs
	from (	
		select 
			subjob.id
		from 
			${mainSchemaName}.scheduled_task_stage task_stage
		join ${stagingSchemaName}.scheduled_task_subjob subjob
			on subjob.scheduled_task_stage_id = task_stage.id
			and i_iteration_number > 0
			and subjob.iteration_number = i_iteration_number - 1 
		where
			task_stage.id = i_scheduled_task_stage_id
		union all
		select 
			subjob.id
		from 
			${mainSchemaName}.scheduled_task_stage task_stage
		join ${mainSchemaName}.scheduled_task_stage prev_task_stage
			on prev_task_stage.scheduled_task_id = task_stage.scheduled_task_id
			and prev_task_stage.ordinal_position < task_stage.ordinal_position
			and prev_task_stage.is_disabled = false
		join ${stagingSchemaName}.scheduled_task_subjob subjob
			on subjob.scheduled_task_stage_id = prev_task_stage.id 
		where
			task_stage.id = i_scheduled_task_stage_id
	) subjob
	;
	
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
			, scheduled_task_stage_id
			, iteration_number
		)
		values(
			l_subjob_id
			, i_scheduled_task_stage_id
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