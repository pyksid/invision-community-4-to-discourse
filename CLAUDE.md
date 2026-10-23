# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file Discourse import script (`ipboard4.rb`) that migrates an Invision Community / IP.Board v4 MySQL database into Discourse. It is not standalone: it subclasses `ImportScripts::Base` and `require`s `base.rb` from its own directory, so it must be copied into a Discourse checkout at `script/import_scripts/ipboard4.rb` and run inside the Discourse Rails environment (`SiteSetting`, `Post`, `Topic`, `PostActionCreator`, `DiscourseTagging`, etc. all come from Discourse). There is no build, lint config, or test suite in this repo; `ruby -c ipboard4.rb` is the only check that works outside Discourse.

Run from the Discourse root. `IMPORT=1` is required so Bundler loads the `:import` Gemfile group (`mysql2`, `reverse_markdown`):

```
IMPORT=1 bundle install
DB_HOST=localhost DB_USER=root DB_PW=... DB_NAME=... TABLE_PREFIX=ips_ \
  IMPORT=1 bundle exec ruby script/import_scripts/ipboard4.rb
```

## Configuration that is hardcoded and must be edited per site

- `UPLOADS_DIR` — path to the IPB `uploads/` directory (avatars, attachments, `imageproxy/`, `emoticons/`).
- `about_me_column = "field_1"` in `import_users` — the `core_pfields_content` custom field holding the bio (map `pf_id` → label via `core_sys_lang_words` key `core_pfield_<id>`).
- `ADMIN_GROUP_IDS` — IPB groups whose members become Discourse admins.
- `REACTION_EMOJIS` / `REACTIONS_EXCLUDED_FROM_LIKE` — IPB reaction ids (`core_reactions`, labels in `reaction_title_<id>`) mapped to Discourse emojis.
- `cms_custom_database_1` with `field_1`/`field_2`/`field_3` in `import_articles` — the IPB Pages database used for articles.
- Articles are only imported if a Discourse category named exactly `articles` already exists.

## Architecture

`execute` runs the phases in a fixed order; later phases depend on ID mappings created by earlier ones: users → categories → topics → posts → reactions → tags → articles.

- **Imported-ID conventions**: topic first posts are `"t-<tid>"`, articles are `"a-<id>"`, replies use the raw IPB `pid`. Anything holding a raw IPB pid (likes' `type_id`, quotes' `data-cid`) must resolve it with `post_id_from_imported_pid`, which falls back to `"t-<tid>"` for opening posts; `post_id_from_imported_post_id` alone only matches replies. For topic ids use `topic_lookup_from_imported_post_id("t-<tid>")[:topic_id]`, not the first post's id.
- **Pagination** is keyset-based (`WHERE id > last_id ORDER BY id LIMIT BATCH_SIZE`) inside `batches`, with `offset` only used for progress reporting.
- **Re-runnable**: each phase skips records already imported (`next if ..._from_imported_..._id`), so the script can be resumed after a failure.
- **Users**: only members with forum posts, reactions or private messages are imported, plus staff (`active_member_condition`); the rest are inactive or spam accounts.
- **Categories**: names/descriptions use the default language (`core_sys_lang.lang_default`); `core_sys_lang_words` has one row per language. IPB root categories (`parent_id = -1`) are dropped, their forums become top-level categories and sub-forums become subcategories.
- **Filtering**: topics need `approved = 1`; posts need `pdelete_time = 0` and `queued = 0` (IPB4's visibility flag for posts); articles need `record_approved = 1`. Topics are imported open on purpose (IPB had auto-locked almost all of them); Pages articles take their closed state from `record_locked`. `topic_close_time` is only a scheduled auto-close and is not used.
- **Roles**: admins are members of `ADMIN_GROUP_IDS` plus member rows of `core_admin_permission_rows`; moderators are members of moderator groups/members in `core_moderators` and of other ACP groups. Group membership includes secondary groups (`mgroup_others`). `temp_ban` is `-1` for a permanent ban (suspended 100 years) or an unban timestamp (suspended until then if still in the future).
- **Reactions** only read `core_reputation_index` rows with `app = 'forums' AND type = 'pid'` (other content types reuse `type_id` for unrelated ids) and go through the discourse-reactions plugin: `heart` is a plain like, other emojis get a `DiscourseReactions::ReactionUser` plus a like unless excluded. `import_reactions` writes the records directly instead of `ReactionManager#toggle!` to avoid notifications. `rep_rating` is not used: neutral reactions such as J'aime have `rep_rating = 0`.
- **`clean_up(raw, user_id)`** converts IPB HTML to Markdown via Nokogiri then `ReverseMarkdown`. It rewrites IPB quotes into Discourse `[quote]` BBCode, resolves attachments (`<___base_url___>…module=attach`, `attachment.php?id=`, `<fileStore.core_Attachment>/`) and `imageproxy`/emoticon images into Discourse uploads, converts iframes/embeds to oneboxable URLs, and drops other `<...>`-placeholder links. Local images whose file is missing are removed; external `http(s)` images are kept as-is.
- **Attachments** are uploaded from their hashed `attach_location` path with the original `attach_file` name passed separately (`upload_attachment`); files in `UPLOADS_DIR` are never modified.
- **`mysql_query`** swallows `Mysql2::Error`, logs it, and returns `[]`; use `mysql_count` for `COUNT(*)` queries so a missing table yields 0 instead of a crash.
- The MySQL connection uses `character_set_results = binary`, so every string column must be explicitly `encode`d to UTF-8 (the existing code does this per field).

## Style

The file uses 4-space indentation (unlike Discourse's 2-space convention); keep it consistent with the surrounding code.
