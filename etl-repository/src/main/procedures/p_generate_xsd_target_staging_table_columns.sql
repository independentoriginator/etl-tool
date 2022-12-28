create or replace procedure p_generate_xsd_target_staging_table_columns(
	i_xsd_entity_id ${mainSchemaName}.xsd_entity.id%type
)
language plpgsql
as $procedure$
declare 
	l_column_rec record;
begin
	for l_column_rec in (
		select 
			a.schema_name
			, a.table_name
			, a.column_name
			, a.is_target_column_exists 
			, a.description
			, a.target_column_description
			, a.column_type	
			, a.target_column_type			
			, a.nullable
			, a.is_notnull_constraint_exists
		from 
			${mainSchemaName}.v_xsd_entity_attr a
		where 
			a.xsd_entity_id = i_xsd_entity_id
	) 
	loop
		if not l_column_rec.is_target_column_exists then
			execute format('
				alter table %I.%I 
					add column %I %s %snull 
				'
				, l_column_rec.schema_name
				, l_column_rec.table_name
				, l_column_rec.column_name
				, l_column_rec.column_type
				, case when l_column_rec.nullable then '' else 'not ' end
			);
		else
			if l_column_rec.column_type <> l_column_rec.target_column_type then
				call ${stagingSchemaName}.p_alter_table_column_type(
					i_schema_name => l_column_rec.schema_name
					, i_table_name => l_column_rec.table_name
					, i_column_name => l_column_rec.column_name
					, i_column_type => l_column_rec.column_type
				);			
			end if;		
		
			if not l_column_rec.nullable and not l_column_rec.is_notnull_constraint_exists then
				execute format('
					alter table %I.%I 
						alter column %I set not null
					'
					, l_column_rec.schema_name
					, l_column_rec.table_name
					, l_column_rec.column_name
				);
			elsif l_column_rec.nullable and l_column_rec.is_notnull_constraint_exists then
				execute format('
					alter table %I.%I 
						alter column %I drop not null
					'
					, l_column_rec.schema_name
					, l_column_rec.table_name
					, l_column_rec.column_name
				);
			end if;
		end if;
	
		if ${mainSchemaName}.f_values_are_different(l_column_rec.description, l_column_rec.target_column_description) then
			execute format('
				comment on column %I.%I.%I is $comment$%s$comment$
				'
				, l_column_rec.schema_name
				, l_column_rec.table_name
				, l_column_rec.column_name
				, l_column_rec.description
			);
		end if;
	end loop;
end
$procedure$;			
