drop function if exists 
	f_transfer_chain(
		${mainSchemaName}.transfer.id%type
	)
	cascade
;

create or replace function 
	f_transfer_chain_id(
		i_transfer_id ${mainSchemaName}.transfer.id%type
	)
returns ${mainSchemaName}.transfer.id%type
language sql
security definer
stable
as $function$
with recursive 
	dependent_transfer as (
		select 
			t.id
			, master_transfer.id as master_id
			, 0 as dep_level
			, array[t.id] as dep_seq 
		from
			${mainSchemaName}.transfer t 
		left join ${mainSchemaName}.transfer_dependency dep
			on dep.transfer_id = t.id
		join ${mainSchemaName}.transfer master_transfer
			on (
				master_transfer.id = t.master_id
				or master_transfer.id = dep.master_transfer_id
			) 
			and not master_transfer.is_virtual
		where 
			t.id = i_transfer_id
		union all
		select
			t.id as id
			, master_transfer.id as master_id
			, dependent_transfer.dep_level + 1 as dep_level
			, dependent_transfer.dep_seq || t.id as dep_seq
		from
			dependent_transfer 
		join ${mainSchemaName}.transfer t			
			on t.id = dependent_transfer.master_id
		left join ${mainSchemaName}.transfer_dependency dep
			on dep.transfer_id = t.id
		join ${mainSchemaName}.transfer master_transfer
			on (
				master_transfer.id = t.master_id
				or master_transfer.id = dep.master_transfer_id
			)
			and not master_transfer.is_virtual			
		where 
			t.id <> all(dependent_transfer.dep_seq)
	)
select 
	coalesce((
			select 
				t.master_id as id
			from 
				dependent_transfer t
			order by
				t.dep_level desc
			limit 1
		)
		, (
			select 
				t.id
			from
				${mainSchemaName}.transfer t
			where 
				t.id = i_transfer_id
				and not t.is_virtual
		)				
	)
		
$function$
;
