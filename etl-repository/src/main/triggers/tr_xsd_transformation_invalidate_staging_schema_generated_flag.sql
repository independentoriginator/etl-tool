drop trigger if exists tr_xsd_transformation_invalidate_staging_schema_generated_flag on xsd_transformation;
create trigger tr_xsd_transformation_invalidate_staging_schema_generated_flag
before update 
on xsd_transformation
for each row 
when (old.is_staging_schema_generated = true)
execute function ${mainSchemaName}.trf_xsd_transformation_before_update();
