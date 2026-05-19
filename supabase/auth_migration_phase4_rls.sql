-- ============================================================
-- M7 W Management - الترحيل لـ Supabase Auth - المرحلة 4
-- RLS Policies للإنتاج
-- ============================================================
-- شغّل هذا فقط بعد:
--   1) تشغيل auth_migration_phase1.sql
--   2) ترحيل كل الحسابات (تسجيل دخول كل مستخدم مرة)
--   3) التأكد من عمل Auth بشكل صحيح
-- ============================================================

-- ╔══════════════════════════════════════════════════════════╗
-- ║ Pattern عام:                                              ║
-- ║   - SELECT: مفتوح للمستخدم في دولته فقط                  ║
-- ║   - INSERT/UPDATE/DELETE: حسب الصلاحية                   ║
-- ║   - Super Admin يتجاوز كل شيء                            ║
-- ╚══════════════════════════════════════════════════════════╝

-- ============================================================
-- accounts
-- ============================================================
drop policy if exists "allow_all" on public.accounts;

create policy "accounts_read"
  on public.accounts for select to authenticated
  using (
    public.is_super_admin()
    or auth_user_id = auth.uid()
    or public.has_permission('admin.users.view')
  );

create policy "accounts_insert"
  on public.accounts for insert to authenticated
  with check (public.has_permission('admin.users.manage'));

create policy "accounts_update"
  on public.accounts for update to authenticated
  using (
    public.has_permission('admin.users.manage')
    or auth_user_id = auth.uid()  -- المستخدم يقدر يعدّل بياناته
  );

create policy "accounts_delete"
  on public.accounts for delete to authenticated
  using (
    public.has_permission('admin.users.manage')
    and is_super_admin = false  -- لا أحد يحذف Super Admin
  );

-- ============================================================
-- audit_logs - immutable + admins فقط يقرأون
-- ============================================================
drop policy if exists "audit_logs_read" on public.audit_logs;
drop policy if exists "audit_logs_insert" on public.audit_logs;

create policy "audit_logs_insert" on public.audit_logs
  for insert to authenticated, anon
  with check (true);

create policy "audit_logs_read" on public.audit_logs
  for select to authenticated
  using (
    public.is_super_admin()
    or public.has_permission('admin.audit.view')
  );

-- ❌ بدون UPDATE/DELETE → مرفوضة آلياً (immutable)

-- ============================================================
-- countries / cities / areas / business_types - مرجعيات (قراءة عامة)
-- ============================================================
do $$
declare t text;
begin
  for t in select unnest(array[
    'countries','cities','areas','business_types',
    'job_titles','departments','marital_statuses',
    'nationalities','visa_types'
  ]) loop
    execute format('drop policy if exists "allow_all" on public.%I', t);
    execute format('create policy "%s_read" on public.%I for select to authenticated using (true)', t, t);
    execute format('create policy "%s_write" on public.%I for all to authenticated using (public.has_permission(''settings.lookups.edit'') or public.is_super_admin()) with check (public.has_permission(''settings.lookups.edit'') or public.is_super_admin())', t, t);
  end loop;
end $$;

-- ============================================================
-- masters / points / sites - فلتر بالدولة
-- ============================================================
drop policy if exists "allow_all" on public.masters;
create policy "masters_read" on public.masters for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );
create policy "masters_write" on public.masters for all to authenticated
  using (public.has_permission('sites.edit') or public.is_super_admin())
  with check (public.has_permission('sites.create') or public.is_super_admin());

drop policy if exists "allow_all" on public.points;
create policy "points_read" on public.points for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );
create policy "points_write" on public.points for all to authenticated
  using (public.has_permission('sites.edit') or public.is_super_admin())
  with check (public.has_permission('sites.create') or public.is_super_admin());

drop policy if exists "allow_all" on public.sites;
create policy "sites_read" on public.sites for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );
create policy "sites_write" on public.sites for all to authenticated
  using (public.has_permission('sites.edit') or public.is_super_admin())
  with check (public.has_permission('sites.create') or public.is_super_admin());

