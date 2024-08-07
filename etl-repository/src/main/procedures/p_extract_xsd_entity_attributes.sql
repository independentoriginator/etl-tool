create or replace procedure p_extract_xsd_entity_attributes(
	i_xsd_transformation_id ${mainSchemaName}.xsd_transformation.id%type
)
language plpgsql
as $procedure$
begin
	insert into 
		${mainSchemaName}.xsd_entity_attr(
			xsd_entity_id
			, path
			, name
			, column_name
			, description
			, type
			, nullable
			, max_length
			, total_digits
			, fraction_digits
			, is_multivalued
		)
	select 
		entity.id as xsd_entity_id
		, a.path
		, a.name
		, ${stagingSchemaName}.f_convert_case_camel2snake(
			a.name
		) as column_name
		, nullif(a.description, '') as description
		, nullif(a.type, '') as type
		, coalesce(a.nullable, true) as nullable 
		, a.max_length
		, a.total_digits
		, a.fraction_digits
		, coalesce(a.is_multivalued, false) as is_multivalued
	from (
		select
			t.id as xsd_transformation_id
			, x.entity_path
			, x.path
			, x.name
			, x.description
			, x.type
			, x.nullable
			, x.max_length
			, x.total_digits
			, x.fraction_digits
			, x.is_multivalued
		from
			${mainSchemaName}.xsd_transformation t
			, xmltable(
				xmlnamespaces(t.namespace as tns)
				, '/tns:relational_schema/tns:table/tns:column'
				passing relational_schema
				columns 
					entity_path text path '../@path'
					, path text path '@path'
					, name text path '@name'
					, description text path '@comment'
					, type text path '@type'
					, nullable boolean path '@nullable'
					, max_length integer path '@maxLength'
					, total_digits integer path '@totalDigits'
					, fraction_digits integer path '@fractionDigits'
					, is_multivalued boolean path '@isMultivalued'
			) x
		where 
			t.id = i_xsd_transformation_id
	) a
	join ${mainSchemaName}.xsd_entity entity
		on entity.xsd_transformation_id = a.xsd_transformation_id
		and entity.path = a.entity_path
	;
end
$procedure$;	

comment on procedure p_extract_xsd_entity_attributes(
	${mainSchemaName}.xsd_transformation.id%type
) is 'Извлечение атрибутов сущностей';
