create or replace function f_generate_uuid()
returns uuid
language sql
volatile
parallel safe
as $function$
set local search_path = pg_catalog,${dbms_extension.uuid-ossp.schema},public
;
select 
	/* #if #server_major_version >= 13 */
	/* #then */
	pg_catalog.gen_random_uuid()
	/* #else */
	/* ${dbms_extension.uuid-ossp.schema}.uuid_generate_v4() */
	/* #endif */
$function$
;

comment on function f_generate_uuid(
) is 'Сгенерировать UUID'
;
