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
begin
	if coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_left), '') = 
		coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_right), '') 
	then 
		return true;
	end if;
	
	-- pg_trgm extension is required
	if exists (
		select 
			1
		from
			information_schema.routines r
		where 
			r.routine_name = 'similarity'
			and r.routine_type = 'FUNCTION'
	) 
	then
		execute 'select similarity($1, $2)' into l_similarity_level using i_left, i_right;
		if l_similarity_level >= i_similarity_threshold then
			return true;
		end if;
	end if;
	
	return false;	
end
$function$;		