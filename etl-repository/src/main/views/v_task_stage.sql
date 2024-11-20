drop view if exists v_task_stage
;

create view v_task_stage
as
with recursive 
	task_stage as (
		select 
			ts.task_id
			, ts.transfer_id
			, tr.master_id as master_transfer_id
			, coalesce(dep.master_transfer_id, tr.master_id) as preceding_transfer_id
			, ts.transfer_id as target_transfer_id
			, tr.container as target_container
			, tr.is_deletion as is_target_transfer_deletion 
			, t.are_del_ins_stages_separated
			, coalesce(ts.ordinal_position, 0) as ordinal_position
			, coalesce(ts.ordinal_position, 0) as stage_ordinal_position
			, array[ts.transfer_id] as chain_transfers 
		from 
			${mainSchemaName}.task t
		join ${mainSchemaName}.task_stage ts 
			on ts.task_id = t.id 
			and ts.is_disabled = false
		join ${mainSchemaName}.transfer tr 
			on tr.id = ts.transfer_id
		left join ${mainSchemaName}.transfer_dependency dep 
			on dep.transfer_id = ts.transfer_id
		union 
		select 
			ts.task_id
			, ts.transfer_id
			, tr.master_id as master_transfer_id
			, dep.master_transfer_id as preceding_transfer_id
			, ts.transfer_id as target_transfer_id
			, tr.container as target_container
			, tr.is_deletion as is_target_transfer_deletion 
			, t.are_del_ins_stages_separated
			, coalesce(ts.ordinal_position, 0) as ordinal_position
			, coalesce(ts.ordinal_position, 0) as stage_ordinal_position
			, array[ts.transfer_id] as chain_transfers 
		from 
			${mainSchemaName}.task t
		join ${mainSchemaName}.task_stage ts 
			on ts.task_id = t.id 
			and ts.is_disabled = false
		join ${mainSchemaName}.transfer tr 
			on tr.id = ts.transfer_id
		join ${mainSchemaName}.transfer_dependency dep 
			on dep.transfer_id = ts.transfer_id
		union all
		select
			ts.task_id
			, ts.preceding_transfer_id as transfer_id
			, preceding_transfer.master_id as master_transfer_id
			, p_preceding_transfer.id as preceding_transfer_id
			, ts.target_transfer_id
			, ts.target_container
			, ts.is_target_transfer_deletion
			, ts.are_del_ins_stages_separated
			, (
				ts.ordinal_position
				- case when p_preceding_transfer.id = preceding_transfer.master_id then 1 else 2 end
			) as ordinal_position
			, ts.stage_ordinal_position
			, ts.chain_transfers || ts.preceding_transfer_id as chain_transfers
		from 
			task_stage ts
		join ${mainSchemaName}.transfer preceding_transfer
			on preceding_transfer.id = ts.preceding_transfer_id
		left join ${mainSchemaName}.transfer_dependency dep 
			on dep.transfer_id = preceding_transfer.id
		left join ${mainSchemaName}.transfer dep_master_transfer
			on dep_master_transfer.id = dep.master_transfer_id
		left join ${mainSchemaName}.transfer p_preceding_transfer
			on p_preceding_transfer.id = preceding_transfer.master_id 
			or p_preceding_transfer.id = dep.master_transfer_id			
		where 
			ts.preceding_transfer_id <> all(ts.chain_transfers)
	)
	, dependent_transfer_group as (
		with recursive 
			transfer_group as (
				select 
					tg.id as transfer_group_id
					, dep.master_transfer_group_id
					, case
						when dep.master_transfer_group_id is not null then 1
						else 0
					end as dep_level
					, array[dep.master_transfer_group_id] as transfer_group_seq
				from
					${mainSchemaName}.transfer_group tg
				left join ${mainSchemaName}.transfer_group_dependency dep 
					on dep.transfer_group_id = tg.id
				union all
				select
					tg.transfer_group_id
					, dep.master_transfer_group_id
					, tg.dep_level + 1 as dep_level 
					, tg.transfer_group_seq || dep.master_transfer_group_id as transfer_group_seq
				from 
					transfer_group tg
				join ${mainSchemaName}.transfer_group_dependency dep 
					on dep.transfer_group_id = tg.master_transfer_group_id
				where 
					dep.master_transfer_group_id <> all(tg.transfer_group_seq)
			)
		select 
			tg.transfer_group_id
			, tg.master_transfer_group_id
			, tg.dep_level
			, first_value(
				coalesce(
					tg.master_transfer_group_id
					, tg.transfer_group_id
				)
			)
				over(
					partition by 
						tg.transfer_group_id
					order by 
						tg.dep_level desc
				)
				as transfer_group_chain_id
		from 
			transfer_group tg	
	)
	, task_transfers as ( 
		select 
			ts.task_id
			, t.internal_name as task_name
			, p.internal_name as project_name
			, trp.internal_name as transfer_project_name
			, tr.group_id as transfer_group_id
			, tg.transfer_group_chain_id
			, tg.dep_level as transfer_group_dep_level
			, ts.transfer_id
			, tr.internal_name as transfer_name
			, trt.internal_name as transfer_type_name
			, st.internal_name as source_type_name
			, s.internal_name as source_name
			, s.connection_string
			, s.user_name
			, s.user_password
			, ct.internal_name as container_type_name
			, tr.container
			, tr.is_virtual
			, tr.reexec_results
			, tr.is_chunking
			, tr.is_chunking_parallelizable
			, tr.is_deletion			
			, ts.ordinal_position
			, ts.target_transfer_id
			, ts.target_container
			, ts.is_target_transfer_deletion
			, ts.stage_ordinal_position
			, params.positional_arguments as transfer_positional_arguments
			, ts.preceding_transfer_id
			, ts.master_transfer_id
			, mtr.internal_name as master_transfer_name
			, mtrt.internal_name as master_transfer_type_name
			, ms.internal_name as master_source_name
			, mst.internal_name as master_source_type_name
			, mct.internal_name as master_container_type_name
			, mtr.container as master_container    
			, mtr.is_virtual as is_master_transfer_virtual
			, case when t.are_del_ins_stages_separated then ts.is_target_transfer_deletion else null::boolean end as is_deletion_stage
			, t.are_del_ins_stages_separated
			, ts.chain_transfers
			, ${mainSchemaName}.f_transfer_chain_id(
				i_transfer_id => ts.transfer_id
			) as transfer_chain_id
		from 
			task_stage ts
		join ${mainSchemaName}.task t 
			on t.id = ts.task_id
		join ${mainSchemaName}.project p 
			on p.id = t.project_id
		join ${mainSchemaName}.transfer tr 
			on tr.id = ts.transfer_id
		join lateral (
			select 
				tg.transfer_group_id
				, tg.dep_level
				, tg.transfer_group_chain_id
			from 
				dependent_transfer_group tg
			where 
				tg.transfer_group_id = tr.group_id
			order by 
				tg.dep_level desc
			limit 1
		) tg
			on true
		join ${mainSchemaName}.transfer_type trt 
			on trt.id = tr.type_id
		join ${mainSchemaName}.project trp 
			on trp.id = tr.project_id
		join ${mainSchemaName}.source s 
			on s.id = tr.source_id
		join ${mainSchemaName}.source_type st 
			on st.id = s.source_type_id
		left join ${mainSchemaName}.container_type ct 
			on ct.id = tr.container_type_id
		left join ${mainSchemaName}.transfer mtr 
			on mtr.id = ts.master_transfer_id
		left join ${mainSchemaName}.transfer_type mtrt 
			on mtrt.id = mtr.type_id
		left join ${mainSchemaName}.source ms 
			on ms.id = mtr.source_id
		left join ${mainSchemaName}.source_type mst 
			on mst.id = ms.source_type_id
		left join ${mainSchemaName}.container_type mct 
			on mct.id = mtr.container_type_id
		left join lateral (
			select 
				string_agg(tp.param_value, ',' order by tp.ordinal_position) as positional_arguments
			from 
				${mainSchemaName}.transfer_param tp
			where 
				tp.transfer_id = ts.transfer_id
				and tp.is_disabled = false
		) params on true
	)
	, chain_transfers as (
		select distinct on (
				t.task_id
				, t.transfer_id
			)
			t.task_id
			, t.task_name
			, t.project_name
			, t.transfer_project_name
			, t.transfer_group_id
			, t.transfer_group_chain_id
			, t.transfer_group_dep_level
			, t.transfer_id
			, t.transfer_name
			, t.transfer_type_name
			, t.source_type_name
			, t.source_name
			, t.connection_string
			, t.user_name
			, t.user_password
			, t.container_type_name
			, t.container
			, t.is_virtual
			, t.reexec_results
			, t.is_chunking
			, t.is_chunking_parallelizable
			, t.is_deletion			
			, t.ordinal_position
			, t.target_transfer_id
			, t.target_container
			, t.is_target_transfer_deletion
			, t.stage_ordinal_position
			, t.transfer_positional_arguments
			, t.preceding_transfer_id
			, t.master_transfer_id
			, t.master_transfer_name
			, t.master_transfer_type_name
			, t.master_source_name
			, t.master_source_type_name
			, t.master_container_type_name
			, t.master_container    
			, t.is_master_transfer_virtual
			, t.is_deletion_stage
			, t.are_del_ins_stages_separated
			, t.chain_transfers
			, t.transfer_chain_id
		from 
			task_transfers t
		order by 
			t.task_id
			, t.transfer_id
			, t.stage_ordinal_position
			, t.ordinal_position
			, case when t.is_master_transfer_virtual then 1 else 0 end
	)
	, reexecuted_task_transfers as (
		select 
			row_number() 
				over(
					partition by 
						t.task_id
						, case 
							when t.are_del_ins_stages_separated then t.is_target_transfer_deletion 
							else null::boolean
						end
						, t.transfer_chain_id
					order by 
						t.stage_ordinal_position
						, t.ordinal_position
						, t.ordinal_shift
						, case when t.is_target_transfer_deletion then 0 else 1 end
						, case when t.preceding_transfer_id = t.master_transfer_id then 0 else 1 end
						, t.target_container
				)
				as sort_order
			, t.task_id
			, t.task_name
			, t.project_name
			, t.transfer_project_name
			, t.transfer_group_id
			, t.transfer_group_chain_id
			, t.transfer_group_dep_level
			, t.transfer_id
			, t.transfer_name
			, t.transfer_type_name
			, t.source_type_name
			, t.source_name
			, t.connection_string
			, t.user_name
			, t.user_password
			, t.container_type_name
			, t.container
			, t.is_virtual
			, t.reexec_results
			, t.is_reexecution
			, t.is_chunking
			, t.is_chunking_parallelizable
			, t.is_deletion			
			, t.ordinal_position
			, t.target_transfer_id
			, t.target_container
			, t.is_target_transfer_deletion
			, t.stage_ordinal_position
			, t.transfer_positional_arguments
			, t.preceding_transfer_id
			, t.master_transfer_id
			, t.master_transfer_name
			, t.master_transfer_type_name
			, t.master_source_name
			, t.master_source_type_name
			, t.master_container_type_name
			, t.master_container    
			, t.is_master_transfer_virtual
			, t.is_deletion_stage
			, t.are_del_ins_stages_separated
			, t.transfer_chain_id
		from (
			select 
				t.task_id
				, t.task_name
				, t.project_name
				, t.transfer_project_name
				, t.transfer_group_id
				, t.transfer_group_chain_id
				, t.transfer_group_dep_level
				, t.transfer_id
				, t.transfer_name
				, t.transfer_type_name
				, t.source_type_name
				, t.source_name
				, t.connection_string
				, t.user_name
				, t.user_password
				, t.container_type_name
				, t.container
				, t.is_virtual
				, t.reexec_results
				, false as is_reexecution
				, t.is_chunking
				, t.is_chunking_parallelizable
				, t.is_deletion			
				, t.ordinal_position
				, 0 as ordinal_shift
				, t.target_transfer_id
				, t.target_container
				, t.is_target_transfer_deletion
				, t.stage_ordinal_position
				, t.transfer_positional_arguments
				, t.preceding_transfer_id
				, t.master_transfer_id
				, t.master_transfer_name
				, t.master_transfer_type_name
				, t.master_source_name
				, t.master_source_type_name
				, t.master_container_type_name
				, t.master_container    
				, t.is_master_transfer_virtual
				, t.is_deletion_stage
				, t.are_del_ins_stages_separated
				, t.transfer_chain_id
			from 
				chain_transfers t
			where 
				t.transfer_chain_id is not null
			union all
			select
				t.task_id
				, t.task_name
				, t.project_name
				, t.transfer_project_name
				, t.transfer_group_id
				, t.transfer_group_chain_id
				, t.transfer_group_dep_level
				, t.transfer_id
				, t.transfer_name
				, t.transfer_type_name
				, t.source_type_name
				, t.source_name
				, t.connection_string
				, t.user_name
				, t.user_password
				, t.container_type_name
				, t.container
				, t.is_virtual
				, t.reexec_results
				, true as is_reexecution
				, t.is_chunking
				, t.is_chunking_parallelizable
				, t.is_deletion			
				, t.ordinal_position
				, 1 as ordinal_shift
				, t.target_transfer_id
				, t.target_container
				, t.is_target_transfer_deletion
				, t.stage_ordinal_position
				, null as transfer_positional_arguments
				, t.preceding_transfer_id
				, t.transfer_id as master_transfer_id
				, t.transfer_name as master_transfer_name
				, t.transfer_type_name as master_transfer_type_name
				, t.source_name as master_source_name
				, t.source_type_name as master_source_type_name
				, t.container_type_name as master_container_type_name
				, t.container as master_container    
				, t.is_virtual as is_master_transfer_virtual
				, t.is_deletion_stage
				, t.are_del_ins_stages_separated
				, t.transfer_chain_id
			from 
				chain_transfers t
			where
				t.reexec_results = true
				and t.is_virtual = false
				and t.transfer_chain_id is not null
			union all
			select
				t.task_id
				, t.task_name
				, t.project_name
				, t.transfer_project_name
				, t.transfer_group_id
				, t.transfer_group_chain_id
				, t.transfer_group_dep_level
				, t.transfer_id
				, t.transfer_name
				, t.transfer_type_name
				, t.source_type_name
				, t.source_name
				, t.connection_string
				, t.user_name
				, t.user_password
				, t.container_type_name
				, t.container
				, t.is_virtual
				, t.reexec_results
				, false as is_reexecution
				, t.is_chunking
				, t.is_chunking_parallelizable
				, t.is_deletion			
				, t.ordinal_position
				, -1 as ordinal_shift
				, t.target_transfer_id
				, t.target_container
				, t.is_target_transfer_deletion
				, t.stage_ordinal_position
				, t.transfer_positional_arguments
				, t.preceding_transfer_id
				, t.master_transfer_id
				, t.master_transfer_name
				, t.master_transfer_type_name
				, t.master_source_name
				, t.master_source_type_name
				, t.master_container_type_name
				, t.master_container    
				, t.is_master_transfer_virtual
				, t.is_deletion_stage
				, t.are_del_ins_stages_separated
				, following_transfer.transfer_chain_id
			from 
				task_transfers t
			join task_transfers following_transfer
				on following_transfer.task_id = t.task_id
				and following_transfer.master_transfer_id = t.transfer_id
				and following_transfer.target_transfer_id = t.target_transfer_id
			where 
				t.is_virtual
				and t.transfer_chain_id is null 
		) t
	)
