create or replace function f_xsd_entity_dependency_level(
	i_xsd_transformation_id ${mainSchemaName}.xsd_transformation.id%type
	, i_entity_path ${mainSchemaName}.xsd_entity.path%type
)
returns integer
language sql
stable
as $function$
select 
	coalesce((
			select 
				max(
					${mainSchemaName}.f_xsd_entity_dependency_level(
						i_xsd_transformation_id => i_xsd_transformation_id
						, i_entity_path => e.master_entity
					)
				)
			from 
				${mainSchemaName}.xsd_entity e 
			where 
				e.xsd_transformation_id = i_xsd_transformation_id
				and e.path = i_entity_path
				and e.master_entity is not null
				and e.master_entity <> e.path
		) + 1,
		0
	)
$function$;

comment on function f_xsd_entity_dependency_level(
	${mainSchemaName}.xsd_transformation.id%type
	, ${mainSchemaName}.xsd_entity.path%type
) is 'XSD. Уровень зависимости сущности';