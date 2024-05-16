create or replace function f_generate_uuid()
returns uuid
language sql
immutable
parallel safe
as $function$
select 
	/* #if #server_major_version >= 13 */
	/* #then */
	gen_random_uuid()
	/* #else */
	/* uuid_generate_v4() */
	/* #endif */
$function$
;

comment on function f_generate_uuid(
) is 'Сгенерировать UUID'
;
