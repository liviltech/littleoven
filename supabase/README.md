# Little Oven Supabase setup

The customer app and manager console use the Supabase project configured in `../supabase-config.js`. That file contains the public anon key, which is intended for browser use. Never put a service-role or secret key in the website.

## Activate the database

1. Open the Supabase project and go to **SQL Editor**.
2. Open [schema.sql](./schema.sql), copy the full file, paste it into a new SQL query, and run it.
3. In **Authentication → Users**, create the Little Oven manager account. Copy its user UUID.
4. In SQL Editor, give that account manager access:
   ```sql
   insert into public.manager_roles(user_id) values ('PASTE_MANAGER_USER_UUID');
   ```
5. In **Authentication → URL Configuration**, set the Site URL to:
   `https://liviltech.github.io/littleoven/`
   Add that same URL to the Redirect URLs list.
6. Open [the manager console](https://liviltech.github.io/littleoven/admin.html) and sign in with the manager account.

The member app uses email and password for Supabase Auth. Members can create accounts from the site; birthday vouchers are generated automatically during the member's birthday month. Manager-issued messages appear in the member's **Messages** menu.

## Manager tools

The manager console supports member search, status changes, point adjustments with a transaction record, voucher generation for one or all active members, promotions, direct in-app messages, and CSV reports for all members, active members, and birthday members.

Birthday vouchers give RM20 off an 8-inch or 10-inch whole cake. Members walk in and show the voucher at the counter to claim it. The voucher is generated once per member per calendar year and follows Malaysia time.

## Existing browser data

Old preview accounts, points, and activity stored in browsers are not automatically copied into Supabase. New member signups and data created after the database setup are stored centrally. Existing real member records need to be entered or imported into the Supabase project separately.
