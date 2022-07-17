create or replace procedure p_execute_task(
	i_task_name ${mainSchemaName}.task.internal_name%type
	, i_project_name ${mainSchemaName}.project.internal_name%type
	, i_thread_max_count integer = 10
)
language plpgsql
as $procedure$
declare 
	l_task_commands text[];
begin
	select
		array_agg(
			format(
				'call ${mainSchemaName}.p_execute_task_transfer_chain(
					i_task_id => %s
					, i_transfer_chain_id => %s
				)'
				, ts.task_id 
				, ts.transfer_chain_id
			)
			order by 
				chain_order_num
		)
	into 
		l_task_commands
	from (
		select distinct
		 	ts.task_id 
			, ts.transfer_chain_id
			, ts.chain_order_num
		from 
			${mainSchemaName}.v_task_stage ts
		where 
			ts.project_name = i_project_name
			and ts.task_name = i_task_name
	) ts
	;
		
	call ${stagingSchemaName}.p_execute_in_parallel(
		i_commands => l_task_commands
		, i_thread_max_count => i_thread_max_count
	);	
end
$procedure$;			
