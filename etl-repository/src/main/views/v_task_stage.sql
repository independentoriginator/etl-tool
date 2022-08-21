create or replace view v_task_stage
as
with 
	recursive task_stage as (
		select 
			ts.task_id
	        , ts.transfer_id
	        , tr.master_id as preceding_transfer_id
	        , ts.transfer_id as target_transfer_id
	        , tr.container as target_container
	        , tr.is_deletion as is_target_transfer_deletion 
			, coalesce(ts.ordinal_position, 0) as ordinal_position
			, coalesce(ts.ordinal_position, 0) as stage_ordinal_position
		from 
			${mainSchemaName}.task t
		join ${mainSchemaName}.task_stage ts on ts.task_id = t.id and ts.is_disabled = false
		join ${mainSchemaName}.transfer tr on tr.id = ts.transfer_id
		union all
		select
			ts.task_id
			, preceding_transfer.id as transfer_id
	        , preceding_transfer.master_id as preceding_transfer_id
	        , ts.target_transfer_id
	        , ts.target_container
	        , ts.is_target_transfer_deletion
	        , ts.ordinal_position - 1 as ordinal_position
	        , ts.stage_ordinal_position
		from 
			task_stage ts
		join ${mainSchemaName}.transfer preceding_transfer
			on preceding_transfer.id = ts.preceding_transfer_id
	)
	, task_transfers as ( 
		select
			row_number() 
				over(
					partition by ts.task_id 
					order by 
						ts.stage_ordinal_position
						, ts.target_container
						, case when ts.is_target_transfer_deletion then 0 else 1 end
						, ts.target_transfer_id
						, ts.ordinal_position
				) * 10 as sort_order
			, ts.task_id
			, t.internal_name as task_name
			, p.internal_name as project_name
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
			, tr.is_deletion			
			, ts.ordinal_position
			, ts.target_transfer_id
			, ts.stage_ordinal_position
			, params.positional_arguments as transfer_positional_arguments
		    , ts.preceding_transfer_id
			, ptr.internal_name as master_transfer_name
			, ptrt.internal_name as master_transfer_type_name
		    , ps.internal_name as master_source_name
			, pst.internal_name as master_source_type_name
			, pct.internal_name as master_container_type_name
			, ptr.container as master_container    
			, ptr.is_virtual as is_master_transfer_virtual
		from 
			task_stage ts
		join ${mainSchemaName}.task t 
			on t.id = ts.task_id
		join ${mainSchemaName}.project p 
			on p.id = t.project_id
		join ${mainSchemaName}.transfer tr 
			on tr.id = ts.transfer_id
		join ${mainSchemaName}.transfer_type trt 
			on trt.id = tr.type_id
		join ${mainSchemaName}.source s 
			on s.id = tr.source_id
		join ${mainSchemaName}.source_type st 
			on st.id = s.source_type_id
		left join ${mainSchemaName}.container_type ct 
			on ct.id = tr.container_type_id
		left join ${mainSchemaName}.transfer ptr 
			on ptr.id = ts.preceding_transfer_id
		left join ${mainSchemaName}.transfer_type ptrt 
			on ptrt.id = ptr.type_id
		left join ${mainSchemaName}.source ps 
			on ps.id = ptr.source_id
		left join ${mainSchemaName}.source_type pst 
			on pst.id = ps.source_type_id
		left join ${mainSchemaName}.container_type pct 
			on pct.id = ptr.container_type_id
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
	, reexecuted_task_transfers as (
		select
			t.sort_order
			, t.task_id
			, t.task_name
			, t.project_name
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
			, t.is_deletion			
			, t.ordinal_position
			, t.target_transfer_id
			, t.stage_ordinal_position
			, t.transfer_positional_arguments
		    , t.preceding_transfer_id
			, t.master_transfer_name
			, t.master_transfer_type_name
		    , t.master_source_name
			, t.master_source_type_name
			, t.master_container_type_name
			, t.master_container    
			, t.is_master_transfer_virtual
			, first_value(t.transfer_id) 
				over(
					partition by 
						t.task_id 
						, t.target_transfer_id 
					order by 
						t.sort_order
				) as transfer_chain_id
		from (
			select
				t.sort_order
				, t.task_id
				, t.task_name
				, t.project_name
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
				, t.is_deletion			
				, t.ordinal_position
				, t.target_transfer_id
				, t.stage_ordinal_position
				, t.transfer_positional_arguments
			    , t.preceding_transfer_id
				, t.master_transfer_name
				, t.master_transfer_type_name
			    , t.master_source_name
				, t.master_source_type_name
				, t.master_container_type_name
				, t.master_container    
				, t.is_master_transfer_virtual
			from 
				task_transfers t
			union all
			select
				t.sort_order + 1 as sort_order
				, t.task_id
				, t.task_name
				, t.project_name
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
				, t.is_deletion			
				, t.ordinal_position
				, t.target_transfer_id
				, t.stage_ordinal_position
				, null as transfer_positional_arguments
			    , t.preceding_transfer_id
				, t.transfer_name as master_transfer_name
				, t.transfer_type_name as master_transfer_type_name
			    , t.source_name as master_source_name
				, t.source_type_name as master_source_type_name
				, t.container_type_name as master_container_type_name
				, t.container as master_container    
				, t.is_virtual as is_master_transfer_virtual
			from 
				task_transfers t
			where
				t.reexec_results = true
				and t.is_virtual = false
		) t
	)
select
	t.sort_order
	, t.task_id
	, t.task_name
	, t.project_name
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
	, t.is_deletion			
	, t.ordinal_position
	, t.target_transfer_id
	, t.stage_ordinal_position
	, t.transfer_positional_arguments
    , t.preceding_transfer_id
	, t.master_transfer_name
	, t.master_transfer_type_name
    , t.master_source_name
	, t.master_source_type_name
	, t.master_container_type_name
	, t.master_container    
	, t.is_master_transfer_virtual
	, t.transfer_chain_id
	, first_value(t.sort_order) 
		over(
			partition by 
				t.task_id
				, t.transfer_chain_id
			order by 
				t.sort_order
		) as chain_order_num
from 
	reexecuted_task_transfers t
where 
	not exists (
		select 
			1
		from 
			reexecuted_task_transfers tt
		where 
			tt.task_id = t.task_id
			and tt.transfer_id = t.transfer_id
			and tt.sort_order < t.sort_order
			and tt.is_reexecution = t.is_reexecution
	)
;