create or replace view v_xsd_transformation
as
select 
	t.id
	, t.internal_name
	, t.version
	, t.name
	, t.description
	, t.source_xsd
	, t.transformed_xsd
	, t.target_staging_schema
	, case when t.is_staging_schema_generated and target_schema.oid is not null then true else false end as is_staging_schema_generated  
from 
	${mainSchemaName}.xsd_transformation t
left join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = t.target_staging_schema
;