create or replace function f_cron_expr_timestamps(
	i_cron_expr text
	, i_time_from timestamptz = current_timestamp
	, i_time_to timestamptz = null
)
returns setof timestamptz
language sql
immutable
parallel safe
as $function$
with 
	time_interval as (
		select 
			date_trunc('minute', coalesce(i_time_from, current_timestamp)) as time_from
			, date_trunc('minute', i_time_to) as time_to 
	)
	, expr_parts as (
		select 
			p.name
			, coalesce(
				p.range_start::integer
				, case p.name
					when 'minute' then 0
					when 'hour' then 0
					when 'day of month' then 1
					when 'month' then 1		
					when 'day of week' then 0
				end
			) as range_start
			, coalesce(
				p.range_end::integer
				, case p.name
					when 'minute' then 59
					when 'hour' then 23
					when 'day of month' then 31
					when 'month' then 12
					when 'day of week' then 6
				end
			) as range_end
			, coalesce(
				p.step::integer
				, 1
			) as step
			, case 
				when p.range_start is null then false
				else true
			end as is_given
		from (
			select 
				p.name
				, p.range_start
				, coalesce(
					p.range_end
					, p.range_start
				) as range_end
				, p.step
			from (
				select 
					case p.ord_num
						when 1 then 'minute'
						when 2 then 'hour'				
						when 3 then 'day of month'				
						when 4 then 'month'				
						when 5 then 'day of week'				
						when 6 then 'year'				
					end as name
					, substring(list_item, '(^[^/\-*]+).*') as range_start
					, substring(list_item, '\w+-(\w+).*') as range_end
					, substring(list_item, '[^/]*/(\d+)') as step
				from 
					regexp_split_to_table(trim(i_cron_expr), '\s+') with ordinality as p(part, ord_num)
				join lateral 
					regexp_split_to_table(
						case p.ord_num
							when 4 then 
								ng_etl.f_substitute(
									i_text => upper(p.part)
									, i_keys => array['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC']
									, i_values => array['1','2','3','4','5','6','7','8','9','10','11','12']
									, i_quote_value => false
								)				
							when 5 then 
								ng_etl.f_substitute(
									i_text => upper(p.part)
									, i_keys => array['SUN','MON','TUE','WED','THU','FRI','SAT','7']
									, i_values => array['0','1','2','3','4','5','6','0']
									, i_quote_value => false
								)				
							else p.part
						end 
						, ','
					) as list_item on true
			) p
		) p
	)
	, years as (
		select distinct
			value
		from 
			expr_parts p
		join lateral generate_series(p.range_start, p.range_end, p.step) as value on true
		where 
			p.name = 'year'
		union
		select
			extract(year from t) as value
		from 
			time_interval
		join lateral generate_series(time_interval.time_from, coalesce(time_interval.time_to, time_interval.time_from), '1 year') t on true
		where 
			not exists (
				select 
					1
				from 
					expr_parts p
				where 
					p.name = 'year'
			)
	)
	, months as (
		select distinct
			value
		from 
			expr_parts p
		join lateral generate_series(p.range_start, p.range_end, p.step) as value on true
		where 
			p.name = 'month'
	)
	, days_of_month as (
		select distinct
			value
		from 
			expr_parts p
		join lateral generate_series(p.range_start, p.range_end, p.step) as value on true
		where 
			p.name = 'day of month'
	)
	, days_of_week as (
		select distinct
			value
		from 
			expr_parts p
		join lateral generate_series(p.range_start, p.range_end, p.step) as value on true
		where 
			p.name = 'day of week'
	)
	, day_matching_mode as (
		select 
			case 
				when exists (
					select 
						1
					from 
						expr_parts dow
					where
						dow.name = 'day of month'
						and dow.is_given = true
				)
				and exists (
					select 
						1
					from 
						expr_parts dow
					where
						dow.name = 'day of week'
						and dow.is_given = true
				) 
				then 'union'
				else 'intersect'
			end as matching_mode
	)
	, hours as (
		select distinct
			value
		from 
			expr_parts p
		join lateral generate_series(p.range_start, p.range_end, p.step) as value on true
		where 
			p.name = 'hour'
	)
	, minutes as (
		select distinct
			value
		from 
			expr_parts p
		join lateral generate_series(p.range_start, p.range_end, p.step) as value on true
		where 
			p.name = 'minute'
	)
select 
	t.value
from (
	select 
		to_timestamp(
			years.value::varchar
			|| '-' || months.value::varchar 
			|| '-' || days.value::varchar
			|| ' ' || hours.value::varchar
			|| ':' || minutes.value::varchar
			, 'yyyy-mm-dd hh24:mi'
		) as value
	from 
		years
	join months	on true
	join generate_series(1, 31) as days(value) 
		on days.value <= 
			date_part(
				'day'
				, ng_etl.f_last_day(
					to_date(
						years.value::varchar
						|| '-' || months.value::varchar 
						|| '-01'
						, 'yyyy-mm-dd'
					)
				)
			)::integer
	join day_matching_mode dmm on true
	left join days_of_month dom 
		on dom.value = days.value 
	left join days_of_week dow 
		on dow.value = 
			mod(
				date_part(
					'dow'
					, to_date(
						years.value::varchar
						|| '-' || months.value::varchar 
						|| '-' || days.value::varchar
						, 'yyyy-mm-dd'
					)
				)::integer
				, 7
			)
	join hours on true
	join minutes on true
	where
		(
			dmm.matching_mode = 'union'
			and (
				dom.value is not null
				or dow.value is not null 
			)
		) 
		or (
			dmm.matching_mode = 'intersect'
			and (
				dom.value is not null
				and dow.value is not null 
			)
		) 
) t
join time_interval 
	on time_interval.time_from <= t.value
	and (time_interval.time_to >= t.value or time_interval.time_to is null)
$function$;		