drop function if exists 
	f_is_transfer_chunked(
		${mainSchemaName}.transfer.id%type
	)
;

create or replace function 
	f_is_transfer_chunked(
		i_transfer_id ${mainSchemaName}.transfer.id%type
		, i_chunked_sequence_id ${mainSchemaName}.transfer.id%type
	)
returns boolean
language sql
security definer
stable
as $function$
with recursive 
	sequence_transfer as (
		select 
			master_transfer.id as master_id
			, t.id as id
			, true as is_chunked
			, 0 as dep_level
			, array[t.id] as dep_seq 
		from
			${mainSchemaName}.transfer master_transfer 
		left join ${mainSchemaName}.transfer_dependency dep
			on dep.master_transfer_id = master_transfer.id
		join ${mainSchemaName}.transfer t 
			on t.master_id = master_transfer.id
			or t.id = dep.transfer_id
		where 
			master_transfer.id = i_chunked_sequence_id
			and master_transfer.is_chunking
		union all
		select
			master_transfer.id as master_id
			, t.id as id
			, (
				sequence_transfer.is_chunked
				and (
					master_transfer.id = t.master_id
					or strpos('{{chunk_id}}', t.container) > 0
				)
			) as is_chunked
			, sequence_transfer.dep_level + 1 as dep_level
			, sequence_transfer.dep_seq || t.id as dep_seq
		from
			sequence_transfer 
		join ${mainSchemaName}.transfer master_transfer			
			on master_transfer.id = sequence_transfer.id
		left join ${mainSchemaName}.transfer_dependency dep
			on dep.master_transfer_id = master_transfer.id
		join ${mainSchemaName}.transfer t
			on t.master_id = master_transfer.id
			or t.id = dep.transfer_id
		where 
			t.id <> all(sequence_transfer.dep_seq)
	)
select ( 
	exists (
		select 
			1
		from 
			sequence_transfer
		where 
			id = i_transfer_id
			and is_chunked
	)
) as is_chunked
$function$
;
