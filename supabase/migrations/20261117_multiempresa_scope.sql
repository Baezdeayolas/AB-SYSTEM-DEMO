-- AB SYSTEM: primera migración de aislamiento multiempresa.
-- Aplicar únicamente en AB-SYSTEM-DEMO, nunca en el proyecto histórico de Ko'eju.
-- Requiere respaldo reciente. Ejecutar en Supabase SQL Editor y revisar el resultado.
-- La migración aborta si no existe exactamente una empresa activa para asignar los
-- registros DEMO existentes. No descuenta ni modifica inventario ni pedidos.

begin;

do $$
declare
  v_company_id uuid;
  v_company_count integer;
begin
  select count(*), (array_agg(id))[1] into v_company_count, v_company_id
  from public.companies
  where status = 'active';

  if v_company_count <> 1 then
    raise exception 'Se esperaba exactamente una empresa activa para asignar los datos actuales; se encontraron %.', v_company_count;
  end if;

  alter table public.catalog_items add column if not exists company_id uuid;
  alter table public.catalog_clients add column if not exists company_id uuid;
  alter table public.catalog_import_rows add column if not exists company_id uuid;
  alter table public.inventory_current add column if not exists company_id uuid;
  alter table public.orders add column if not exists company_id uuid;
  alter table public.seller_assignments add column if not exists company_id uuid;

  update public.catalog_items set company_id = v_company_id where company_id is null;
  update public.catalog_clients set company_id = v_company_id where company_id is null;
  update public.catalog_import_rows set company_id = v_company_id where company_id is null;
  update public.inventory_current set company_id = v_company_id where company_id is null;
  update public.orders set company_id = v_company_id where company_id is null;
  update public.seller_assignments set company_id = v_company_id where company_id is null;
end $$;

alter table public.catalog_items alter column company_id set not null;
alter table public.catalog_clients alter column company_id set not null;
alter table public.catalog_import_rows alter column company_id set not null;
alter table public.inventory_current alter column company_id set not null;
alter table public.orders alter column company_id set not null;
alter table public.seller_assignments alter column company_id set not null;

-- Reemplazar claves primarias globales por claves compuestas para permitir
-- códigos de artículo/cliente iguales en empresas diferentes.
do $$
declare
  t text;
  c record;
begin
  foreach t in array array['catalog_items','catalog_clients','catalog_import_rows','inventory_current','seller_assignments'] loop
    for c in
      select conname from pg_constraint
      where conrelid = format('public.%I', t)::regclass and contype = 'p'
    loop
      execute format('alter table public.%I drop constraint %I', t, c.conname);
    end loop;
  end loop;
end $$;

alter table public.catalog_items add constraint catalog_items_pkey primary key (company_id, code);
alter table public.catalog_clients add constraint catalog_clients_pkey primary key (company_id, code);
alter table public.catalog_import_rows add constraint catalog_import_rows_pkey primary key (company_id, import_id, catalog_type, code);
alter table public.inventory_current add constraint inventory_current_pkey primary key (company_id, id);
alter table public.seller_assignments add constraint seller_assignments_pkey primary key (company_id, user_id, seller_label);

-- La unicidad de los pedidos también debe estar limitada a cada empresa.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.orders'::regclass and contype = 'u'
  loop
    execute format('alter table public.orders drop constraint %I', c.conname);
  end loop;
end $$;
create unique index if not exists orders_company_owner_source_legacy_uidx
  on public.orders(company_id, owner_id, legacy_source, legacy_id);

-- Relaciones de pertenencia a empresa.
do $$
declare t text;
begin
  foreach t in array array['catalog_items','catalog_clients','catalog_import_rows','inventory_current','orders','seller_assignments'] loop
    if not exists (
      select 1 from pg_constraint
      where conrelid = format('public.%I',t)::regclass
        and conname = t || '_company_id_fkey'
    ) then
      execute format('alter table public.%I add constraint %I foreign key (company_id) references public.companies(id) on delete restrict',
        t, t || '_company_id_fkey');
    end if;
  end loop;
end $$;

create index if not exists company_memberships_user_status_idx
  on public.company_memberships(user_id, status);
create unique index if not exists company_memberships_company_user_uidx
  on public.company_memberships(company_id, user_id);

-- Impedir que una fila ya creada se traslade a otra empresa mediante UPDATE.
create or replace function public.ab_prevent_company_reassignment()
returns trigger
language plpgsql
set search_path = ''
as $
begin
  if old.company_id is distinct from new.company_id then
    raise exception 'No se permite cambiar la empresa propietaria del registro.';
  end if;
  return new;
end;
$;

