create or replace function f_string_are_the_same(
	i_left text
	, i_right text
	, i_similarity_threshold real = 0.75 
)
returns boolean
language plpgsql
stable
parallel safe
as $function$
declare 
	l_similarity_level real;
	l_similarity_func_schema name;
begin
	if coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_left), '') = 
		coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_right), '') 
	then 
		return true;
	end if;
	
	-- pg_trgm extension is required
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
		if l_similarity_level >= i_similarity_threshold then
			return true;
		end if;
	end if;
	
	return false;	
end
$function$;		