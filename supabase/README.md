# Little Oven Supabase setup

The customer app and manager console use the Supabase project configured in `../supabase-config.js`. That file contains the public anon key, which is intended for browser use. Never put the service-role key in the website.

## Activate the database

1. Open the Supabase project and go to **SQL Editor**.
2. Open [schema.sql](./schema.sql), copy the full file, paste it into a new SQL query, and run it. If you already ran an earlier version, run the current full file again; it creates the new member-management RPCs and is written to be repeatable.
3. In **Authentication → Users**, create the Little Oven manager account. Copy its user UUID.
4. In SQL Editor, give that account manager access:
   ```sql
   insert into public.manager_roles(user_id) values ('MANAGER_USER_UUID');
   ```
5. In **Authentication → URL Configuration**, set the Site URL to:
   `https://liviltech.github.io/littleoven/`
   Add that same URL to the Redirect URLs list.
6. Open [the manager console](https://liviltech.github.io/littleoven/admin.html) and sign in with the manager account.

## Deploy the secure manager member function

Creating a member account or changing the account email requires Supabase Auth's server-side admin API. The site calls the Edge Function source at [manager-members](./functions/manager-members/index.ts); the service-role key stays in Supabase's function environment and is never put in GitHub or the browser.

In your Supabase project:

1. Open **Edge Functions → Deploy a new function → Via Editor** and create a function named `manager-members`.
2. Replace the starter code with the full contents of [index.ts](./functions/manager-members/index.ts), then deploy it.
3. Keep the function's JWT verification enabled. The function also checks the caller's manager role before performing any action.

The platform provides `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions as a server-side environment variable. Do not paste it into this repository, the browser config, or this chat.

The **Members** page can then invite a new member by email and edit a member's name, email, phone, sex, and birthday. Invitations are delivered by Supabase Auth email. Point adjustments and status changes use protected database functions.

## Manager tools

The manager console supports member search, status changes, point adjustments with a transaction record, voucher generation for one or all active members, promotions, direct in-app messages, and CSV reports for all members, active members, and birthday members.

Birthday vouchers give RM20 off an 8-inch or 10-inch whole cake. Members walk in and show the voucher at the counter to claim it. The voucher is generated once per member per calendar year and follows Malaysia time.

## Existing browser data

Old preview accounts, points, and activity stored in browsers are not automatically copied into Supabase. New member signups and data created after the database setup are stored centrally. Existing real member records need to be entered or imported into the Supabase project separately.
