create or replace function trf_scheduled_task_before_update()
returns trigger
language plpgsql
as $$
begin
	new.is_built = false;
	
	return new;
end
$$;			
