create or replace function f_strings_similarity(
	i_left text
	, i_right text
)
returns real
language plpgsql
stable
parallel safe
as $function$
declare 
	l_similarity_level real := .0;
	l_similarity_func_schema name;
begin
	if i_left = i_right then
		return 1.0;
	end if;
	
	-- Conditionally less then 1.0 for incomplete matching
	if coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_left), '') = 
		coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_right), '') then 
		return 0.99;
	end if;
	
	-- For best result pg_trgm extension with 'similarity' function is required
	select 
		r.routine_schema
	into 
		l_similarity_func_schema
	from
		information_schema.routines r
	where 
		r.routine_name = 'similarity'
		and r.routine_type = 'FUNCTION'
	;
	 
	if l_similarity_func_schema is not null
	then
		execute format('select %I.similarity($1, $2)', l_similarity_func_schema) into l_similarity_level using i_left, i_right;
		return l_similarity_level;
	end if;
	
	return .0;	
end
$function$;		