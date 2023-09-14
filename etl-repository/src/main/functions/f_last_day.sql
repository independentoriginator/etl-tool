create or replace function f_last_day(
	date
)
returns date
language sql
immutable
strict
parallel safe
as $function$
select (date_trunc('month', $1) + interval '1 month' - interval '1 day')::date
$function$;

comment on function f_last_day(
	date
) is 'Последний день месяца';