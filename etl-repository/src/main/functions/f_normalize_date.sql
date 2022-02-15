create or replace function f_normalize_date(
	i_raw_value text
	, i_type "char" -- 's, n, d, b'
)
returns date
language plpgsql
immutable
parallel safe
as $function$
begin
	if length(coalesce(i_raw_value, '')) > 0 then
		if i_type = 'd' 
		then 
			return to_date(i_raw_value, 'yyyy-mm-dd');
		elseif i_type = 'n' then 
			-- Internal Excel date value, 1900 system for dates is assumed (not 1904 system)
			return to_date('1900-03-01', 'yyyy-mm-dd') - interval '61 day' + floor(i_raw_value::numeric) * interval '1 day';
		elsif regexp_replace(i_raw_value, '\s', '', 'g') ~ '^\d{1,2}\.\d{1,2}\.\d{4}' then 
			return to_date(substring(regexp_replace(i_raw_value, '\s', '', 'g'), 1, 10), 'dd.mm.yyyy');
		elsif regexp_replace(i_raw_value, '\s', '', 'g') ~ '^\d{1,2}\.\d{4}' then 
			return to_date('01.' || substring(regexp_replace(i_raw_value, '\s', '', 'g'), 1, 7), 'dd.mm.yyyy');
		elsif i_raw_value ~ '^\d{4}\s*г{0,1}.*' then 
			return to_date(regexp_replace(i_raw_value, '(\d{4})(.*)', '\1') || '-01-01', 'yyyy-mm-dd');
		elsif i_raw_value ~ 'Всего на конец \d{4}.*' then 
			return to_date(regexp_replace(i_raw_value, '(.*)(\d{4})(.*)', '\2') || '-12-31', 'yyyy-mm-dd');
		elsif i_raw_value ~ '\d*\w+ \d{4}.*' then
			perform set_config('lc_time', 'ru_RU.utf8', true);
			return (
				select 
					case 
						when i_raw_value ~ '^\w+ \d{4}.*' 
							then to_date(regexp_replace(i_raw_value, '(.*)(\d{4})(.*)', '\2') || '-' || m.n_month::text || '-1', 'yyyy-mm-dd')
						else to_date(regexp_replace(i_raw_value, '(\d{1,2})(.*)(\d{4})(.*)', '\3-' || m.n_month::text || '-\1'), 'yyyy-mm-dd')
					end
				from (
					select 
						m as n_month, to_char(to_date(m::text, 'mm'), 'tmmonth') as s_month
					from 
						generate_series(1, 12) m
					union all
					select 
						m as n_month, 
						replace(
							replace(
								to_char(to_date(m::text, 'mm'), 'tmmonth'),
								'ь', 'я'
							),
							'й', 'я'
						) 
						|| case when m in (3, 8) then 'а' else '' end 
						as s_month_in_genitive_case
					from 
						generate_series(1, 12) m
				) m	
				where 
					strpos(lower(i_raw_value), m.s_month) > 0
			);
		end if;
	end if;
	return null::date;
exception
	when others then
		return null::date;
end	
$function$;		