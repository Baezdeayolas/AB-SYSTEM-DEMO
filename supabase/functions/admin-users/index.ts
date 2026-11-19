import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Método no permitido." }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) {
      return reply({ error: "Faltan variables de entorno de Supabase." }, 500);
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return reply({ error: "Sesión no autorizada." }, 401);
    }

    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await caller.auth.getUser();
    if (authError || !authData.user) return reply({ error: "La sesión no es válida." }, 401);

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: globalRole, error: roleError } = await admin
      .from("global_roles")
      .select("role")
      .eq("user_id", authData.user.id)
      .eq("role", "superadmin_global")
      .maybeSingle();
    if (roleError) throw roleError;
    if (!globalRole) return reply({ error: "Solo el superadministrador global puede realizar esta operación." }, 403);

    const body = await req.json();
    const action = String(body.action || "");

    if (action === "list") {
      const { data: memberships, error } = await admin
        .from("company_memberships")
        .select("company_id,user_id,role,status,companies(name,code)")
        .order("created_at", { ascending: false });
      if (error) throw error;

      const userIds = [...new Set((memberships || []).map((m: any) => m.user_id))];
      const profileMap = new Map<string, any>();
      if (userIds.length) {
        const { data: profiles, error: profileError } = await admin
          .from("profiles")
          .select("id,seller_label")
          .in("id", userIds);
        if (profileError) throw profileError;
        for (const profile of profiles || []) profileMap.set(profile.id, profile);
      }

      const users: any[] = [];
      for (let page = 1; page <= 10; page++) {
        const { data, error: usersError } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
        if (usersError) throw usersError;
        users.push(...data.users);
        if (data.users.length < 1000) break;
      }
      const userMap = new Map(users.map((u: any) => [u.id, u]));
      return reply({
        memberships: (memberships || []).map((m: any) => {
          const u: any = userMap.get(m.user_id);
          const p = profileMap.get(m.user_id);
          const company = Array.isArray(m.companies) ? m.companies[0] : m.companies;
          return {
            company_id: m.company_id,
            company_name: company?.name || company?.code || "Empresa",
            user_id: m.user_id,
            email: u?.email || "",
            display_name: p?.seller_label || u?.user_metadata?.full_name || u?.email || "Usuario",
            role: m.role,
            status: m.status,
          };
        }),
      });
    }

    if (action === "create-company") {
      const name = String(body.name || "").trim();
      const code = String(body.code || "").trim().toUpperCase();
      if (!name || name.length > 120 || !/^[A-Z0-9_-]{2,24}$/.test(code)) {
        return reply({ error: "El nombre debe tener hasta 120 caracteres y el código entre 2 y 24 caracteres (A-Z, 0-9, guion o guion bajo)." }, 400);
      }
      const { data: company, error: createError } = await admin
        .from("companies")
        .insert({ name, code, status: "active" })
        .select("id,code,name,status")
        .single();
      if (createError) {
        if (createError.code === "23505") return reply({ error: "Ya existe una empresa con ese código." }, 409);
        throw createError;
      }
      return reply({ ok: true, company });
    }

    if (action === "set-company-status") {
      const companyId = String(body.companyId || "");
      const status = String(body.status || "");
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(companyId) ||
          !["active", "suspended"].includes(status)) {
        return reply({ error: "La empresa o el estado solicitado no son válidos." }, 400);
      }
      const { data: company, error: statusError } = await admin
        .from("companies")
        .update({ status })
        .eq("id", companyId)
        .select("id,code,name,status")
        .maybeSingle();
      if (statusError) throw statusError;
      if (!company) return reply({ error: "No se encontró la empresa indicada." }, 404);
      return reply({ ok: true, company });
    }

    if (action === "invite") {
      const companyId = String(body.companyId || "");
      const email = String(body.email || "").trim().toLowerCase();
      const displayName = String(body.displayName || "").trim();
      const role = String(body.role || "seller");
      if (!companyId || !/^\S+@\S+\.\S+$/.test(email) || !displayName) {
        return reply({ error: "Completá empresa, nombre y un correo válido." }, 400);
      }
      if (!["seller", "company_admin"].includes(role)) {
        return reply({ error: "El rol solicitado no está permitido." }, 400);
      }
      const { data: company, error: companyError } = await admin
        .from("companies").select("id,status").eq("id", companyId).maybeSingle();
      if (companyError) throw companyError;
      if (!company || company.status !== "active") {
        return reply({ error: "La empresa no existe o está suspendida." }, 400);
      }

      let existing: any = null;
      for (let page = 1; page <= 10 && !existing; page++) {
        const { data, error: listError } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
        if (listError) throw listError;
        existing = data.users.find((u: any) => String(u.email || "").toLowerCase() === email) || null;
        if (data.users.length < 1000) break;
      }

      let invited = false;
      let targetUser = existing;
      if (!targetUser) {
        const { data, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
          data: { full_name: displayName, seller_label: displayName },
        });
        if (inviteError) throw inviteError;
        targetUser = data.user;
        invited = true;
      }
      if (!targetUser?.id) throw new Error("Supabase no devolvió el usuario creado.");

      const { data: existingProfile, error: profileLookupError } = await admin
        .from("profiles").select("id,role").eq("id", targetUser.id).maybeSingle();
      if (profileLookupError) throw profileLookupError;
      if (existingProfile) {
        const { error: profileUpdateError } = await admin.from("profiles")
          .update({ seller_label: displayName }).eq("id", targetUser.id);
        if (profileUpdateError) throw profileUpdateError;
      } else {
        const { error: profileInsertError } = await admin.from("profiles").insert({
          id: targetUser.id,
          role: "seller",
          seller_label: displayName,
        });
        if (profileInsertError) throw profileInsertError;
      }

      // The requester's global-superadmin role was verified above. Use the
      // service client here so the membership write is not dependent on
      // browser-session RLS state after an auth invitation was created.
      const { error: membershipError } = await admin.from("company_memberships").upsert({
        company_id: companyId,
        user_id: targetUser.id,
        role,
        status: "active",
      }, { onConflict: "company_id,user_id" });
      if (membershipError) throw membershipError;
      return reply({ ok: true, invited, userId: targetUser.id });
    }

    if (action === "remove-membership") {
      const companyId = String(body.companyId || "");
      const userId = String(body.userId || "");
      const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      if (!uuidPattern.test(companyId) || !uuidPattern.test(userId)) {
        return reply({ error: "La empresa o el usuario indicados no son válidos." }, 400);
      }
      const { data: target, error: targetError } = await admin
        .from("company_memberships").select("role,status")
        .eq("company_id", companyId).eq("user_id", userId).maybeSingle();
      if (targetError) throw targetError;
      if (!target) return reply({ error: "La membresía ya no existe." }, 404);
      if (target.role === "company_admin" && target.status === "active") {
        const { count, error: countError } = await admin
          .from("company_memberships").select("user_id", { count: "exact", head: true })
          .eq("company_id", companyId).eq("role", "company_admin").eq("status", "active");
        if (countError) throw countError;
        if ((count || 0) <= 1) return reply({ error: "No se puede quitar al último administrador activo de la empresa." }, 409);
      }
      const { error: deleteError } = await admin.from("company_memberships")
        .delete().eq("company_id", companyId).eq("user_id", userId);
      if (deleteError) throw deleteError;
      return reply({ ok: true });
    }

    if (action === "update-membership") {
      const companyId = String(body.companyId || "");
      const userId = String(body.userId || "");
      const role = String(body.role || "");
      const status = String(body.status || "");
      if (!companyId || !userId || !["seller", "company_admin"].includes(role) ||
          !["active", "suspended"].includes(status)) {
        return reply({ error: "Los datos de membresía no son válidos." }, 400);
      }
      const { data: current, error: currentError } = await admin.from("company_memberships")
        .select("role,status").eq("company_id", companyId).eq("user_id", userId).maybeSingle();
      if (currentError) throw currentError;
      if (!current) return reply({ error: "La membresía ya no existe." }, 404);
      if (current.role === "company_admin" && current.status === "active" &&
          (role !== "company_admin" || status !== "active")) {
        const { count, error: countError } = await admin
          .from("company_memberships").select("user_id", { count: "exact", head: true })
          .eq("company_id", companyId).eq("role", "company_admin").eq("status", "active");
        if (countError) throw countError;
        if ((count || 0) <= 1) return reply({ error: "La empresa debe conservar al menos un administrador activo." }, 409);
      }
      // Preserve the authenticated superadmin JWT for the database trigger.
      // The trigger validates auth.uid() and the caller's global role.
      const { error } = await caller.from("company_memberships")
        .update({ role, status }).eq("company_id", companyId).eq("user_id", userId);
      if (error) throw error;
      return reply({ ok: true });
    }

    return reply({ error: "Acción no reconocida." }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Error interno.";
    return reply({ error: message }, 400);
  }
});
