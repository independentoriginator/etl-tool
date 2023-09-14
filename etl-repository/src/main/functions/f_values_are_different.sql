create or replace function f_values_are_different(
	i_left text
	, i_right text
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;

comment on function f_values_are_different(
	text
	, text
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left varchar
	, i_right varchar
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;		

comment on function f_values_are_different(
	varchar
	, varchar
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left numeric
	, i_right numeric
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;		

comment on function f_values_are_different(
	numeric
	, numeric
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left date
	, i_right date
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;		

comment on function f_values_are_different(
	date
	, date
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left timestamp
	, i_right timestamp
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;	

comment on function f_values_are_different(
	timestamp
	, timestamp
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left boolean
	, i_right boolean
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;	

comment on function f_values_are_different(
	boolean
	, boolean
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left bigint
	, i_right bigint
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;	

comment on function f_values_are_different(
	bigint
	, bigint
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left integer
	, i_right integer
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;	

comment on function f_values_are_different(
	integer
	, integer
) is 'Признак различающихся двух значений';

create or replace function f_values_are_different(
	i_left interval
	, i_right interval
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when nullif(i_left, i_right) is not null or (i_left is null and i_right is not null) then true
		else false
	end
$function$;

comment on function f_values_are_different(
	interval
	, interval
) is 'Признак различающихся двух значений';
