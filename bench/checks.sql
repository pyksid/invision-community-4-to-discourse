-- Aggregate checks on the bench Discourse database after an import (counts only, no personal data):
--   docker exec -i -u postgres discourse_dev psql discourse_development < bench/checks.sql

\echo '== Content'
SELECT
    (SELECT COUNT(*) FROM users WHERE id > 0) AS users,
    (SELECT COUNT(*) FROM topics WHERE archetype = 'regular' AND user_id > 0) AS topics,
    (SELECT COUNT(*) FROM posts p JOIN topics t ON t.id = p.topic_id WHERE t.archetype = 'regular') AS posts,
    (SELECT COUNT(*) FROM topics WHERE archetype = 'private_message') AS private_messages,
    (SELECT COUNT(*) FROM categories) AS categories,
    (SELECT COUNT(*) FROM permalinks) AS permalinks;

\echo '== Users'
SELECT
    (SELECT COUNT(*) FROM user_custom_fields WHERE name = 'import_archived') AS archived,
    (SELECT COUNT(*) FROM user_custom_fields WHERE name = 'import_dormant') AS dormant,
    (SELECT COUNT(*) FROM user_custom_fields WHERE name = 'import_anon_key') AS anonymized,
    (SELECT COUNT(*) FROM user_custom_fields WHERE name = 'import_pass') AS password_hashes,
    (SELECT COUNT(*) FROM users WHERE id > 0 AND uploaded_avatar_id IS NOT NULL) AS avatars,
    (SELECT COUNT(*) FROM user_profiles WHERE profile_background_upload_id IS NOT NULL) AS profile_backgrounds,
    (SELECT COUNT(*) FROM user_profiles WHERE card_background_upload_id IS NOT NULL) AS card_backgrounds,
    (SELECT COUNT(*) FROM user_profiles WHERE COALESCE(location, '') <> '') AS locations;

\echo '== Archived accounts must hold no personal data (all zeros)'
SELECT
    COUNT(*) FILTER (WHERE e.email NOT LIKE '%@archived.invalid') AS real_email,
    COUNT(*) FILTER (WHERE u.ip_address IS NOT NULL OR u.registration_ip_address IS NOT NULL) AS ip,
    COUNT(*) FILTER (WHERE u.date_of_birth IS NOT NULL) AS birthday,
    COUNT(*) FILTER (WHERE COALESCE(p.location, '') <> '') AS location,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM user_custom_fields c
        WHERE c.user_id = u.id AND (c.name = 'import_pass' OR c.name LIKE 'user\_field\_%')
    )) AS hash_or_fields,
    COUNT(*) FILTER (WHERE u.admin OR u.moderator) AS staff
FROM user_custom_fields a
JOIN users u ON u.id = a.user_id
JOIN user_emails e ON e.user_id = u.id AND e.primary
JOIN user_profiles p ON p.user_id = u.id
WHERE a.name = 'import_archived';

\echo '== Imported accounts must be able to log in without re-confirming their email (0)'
SELECT COUNT(*) AS unconfirmed_email
FROM users u
JOIN user_emails e ON e.user_id = u.id AND e.primary
WHERE u.id > 0
AND EXISTS (SELECT 1 FROM user_custom_fields c WHERE c.user_id = u.id AND c.name = 'import_id')
AND NOT EXISTS (SELECT 1 FROM user_custom_fields c WHERE c.user_id = u.id AND c.name = 'import_archived')
AND EXISTS (SELECT 1 FROM email_tokens t WHERE t.user_id = u.id)
AND NOT EXISTS (SELECT 1 FROM email_tokens t WHERE t.user_id = u.id AND t.email = e.email AND t.confirmed);

\echo '== Inactive members kept with 10+ posts: real email, no emails sent (bad_* all zeros)'
SELECT
    COUNT(*) AS dormant,
    COUNT(*) FILTER (WHERE e.email LIKE '%@archived.invalid') AS bad_archived_email,
    COUNT(*) FILTER (WHERE o.email_level <> 2 OR o.email_messages_level <> 2 OR o.email_digests) AS bad_emails_on,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM user_custom_fields c WHERE c.user_id = u.id AND c.name = 'import_archived'
    )) AS bad_also_archived
FROM user_custom_fields d
JOIN users u ON u.id = d.user_id
JOIN user_emails e ON e.user_id = u.id AND e.primary
JOIN user_options o ON o.user_id = u.id
WHERE d.name = 'import_dormant';

\echo '== User fields'
SELECT f.name, COUNT(DISTINCT c.user_id) AS members
FROM user_fields f
LEFT JOIN user_custom_fields c ON c.name = 'user_field_' || f.id AND c.value <> ''
GROUP BY f.name, f.position
ORDER BY f.position;

\echo '== Groups'
SELECT g.name, g.full_name, COUNT(gu.user_id) AS members
FROM groups g
JOIN group_custom_fields f ON f.group_id = g.id AND f.name = 'import_id'
LEFT JOIN group_users gu ON gu.group_id = g.id
GROUP BY g.name, g.full_name
ORDER BY g.name;

\echo '== Polls'
SELECT COUNT(*) AS polls, COUNT(DISTINCT post_id) AS posts,
    (SELECT COUNT(*) FROM poll_votes) AS votes,
    (SELECT COALESCE(SUM(anonymous_votes), 0) FROM poll_options) AS anonymous_votes
FROM polls;

\echo '== Private messages by number of participants'
SELECT participants, COUNT(*) AS conversations
FROM (
    SELECT t.id, COUNT(tau.user_id) AS participants
    FROM topics t
    LEFT JOIN topic_allowed_users tau ON tau.topic_id = t.id
    WHERE t.archetype = 'private_message'
    GROUP BY t.id
) counts
GROUP BY participants
ORDER BY participants;

\echo '== Rank badges'
SELECT b.name, COUNT(ub.id) AS holders
FROM badges b
JOIN badge_groupings bg ON bg.id = b.badge_grouping_id AND bg.name = 'Rangs'
LEFT JOIN user_badges ub ON ub.badge_id = b.id
GROUP BY b.name, b.id
ORDER BY b.id;

\echo '== Links left to old forum paths (posts whose target was not imported)'
SELECT COUNT(*) AS posts
FROM posts
WHERE raw ~ '\]\(/(topic|forum|profile|blogs)/';
