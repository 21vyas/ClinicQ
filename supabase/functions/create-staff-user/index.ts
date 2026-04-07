// Supabase Edge Function: create-staff-user
// Creates a new Supabase auth user + adds them to hospital_users.
// Only callable by hospital admins. Enforces max 5 staff per hospital.

import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Max-Age': '86400',
}

const MAX_STAFF = 5

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ error: 'Missing authorization' }, 401)

    // ── Caller client (RLS-enforced, uses caller's JWT) ──────
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )

    // ── Admin client (service role, bypasses RLS) ────────────
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { hospital_id, email, password, full_name, role = 'staff' } =
      await req.json()

    // Validate inputs
    if (!hospital_id || !email || !password) {
      return jsonResponse({ error: 'hospital_id, email, and password are required' }, 400)
    }
    if (!['admin', 'staff'].includes(role)) {
      return jsonResponse({ error: 'role must be admin or staff' }, 400)
    }
    if (password.length < 6) {
      return jsonResponse({ error: 'Password must be at least 6 characters' }, 400)
    }

    // ── 1. Verify caller is a hospital admin ─────────────────
    const { data: myHospital, error: hospitalErr } =
      await callerClient.rpc('get_my_hospital')

    if (hospitalErr || !myHospital) {
      return jsonResponse({ error: 'UNAUTHORIZED: Could not verify your hospital' }, 403)
    }
    if (myHospital.id !== hospital_id) {
      return jsonResponse({ error: 'UNAUTHORIZED: Hospital mismatch' }, 403)
    }
    if (myHospital.my_role !== 'admin') {
      return jsonResponse({ error: 'UNAUTHORIZED: Only admins can create staff accounts' }, 403)
    }

    // ── 2. Check staff count limit ───────────────────────────
    const { count: staffCount, error: countErr } = await adminClient
      .from('hospital_users')
      .select('*', { count: 'exact', head: true })
      .eq('hospital_id', hospital_id)
      .eq('role', 'staff')
      .eq('is_active', true)

    if (countErr) return jsonResponse({ error: countErr.message }, 500)

    if ((staffCount ?? 0) >= MAX_STAFF) {
      return jsonResponse({
        error: `LIMIT_REACHED: Maximum ${MAX_STAFF} active staff accounts allowed per hospital`,
        limit: MAX_STAFF,
        current: staffCount,
      }, 400)
    }

    // ── 3. Create the auth user ──────────────────────────────
    const { data: authData, error: authErr } =
      await adminClient.auth.admin.createUser({
        email: email.trim().toLowerCase(),
        password,
        user_metadata: { full_name: full_name?.trim() ?? '' },
        email_confirm: true, // auto-confirm so they can log in immediately
      })

    if (authErr) {
      if (authErr.message.toLowerCase().includes('already been registered') ||
          authErr.message.toLowerCase().includes('already exists')) {
        return jsonResponse({ error: 'EMAIL_EXISTS: An account with this email already exists' }, 400)
      }
      return jsonResponse({ error: authErr.message }, 400)
    }

    const newAuthId = authData.user.id

    // ── 4. Ensure public.users row exists ────────────────────
    // The handle_new_user trigger fires async — upsert to be safe.
    const { data: userRow, error: upsertErr } = await adminClient
      .from('users')
      .upsert({
        auth_id:   newAuthId,
        email:     email.trim().toLowerCase(),
        full_name: full_name?.trim() ?? '',
      }, { onConflict: 'auth_id' })
      .select('id')
      .single()

    if (upsertErr || !userRow) {
      return jsonResponse({ error: 'Failed to create user profile: ' + upsertErr?.message }, 500)
    }

    // ── 5. Get caller's user id for invited_by ───────────────
    const { data: { user: callerAuth } } = await callerClient.auth.getUser()
    const { data: callerRow } = await adminClient
      .from('users')
      .select('id')
      .eq('auth_id', callerAuth?.id ?? '')
      .maybeSingle()

    // ── 6. Add to hospital_users ─────────────────────────────
    const { error: huErr } = await adminClient
      .from('hospital_users')
      .insert({
        hospital_id,
        user_id:    userRow.id,
        role,
        is_active:  true,
        invited_by: callerRow?.id ?? null,
      })

    if (huErr) {
      if (huErr.code === '23505') {
        return jsonResponse({ error: 'ALREADY_MEMBER: This user is already in your hospital' }, 400)
      }
      return jsonResponse({ error: huErr.message }, 500)
    }

    return jsonResponse({
      success:   true,
      user_id:   userRow.id,
      email:     email.trim().toLowerCase(),
      full_name: full_name?.trim() ?? '',
      role,
    })
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500)
  }
})