-- ============================================================
-- employees - فلتر بالدولة
-- ============================================================
drop policy if exists "allow_all" on public.employees;
create policy "employees_read" on public.employees for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );
create policy "employees_insert" on public.employees for insert to authenticated
  with check (public.has_permission('employees.create'));
create policy "employees_update" on public.employees for update to authenticated
  using (public.has_permission('employees.edit'));
create policy "employees_delete" on public.employees for delete to authenticated
  using (public.has_permission('employees.delete'));

-- ============================================================
-- buses - فلتر بالدولة
-- ============================================================
drop policy if exists "allow_all" on public.buses;
create policy "buses_read" on public.buses for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );
create policy "buses_insert" on public.buses for insert to authenticated
  with check (public.has_permission('buses.create'));
create policy "buses_update" on public.buses for update to authenticated
  using (public.has_permission('buses.edit'));
create policy "buses_delete" on public.buses for delete to authenticated
  using (public.has_permission('buses.delete'));

-- ============================================================
-- weekly_rosters + roster_assignments
-- ============================================================
drop policy if exists "allow_all" on public.weekly_rosters;
create policy "rosters_read" on public.weekly_rosters for select to authenticated
  using (
    public.is_super_admin()
    or public.has_permission('rosters.view')
    or point_id = public.current_user_point_id()  -- المشرف يرى نقطته
  );
create policy "rosters_insert" on public.weekly_rosters for insert to authenticated
  with check (public.has_permission('rosters.create'));
create policy "rosters_update" on public.weekly_rosters for update to authenticated
  using (
    public.has_permission('rosters.approve')
    or (public.has_permission('rosters.create') and point_id = public.current_user_point_id())
  );
create policy "rosters_delete" on public.weekly_rosters for delete to authenticated
  using (public.is_super_admin());

drop policy if exists "allow_all" on public.roster_assignments;
create policy "roster_assignments_all" on public.roster_assignments for all to authenticated
  using (
    public.is_super_admin()
    or exists (
      select 1 from public.weekly_rosters wr
      where wr.id = roster_id
        and (
          public.has_permission('rosters.view')
          or wr.point_id = public.current_user_point_id()
        )
    )
  )
  with check (
    public.is_super_admin()
    or public.has_permission('rosters.create')
    or public.has_permission('rosters.approve')
  );

-- ============================================================
-- bus_plans + bus_plan_details
-- ============================================================
drop policy if exists "allow_all" on public.bus_plans;
create policy "bus_plans_read" on public.bus_plans for select to authenticated
  using (true);  -- مرتبط بـ details التي فيها فلترة
create policy "bus_plans_write" on public.bus_plans for all to authenticated
  using (public.has_permission('buses.assign') or public.is_super_admin())
  with check (public.has_permission('buses.assign') or public.is_super_admin());

drop policy if exists "allow_all" on public.bus_plan_details;
create policy "bus_plan_details_all" on public.bus_plan_details for all to authenticated
  using (public.has_permission('buses.assign') or public.is_super_admin())
  with check (public.has_permission('buses.assign') or public.is_super_admin());

-- ============================================================
-- camp data: rooms, room_employees, laundry_tickets, violations, morning_checklists
-- ============================================================
drop policy if exists "allow_all" on public.rooms;
create policy "rooms_read" on public.rooms for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );
create policy "rooms_write" on public.rooms for all to authenticated
  using (public.has_permission('camp.rooms.rate') or public.is_super_admin())
  with check (public.has_permission('camp.rooms.rate') or public.is_super_admin());

drop policy if exists "allow_all" on public.room_employees;
create policy "room_employees_all" on public.room_employees for all to authenticated
  using (public.has_permission('camp.rooms.view') or public.is_super_admin())
  with check (public.has_permission('camp.rooms.rate') or public.is_super_admin());

drop policy if exists "allow_all" on public.laundry_tickets;
create policy "laundry_read" on public.laundry_tickets for select to authenticated
  using (public.has_permission('camp.laundry.view') or public.is_super_admin());
