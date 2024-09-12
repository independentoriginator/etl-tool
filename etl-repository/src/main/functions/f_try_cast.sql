create or replace function f_try_cast(
	in i_in text, 
	inout i_out anyelement
)
language plpgsql
as
$function$
begin
	execute 
		format(
			'select %L::%s'
			, i_in
			, pg_typeof(i_out)
		)
	into
		i_out
	;
exception when others then
   -- do nothing: i_out already carries default
end
$function$
;
