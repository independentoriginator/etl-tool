create or replace function 
	f_truncate_string(
		i_str text
		, i_max_length integer
		, i_ending text = '...'
	)
returns text
language sql
immutable
parallel safe
as $function$
select 
	case 
		when length(i_str) > i_max_length then	
			left(i_str, i_max_length - length(i_ending)) || coalesce(i_ending, '')
		else 
			i_str
	end
$function$;		

comment on function 
	f_truncate_string(
		text
		, integer
		, text
	) 
	is 'Усечение строки'
;