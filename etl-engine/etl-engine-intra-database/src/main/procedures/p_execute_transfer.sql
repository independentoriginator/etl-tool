create or replace procedure p_execute_transfer(
	i_transfer_id ${database.defaultSchemaName}.transfer.id%type
)
language plpgsql
as $procedure$
declare 
	l_stage_rec record;
	l_is_this_database boolean := false;
	l_extraction_command ${database.defaultSchemaName}.source.container%type;
	l_load_command ${database.defaultSchemaName}.source.container%type;
begin
	for l_stage_rec in (
		select
			ts.*
		from 
			${database.defaultSchemaName}.v_transfer_stage ts
		where
			ts.transfer_id = i_transfer_id
		order by 
			ordinal_position 
	) 
	loop
		if l_stage_rec.source_type_name = 'dbms' then
			if l_stage_rec.source_name = 'this database' then
				l_is_this_database := true;
			else
				raise exception 'Unsupported DBMS connection type specified: %', l_stage_rec.source_name;
			end if;
		elsif l_stage_rec.source_type_name = 'extraction' then
			if l_stage_rec.container_type_name <> 'sql' then
				raise exception 'Unsupported container type specified: %', l_stage_rec.container_type_name;
			end if;
			
			l_extraction_command := l_stage_rec.container;
			
			if l_stage_rec.master_source_type_name = 'extraction' then
				if l_stage_rec.master_container_type_name <> 'sql' then
					raise exception 'Unsupported container type specified: %', l_stage_rec.master_container_type_name;
				end if;

				if l_is_this_database then
					l_extraction_command := replace(l_extraction_command, '{{master_recordset}}', '(' || l_stage_rec.master_container || ')');
				end if;
			end if;			
		elsif l_stage_rec.source_type_name = 'load' then
			if l_stage_rec.container_type_name = 'table' then
				l_load_command := 
					format('
							insert into %I
							select *
							from (%s) t
						'
						, l_stage_rec.source_name
						, l_extraction_command
					);
			else
				raise exception 'Unsupported container type specified: %', l_stage_rec.container_type_name;
			end if;
			
			execute l_load_command;
		end if;		
	end loop;
end
$procedure$;			
