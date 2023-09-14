create or replace function f_normalize_number(
	i_raw_value text
	, i_type text -- 's, n, d, b'
	, i_round_using_predef_scale boolean default true
	, i_format text default null::text
	, i_fix_num_percent_as_text_expected boolean default false
	, i_max_precision integer default ${type.precision.numeric}
	, i_max_scale integer default ${type.scale.numeric}
)
returns numeric
language plpgsql
immutable
parallel safe
as $function$
declare 
	l_result numeric;
	l_str_components text[];
begin
	if length(coalesce(i_raw_value, '')) > 0
	then
		if i_type = 'n' 
		then 
			if i_fix_num_percent_as_text_expected and i_format ~ '.*\%$'
			then 
				l_result := (i_raw_value::numeric) * 100.0;
			else 
				l_result := i_raw_value::numeric;
			end if;
		else
			l_str_components := 
				${mainSchemaName}.f_extract_number(
					i_str_as_prefix_number_suffix => i_raw_value
				);
			if l_str_components is not null 
			then
				-- null if number is inside a sentence 
				if length(coalesce(l_str_components[1], '')) > 0 and length(coalesce(l_str_components[3], '')) > 0
				then 
					l_result := null::numeric;
				else
					l_result :=
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
	
	if i_round_using_predef_scale then
		l_result := round(l_result, i_max_scale);
	end if;
	
	if l_result > 0 
		and l_result > ${mainSchemaName}.f_number_value_limit(
			i_is_negative => false
			, i_precision => i_max_precision
			, i_scale => i_max_scale
		) then
		l_result := null::numeric;
	elsif l_result < 0 
		and l_result < ${mainSchemaName}.f_number_value_limit(
			i_is_negative => true
			, i_precision => i_max_precision
			, i_scale => i_max_scale
		) then 
		l_result := null::numeric;
	end if; 
	
	return l_result;
exception
	when others then
		return null::numeric;
end
$function$;		

comment on function f_normalize_number(
	text
	, text
	, boolean
	, text
	, boolean
	, integer
	, integer
) is 'Нормализация числа';