create policy "laundry_write" on public.laundry_tickets for all to authenticated
  using (public.has_permission('camp.laundry.process') or public.is_super_admin())
  with check (public.has_permission('camp.laundry.process') or public.is_super_admin());

drop policy if exists "allow_all" on public.violations;
create policy "violations_read" on public.violations for select to authenticated
  using (public.has_permission('camp.violations.view') or public.is_super_admin());
create policy "violations_write" on public.violations for all to authenticated
  using (public.has_permission('camp.violations.create') or public.is_super_admin())
  with check (public.has_permission('camp.violations.create') or public.is_super_admin());

drop policy if exists "allow_all" on public.morning_checklists;
create policy "morning_checklists_read" on public.morning_checklists for select to authenticated
  using (public.has_permission('camp.checklist.view') or public.is_super_admin());
create policy "morning_checklists_write" on public.morning_checklists for all to authenticated
  using (public.has_permission('camp.checklist.create') or public.is_super_admin())
  with check (public.has_permission('camp.checklist.create') or public.is_super_admin());

-- ============================================================
-- RBAC tables: roles, permissions, role_permissions, user_roles, user_countries
-- ============================================================
drop policy if exists "allow_all" on public.roles;
create policy "roles_read" on public.roles for select to authenticated using (true);
create policy "roles_write" on public.roles for all to authenticated
  using (public.has_permission('admin.roles.manage') or public.is_super_admin())
  with check (public.has_permission('admin.roles.manage') or public.is_super_admin());

drop policy if exists "allow_all" on public.permissions;
create policy "permissions_read" on public.permissions for select to authenticated using (true);
-- لا أحد يضيف/يحذف permissions (هي ثابتة من seed)

drop policy if exists "allow_all" on public.role_permissions;
create policy "role_perms_read" on public.role_permissions for select to authenticated using (true);
create policy "role_perms_write" on public.role_permissions for all to authenticated
  using (public.has_permission('admin.roles.manage') or public.is_super_admin())
  with check (public.has_permission('admin.roles.manage') or public.is_super_admin());

drop policy if exists "allow_all" on public.user_roles;
create policy "user_roles_read" on public.user_roles for select to authenticated
  using (
    public.is_super_admin()
    or public.has_permission('admin.users.view')
    or user_id = public.current_account_id()
  );
create policy "user_roles_write" on public.user_roles for all to authenticated
  using (public.has_permission('admin.users.manage') or public.is_super_admin())
  with check (public.has_permission('admin.users.manage') or public.is_super_admin());

drop policy if exists "allow_all" on public.user_countries;
create policy "user_countries_read" on public.user_countries for select to authenticated
  using (
    public.is_super_admin()
    or public.has_permission('admin.users.view')
    or user_id = public.current_account_id()
  );
create policy "user_countries_write" on public.user_countries for all to authenticated
  using (public.has_permission('admin.users.manage') or public.is_super_admin())
  with check (public.has_permission('admin.users.manage') or public.is_super_admin());

-- ============================================================
-- Numbering: entity_numbering_rules, country_numbering_counters
-- ============================================================
drop policy if exists "allow_all" on public.entity_numbering_rules;
create policy "numbering_rules_read" on public.entity_numbering_rules for select to authenticated using (true);
create policy "numbering_rules_write" on public.entity_numbering_rules for all to authenticated
  using (public.has_permission('settings.numbering.edit') or public.is_super_admin())
  with check (public.has_permission('settings.numbering.edit') or public.is_super_admin());

drop policy if exists "allow_all" on public.country_numbering_counters;
create policy "numbering_counters_all" on public.country_numbering_counters for all to authenticated
  using (true)  -- يقرأ ويكتب الـ RPC
  with check (true);

-- ============================================================
-- التحقق
-- ============================================================
select tablename, count(*) as policy_count
from pg_policies
where schemaname = 'public'
group by tablename
order by tablename;
