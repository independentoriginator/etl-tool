create or replace function f_months_between(
	date
	, date
)
returns float
language sql
immutable
strict
parallel safe
as $function$
select
	(extract(year from $1) - extract(year from $2)) * 12.0
	+ extract(month from $1) - extract(month from $2)
	+ case
		when extract(day from $2) = extract(day from ${mainSchemaName}.f_last_day($2))
			and extract(day from $1) = extract(day from ${mainSchemaName}.f_last_day($1))
		then
			0
		else
			(extract(day from $1) - extract(day from $2)) / 31.0
	end
$function$;		

comment on function f_months_between(
	date
	, date
) is 'Кол-во месяцев между датами';