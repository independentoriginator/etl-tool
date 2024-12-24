create or replace function 
	f_extract_url_parameters(
		i_url varchar
	)
returns 
	table(	
		key varchar
		, value varchar
	)
language sql
immutable
parallel safe
as $function$
select 
	arg.key
	, arg.value
from (
	select 
		regexp_split_to_table(
			substring(
				i_url
		 		, position('?' in i_url) + 1
		 	)
		 	, '&'
		) as arg
) args
join lateral (
	select 
		regexp_replace(args.arg, '(.+)=(.*)', '\1') as key
		, regexp_replace(args.arg, '(.+)=(.+)', '\2') as value
) arg
	on true
$function$;	

comment on function 
	f_extract_url_parameters(
		varchar
	) 
	is 'Параметры URL'
;