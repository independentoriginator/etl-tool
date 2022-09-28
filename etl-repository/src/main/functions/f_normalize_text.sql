create or replace function f_normalize_text(
	i_text text
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	nullif(
		nullif(
			regexp_replace(
				btrim(
					regexp_replace(
						regexp_replace(
							i_text
							, '[\n\r]|\s{2,}'
							, ' '
							, 'g' 
						)
						, '[^[:print:]]|_x0002_|\@page( \{.*\})*( p( p\.western)*( p\.cjk)*)*'
						, ''
						, 'g'
					)
				)
				, '^([\''\"]+)(.*)([\''\"]+)$'
				, '\2'
			)
			, '-'
		)
		, ''
	)
-- _x0002_ - unexpected "START OF TEXT" unicode control charaсter sequence
$function$;		