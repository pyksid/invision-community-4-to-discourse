# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file Discourse import script (`ipboard4.rb`) that migrates an Invision Community / IP.Board v4 MySQL database into Discourse. It is not standalone: it subclasses `ImportScripts::Base` and `require`s `base.rb` from its own directory, so it must be copied into a Discourse checkout at `script/import_scripts/ipboard4.rb` and run inside the Discourse Rails environment (`SiteSetting`, `Post`, `Topic`, `PostActionCreator`, `DiscourseTagging`, etc. all come from Discourse). There is no build, lint config, or test suite in this repo; `ruby -c ipboard4.rb` is the only check that works outside Discourse.

Run from the Discourse root. `IMPORT=1` is required so Bundler loads the `:import` Gemfile group (`mysql2`, `reverse_markdown`):

```
IMPORT=1 bundle install
DB_HOST=localhost DB_PORT=3306 DB_USER=root DB_PW=... DB_NAME=... TABLE_PREFIX=ips_ \
  IMPORT=1 bundle exec ruby script/import_scripts/ipboard4.rb
```

Pitfalls seen when running it (Discourse dev container, late 2026):

- In a Discourse **development** environment, set `RAILS_DISABLE_ACTIVERECORD_LOGS=1` and `DISCOURSE_DEV_LOG_LEVEL=warn`: dev SQL logging makes Logster keep a ~14 KB backtrace per log line in memory (RSS +20 MB/min, OOM-killed after a few hours) and triples import time. Production does not log SQL. Also preload jemalloc (`LD_PRELOAD=/usr/lib/libjemalloc.so`) as Discourse's `d/exec` does; with both, RSS stays ~600 MB at ~1000 posts/min.
- The import is resumable (every phase skips imported records), so wrapping it in a loop that re-runs it until it exits 0 is a safe guard against crashes.
- `IMPORT=1 bundle install` can fail because Discourse's `Gemfile` declares `sqlite3` twice with different requirements (the `IMPORT` block vs `:generic_import`); align the requirement locally.
- Starting the Discourse server without `IMPORT=1` rewrites `Gemfile.lock` without the import gems; start it with `IMPORT=1` too, or run `IMPORT=1 bundle install` again before the next import.
- `mysql2` needs the MySQL/MariaDB client headers (`apt-get install default-libmysqlclient-dev`) in the container.

## Configuration that is hardcoded and must be edited per site

- `UPLOADS_DIR` (or the `UPLOADS_DIR` env var) — path to the IPB `uploads/` directory (avatars, attachments, `imageproxy/`, `emoticons/`, rank icons).
- `about_me_column = "field_1"` in `import_users` — the `core_pfields_content` custom field holding the bio (map `pf_id` → label via `core_sys_lang_words` key `core_pfield_<id>`).
- `ADMIN_GROUP_IDS` — IPB groups whose members become Discourse admins.
- `REACTION_EMOJIS` / `REACTIONS_EXCLUDED_FROM_LIKE` — IPB reaction ids (`core_reactions`, labels in `reaction_title_<id>`) mapped to Discourse emojis.
- `BLOG_CATEGORY_NAME` — category receiving the IPB blog entries.
- `SOLVED_TAG` — tag given to every solved topic.
- `OLD_BASE_URLS` — hosts/path prefixes the forum was served from, so absolute links to them are treated like `<___base_url___>` links.
- `cms_custom_database_1` with `field_1`/`field_2`/`field_3` in `import_articles` — the IPB Pages database used for articles.
- Articles are only imported if a Discourse category named exactly `articles` already exists.

## Architecture

`execute` runs the phases in a fixed order; later phases depend on ID mappings created by earlier ones: users → avatars → password hashes → categories → topics → posts → blog entries → blog comments → reactions → tags → solved → follows → articles → private messages → message replies → PM participant sync → internal link fix → ranks → permalinks.

