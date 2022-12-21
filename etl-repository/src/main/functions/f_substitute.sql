create or replace function f_substitute(
	i_text text
	, i_keys text[]
	, i_values text[]
)
returns text
language plpgsql
immutable
parallel safe
as $function$
declare 
	l_result text := i_text;
begin
	if i_keys is not null then
		for i in array_lower(i_keys, 1) .. array_upper(i_keys, 1) loop
			l_result := replace(l_result, i_keys[i], quote_nullable(i_values[i]));
		end loop;
	end if;
	return l_result;
end
$function$;		