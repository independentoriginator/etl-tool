create or replace function f_xsd_entity_attr_column_type(
	i_entity_attr ${mainSchemaName}.xsd_entity_attr
)
returns text
language sql
stable
as $function$
select 
	case i_entity_attr.type
		when 'xs:string' then 
			case when i_entity_attr.max_length > 0 then 'varchar(' || i_entity_attr.max_length::text || ')' else 'text' end
		when 'xs:decimal' then 'numeric' 
			|| case when i_entity_attr.total_digits > 0 then '(' || i_entity_attr.total_digits::text 
				|| case when i_entity_attr.fraction_digits is not null then ',' || i_entity_attr.fraction_digits::text else '' end || ')' else '' end  
		when 'xs:int' then 'integer'
		when 'xs:integer' then 'integer'
		when 'xs:long' then 'bigint'
		when 'xs:short' then 'smallint'
		when 'xs:float' then 'real'
		when 'xs:double' then 'float8'
		when 'xs:boolean' then 'boolean'
		when 'xs:date' then 'date'
		when 'xs:dateTime' then 'timestamp'
		when 'xs:time' then 'time'
		else 'text'
	end	
$function$;		