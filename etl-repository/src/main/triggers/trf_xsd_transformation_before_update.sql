create or replace function trf_xsd_transformation_before_update()
returns trigger
language plpgsql
as $$
begin
	new.is_staging_schema_generated = false;
	
	return new;
end
$$;			

comment on function trf_xsd_transformation_before_update() is 'XSD-трансформация. Триггерная функция для события "Перед обновлением"';