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

      const { error: profileError } = await admin.from("profiles").upsert({
        id: targetUser.id,
        role: role === "company_admin" ? "admin" : "seller",
        seller_label: displayName,
      }, { onConflict: "id" });
      if (profileError) throw profileError;

      const { error: membershipError } = await caller.from("company_memberships").upsert({
        company_id: companyId,
        user_id: targetUser.id,
        role,
        status: "active",
      }, { onConflict: "company_id,user_id" });
      if (membershipError) throw membershipError;
      return reply({ ok: true, invited, userId: targetUser.id });
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
