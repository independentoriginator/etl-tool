create or replace function f_is_transfer_chunked(
	i_transfer_id ${mainSchemaName}.transfer.id%type
)
returns boolean
language sql
security definer
stable
as $function$
with 
	recursive dependent_transfer as (
		select 
			t.id
			, master_transfer.id as master_id
			, master_transfer.is_chunking as is_chunked
		from
			${mainSchemaName}.transfer t 
		left join ${mainSchemaName}.transfer_dependency dep
			on dep.transfer_id = t.id
		join ${mainSchemaName}.transfer master_transfer
			on master_transfer.id = t.master_id
			or master_transfer.id = dep.master_transfer_id
		where 
			t.id = i_transfer_id
			and not t.is_chunking
		union all
		select
			t.id as id
			, master_transfer.id as master_id
			, master_transfer.is_chunking as is_chunked
		from
			dependent_transfer 
		join ${mainSchemaName}.transfer t			
			on t.id = dependent_transfer.master_id
		left join ${mainSchemaName}.transfer_dependency dep
			on dep.transfer_id = t.id
		join ${mainSchemaName}.transfer master_transfer
			on master_transfer.id = t.master_id
			or master_transfer.id = dep.master_transfer_id
	)
select 
	coalesce(bool_or(t.is_chunked), false) as is_chunked
from 
	dependent_transfer t
$function$;