select
	t.sort_order
	, t.task_id
	, t.task_name
	, t.project_name
	, t.transfer_project_name
	, t.transfer_group_id
	, t.transfer_group_dep_level
	, t.transfer_group_chain_id
	, t.transfer_id
	, t.transfer_name
	, t.transfer_type_name
	, t.source_type_name
	, t.source_name
	, t.connection_string
	, t.user_name
	, t.user_password
	, t.container_type_name
	, t.container
	, t.is_virtual
	, t.reexec_results
	, t.is_reexecution
	, t.is_chunking
	, t.is_chunking_parallelizable
	, t.is_chunked	
	, case when t.is_chunked then t.chunked_sequence_id end as chunked_sequence_id
	, t.is_deletion			
	, t.ordinal_position
	, t.target_transfer_id
	, t.target_container
	, t.is_target_transfer_deletion
	, t.stage_ordinal_position
	, t.transfer_positional_arguments
	, t.preceding_transfer_id
	, t.master_transfer_id
	, t.master_transfer_name
	, t.master_transfer_type_name
	, t.master_source_name
	, t.master_source_type_name
	, t.master_container_type_name
	, t.master_container    
	, t.is_master_transfer_virtual
	, t.is_master_transfer_chunked
	, t.transfer_chain_id
	, t.chain_order_num
	, t.is_deletion_stage
	, t.are_del_ins_stages_separated
