# Little Oven manager backend (Supabase)

The customer site currently runs on GitHub Pages. This folder prepares a Supabase database with row-level security for member profiles, point changes, promotions, vouchers, and in-app messages.

## Setup

1. Create a Supabase project.
2. Run \`schema.sql\` in the Supabase SQL Editor.
3. In Supabase Authentication, create the first manager account.
4. Copy that account's user UUID from Authentication → Users, then run:
   \`\`\`sql
   insert into public.manager_roles(user_id) values ('AUTH_USER_UUID');
   \`\`\`
5. Put your project URL and **public anon/publishable key** in \`../supabase-config.js\`.
6. Open \`/admin.html\` and sign in with the manager account.

Do not put a service-role key in the site. RLS and manager-checked SQL functions protect privileged operations.

## Current scope

The schema and manager console are the backend foundation. To activate real member operations, the member app must use Supabase Auth and persist member data in these tables; the current Pages preview keeps accounts and points in browser storage. Existing browser-only demo accounts are not imported automatically. Member app integration and migration require the project URL/key and an agreed import of any real member data.