do $
declare t text;
begin
  foreach t in array array[
    'catalog_items','catalog_clients','catalog_import_rows',
    'inventory_current','orders','seller_assignments','company_memberships'
  ] loop
    execute format('drop trigger if exists ab_company_immutable on public.%I', t);
    execute format(
      'create trigger ab_company_immutable before update of company_id on public.%I for each row execute function public.ab_prevent_company_reassignment()',
      t
    );
  end loop;
end $;

-- El acceso global se consulta mediante RPC; la tabla de roles globales no se
-- expone directamente al navegador.
create or replace function public.ab_is_global_superadmin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.global_roles gr
    where gr.user_id = (select auth.uid())
      and gr.role = 'superadmin_global'
  );
$$;
revoke all on function public.ab_is_global_superadmin() from public, anon;
grant execute on function public.ab_is_global_superadmin() to authenticated;

-- Sustituir las políticas de la etapa DEMO por políticas con ámbito de empresa.
do $$
declare t text; p record;
begin
  foreach t in array array[
    'companies','company_memberships','catalog_items','catalog_clients',
    'catalog_import_rows','inventory_current','orders','seller_assignments'
  ] loop
    for p in
      select policyname from pg_policies
      where schemaname='public' and tablename=t
    loop
      execute format('drop policy if exists %I on public.%I', p.policyname, t);
    end loop;
  end loop;
end $$;

alter table public.companies enable row level security;
alter table public.company_memberships enable row level security;
alter table public.catalog_items enable row level security;
alter table public.catalog_clients enable row level security;
alter table public.catalog_import_rows enable row level security;
alter table public.inventory_current enable row level security;
alter table public.orders enable row level security;
alter table public.seller_assignments enable row level security;

create policy companies_read_member_or_global on public.companies
for select to authenticated
using (public.ab_has_company_access(id) or public.ab_is_global_superadmin());
create policy companies_global_manage on public.companies
for all to authenticated
using (public.ab_is_global_superadmin())
with check (public.ab_is_global_superadmin());

create policy memberships_read_self_or_company_admin on public.company_memberships
for select to authenticated
using (user_id = (select auth.uid())
  or public.ab_is_company_admin(company_id)
  or public.ab_is_global_superadmin());
create policy memberships_company_admin_manage on public.company_memberships
for all to authenticated
using (public.ab_is_company_admin(company_id) or public.ab_is_global_superadmin())
with check (public.ab_is_global_superadmin() or (public.ab_is_company_admin(company_id) and (user_id <> (select auth.uid()) or role = 'seller')));

create policy items_read_company on public.catalog_items
for select to authenticated using (public.ab_has_company_access(company_id));
create policy items_admin_manage_company on public.catalog_items
for all to authenticated
using (public.ab_is_company_admin(company_id))
with check (public.ab_is_company_admin(company_id));

create policy clients_read_company on public.catalog_clients
for select to authenticated using (public.ab_has_company_access(company_id));
create policy clients_admin_manage_company on public.catalog_clients
for all to authenticated
using (public.ab_is_company_admin(company_id))
with check (public.ab_is_company_admin(company_id));

create policy inventory_read_company on public.inventory_current
for select to authenticated using (public.ab_has_company_access(company_id));
create policy inventory_admin_manage_company on public.inventory_current
for all to authenticated
using (public.ab_is_company_admin(company_id))
with check (public.ab_is_company_admin(company_id));

create policy imports_admin_manage_company on public.catalog_import_rows
for all to authenticated
using (public.ab_is_company_admin(company_id))
with check (public.ab_is_company_admin(company_id));

create policy orders_read_company on public.orders
for select to authenticated
using (owner_id = (select auth.uid()) or public.ab_is_company_admin(company_id));
create policy orders_insert_company on public.orders
for insert to authenticated
with check (owner_id = (select auth.uid()) and public.ab_has_company_access(company_id));
create policy orders_update_company on public.orders
for update to authenticated
using (owner_id = (select auth.uid()) or public.ab_is_company_admin(company_id))
with check (public.ab_has_company_access(company_id) and (owner_id = (select auth.uid()) or public.ab_is_company_admin(company_id)));
create policy orders_delete_company on public.orders
for delete to authenticated
using (owner_id = (select auth.uid()) or public.ab_is_company_admin(company_id));

create policy assignments_read_company on public.seller_assignments
for select to authenticated
using (user_id = (select auth.uid()) or public.ab_is_company_admin(company_id));
create policy assignments_admin_manage_company on public.seller_assignments
for all to authenticated
using (public.ab_is_company_admin(company_id))
with check (public.ab_is_company_admin(company_id));

commit;

-- Verificación posterior:
-- select c.name, c.code,
--   (select count(*) from public.catalog_items x where x.company_id=c.id) products,
--   (select count(*) from public.catalog_clients x where x.company_id=c.id) clients,
--   (select count(*) from public.orders x where x.company_id=c.id) orders
-- from public.companies c order by c.name;
