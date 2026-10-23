# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file Discourse import script (`ipboard4.rb`) that migrates an Invision Community / IP.Board v4 MySQL database into Discourse. It is not standalone: it subclasses `ImportScripts::Base` and `require`s `base.rb` from its own directory, so it must be copied into a Discourse checkout at `script/import_scripts/ipboard4.rb` and run inside the Discourse Rails environment (`SiteSetting`, `Post`, `Topic`, `PostActionCreator`, `DiscourseTagging`, etc. all come from Discourse). There is no build, lint config, or test suite in this repo.

Run from the Discourse root (the usual way to run Discourse importers):

```
DB_HOST=localhost DB_USER=root DB_PW=... DB_NAME=... TABLE_PREFIX=ipb_ \
  bundle exec ruby script/import_scripts/ipboard4.rb
```

## Configuration that is hardcoded and must be edited per site

- `UPLOADS_DIR` — path to the IPB `uploads/` directory (avatars, attachments, `imageproxy/`, `emoticons/`).
- `about_me_column = "field_11"` in `import_users` — the `core_pfields_content` custom field holding the bio.
- `cms_custom_database_1` with `field_1`/`field_2`/`field_3` in `import_articles` — the IPB Pages database used for articles.
- Articles are only imported if a Discourse category named exactly `articles` already exists.

## Architecture

`execute` runs the phases in a fixed order; later phases depend on ID mappings created by earlier ones: users → categories → topics → posts → likes → tags → articles.

- **Imported-ID conventions** (used with `post_id_from_imported_post_id` / `topic_lookup_from_imported_post_id`): topic first posts are `"t-<tid>"`, articles are `"a-<id>"`, replies use the raw IPB `pid`. Anything that looks up a post must use the right form — e.g. likes and quote (`data-cid`) lookups use the raw pid, so they only resolve against replies, not opening posts.
- **Pagination** is keyset-based (`WHERE id > last_id ORDER BY id LIMIT BATCH_SIZE`) inside `batches`, with `offset` only used for progress reporting.
- **Re-runnable**: each phase skips records already imported (`next if ..._from_imported_..._id`), so the script can be resumed after a failure.
- **Filtering**: only approved, non-deleted, non-queued content is imported; topics with a non-zero `topic_close_time` are skipped entirely.
- **Roles**: admins come from `core_admin_permission_rows` (both group and member rows); moderators from `core_moderators` with `type = 'm'`. `temp_ban = 1` users are suspended for 100 years.
- **`clean_up(raw, user_id)`** converts IPB HTML to Markdown via Nokogiri then `ReverseMarkdown`. It rewrites IPB quotes into Discourse `[quote]` BBCode, resolves attachments from the `<___base_url___>`, `attachment.php?id=`, and `<fileStore.core_Attachment>/` URL forms plus `imageproxy`/emoticon images into Discourse uploads, converts iframes/embeds to oneboxable URLs, and drops any other `<...>`-placeholder links and unresolvable images.
  - Side effect: attachment handling **renames files on disk** inside `UPLOADS_DIR` (from the stored hashed name to the original filename) before uploading.
- **`mysql_query`** swallows `Mysql2::Error`, logs it, and returns `[]` — a broken query looks like "nothing to import" rather than a crash.
- The MySQL connection uses `character_set_results = binary`, so every string column must be explicitly `encode`d to UTF-8 (the existing code does this per field).

## Style

The file uses 4-space indentation (unlike Discourse's 2-space convention); keep it consistent with the surrounding code.
