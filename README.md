# Mizan landing page

Single static HTML file, no build step, no framework. `index.html` is the whole site.

## Live, and already CI/CD

**Live at https://qureshi08.github.io/Mizan.Guide/.** GitHub Pages is on (enabled 2026-09-07).
This already IS the CI/CD: every `git push` to `main` triggers GitHub's own build and redeploy
automatically, nothing separate to configure, no Actions workflow needed for a static file like
this. Put the live URL in the Instagram bio link.

## The form / funnel

The intake form posts directly to Supabase using the public anon key, safe to expose because it
can only INSERT rows (see `supabase_setup.sql`). **Still needs one manual step, blocked on this
end for real:** the anon/service_role keys can write rows to an existing table but cannot create
one, that needs either your database password (Project Settings > Database > Connection string)
or a personal access token (Account > Access Tokens, starts with `sbp_`), neither of which were
provided. Until then:

1. Open your Supabase project > SQL Editor > New query.
2. Paste the entire contents of `supabase_setup.sql` and run it once.
3. Submissions land in Table Editor > `mizan_leads`. Nobody but you (logged into Supabase) can
   read them, the anon key is insert-only.

## Email notification on every new submission (added 2026-09-07)

The form also fires an email via EmailJS (client-side, no backend, free tier up to 200/month) the
moment someone submits, so you don't have to keep checking the Supabase table manually. **Three
values in `index.html` need filling in** (currently blank, form still works and still saves to
Supabase without them, you just won't get emailed):

1. Sign up free at emailjs.com (about 2 minutes, no card).
2. Email Services > Add New Service > connect your Gmail (or any inbox) > copy the **Service ID**.
3. Email Templates > Create New Template. Build it however you like using these variables:
   `{{instagram}}`, `{{email}}`, `{{struggle}}`, `{{timing}}`, `{{duration}}`, `{{tried}}`,
   `{{more}}`. Copy the **Template ID**.
4. Account > General > copy the **Public Key**.
5. Open `index.html`, find `EMAILJS_PUBLIC_KEY` / `EMAILJS_SERVICE_ID` / `EMAILJS_TEMPLATE_ID`
   near the top of the `<script>` block, paste the three values in, commit, push. Done, live
   within the minute since Pages redeploys automatically.

## What NOT to put in this repo

Never commit the Supabase `service_role` / secret key anywhere in this folder. It grants full
database access and this repo is public. The anon key and the EmailJS public key are both safe
by design (insert-only / template-locked respectively), the Supabase secret key is not.