from ( 
	select
		t.sort_order
		, t.task_id
		, t.task_name
		, t.project_name
		, t.transfer_project_name
		, t.transfer_group_id
		, t.transfer_group_chain_id
		, t.transfer_group_dep_level
		, t.transfer_id
		, t.transfer_name
		, t.transfer_type_name
		, t.source_type_name
		, t.source_name
		, t.connection_string
		, t.user_name
		, t.user_password
		, t.container_type_name
		, t.container
		, t.is_virtual
		, t.reexec_results
		, t.is_reexecution
		, t.is_chunking
		, t.is_chunking_parallelizable
		, chunking.chunked_sequence_id
		, ${mainSchemaName}.f_is_transfer_chunked(
			i_transfer_id => t.transfer_id
			, i_chunked_sequence_id => chunking.chunked_sequence_id 
		) as is_chunked
		, ${mainSchemaName}.f_is_transfer_chunked(
			i_transfer_id => t.master_transfer_id
			, i_chunked_sequence_id => chunking.master_transfer_chunked_sequence_id 
		) as is_master_transfer_chunked	
		, t.is_deletion			
		, t.ordinal_position
		, t.target_transfer_id
		, t.target_container
		, t.is_target_transfer_deletion
		, t.stage_ordinal_position
		, t.transfer_positional_arguments
		, t.preceding_transfer_id
		, t.master_transfer_id
		, t.master_transfer_name
		, t.master_transfer_type_name
		, t.master_source_name
		, t.master_source_type_name
		, t.master_container_type_name
		, t.master_container    
		, t.is_master_transfer_virtual
		, t.transfer_chain_id
		, t.is_deletion_stage
		, t.are_del_ins_stages_separated
		, last_value(t.stage_ordinal_position) 
			over(
				partition by 
					t.task_id
					, t.transfer_group_chain_id
					, t.transfer_chain_id
					, t.is_deletion_stage
				order by 
					t.sort_order
				range between 
		            unbounded preceding and 
		            unbounded following						
			) 
			as chain_order_num
	from 
		reexecuted_task_transfers t
	join lateral (
		select 
			${mainSchemaName}.f_transfer_chunked_sequence_id(
				i_transfer_id => t.transfer_id
			) as chunked_sequence_id
			, ${mainSchemaName}.f_transfer_chunked_sequence_id(
				i_transfer_id => t.master_transfer_id
			) as master_transfer_chunked_sequence_id
	) as chunking(
		chunked_sequence_id
		, master_transfer_chunked_sequence_id
	) 
		on true
	where 
		not exists (
			select 
				1
			from 
				reexecuted_task_transfers tt
			where 
				tt.task_id = t.task_id
				and tt.transfer_id = t.transfer_id
				and tt.transfer_chain_id = t.transfer_chain_id
				and tt.sort_order < t.sort_order
				and tt.is_reexecution = t.is_reexecution
		)
) t
;

comment on view v_task_stage is 'Этапы задач';

grant select on v_task_stage to ${etlUserRole};