- **Imported-ID conventions**: topic first posts are `"t-<tid>"`, articles are `"a-<id>"`, blog entries `"b-<entry_id>"` and blog comments `"bc-<comment_id>"`, replies use the raw IPB `pid`, private conversations are `"pm-t-<mt_id>"` and their replies `"pm-<msg_id>"`. Anything holding a raw IPB pid (likes' `type_id`, quotes' `data-cid`) must resolve it with `post_id_from_imported_pid`, which falls back to `"t-<tid>"` for opening posts; `post_id_from_imported_post_id` alone only matches replies. For topic ids use `topic_lookup_from_imported_post_id("t-<tid>")[:topic_id]`, not the first post's id.
- **Pagination** is keyset-based (`WHERE id > last_id ORDER BY id LIMIT BATCH_SIZE`) inside `batches`, with `offset` only used for progress reporting.
- **Re-runnable**: each phase skips records already imported (`next if ..._from_imported_..._id`), so the script can be resumed after a failure.
- **Users**: only members with forum posts, blog entries/comments, reactions or private messages are imported, plus staff (`active_member_condition`); the rest are inactive or spam accounts.
- **Categories**: names/descriptions use the default language (`core_sys_lang.lang_default`); `core_sys_lang_words` has one row per language. IPB root categories (`parent_id = -1`) are dropped, their forums become top-level categories and sub-forums become subcategories. Forums whose `core_permission_index.perm_view` lists only staff groups (`staff_group_ids`) become categories restricted to Discourse's `staff` group.
- **Filtering**: topics need `approved = 1`; posts need `pdelete_time = 0` and `queued = 0` (IPB4's visibility flag for posts); articles need `record_approved = 1`. Topics are imported open on purpose (IPB had auto-locked almost all of them); Pages articles take their closed state from `record_locked`. `topic_close_time` is only a scheduled auto-close and is not used.
- **Roles**: admins are members of `ADMIN_GROUP_IDS` plus member rows of `core_admin_permission_rows`; moderators are members of moderator groups/members in `core_moderators` and of other ACP groups. Group membership includes secondary groups (`mgroup_others`). `temp_ban` is `-1` for a permanent ban (suspended 100 years) or an unban timestamp (suspended until then if still in the future).
- **Reactions** only read `core_reputation_index` rows with `app = 'forums' AND type = 'pid'` (other content types reuse `type_id` for unrelated ids) and go through the discourse-reactions plugin: `heart` is a plain like, other emojis get a `DiscourseReactions::ReactionUser` plus a like unless excluded. `import_reactions` writes the records directly instead of `ReactionManager#toggle!` to avoid notifications. `rep_rating` is not used: neutral reactions such as J'aime have `rep_rating = 0`.
- **`clean_up(raw, user_id)`** converts IPB HTML to Markdown via Nokogiri then `ReverseMarkdown`, for forum posts and private messages alike. Discourse-specific output goes through `placeholder` so ReverseMarkdown neither escapes nor reflows it; anything inserted into the DOM that must survive verbatim (BBCode, `@username`, `:emoji:`, upload markdown, onebox URLs) has to use it. Conversions, in order:
  - `blockquote.ipsQuote` → `[quote="user, post:N, topic:T"]` (innermost first), `div.ipsSpoiler` → `[details="title"]`;
  - `a[data-mentionid]` → `@username`;
  - emoticon images → the emoji mapped in `EMOTICON_EMOJIS` (by code) or `EMOTICON_SET_EMOJIS` (by IPB emoticon set name, `core_emoticon_group_<emo_set>`), else the Discourse emoji of the same `:code:`, else a custom emoji created from the IPB image (`core_emoticons`), else the typed text (`;)`, `:P`…). Mapped names must exist in the `discourse-emojis` gem; same-name matches can be wrong (`:cool:` is 🆒, `:tongue:` 👅), hence the explicit map;
  - `data-fileid` / `attachment.php?id=` / `<fileStore.*>` / `<___base_url___>/uploads/` files and `<video>` sources → uploads (`upload_markdown`); external `http(s)` images are kept, other local images are dropped;
  - iframes → oneboxable URLs on their own line (`embed_url`);
  - internal links (`ipb_path`) → the Discourse URL (`discourse_url_for`), or the IPB `/topic|forum|profile/<id>` path for a permalink to redirect; other `<___base_url___>` links are unwrapped. A target imported later than the linking post is not known yet, so `fix_internal_links` runs once everything is imported: it rewrites the imported posts' raw (then `rebake!`) to point those IPB paths to Discourse, and replaces links whose text is an old forum URL with the bare `Discourse.base_url` URL, which Discourse renders as the topic title inline or a onebox on its own line.
- **Files**: every IPB storage area (`<fileStore.core_Attachment>`, `<fileStore.core_Emoticons>`…) maps to `UPLOADS_DIR` (single `FileSystem` storage). Attachments are uploaded from their hashed `attach_location` path with the original `attach_file` name passed separately (`upload_attachment`); Discourse takes the extension from that name. Files in `UPLOADS_DIR` are never modified.
- **Deleted members and guests**: content whose author is 0 or was not imported (forum topics/posts, blog entries/comments) goes to one anonymized account per original author name (`anonymous_user_id`), shaped like Discourse's `UserAnonymizer` output (`anonNNNNNNNN`, `@anonymized.invalid` email, no profile). Only a SHA-1 of the name is stored (`import_anon_key` user custom field) so re-runs reuse the account. Private messages have no author name and fall back to the system user.
- **Avatars**: only `pp_photo_type = 'custom'` photos are files in `UPLOADS_DIR` (`none` holds a letter-avatar color, `sync-*` a social network URL; both are skipped). `import_avatars` is its own phase and only fills members without an avatar, so a re-run picks up files added later.
- **Passwords**: IPB4 bcrypt hashes (`members_pass_hash`, `$2y$`/`$2a$`) go to the `import_pass` user custom field, never to `password` (`base.rb` would make the hash itself a valid password). Discourse cannot check them: the third-party [discourse-migratepassword](https://github.com/communiteq/discourse-migratepassword) plugin must be installed on the target site. On login it checks the typed password against the hash, sets it as the Discourse password and deletes the hash (also on any other login). Enable `migratepassword_allow_insecure_passwords`, otherwise an old password shorter than `min_password_length` (10) is refused as "incorrect". Members without a hash (social logins) must reset their password. Once most members have logged in, remove the plugin and the remaining `import_pass` fields. `import_password_hashes` skips members who already have a Discourse password, so a re-run never revives an old one.
- **Duplicate accounts**: members whose email equals another's once normalized (`UserEmail.find_by_normalized`: dots and `+suffix` ignored, as `normalize_emails` does) are merged into the account imported first.
- **Blogs**: every IPB blog is personal (one author). Entries (`entry_status = 'published' AND entry_hidden = 1` — `entry_hidden` is the approval flag) become topics in `BLOG_CATEGORY_NAME`, imported open, with the cover photo prepended; approved comments become replies. Each blog gets a tag `blog-<owner username>` whose description is the blog name (`blog_tags`, names from `core_sys_lang_words` key `blogs_blog_<id>`). Reactions, follows (entry → topic, blog → tag), quotes, internal links and permalinks cover blogs too.
- **Follows**: forum/topic follows (`core_follow`) become category/topic notification levels — `watching` when the follow notified (immediate, daily or weekly; Discourse has no per-topic digest), `tracking` otherwise. Member follows are skipped (no core equivalent).
- **Ranks**: IPB rank names, icons and point thresholds (`core_member_ranks`, names in `core_member_rank_<id>`) become badges in a "Rangs" grouping, granted daily by a badge SQL query (`rank_badge_query`, needs the hidden `enable_badge_sql` setting) on the discourse-gamification leaderboard score. IPB points and earned ranks are deliberately not imported: the plugin scores the whole imported history (default values give a distribution close to IPB's), and ranks keep progressing afterwards. Badges allow titles but no title is set. IPB badges (`core_badges`) are not imported: Discourse's built-in badges cover them.
- **Solved topics**: two systems coexist. IPB's native one (`forums_topics.topic_answered_pid`, accepter in `core_solved_index`) becomes a discourse-solved accepted answer; a custom plugin flagged whole topics in an added `forums_topics.solved` column (mostly 2017–2020) with no answer post. Every solved topic gets `SOLVED_TAG`. Records are written directly (`SolvedTopic`, `TopicAnswer`, `UserAction`) rather than through `DiscourseSolved::AcceptAnswer`, to avoid notifications.
- **Private messages**: drafts and deleted conversations are skipped; only participants with `map_user_active = 1` get access (IPB removes access when a member leaves); messages from deleted members are attributed to the system user. A conversation every other participant left (or whose recipients were deleted) is imported with its author as the only participant, as Discourse leaves a PM after `remove_allowed_user`; one nobody can see any more is skipped. Discourse always adds the creator and re-adds anyone who posts (`PostCreator#ensure_in_allowed_users`), so `sync_private_message_participants` resets each conversation's `topic_allowed_users` to IPB's active participants once replies are in.
- **Permalinks**: `create_permalinks` stores `topic/<tid>`, `comment/<pid>`, `forum/<id>`, `profile/<member_id>`, `blog-entry/<id>`, `blog-comment/<id>` and `blog/<id>` from the `import_id` custom fields, and `PERMALINK_NORMALIZATIONS` reduces incoming IPB URLs (slugs, `/forums/` prefix, `?do=findComment&comment=`) to those keys. Normalization rules are `|`-separated, so a rule must not contain `|`.
- **`mysql_query`** swallows `Mysql2::Error`, logs it, and returns `[]`; use `mysql_count` for `COUNT(*)` queries so a missing table yields 0 instead of a crash.
- The MySQL connection uses `character_set_results = binary`, so every string column must be explicitly `encode`d to UTF-8 (the existing code does this per field).

## Style

The file uses 4-space indentation (unlike Discourse's 2-space convention); keep it consistent with the surrounding code.
