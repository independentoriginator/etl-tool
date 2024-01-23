do $plpgsql$
begin
drop function if exists f_generate_pgpro_scheduler_subjobs(
	${mainSchemaName}.scheduled_task_stage.id%type 
	, ${stagingSchemaName}.scheduled_task_subjob.iteration_number%type
	, text[]
);

execute format($func$
create or replace function f_generate_pgpro_scheduler_subjobs(
	i_commands text[]
	, i_depends_on ${type.id}[] = null
	, i_scheduled_task_stage_id ${mainSchemaName}.scheduled_task_stage.id%%type = null 
	, i_iteration_number ${stagingSchemaName}.scheduled_task_subjob.iteration_number%%type = 0
	, i_depends_on_previous_iteration_subjobs boolean = true
)
returns ${type.id}[]
language plpgsql
as $function$
declare 
	l_subjobs ${type.id}[];
	l_subjob_id ${type.id};
	l_iteration_number ${stagingSchemaName}.scheduled_task_subjob.iteration_number%%type := coalesce(i_iteration_number, 0); 
	l_prev_iteration_subjobs ${type.id}[];
	l_command text;
begin
	%s
end
$function$;			

comment on function f_generate_pgpro_scheduler_subjobs(
	text[]
	, ${type.id}[]
	, ${mainSchemaName}.scheduled_task_stage.id%%type 
	, ${stagingSchemaName}.scheduled_task_subjob.iteration_number%%type
	, boolean
) is 'Генерация подзадач планового задания pgpro_scheduler';	
$func$
, case 
	when ${mainSchemaName}.f_is_scheduler_type_available(
		i_scheduler_type_name => 'pgpro_scheduler'
	) then 
	$func_body$
	if l_iteration_number < 0 then
		raise exception 'Invalid iteration number specified: %', l_iteration_number;
	end if;

	if i_scheduled_task_stage_id is not null
		and i_depends_on_previous_iteration_subjobs 
	then
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
				and l_iteration_number > 0
				and subjob.iteration_number = l_iteration_number - 1 
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
	end if;

	foreach l_command in array i_commands loop
		l_subjob_id := 
			schedule.submit_job(
				query => l_command
				, depends_on => array_cat(i_depends_on, l_prev_iteration_subjobs)
			);
		
		if l_subjob_id is null then
			raise exception 'Cannot create one-time pgpro_scheduler job';
		end if;
	
		l_subjobs := array_append(l_subjobs, l_subjob_id);
	
		if i_scheduled_task_stage_id is not null then
			insert into ${stagingSchemaName}.scheduled_task_subjob(
				id
				, scheduled_task_stage_id
				, iteration_number
			)
			values(
				l_subjob_id
				, i_scheduled_task_stage_id
				, l_iteration_number
			);
		end if;
	end loop;	

	return 
		l_subjobs;
	$func_body$
else
	$func_body$
	raise notice 'pgpro_scheduler extension is not installed';
	$func_body$
end
);
end
$plpgsql$;