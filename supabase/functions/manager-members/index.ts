import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://liviltech.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function validBirthday(value: unknown): string | null {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error("Birthday must use YYYY-MM-DD format.");
  }
  const parsed = new Date(value + "T12:00:00Z");
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw new Error("Enter a valid birthday.");
  }
  return value;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response({ error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authHeader = req.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !serviceKey || !authHeader) {
    return response({ error: "Manager member function is not configured." }, 500);
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: authError } = await caller.auth.getUser();
  if (authError || !userData.user) return response({ error: "Sign in required." }, 401);

  const { data: manager, error: managerError } = await caller.rpc("current_user_is_manager");
  if (managerError || manager !== true) return response({ error: "Manager access required." }, 403);

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return response({ error: "Invalid JSON request." }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    if (input.action === "create") {
      const email = String(input.email || "").trim().toLowerCase();
      const fullName = String(input.full_name || "").trim();
      const phone = String(input.phone || "").trim();
      const sex = String(input.sex || "").trim();
      const birthday = validBirthday(input.birthday);
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("Enter a valid email address.");
      if (!fullName) throw new Error("Full name is required.");

      const password = String(input.password || "");
      if (password.length < 8) throw new Error("Initial password must be at least 8 characters.");

      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, phone, sex, birthday },
      });
      if (error) throw error;
      return response({ user_id: data.user.id, message: "Member account created and active. No verification email was sent. Share the initial password directly with the member." });
    }

    if (input.action === "update") {
      const memberId = String(input.member_id || "");
      const fullName = String(input.full_name || "").trim();
      const phone = String(input.phone || "").trim();
      const sex = String(input.sex || "").trim();
      const birthday = validBirthday(input.birthday);
      const email = String(input.email || "").trim().toLowerCase();
      if (!memberId || !fullName) throw new Error("Member and full name are required.");

      const { error: profileError } = await caller.rpc("manager_update_member_profile", {
        p_member_id: memberId,
        p_full_name: fullName,
        p_phone: phone,
        p_sex: sex,
        p_birthday: birthday,
      });
      if (profileError) throw profileError;

      const { data: existing, error: lookupError } = await admin.auth.admin.getUserById(memberId);
      if (lookupError) throw lookupError;
      const nextEmail = email || existing.user.email || "";
      const { error: updateError } = await admin.auth.admin.updateUserById(memberId, {
        email: nextEmail,
        user_metadata: { ...existing.user.user_metadata, full_name: fullName, phone, sex, birthday },
      });
      if (updateError) throw updateError;
      return response({ message: "Member details updated. Supabase may ask the member to confirm an email change." });
    }

    return response({ error: "Unknown action." }, 400);
  } catch (error) {
    return response({ error: error instanceof Error ? error.message : String(error) }, 400);
  }
});
