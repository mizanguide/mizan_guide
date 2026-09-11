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

## UTM tagging, locked 2026-09-11

**Every link posted anywhere other than the Instagram bio must carry UTM parameters**, so GA4
and `mizan_events`/`mizan_leads` (both now capture the full query string in `source_path`, not
just the bare path) can attribute a visit to the exact piece of content that drove it, not just
"direct." Without this, GA can only ever show generic events (page_view, section_view, scroll)
with no way to tell which reel, Story, or post a given session came from.

**Format:** `https://mizanguide.github.io/mizan_guide/?utm_source=instagram&utm_medium=<type>&utm_campaign=<YYYY-MM-DD_slug>`

- `utm_source` — always `instagram` unless it's Substack (`substack`) or a direct DM (`dm`).
- `utm_medium` — `story`, `reel`, `post`, or `email` (Substack).
- `utm_campaign` — the topic folder's own date+slug, e.g. `2026-09-11_followerstory`, so it maps
  straight back to the `Animations/` or `CaseStudies/` folder that produced it.

**Where this applies:** any Story link sticker, any Substack post link, any direct DM link. It
does NOT apply to the static Instagram bio link (reels only ever say "link in bio," they can't
carry a per-reel tag) — that one link stays fixed as
`?utm_source=instagram&utm_medium=bio` permanently, so bio-driven traffic is at least
distinguishable from Story/Substack/DM traffic, even without per-reel attribution.

Query the real numbers with `select event_type, source_path, count(*) from mizan_events group by
1, 2 order by 3 desc;` against the anon-readable `mizan_events` table, never trust a screenshot
of the GA4 realtime view for anything beyond a quick sanity check, GA4 doesn't expose per-campaign
funnel counts as easily as a direct SQL query does.

## The form is a stepped quiz, shipped 2026-09-12

Same six fields, same ids, same Supabase payload and EmailJS template, different shape: one
question per screen, tap-to-answer buttons for timing/duration/tried (with a "Something else"
text fallback), the two free-text questions optional, and the Instagram handle asked LAST, after
five answers are already in. The quiz sits directly under the hero; the proof card and the $5
line moved below it. Reason: two days of real funnel data showed the page converting 12.5% of
visits but half of visitors never scrolling to a form whose first field was their Instagram
handle under a page that says "porn." Every step fires a `quiz_step` event (`meta.step`,
`meta.field`, `meta.answered`) so drop-off per question is visible; `form_start` fires on the
first tap. Judge it on visit-to-submit rate after 2026-09-12 versus the 12.5% before.

## On-page event granularity, locked 2026-09-11

Beyond `page_view`, `section_view` (fires once per section: `proof-section`, `offer-section`,
`cta-section`), `form_start`, `form_submit_success`/`form_submit_error`, and
`outbound_dm_click`, the page also fires `scroll_depth` at four real checkpoints (25/50/75/100%
of actual page height), each once, replacing GA4's own single generic "90% scrolled" auto-event.
This answers "how far did they actually get before leaving" with real resolution instead of one
yes/no signal.

## What NOT to put in this repo

Never commit the Supabase `service_role` / secret key anywhere in this folder. It grants full
database access and this repo is public. The anon key and the EmailJS public key are both safe
by design (insert-only / template-locked respectively), the Supabase secret key is not.
