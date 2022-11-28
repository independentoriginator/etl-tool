create or replace procedure p_generate_xsd_target_staging_schemas()
language plpgsql
as $procedure$
declare 
	l_rec record;
begin
	for l_rec in (
		select
			t.*
		from 
			${mainSchemaName}.v_xsd_transformation t
		join ${mainSchemaName}.xsd_transformation xsd_transformation 
			on xsd_transformation.id = t.id
		where 
			coalesce(t.is_staging_schema_generated, false) = false
		for update of xsd_transformation
	) 
	loop
		execute format('create schema if not exists %I', l_rec.target_staging_schema);
	
		
			
		update ${mainSchemaName}.xsd_transformation 
		set is_staging_schema_generated = true
		where id = l_rec.id
		;
	end loop;
end
$procedure$;			
