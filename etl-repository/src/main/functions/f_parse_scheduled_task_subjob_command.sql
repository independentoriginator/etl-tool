create or replace function f_parse_scheduled_task_subjob_command(
	i_command text
)
returns table(	
	etl_task_id ${type.id}
	, etl_transfer_chain_id ${type.id}
	, meta_view_id ${type.id}
)
language sql
immutable
parallel safe
as $function$
select
	etl_task_id[1]::${type.id} as etl_task_id
	, etl_transfer_chain_id[1]::${type.id} as etl_transfer_chain_id
	, meta_view_id[1]::${type.id} as meta_view_id
from (
	select
		regexp_match(
			t.command
			, '\s*call .*p_execute_task_transfer_chain\(\s*i_task_id\s*\=\>\s*(\d+)\s*,'
		) as etl_task_id
		, regexp_match(
			t.command
			, '\s*call .*p_execute_task_transfer_chain\(.*i_transfer_chain_id\s*\=\>\s*(\d+)\s*,'
		) as etl_transfer_chain_id
		, regexp_match(
			t.command
			, '\s*call .*p_refresh_materialized_view\(\s*i_view_id\s*\=\>\s*(\d+)\s*\)'
		) as meta_view_id
	from (
		select 
			i_command as command
	) t
) t
$function$;	

comment on function f_parse_scheduled_task_subjob_command(
	text
) is 'Разбор команды подзадачи планового задания';