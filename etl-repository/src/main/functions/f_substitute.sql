drop function if exists f_substitute(
	text
	, text[]
	, text[]
);

create or replace function f_substitute(
	i_text text
	, i_keys text[]
	, i_values text[]
	, i_quote_value boolean = true
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
			l_result := 
				replace(
					l_result
					, i_keys[i]
					, case 
						when coalesce(i_quote_value, true) then quote_nullable(i_values[i])
						else i_values[i]
					end
				);
		end loop;
	end if;
	return l_result;
end
$function$;		