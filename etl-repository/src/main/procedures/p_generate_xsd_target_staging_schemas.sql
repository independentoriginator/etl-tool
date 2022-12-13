create or replace procedure p_generate_xsd_target_staging_schemas()
language plpgsql
as $procedure$
declare 
	l_rec record;
begin
	for l_rec in (
		select
			t.*
			, case when target_schema.nspname is null then false else true end as is_target_staging_schema_exists
			, schema_usage_permission.has_schema_usage_permission as is_etluser_has_schema_usage_permission
		from 
			${mainSchemaName}.v_xsd_transformation t
		join ${mainSchemaName}.xsd_transformation xsd_transformation 
			on xsd_transformation.id = t.id
		left join pg_catalog.pg_namespace target_schema
			on target_schema.nspname = t.target_staging_schema
		left join lateral (
			select
				true as has_schema_usage_permission
			from
				pg_catalog.aclexplode(target_schema.nspacl) acl
			join pg_catalog.pg_user grantee 
				on acl.grantee = grantee.usesysid
				and grantee.usename = '${etlUserRole}'
			where 
				acl.privilege_type = 'USAGE'
		) schema_usage_permission on true
		where 
			coalesce(t.is_staging_schema_generated, false) = false
		for update of xsd_transformation
	) 
	loop
		raise notice 'Generating schema %...', l_rec.target_staging_schema;
	
		if not l_rec.is_target_staging_schema_exists then
			execute format('create schema %I', l_rec.target_staging_schema);
		end if;
	
		if length('${etlUserRole}') > 0 
			and not l_rec.is_etluser_has_schema_usage_permission
		then
			execute	
				format(
					'grant usage on schema %I to ${etlUserRole}'
					, l_rec.l_rec.target_staging_schema 
				);
		end if;
	
		call ${mainSchemaName}.p_extract_xsd_entities(
			i_xsd_transformation_id => l_rec.id
		);

		call ${mainSchemaName}.p_extract_xsd_entity_attributes(
			i_xsd_transformation_id => l_rec.id
		);

	/*
		call ${mainSchemaName}.p_generate_xsd_target_staging_tables(
			i_xsd_transformation_id => l_rec.id
		);
	*/
		update ${mainSchemaName}.xsd_transformation 
		set is_staging_schema_generated = true
		where id = l_rec.id
		;
	end loop;
end
$procedure$;			
