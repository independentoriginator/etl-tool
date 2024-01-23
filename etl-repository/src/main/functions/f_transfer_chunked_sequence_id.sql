create or replace function f_transfer_chunked_sequence_id(
	i_transfer_id ${mainSchemaName}.transfer.id%type
)
returns ${mainSchemaName}.transfer.id%type
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
			, 0 as dep_level
			, array[t.id] as dep_seq 
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
			, dependent_transfer.dep_level + 1 as dep_level
			, dependent_transfer.dep_seq || t.id as dep_seq
		from
			dependent_transfer 
		join ${mainSchemaName}.transfer t			
			on t.id = dependent_transfer.master_id
		left join ${mainSchemaName}.transfer_dependency dep
			on dep.transfer_id = t.id
		join ${mainSchemaName}.transfer master_transfer
			on master_transfer.id = t.master_id
			or master_transfer.id = dep.master_transfer_id
		where 
			t.id <> all(dependent_transfer.dep_seq)
	)
select 
	t.master_id
from (
	select 
		t.master_id
		, row_number() over(
			order by 
				t.dep_level desc
		) as rn
	from 
		dependent_transfer t
	where 
		coalesce(t.is_chunked, false)
) t 
where 
	t.rn = 1
$function$;
