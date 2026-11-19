-- Disposable PostgreSQL 17 fixture. Never run against hosted or production databases.
DO $roles$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $roles$;
DO $roles$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $roles$;
CREATE TABLE public.companies (
  id uuid PRIMARY KEY,
  code text NOT NULL UNIQUE,
  name text NOT NULL DEFAULT 'Integration fixture',
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended'))
);
CREATE TABLE public.company_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  user_id uuid NOT NULL,
  role text NOT NULL CHECK (role IN ('company_admin', 'seller')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended'))
);
CREATE FUNCTION public.ab_test_membership_identity_guard()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN RETURN NEW; END;
$function$;
CREATE TRIGGER trg_company_memberships_guard_identity
BEFORE UPDATE ON public.company_memberships
FOR EACH ROW EXECUTE FUNCTION public.ab_test_membership_identity_guard();
INSERT INTO public.companies (id, code)
VALUES ('10000000-0000-4000-8000-000000000001', 'BOOTSTRAP');
INSERT INTO public.company_memberships (company_id, user_id, role, status) VALUES
('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'company_admin', 'active'),
('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', 'company_admin', 'active');
