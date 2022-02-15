create or replace function f_normalize_number(
	i_raw_value text
	, i_type text -- 's, n, d, b'
	, i_format text default null::text
	, i_fix_num_percent_as_text_expected boolean default false
)
returns numeric
language plpgsql
immutable
parallel safe
as $function$
declare 
	l_str_components text[];
begin
	if length(coalesce(i_raw_value, '')) > 0
	then
		if i_type = 'n' 
		then 
			if i_fix_num_percent_as_text_expected and i_format ~ '.*\%$'
			then 
				return (i_raw_value::numeric) * 100.0;
			else 
				return i_raw_value::numeric;
			end if;
		else
			l_str_components := 
				${database.defaultSchemaName}.f_extract_number(
					i_str_as_prefix_number_suffix => i_raw_value
				);
			if l_str_components is not null 
			then
				-- null if number is inside a sentence 
				if length(coalesce(l_str_components[1], '')) > 0 and length(coalesce(l_str_components[3], '')) > 0
				then 
					return null::numeric;
				else
					return 
						replace(					
							regexp_replace(
								regexp_replace(
									l_str_components[2], 
									'\s+', 
									'', 
									'g'
								),
								'(.*)(,)(\d*)$', 
								'\1.\3'
							),
							',',
							''
						)::numeric;
				end if;
			end if;
		end if;
	end if;
	return null::numeric;
exception
	when others then
		return null::numeric;
end
$function$;		