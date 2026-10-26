# frozen_string_literal: true

require "mysql2"
require "reverse_markdown"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

class ImportScripts::IPBoard4 < ImportScripts::Base
    BATCH_SIZE = 5000
    UPLOADS_DIR = ENV["UPLOADS_DIR"] || "/path/to/uploads"
    TABLE_PREFIX = ENV["TABLE_PREFIX"] || "ipb_"

    # IPB groups whose members become Discourse admins; other groups with ACP access become moderators
    ADMIN_GROUP_IDS = [4]

    # IPB reaction id => Discourse emoji (discourse-reactions plugin); "heart" is the Discourse like
    REACTION_EMOJIS = {
        1 => "heart",      # J'aime
        2 => "heart_eyes", # J'adore
        3 => "laughing",   # Ahah
        4 => "thinking",   # Perplexe
        5 => "cry",        # Triste
        6 => "+1",         # Plusser (+1)
        7 => "-1",         # Moinsser (-1)
        9 => "angry",      # Grrr
    }
    REACTIONS_EXCLUDED_FROM_LIKE = %w[thinking cry -1 angry]

    # IPB emoticon set name => Discourse emoji used for every emoticon of the set without its own entry
    EMOTICON_SET_EMOJIS = {
        "Satisfait" => "relieved",
        "Mort de rire" => "joy",
        "En colère" => "angry",
        "Surpris" => "open_mouth",
        "Perplexe" => "thinking",
        "Laudatif" => "+1",
        "Triste" => "cry",
        "Moqueur" => "smirk",
    }

    # IPB emoticon code => Discourse emoji; takes precedence over EMOTICON_SET_EMOJIS and over a
    # Discourse emoji of the same name (":cool:" is 🆒 and ":tongue:" 👅 in Discourse).
    # A value may list several emojis. Codes in neither table become custom emojis made from the IPB image.
    EMOTICON_EMOJIS = {
        # Crabe
        ":c_wink:" => "wink",
        ":c_satisfied:" => "relieved",
        ":c_satisfied2:" => "blush",
        ":c_embarrassed:" => "flushed",
        ":c_angry:" => "angry",
        ":c_crying:" => "sob",
        ":c_sad:" => "disappointed",
        ":c_happy:" => "smile",
        ":c_lol:" => "laughing",
        ":c_lol2:" => "joy",
        ":c_coldsweat:" => "sweat_smile",
        ":c_omad:" => "rage",
        ":c_surprised:" => "open_mouth",
        ":c_tongue:" => "stuck_out_tongue",
        ":c_doubtfully:" => "face_with_raised_eyebrow",
        ":c_pokerface:" => "neutral_face",
        ":c_inlove:" => "heart_eyes",
        ":c_sunglasses:" => "sunglasses",
        ":c_angel:" => "innocent",
        ":c_fear:" => "fearful",
        ":c_evil:" => "smiling_imp",
        ":c_magic:" => "magic_wand",
        ":c_wtf:" => "exploding_head",
        # Classique
        ":rolleyes:" => "roll_eyes",
        ":dry:" => "expressionless",
        ":huh:" => "confused",
        ":sad:" => "slightly_frowning_face",
        ":wub:" => "heart_eyes",
        ":cool:" => "sunglasses",
        ":ohmy:" => "astonished",
        ":wink:" => "wink",
        ":angry:" => "angry",
        ":blink:" => "flushed",
        ":blush:" => "blush",
        ":happy:" => "smile",
        ":laugh:" => "laughing",
        ":ph34r:" => "ninja",
        ":sleep:" => "sleeping",
        ":smile:" => "slightly_smiling_face",
        ":wacko:" => "zany_face",
        ":mellow:" => "neutral_face",
        ":tongue:" => "stuck_out_tongue",
        ":unsure:" => "confused",
        ":biggrin:" => "grin",
        # categorised sets: only where the set's emoji does not fit
        ":fist-pump-baby:" => "muscle",
        ":desk-flip-rage-guy:" => "rage",
        ":macron-colere:" => "rage",
        ":grumpy-cat:" => "pouting_cat",
        ":scared-cat:" => "scream_cat",
        ":omg:" => "scream",
        ":sceptique:" => "face_with_raised_eyebrow",
        ":chuck-norris:" => "muscle",
        ":good-job:" => "clap",
        ":risitas-pleure1:" => "sob",
        ":risitas-pleure2:" => "sob",
        ":risitas-pleure3:" => "sob",
        ":jesus-lol:" => "laughing",
        # Pot-pourri (chosen by the forum owner)
        ":evil-plotting-raccoon:" => "smiling_face_with_horns",
        ":drhouse:" => "person_facepalming",
        ":bourdon-est-ce-que-tu-baises:" => "disguised_face",
        ":risitas-no:" => "person_facepalming",
        ":kermit:" => "frog",
        ":maitre-capello:" => "ok_hand",
        ":risitas-sueur:" => "sweat_smile",
        ":frustrated-boromir:" => "person_facepalming",
        ":jacquouille:" => "zany_face",
        ":risitas-adios:" => "waving_hand",
        ":macron-doute:" => "face_with_raised_eyebrow",
        ":relax:" => "ok_hand",
        ":relax2:" => "smiling_face_with_sunglasses",
        ":imagination:" => %w[raising_hands rainbow],
        ":sarkozy-sueur:" => "cold_face",
        ":spongebob:" => "person_pouting",
        ":leo-dancing:" => "man_dancing",
        ":first-day-on-the-internet-kid:" => "nerd_face",
        ":strausskahn2:" => "person_pouting",
        ":oui-monsieur:" => "index_pointing_up",
        ":risitas-euh1:" => "upside_down_face",
        ":wtf:" => "person_facepalming",
        ":allthethings:" => "raising_hands",
        ":guy:" => "nerd_face",
        ":good-guy-putin:" => "+1",
        ":miyamoto:" => "person_gesturing_no",
        ":obi-wan-kenobi:" => "face_with_raised_eyebrow",
        ":michael-jackson-popcorn:" => "popcorn",
        ":waiting-skeleton:" => "skull",
        ":dj-pauly-d:" => "shaking_face",
        ":joker:" => "raising_hands",
        ":drevil:" => "smiling_face_with_horns",
        ":balladur:" => "raised_hand",
        ":money-money:" => "money_mouth_face",
        ":say-that-again-i-dare-you:" => "punch",
        ":spongegar:" => "angry",
        ":spiderman-hospital:" => "sleepy_face",
        ":left-exit-12-off-ramp:" => "end_arrow",
        ":trump-bill-signing:" => "raising_hands",
        ":sarkozy-fuck:" => "fu",
        ":uncle-sam:" => "index_pointing_at_the_viewer",
        ":vomi:" => "face_vomiting",
        ":look-son:" => "eyes",
        ":spiderman-computer-desk:" => "face_without_mouth",
        ":shut-up-and-take-my-money-fry:" => "money_mouth_face",
    }

    # core_pfields_content column copied to the native profile location
    PROFILE_LOCATION_FIELD = "field_8"
    # core_pfields_content columns => Discourse user fields (map pf_id → label via core_sys_lang_words key core_pfield_<id>).
    # A multiselect field keeps the IPB values listed in options; aliases map other values found in the data to an option.
    PROFILE_USER_FIELDS = {
        "field_7" => {
            name: "Système d'exploitation",
            type: "multiselect",
            options: [
                "Windows 11", "Windows 10", "Windows 8", "Windows 7", "Windows XP", "Autre version de Windows",
                "Debian", "Ubuntu", "Linux Mint", "Manjaro", "elementary OS", "KDE neon", "Fedora", "Arch Linux",
                "Zorin OS", "Autre distribution Linux",
            ],
            aliases: { "Distribution GNU/Linux" => "Autre distribution Linux", "Autre distribution GNU/Linux" => "Autre distribution Linux" },
        },
        "field_11" => { name: "Modèle", type: "text" },
        "field_2" => { name: "Processeur", type: "text" },
        "field_3" => { name: "Carte mère", type: "text" },
        "field_4" => { name: "Mémoire vive", type: "text" },
        "field_5" => { name: "Stockage", type: "text" },
        "field_6" => { name: "Carte graphique", type: "text" },
    }

    # Category holding IPB blog entries
    BLOG_CATEGORY_NAME = "Billets"

    # Tag for every solved topic: topics flagged by the custom forums_topics.solved column have no answer post
    SOLVED_TAG = "résolu"

    # Hosts (and path prefix) the forum was served from, so absolute links to it are treated as internal
    OLD_BASE_URLS = %w[community.lecrabeinfo.net lecrabeinfo.net/forums]
    # IPB paths that a permalink redirects (see create_permalinks)
    IPB_CONTENT_PATH = %r{\A/(?:topic|forum|profile|blogs/entry|blogs/blog)/\d+}

    # Reduce old IPB URLs to the keys create_permalinks stores (rules are "|"-separated, so no "|" inside)
    PERMALINK_NORMALIZATIONS = [
        '/^forums\/topic\//topic/',
        '/^forums\/forum\//forum/',
        '/^forums\/profile\//profile/',
        '/^forums\/blogs\//blogs/',
        '/^blogs\/entry\/\d+[^?]*\?.*\bcomment=(\d+).*/blog-comment/\1',
        '/^blogs\/entry\/(\d+).*/blog-entry/\1',
        '/^blogs\/blog\/(\d+).*/blog/\1',
        '/^topic\/\d+[^?]*\?.*\bcomment=(\d+).*/comment/\1',
        '/^topic\/(\d+).*/topic/\1',
        '/^forum\/(\d+).*/forum/\1',
        '/^profile\/(\d+).*/profile/\1',
    ]

    SiteSetting.disable_emails = "non-staff"
    SiteSetting.disable_digest_emails = true

    def initialize
        super

        @client =
        Mysql2::Client.new(
            host: ENV["DB_HOST"] || "localhost",
            port: (ENV["DB_PORT"] || 3306).to_i,
            username: ENV["DB_USER"] || "root",
            password: ENV["DB_PW"],
            database: ENV["DB_NAME"],
        )

        @client.query("SET character_set_results = binary")
    end

    def execute
        import_users
        import_avatars
        import_password_hashes
        import_profile_fields
        import_categories
        import_topics
        import_posts
        import_polls
        import_blog_entries
        import_blog_comments
        import_reactions
        import_tags
        import_solved
        import_follows
        import_articles
        import_private_messages
        import_private_message_replies
        sync_private_message_participants
        fix_internal_links
        import_ranks
        create_permalinks
    end

    # Separate from import_users so that a re-run adds the avatars of members imported before their file was available
    def import_avatars
        puts "", "importing avatars..."

        # "none" members hold a letter-avatar color and "sync-*" ones a social network URL in pp_main_photo
        members = mysql_query(<<~SQL).to_a
            SELECT member_id AS id, pp_main_photo
            FROM #{TABLE_PREFIX}core_members
            WHERE pp_photo_type = 'custom' AND pp_main_photo <> ''
        SQL
        imported = 0
        start_time = Time.now

        members.each_with_index do |m, index|
            print_status(index + 1, members.size, start_time)

            user = User.find_by(id: user_id_from_imported_user_id(m["id"]))
            next if !user || user.uploaded_avatar_id

            path = File.join(UPLOADS_DIR, m["pp_main_photo"].encode("utf-8", "utf-8"))
            next unless File.exist?(path)

            upload = create_upload(user.id, path, File.basename(path))
            next unless upload&.persisted?

            user.create_user_avatar unless user.user_avatar
            user.user_avatar.update(custom_upload_id: upload.id)
            user.update(uploaded_avatar_id: upload.id)
            imported += 1
        rescue StandardError => e
            puts "", "Failed to upload avatar for user #{m["id"]}: #{e.message}"
        end

        puts "", "#{imported} avatars imported"
    end

    # IPB4 bcrypt hashes for the discourse-migratepassword plugin: on login it checks the password against the
    # hash, sets it as the Discourse password and deletes the hash. Members who already have a Discourse password
    # are skipped so that a re-run never brings an old password back; ORDER BY keeps the first merged account's hash.
    def import_password_hashes
        puts "", "importing password hashes..."

        members = mysql_query(<<~SQL).to_a
            SELECT member_id AS id, members_pass_hash
            FROM #{TABLE_PREFIX}core_members
            WHERE members_pass_hash LIKE '$2%'
            ORDER BY member_id
        SQL
        imported = 0
        start_time = Time.now

        members.each_with_index do |m, index|
            print_status(index + 1, members.size, start_time)

            user = User.find_by(id: user_id_from_imported_user_id(m["id"]))
            next if !user || user.has_password? || user.custom_fields["import_pass"].present?

            user.custom_fields["import_pass"] = m["members_pass_hash"].encode("utf-8", "utf-8")
            user.save_custom_fields
            imported += 1
        end

        puts "", "#{imported} password hashes imported"
    end

    # Separate from import_users like import_avatars; only empty values are filled, so a re-run never
    # overwrites what a member changed in Discourse
    def import_profile_fields
        puts "", "importing profile fields..."

        fields = PROFILE_USER_FIELDS.to_h { |column, definition| [column, user_field(definition)] }
        columns = [PROFILE_LOCATION_FIELD, *PROFILE_USER_FIELDS.keys]

        members = mysql_query(<<~SQL).to_a
            SELECT member_id AS id, #{columns.join(", ")}
            FROM #{TABLE_PREFIX}core_pfields_content
            WHERE #{columns.map { |column| "#{column} <> ''" }.join(" OR ")}
        SQL
        imported = 0
        start_time = Time.now

        members.each_with_index do |m, index|
            print_status(index + 1, members.size, start_time)

            user = User.find_by(id: user_id_from_imported_user_id(m["id"]))
            next unless user

            values = columns.to_h { |column| [column, CGI.unescapeHTML(m[column].to_s.encode("utf-8", "utf-8", invalid: :replace, undef: :replace, replace: "")).strip] }

            location = values[PROFILE_LOCATION_FIELD]
            user.user_profile.update_column(:location, location[0, 3000]) if location.present? && user.user_profile.location.blank?

            fields.each do |column, field|
                key = "#{User::USER_FIELD_PREFIX}#{field.id}"
                next if values[column].blank? || user.custom_fields[key].present?

                user.custom_fields[key] =
                    if field.field_type == "multiselect"
                        definition = PROFILE_USER_FIELDS[column]
                        values[column].split(",").filter_map do |value|
                            value = definition[:aliases].fetch(value.strip, value.strip)
                            definition[:options].find { |option| option.casecmp?(value) }
                        end.uniq.presence
                    else
                        values[column][0, UserField.max_length]
                    end
            end

            user.save_custom_fields
            imported += 1
        rescue StandardError => e
            puts "", "Failed to import profile fields for member #{m["id"]}: #{e.message}"
        end

        puts "", "#{imported} member profiles processed"
    end

    def user_field(definition)
        UserField.find_or_create_by!(name: definition[:name]) do |field|
            field.description = definition[:name]
            field.field_type = definition[:type]
            field.editable = true
            field.show_on_profile = true
            field.show_on_signup = false
            field.requirement = :optional
            field.position = UserField.maximum(:position).to_i + 1
            definition[:options]&.each { |option| field.user_field_options.build(value: option) }
        end
    end

    # Primary and secondary (mgroup_others) group memberships
    def members_of_groups(group_ids)
        return [] if group_ids.empty?

        rows = mysql_query(<<~SQL)
            SELECT member_id FROM #{TABLE_PREFIX}core_members
            WHERE member_group_id IN (#{group_ids.join(",")})
            OR mgroup_others REGEXP '(^|,)(#{group_ids.join("|")})(,|$)'
        SQL

        rows.map { |row| row["member_id"].to_i }
    end

    def fetch_admins
        member_rows = mysql_query(<<~SQL)
            SELECT row_id FROM #{TABLE_PREFIX}core_admin_permission_rows WHERE row_id_type = 'member'
        SQL

        (members_of_groups(ADMIN_GROUP_IDS) + member_rows.map { |row| row["row_id"].to_i }).uniq
    end

    # Moderator groups/members, plus groups with ACP access that are not in ADMIN_GROUP_IDS
    def fetch_moderators
        rows = mysql_query(<<~SQL).to_a
            SELECT type, id FROM #{TABLE_PREFIX}core_moderators
            UNION ALL
            SELECT 'g', row_id FROM #{TABLE_PREFIX}core_admin_permission_rows WHERE row_id_type = 'group'
        SQL

        group_ids = rows.select { |row| row["type"] == "g" }.map { |row| row["id"].to_i } - ADMIN_GROUP_IDS
        member_ids = rows.select { |row| row["type"] == "m" }.map { |row| row["id"].to_i }

        (members_of_groups(group_ids.uniq) + member_ids).uniq
    end

    # Members without posts, blog entries/comments, reactions or private messages are not imported, except staff
    def active_member_condition(staff_ids)
        <<~SQL
            (EXISTS (SELECT 1 FROM #{TABLE_PREFIX}forums_posts fp WHERE fp.author_id = m.member_id)
            OR EXISTS (SELECT 1 FROM #{TABLE_PREFIX}core_reputation_index r WHERE r.member_id = m.member_id)
            OR EXISTS (SELECT 1 FROM #{TABLE_PREFIX}core_message_topic_user_map u WHERE u.map_user_id = m.member_id)
            OR EXISTS (SELECT 1 FROM #{TABLE_PREFIX}blog_entries be WHERE be.entry_author_id = m.member_id)
            OR EXISTS (SELECT 1 FROM #{TABLE_PREFIX}blog_comments bc WHERE bc.comment_member_id = m.member_id)
            OR m.member_id IN (#{(staff_ids + [0]).join(",")}))
        SQL
    end

    def import_users
        puts "", "importing users..."

        last_user_id = -1
        about_me_column = "field_1"
        admin_ids = fetch_admins
        moderator_ids = fetch_moderators - admin_ids
        active_members = active_member_condition(admin_ids + moderator_ids)
        total_users = mysql_count("SELECT COUNT(*) count FROM #{TABLE_PREFIX}core_members m WHERE #{active_members}")

        batches(BATCH_SIZE) do |offset|
            users = mysql_query(<<~SQL).to_a
                SELECT m.member_id AS id,
                    m.name,
                    m.email,
                    m.joined,
                    m.ip_address,
                    m.member_title AS title,
                    CASE 
                        WHEN m.bday_year IS NULL OR m.bday_year = 0 
                            OR m.bday_month IS NULL OR m.bday_month = 0 
                            OR m.bday_day IS NULL OR m.bday_day = 0 
                        THEN NULL 
                        ELSE CONCAT(m.bday_year, '-', LPAD(m.bday_month, 2, '0'), '-', LPAD(m.bday_day, 2, '0')) 
                    END AS date_of_birth,
                    m.last_activity,
                    m.temp_ban AS member_banned,
                    m.member_group_id,
                    NULLIF(p.#{about_me_column}, '') AS pp_about_me
                FROM #{TABLE_PREFIX}core_members AS m
                LEFT JOIN #{TABLE_PREFIX}core_pfields_content AS p ON m.member_id = p.member_id
                WHERE m.member_id > #{last_user_id}
                AND #{active_members}
                ORDER BY m.member_id
                LIMIT #{BATCH_SIZE}
            SQL

            break if users.empty?

            last_user_id = users.last["id"] || last_user_id if users.any?

            create_users(users, total: total_users, offset: offset) do |u|
                next if user_id_from_imported_user_id(u["id"])

                %W[name email title pp_about_me].each do |k|
                    u[k]&.encode!("utf-8", "utf-8", invalid: :replace, undef: :replace, replace: "")
                end
                next if u["name"].blank? || !Email.is_valid?(u["email"])

                # With normalize_emails, Discourse treats addresses that differ only by dots or a "+suffix" as
                # one; such duplicate IPB accounts (re-registrations) are merged into the account imported first
                if (existing = UserEmail.find_by_normalized(u["email"])&.user)
                    add_user(u["id"].to_s, existing)
                    puts "", "Merged IPB member #{u["id"]} into #{existing.username} (same normalized email)"
                    next
                end

                is_moderator = moderator_ids.include?(u["id"].to_i)
                is_admin = admin_ids.include?(u["id"].to_i)


                date_of_birth =
                begin
                    Date.parse(u["date_of_birth"]) if u["date_of_birth"].present?
                rescue ArgumentError
                    nil
                end

                {
                    id: u["id"],
                    username: u["name"],
                    email: u["email"],
                    created_at: Time.zone.at(u["joined"]),
                    registration_ip_address: u["ip_address"],
                    title: CGI.unescapeHTML(u["title"].presence || ""),
                    date_of_birth: date_of_birth,
                    last_seen_at: Time.zone.at(u["last_activity"]),
                    admin: is_admin,
                    moderator: is_moderator,
                    bio_raw: clean_up(u["pp_about_me"]),
                    post_create_action:
                        proc do |new_user|
                            ban = u["member_banned"].to_i
                            if ban == -1
                                new_user.update(suspended_at: DateTime.now, suspended_till: 100.years.from_now)
                            elsif ban > Time.now.to_i
                                new_user.update(suspended_at: DateTime.now, suspended_till: Time.zone.at(ban))
                            end
                        end,
                }   
            end
        end
    end

    def import_categories
        puts "", "importing categories..."
        categories = mysql_query(<<~SQL).to_a
            SELECT 
                f.id AS id,
                CASE 
                    WHEN p.parent_id = -1 THEN -1
                    ELSE f.parent_id
                END AS parent_id,
                f.position AS position,
                parent_lang.word_default AS category_name,
                desc_lang.word_default AS description
            FROM #{TABLE_PREFIX}forums_forums f
            JOIN #{TABLE_PREFIX}core_sys_lang_words parent_lang
                ON parent_lang.word_key = CONCAT('forums_forum_', f.id)
                AND parent_lang.lang_id = (SELECT lang_id FROM #{TABLE_PREFIX}core_sys_lang WHERE lang_default = 1)
            LEFT JOIN #{TABLE_PREFIX}core_sys_lang_words desc_lang
                ON desc_lang.word_key = CONCAT('forums_forum_', f.id, '_desc')
                AND desc_lang.lang_id = parent_lang.lang_id
            LEFT JOIN #{TABLE_PREFIX}forums_forums p
                ON f.parent_id = p.id
            WHERE f.parent_id != -1
        SQL

        parent_categories = categories.select { |c| c["parent_id"] == -1 }
        child_categories = categories.select { |c| c["parent_id"] != -1 }
        staff_only = staff_only_forum_ids
        restrict = proc { |id| proc { |category| restrict_to_staff(category) if staff_only.include?(id) } }

        create_categories(parent_categories) do |c|
        next if category_id_from_imported_category_id(c["id"])
        {
            id: c["id"],
            name: c["category_name"].encode("utf-8", "utf-8"),
            description: clean_up(c["description"]),
            position: c["position"],
            post_create_action: restrict.call(c["id"].to_i),
        }
        end
    
        create_categories(child_categories) do |c|
        next if category_id_from_imported_category_id(c["id"])
        {
            id: c["id"],
            parent_category_id: category_id_from_imported_category_id(c["parent_id"]),
            name: c["category_name"].encode("utf-8", "utf-8"),
            description: clean_up(c["description"]),
            position: c["position"],
            post_create_action: restrict.call(c["id"].to_i),
        }
        end
    end

    def staff_group_ids
        rows = mysql_query(<<~SQL)
            SELECT id FROM #{TABLE_PREFIX}core_moderators WHERE type = 'g'
            UNION
            SELECT row_id FROM #{TABLE_PREFIX}core_admin_permission_rows WHERE row_id_type = 'group'
        SQL

        (rows.map { |row| row["id"].to_i } + ADMIN_GROUP_IDS).uniq
    end

    # Forums whose view permission ("*" = everyone, otherwise group ids) lists only staff groups
    def staff_only_forum_ids
        staff_groups = staff_group_ids
        rows = mysql_query(<<~SQL)
            SELECT perm_type_id, perm_view FROM #{TABLE_PREFIX}core_permission_index
            WHERE app = 'forums' AND perm_type = 'forum'
        SQL

        rows
            .reject { |row| row["perm_view"] == "*" }
            .select { |row| (row["perm_view"].to_s.split(",").map(&:to_i) - staff_groups).empty? }
            .map { |row| row["perm_type_id"].to_i }
    end

    def restrict_to_staff(category)
        category.set_permissions("staff" => :full)
        category.save!
        puts "Category #{category.name} restricted to staff"
    end

    def import_topics
        puts "", "importing topics..."
    
        last_topic_id = -1
        total_topics = mysql_count(<<~SQL)
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}forums_topics t
            JOIN #{TABLE_PREFIX}forums_posts p ON t.tid = p.topic_id
            WHERE p.pdelete_time = 0
            AND p.new_topic = 1
            AND t.approved = 1
            AND p.queued = 0
        SQL

        puts "Total topics to be imported: #{total_topics}"

        batches(BATCH_SIZE) do |offset|
            topics = mysql_query(<<~SQL).to_a
                SELECT t.tid AS id, t.title, t.state, t.starter_id, t.starter_name, t.start_date, t.views, t.forum_id, t.pinned, p.post
                FROM #{TABLE_PREFIX}forums_topics t
                JOIN #{TABLE_PREFIX}forums_posts p ON t.tid = p.topic_id
                WHERE p.pdelete_time = 0
                AND p.new_topic = 1
                AND t.approved = 1
                AND p.queued = 0
                AND tid > #{last_topic_id}
                ORDER BY t.tid
                LIMIT #{BATCH_SIZE}
            SQL

            break if topics.empty?

            last_topic_id = topics[-1]["id"]

            create_posts(topics, total: total_topics, offset: offset) do |t|
                next if post_id_from_imported_post_id("t-#{t["id"]}")
                
                created_at = Time.zone.at(t["start_date"])
                user_id = user_id_from_imported_user_id(t["starter_id"]) || anonymous_user_id(t["starter_name"])
                {
                    id: "t-#{t["id"]}",
                    title: CGI.unescapeHTML(t["title"].encode("utf-8", "utf-8")),
                    user_id: user_id,
                    created_at: created_at,
                    views: t["views"],
                    category: category_id_from_imported_category_id(t["forum_id"]),
                    pinned_at: t["pinned"] == 1 ? created_at : nil,
                    raw: clean_up(t["post"], user_id),
                }
            end
        end
    end

    def import_posts
        puts "", "importing posts..."
    
        last_post_id = -1
        total_posts = mysql_count(<<~SQL)
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}forums_posts
            WHERE new_topic = 0
                AND pdelete_time = 0
                AND queued = 0
        SQL

        puts "Total posts to be imported: #{total_posts}"
    
        batches(BATCH_SIZE) do |offset|
            posts = mysql_query(<<~SQL).to_a
                SELECT pid AS id, author_id, author_name, post_date, post, topic_id
                FROM #{TABLE_PREFIX}forums_posts
                WHERE new_topic = 0
                AND pdelete_time = 0
                AND queued = 0
                AND pid > #{last_post_id}
                ORDER BY pid
                LIMIT #{BATCH_SIZE}
            SQL
    
            break if posts.empty?
    
            last_post_id = posts[-1]["id"]
    
            create_posts(posts, total: total_posts, offset: offset) do |p|
                next if post_id_from_imported_post_id(p["id"])
                
                topic = topic_lookup_from_imported_post_id("t-#{p["topic_id"]}")
                if topic.nil?
                    puts "Skipping post #{p["id"]} - Topic ID #{p["topic_id"]} not found"
                    next
                end

                user_id = user_id_from_imported_user_id(p["author_id"]) || anonymous_user_id(p["author_name"])
    
                {
                    id: p["id"],
                    user_id: user_id,
                    created_at: Time.zone.at(p["post_date"]),
                    raw: clean_up(p["post"], user_id),
                    topic_id: topic[:topic_id],
                }
            end
        end
    end

    # IPB blogs are personal (one author each): entries become topics in BLOG_CATEGORY_NAME, comments become
    # replies. Like forum topics, entries are imported open; drafts and
    # hidden/unapproved entries (entry_hidden is the approval flag, 1 = visible) are skipped.
    # IPB polls (forums_topics.poll_state = core_polls.pid) are prepended to the topic's first post, one
    # Discourse poll per IPB question. Votes of members who were not imported are kept as anonymous votes,
    # so totals match IPB. Polls are created directly as PostCreator is not involved.
    def import_polls
        puts "", "importing polls..."

        polls = mysql_query(<<~SQL).to_a
            SELECT p.pid, t.tid, p.choices, p.votes, p.poll_view_voters, p.poll_closed, p.poll_close_date
            FROM #{TABLE_PREFIX}core_polls p
            JOIN #{TABLE_PREFIX}forums_topics t ON t.poll_state = p.pid
            ORDER BY p.pid
        SQL
        imported = 0

        polls.each do |p|
            post = Post.find_by(id: post_id_from_imported_post_id("t-#{p["tid"]}"))
            next if !post || post.polls.exists?

            questions = JSON.parse(p["choices"].encode("utf-8", "utf-8")).sort_by { |key, _| key.to_i }
            close_at = Time.zone.at(p["poll_close_date"]) if p["poll_close_date"].to_i > 0
            closed = p["poll_closed"] == 1 || close_at&.past?

            # question key => [Discourse poll name, IPB choice key => option index]
            layout = {}
            markdown =
                questions.each_with_index.map do |(key, question), index|
                    name = index == 0 ? DiscoursePoll::DEFAULT_POLL_NAME : "poll#{index + 1}"
                    texts = []
                    choice_indexes =
                        question["choice"].sort_by { |choice_key, _| choice_key.to_i }.to_h do |choice_key, text|
                            text = CGI.unescapeHTML(text.to_s).gsub(/\s+/, " ").strip
                            texts << text unless texts.include?(text)
                            [choice_key, texts.index(text)]
                        end
                    layout[key] = [name, choice_indexes]

                    arguments = ["name=#{name}", "results=always"]
                    arguments << (question["multi"] == 1 ? "type=multiple min=1 max=#{texts.size}" : "type=regular")
                    arguments << "public=true" if p["poll_view_voters"] == 1
                    arguments << "status=closed" if closed
                    arguments << "close=#{close_at.iso8601}" if close_at

                    title = CGI.unescapeHTML(question["question"].to_s).strip
                    title = "# #{title}\n" if title.present?
                    "[poll #{arguments.join(" ")}]\n#{title}#{texts.map { |text| "* #{text}" }.join("\n")}\n[/poll]"
                end

            # in one transaction, so that a failure does not leave the markdown prepended without polls
            Post.transaction do
                raw = "#{markdown.join("\n\n")}\n\n#{post.raw}"
                post.update_columns(raw: raw)
                DiscoursePoll::Poll.extract(raw, post.topic_id, post.user_id).each { |poll| DiscoursePoll::Poll.create!(post.id, poll) }
                post.custom_fields[DiscoursePoll::HAS_POLLS] = true
                post.save_custom_fields(true)
                import_poll_votes(p, post, layout, questions.to_h)
            end
            post.rebake!
            imported += 1
        rescue StandardError => e
            puts "", "Failed to import poll #{p["pid"]}: #{e.message}"
        end

        puts "", "#{imported} polls imported"
    end

    def import_poll_votes(ipb_poll, post, layout, questions)
        discourse_polls = post.polls.includes(:poll_options).index_by(&:name)
        votes = mysql_query("SELECT member_id, vote_date, member_choices FROM #{TABLE_PREFIX}core_voters WHERE poll = #{ipb_poll["pid"]}").to_a
        voters = Hash.new { |hash, key| hash[key] = Set.new }

        votes.each do |vote|
            user_id = user_id_from_imported_user_id(vote["member_id"])
            next unless user_id

            JSON.parse(vote["member_choices"].to_s.encode("utf-8", "utf-8").presence || "{}").each do |key, choice_keys|
                name, choice_indexes = layout[key]
                poll = discourse_polls[name]
                next unless poll

                Array.wrap(choice_keys).filter_map { |choice_key| choice_indexes[choice_key.to_s] }.uniq.each do |index|
                    option = poll.poll_options.sort_by(&:id)[index]
                    PollVote.find_or_create_by!(poll: poll, poll_option: option, user_id: user_id) do |poll_vote|
                        poll_vote.created_at = Time.zone.at(vote["vote_date"])
                    end
                end
                voters[name] << user_id
            end
        end

        # IPB counts include votes of deleted members
        layout.each do |key, (name, choice_indexes)|
            poll = discourse_polls[name]
            next unless poll

            ipb_counts = Hash.new(0)
            questions[key]["votes"].to_h.each { |choice_key, count| ipb_counts[choice_indexes[choice_key]] += count.to_i }
            poll.poll_options.sort_by(&:id).each_with_index do |option, index|
                anonymous = ipb_counts[index] - option.poll_votes.count
                option.update!(anonymous_votes: anonymous) if anonymous > 0
            end
            anonymous_voters = ipb_poll["votes"].to_i - voters[name].size
            poll.update!(anonymous_voters: anonymous_voters) if anonymous_voters > 0
        end
    end

    def import_blog_entries
        puts "", "importing blog entries..."

        category = create_category({ name: BLOG_CATEGORY_NAME }, "blogs")

        last_entry_id = -1
        total_entries = mysql_count(<<~SQL)
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}blog_entries
            WHERE entry_status = 'published'
            AND entry_hidden = 1
        SQL

        batches(BATCH_SIZE) do |offset|
            entries = mysql_query(<<~SQL).to_a
                SELECT entry_id AS id, entry_author_id, entry_author_name, entry_name, entry_content, entry_cover_photo, entry_views,
                    IF(entry_publish_date > 0, entry_publish_date, entry_date) AS published_at
                FROM #{TABLE_PREFIX}blog_entries
                WHERE entry_status = 'published'
                AND entry_hidden = 1
                AND entry_id > #{last_entry_id}
                ORDER BY entry_id
                LIMIT #{BATCH_SIZE}
            SQL

            break if entries.empty?

            last_entry_id = entries[-1]["id"]

            create_posts(entries, total: total_entries, offset: offset) do |e|
                next if post_id_from_imported_post_id("b-#{e["id"]}")

                user_id = user_id_from_imported_user_id(e["entry_author_id"]) || anonymous_user_id(e["entry_author_name"])

                raw = clean_up(e["entry_content"], user_id)
                cover = upload_markdown("<fileStore.blog_Entries>/#{e["entry_cover_photo"]}", nil, user_id) if e["entry_cover_photo"].present?

                {
                    id: "b-#{e["id"]}",
                    title: CGI.unescapeHTML(e["entry_name"].encode("utf-8", "utf-8")),
                    user_id: user_id,
                    created_at: Time.zone.at(e["published_at"]),
                    views: e["entry_views"],
                    category: category.id,
                    raw: cover ? "#{cover}\n\n#{raw}" : raw,
                }
            end
        end
    end

    def import_blog_comments
        puts "", "importing blog comments..."

        last_comment_id = -1
        total_comments = mysql_count("SELECT COUNT(*) count FROM #{TABLE_PREFIX}blog_comments WHERE comment_approved = 1")

        batches(BATCH_SIZE) do |offset|
            comments = mysql_query(<<~SQL).to_a
                SELECT comment_id AS id, comment_entry_id, comment_member_id, comment_member_name, comment_date, comment_text
                FROM #{TABLE_PREFIX}blog_comments
                WHERE comment_approved = 1
                AND comment_id > #{last_comment_id}
                ORDER BY comment_id
                LIMIT #{BATCH_SIZE}
            SQL

            break if comments.empty?

            last_comment_id = comments[-1]["id"]

            create_posts(comments, total: total_comments, offset: offset) do |c|
                next if post_id_from_imported_post_id("bc-#{c["id"]}")

                topic = topic_lookup_from_imported_post_id("b-#{c["comment_entry_id"]}")
                next unless topic

                user_id = user_id_from_imported_user_id(c["comment_member_id"]) || anonymous_user_id(c["comment_member_name"])

                {
                    id: "bc-#{c["id"]}",
                    topic_id: topic[:topic_id],
                    user_id: user_id,
                    created_at: Time.zone.at(c["comment_date"]),
                    raw: clean_up(c["comment_text"], user_id),
                }
            end
        end
    end

    # blog_id => Discourse id of the blog's owner, whose profile replaces the blog page
    def blog_owners
        @blog_owners ||=
            mysql_query("SELECT blog_id, blog_member_id FROM #{TABLE_PREFIX}blog_blogs").each_with_object({}) do |row, owners|
                user_id = user_id_from_imported_user_id(row["blog_member_id"])
                owners[row["blog_id"].to_i] = user_id if user_id
            end
    end

    def configure_reactions
        SiteSetting.discourse_reactions_enabled = true
        SiteSetting.discourse_reactions_reaction_for_like = "heart"

        emojis = REACTION_EMOJIS.values - ["heart"]
        SiteSetting.discourse_reactions_enabled_reactions =
            (SiteSetting.discourse_reactions_enabled_reactions.split("|") | emojis).join("|")
        SiteSetting.discourse_reactions_excluded_from_like =
            (SiteSetting.discourse_reactions_excluded_from_like.split("|") | REACTIONS_EXCLUDED_FROM_LIKE).join("|")
    end

    # Mirrors DiscourseReactions::ReactionManager without notifications: the main reaction is a
    # plain like, other reactions get a ReactionUser plus a like unless excluded from likes
    def import_reactions
        puts "", "importing post reactions"

        configure_reactions
        last_id = -1
        RateLimiter.disable

        reaction_condition = "((app = 'forums' AND type = 'pid') OR (app = 'blog' AND type IN ('entry_id', 'comment_id')))"
        total_reactions = mysql_count("SELECT COUNT(*) count FROM #{TABLE_PREFIX}core_reputation_index WHERE #{reaction_condition}")
        start_time = Time.now

        batches(BATCH_SIZE) do |offset|
            reactions = mysql_query(<<~SQL).to_a
                SELECT id, type, member_id AS user_id, type_id AS post_id, rep_date AS created_at, reaction
                FROM #{TABLE_PREFIX}core_reputation_index
                WHERE #{reaction_condition}
                AND id > #{last_id}
                ORDER BY id
                LIMIT #{BATCH_SIZE}
            SQL

            break if reactions.empty?

            last_id = reactions[-1]["id"]

            reactions.each do |r|
                emoji = REACTION_EMOJIS[r["reaction"].to_i]
                next unless emoji

                user = User.find_by(id: user_id_from_imported_user_id(r["user_id"]))
                next unless user

                post_id =
                    case r["type"]
                    when "pid" then post_id_from_imported_pid(r["post_id"])
                    when "entry_id" then post_id_from_imported_post_id("b-#{r["post_id"]}")
                    else post_id_from_imported_post_id("bc-#{r["post_id"]}")
                    end
                post = Post.find_by(id: post_id)
                next unless post

                created_at = Time.zone.at(r["created_at"])
                liked = PostAction.exists?(user_id: user.id, post_id: post.id, post_action_type_id: PostActionType::LIKE_POST_ACTION_ID)

                begin
                    if emoji != "heart" && !DiscourseReactions::ReactionUser.exists?(user_id: user.id, post_id: post.id)
                        reaction = DiscourseReactions::Reaction.find_or_create_by!(post_id: post.id, reaction_type: :emoji, reaction_value: emoji)
                        DiscourseReactions::ReactionUser.create!(reaction: reaction, user_id: user.id, post_id: post.id, created_at: created_at)
                    end

                    if !liked && !REACTIONS_EXCLUDED_FROM_LIKE.include?(emoji)
                        PostActionCreator.create(user, post, :like, created_at: created_at, silent: true)
                    end
                rescue StandardError => e
                    puts "Error importing reaction #{r["id"]} on post #{r["post_id"]}: #{e.message}"
                end
            end

            print_status(offset + reactions.size, total_reactions, start_time)
        end
        RateLimiter.enable
    end

    def import_tags
        puts "", "importing tags..."
        
        SiteSetting.tagging_enabled = true
        SiteSetting.max_tags_per_topic = 100

        last_topic_id = -1

        batches(BATCH_SIZE) do |offset|
            tags = mysql_query(<<~SQL).to_a
                SELECT 
                    t.tag_meta_id AS topic_id, 
                    GROUP_CONCAT(LOWER(TRIM(t.tag_text)) ORDER BY t.tag_id SEPARATOR ', ') AS tags
                FROM #{TABLE_PREFIX}core_tags t
                LEFT JOIN #{TABLE_PREFIX}forums_topics ft ON t.tag_meta_id = ft.tid
                WHERE t.tag_meta_app = 'forums'
                AND tid > #{last_topic_id}
                GROUP BY t.tag_meta_id
                ORDER BY topic_id
                LIMIT #{BATCH_SIZE}
            SQL

            break if tags.empty?

            last_topic_id = tags[-1]["topic_id"]
        
            tags.each do |tag|
                topic = topic_lookup_from_imported_post_id("t-#{tag["topic_id"]}")

                if topic.is_a?(Hash) && topic[:topic_id]
                    topic = Topic.find_by(id: topic[:topic_id])
                end

                if topic.is_a?(Topic)

                    tag_names = tag["tags"].encode("utf-8", "utf-8", invalid: :replace, undef: :replace, replace: "")
                                    .split(",").map(&:strip).reject(&:empty?)
                
                    if tag_names.any?
                        DiscourseTagging.tag_topic_by_names(topic, staff_guardian, tag_names)
                    end
                end
            end
        end
    end

    def import_articles
        puts "", "importing articles..."
    
        last_article_id = -1
        total_articles = mysql_count(<<~SQL)
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}cms_custom_database_1
            WHERE record_approved = 1
        SQL

        puts "Total articles to be imported: #{total_articles}"
        articles_category_id = Category.find_by(name: "articles")&.id

        puts "First create a category named articles" if articles_category_id.nil?
        return if articles_category_id.nil?


        batches(BATCH_SIZE) do |offset|
            articles = mysql_query(<<~SQL).to_a
                SELECT primary_id_field AS id, field_1 AS title, member_id, record_publish_date, record_views AS views, record_locked,
                CONCAT(field_2, '<br><br><hr><br><br>', field_3) AS post
                FROM #{TABLE_PREFIX}cms_custom_database_1
                WHERE record_approved = 1
                AND primary_id_field > #{last_article_id}
                ORDER BY primary_id_field
                LIMIT #{BATCH_SIZE}
            SQL

            break if articles.empty?

            last_article_id = articles[-1]["id"]

            create_posts(articles, total: total_articles, offset: offset) do |t|
                next if post_id_from_imported_post_id("a-#{t["id"]}")
                
                created_at = Time.zone.at(t["record_publish_date"])
                user_id = user_id_from_imported_user_id(t["member_id"])
                
                if user_id.nil?
                    puts "Skipping article #{t["id"]} - User ID #{t['member_id']} not found"
                    next
                end

                {
                    id: "a-#{t["id"]}",
                    title: CGI.unescapeHTML(t["title"].encode("utf-8", "utf-8")),
                    user_id: user_id,
                    created_at: created_at,
                    views: t["views"],
                    category: articles_category_id,
                    raw: clean_up(t["post"], user_id),
                    closed: t["record_locked"] == 1
                }
            end
        end
    end

    # Followed topics/forums (and blog entries, as topics): Discourse has no per-topic digest, so any notifying follow (immediate,
    # daily, weekly) becomes "watching" and a follow without notifications becomes "tracking".
    # Member and whole-blog follows have no core equivalent and are skipped.
    def import_follows
        puts "", "importing topic and forum subscriptions..."

        follows = mysql_query(<<~SQL).to_a
            SELECT follow_area, follow_rel_id, follow_member_id, follow_notify_do, follow_notify_freq
            FROM #{TABLE_PREFIX}core_follow
            WHERE (follow_app = 'forums' AND follow_area IN ('topic', 'forum'))
            OR (follow_app = 'blog' AND follow_area = 'entry')
        SQL

        puts "Subscriptions to be processed: #{follows.size}"

        follows.each do |f|
            user = User.find_by(id: user_id_from_imported_user_id(f["follow_member_id"]))
            next unless user

            notify = f["follow_notify_do"] == 1 && f["follow_notify_freq"] != "none"

            begin
                case f["follow_area"]
                when "topic", "entry"
                    prefix = f["follow_area"] == "topic" ? "t" : "b"
                    lookup = topic_lookup_from_imported_post_id("#{prefix}-#{f["follow_rel_id"]}")
                    next unless lookup

                    level = TopicUser.notification_levels[notify ? :watching : :tracking]
                    TopicUser.change(user.id, lookup[:topic_id], notification_level: level)
                else
                    category_id = category_id_from_imported_category_id(f["follow_rel_id"])
                    next unless category_id

                    level = CategoryUser.notification_levels[notify ? :watching : :tracking]
                    CategoryUser.set_notification_level_for_category(user, level, category_id)
                end
            rescue StandardError => e
                puts "Error importing subscription of member #{f["follow_member_id"]}: #{e.message}"
            end
        end
    end

    # IPB rank names, icons and thresholds (core_member_ranks) become badges that a daily badge SQL query
    # grants from the discourse-gamification score. IPB points and earned ranks are not imported: the score
    # is computed by the plugin over the whole imported history, so ranks keep progressing after the
    # migration. Titles stay a member's choice.
    def import_ranks
        puts "", "importing ranks..."

        SiteSetting.discourse_gamification_enabled = true
        SiteSetting.enable_badge_sql = true

        leaderboard =
            DiscourseGamification::GamificationLeaderboard.first ||
                DiscourseGamification::GamificationLeaderboard.create!(name: "Classement", created_by_id: Discourse::SYSTEM_USER_ID)

        ranks = mysql_query(<<~SQL).to_a
            SELECT r.id, r.points, r.icon, TRIM(w.word_default) AS name
            FROM #{TABLE_PREFIX}core_member_ranks r
            JOIN #{TABLE_PREFIX}core_sys_lang_words w
                ON w.word_key = CONCAT('core_member_rank_', r.id)
                AND w.lang_id = (SELECT lang_id FROM #{TABLE_PREFIX}core_sys_lang WHERE lang_default = 1)
            ORDER BY r.points
        SQL

        grouping = BadgeGrouping.find_or_create_by!(name: "Rangs") { |g| g.position = 10 }

        badges =
            ranks.filter_map do |rank|
                name = rank["name"].encode("utf-8", "utf-8")
                # the first rank (0 points in IPB) needs at least one point, so no member has a rank without activity
                points = [rank["points"].to_i, 1].max

                badge = Badge.find_or_initialize_by(name: name)
                badge.assign_attributes(
                    description: "Rang atteint à partir de #{points} #{points == 1 ? "point" : "points"}.",
                    badge_type_id: points >= 10_000 ? BadgeType::Gold : points >= 1_000 ? BadgeType::Silver : BadgeType::Bronze,
                    badge_grouping: grouping,
                    allow_title: true,
                    multiple_grant: false,
                    listable: true,
                    auto_revoke: false,
                    enabled: true,
                    trigger: Badge::Trigger::None,
                    query: rank_badge_query(leaderboard.id, points),
                    icon: "anchor",
                )
                badge.image_upload_id ||= rank_icon_upload(rank["icon"])&.id
                badge.save!
                badge
            rescue StandardError => e
                puts "Error creating badge for rank #{rank["id"]}: #{e.message}"
                nil
            end

        first_post_at = Post.minimum(:created_at)&.to_date || Date.today
        DiscourseGamification::GamificationLeaderboardScore.calculate_scores(leaderboard, since_date: leaderboard.from_date || first_post_at)
        badges.each { |badge| BadgeGranter.backfill(badge) }
    end

    def rank_badge_query(leaderboard_id, points)
        <<~SQL
            SELECT s.user_id, MAX(s.date)::timestamp AS granted_at
            FROM gamification_leaderboard_scores s
            WHERE s.leaderboard_id = #{leaderboard_id}
            GROUP BY s.user_id
            HAVING SUM(s.score) >= #{points}
        SQL
    end

    # Rank icons are SVG files in the uploads dir; the badge keeps its "anchor" icon if the upload is refused
    def rank_icon_upload(icon)
        path = icon.present? && File.join(UPLOADS_DIR, icon)
        return unless path && File.exist?(path)

        upload = create_upload(Discourse::SYSTEM_USER_ID, path, File.basename(path))
        upload if upload&.persisted?
    end

    # Two solved systems coexist: IPB's native one (topic_answered_pid, with core_solved_index for who
    # accepted it) becomes a discourse-solved accepted answer, and a custom plugin that flagged the topic
    # itself (forums_topics.solved). Every solved topic also gets SOLVED_TAG so one filter lists them all.
    # Records are written directly instead of DiscourseSolved::AcceptAnswer to avoid notifications.
    def import_solved
        puts "", "importing solved topics..."

        SiteSetting.solved_enabled = true
        SiteSetting.allow_solved_on_all_topics = true
        SiteSetting.tagging_enabled = true

        rows = mysql_query(<<~SQL).to_a
            SELECT t.tid, t.topic_answered_pid, MIN(s.member_id) AS accepter_id
            FROM #{TABLE_PREFIX}forums_topics t
            LEFT JOIN #{TABLE_PREFIX}core_solved_index s
                ON s.app = 'forums' AND s.item_id = t.tid AND s.comment_id = t.topic_answered_pid
            WHERE t.topic_answered_pid > 0 OR t.solved = 1
            GROUP BY t.tid, t.topic_answered_pid
        SQL

        puts "Solved topics to be processed: #{rows.size}"

        rows.each do |row|
            lookup = topic_lookup_from_imported_post_id("t-#{row["tid"]}")
            topic = lookup && Topic.find_by(id: lookup[:topic_id])
            next unless topic

            begin
                DiscourseTagging.tag_topic_by_names(topic, staff_guardian, [SOLVED_TAG], append: true)

                answer = Post.find_by(id: post_id_from_imported_pid(row["topic_answered_pid"])) if row["topic_answered_pid"].to_i > 0
                next if !answer || answer.topic_id != topic.id || answer.post_number <= 1

                solved_topic = DiscourseSolved::SolvedTopic.find_or_create_by!(topic: topic)
                next if solved_topic.topic_answers.exists?

                accepter = User.find_by(id: user_id_from_imported_user_id(row["accepter_id"])) || Discourse.system_user
                DiscourseSolved::TopicAnswer.create!(solved_topic: solved_topic, post: answer, accepter: accepter)
                UserAction.log_action!(
                    action_type: UserAction::SOLVED,
                    user_id: answer.user_id,
                    acting_user_id: accepter.id,
                    target_post_id: answer.id,
                    target_topic_id: topic.id,
                )
            rescue StandardError => e
                puts "Error importing solved state of topic #{row["tid"]}: #{e.message}"
            end
        end
    end

    # Only participants still in the conversation keep access (IPB removes it when they leave);
    # messages from deleted members are attributed to the system user
    def import_private_messages
        puts "", "importing private messages..."

        last_topic_id = -1
        total_topics = mysql_count(<<~SQL)
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}core_message_topics
            WHERE mt_is_draft = 0
            AND mt_is_deleted = 0
        SQL

        batches(BATCH_SIZE) do |offset|
            topics = mysql_query(<<~SQL).to_a
                SELECT t.mt_id AS id, t.mt_title AS title, p.msg_date, p.msg_post, p.msg_author_id,
                    (SELECT GROUP_CONCAT(u.map_user_id)
                     FROM #{TABLE_PREFIX}core_message_topic_user_map u
                     WHERE u.map_topic_id = t.mt_id AND u.map_user_active = 1) AS participants
                FROM #{TABLE_PREFIX}core_message_topics t
                JOIN #{TABLE_PREFIX}core_message_posts p ON p.msg_topic_id = t.mt_id AND p.msg_is_first_post = 1
                WHERE t.mt_is_draft = 0
                AND t.mt_is_deleted = 0
                AND t.mt_id > #{last_topic_id}
                ORDER BY t.mt_id
                LIMIT #{BATCH_SIZE}
            SQL

            break if topics.empty?

            last_topic_id = topics[-1]["id"]

            create_posts(topics, total: total_topics, offset: offset) do |t|
                next if post_id_from_imported_post_id("pm-t-#{t["id"]}")

                author_id = user_id_from_imported_user_id(t["msg_author_id"])
                user_id = author_id || Discourse::SYSTEM_USER_ID
                active_ids = t["participants"].to_s.split(",")
                participant_ids = active_ids.map { |id| user_id_from_imported_user_id(id) }.compact - [user_id]

                # Everyone else left (or was deleted): the author alone still sees it in IPB. Discourse needs a
                # recipient to create a PM, so the author is given as one and becomes the only participant.
                # Conversations nobody can see any more are skipped.
                if participant_ids.empty?
                    next unless author_id && active_ids.include?(t["msg_author_id"].to_s)
                    participant_ids = [author_id]
                end

                {
                    id: "pm-t-#{t["id"]}",
                    archetype: Archetype.private_message,
                    title: CGI.unescapeHTML(t["title"].encode("utf-8", "utf-8")),
                    user_id: user_id,
                    target_usernames: User.where(id: participant_ids).pluck(:username),
                    created_at: Time.zone.at(t["msg_date"]),
                    raw: clean_up(t["msg_post"], user_id),
                }
            end
        end
    end

    def import_private_message_replies
        puts "", "importing private message replies..."

        last_message_id = -1
        total_messages = mysql_count("SELECT COUNT(*) count FROM #{TABLE_PREFIX}core_message_posts WHERE msg_is_first_post = 0")

        batches(BATCH_SIZE) do |offset|
            messages = mysql_query(<<~SQL).to_a
                SELECT msg_id AS id, msg_topic_id, msg_date, msg_post, msg_author_id
                FROM #{TABLE_PREFIX}core_message_posts
                WHERE msg_is_first_post = 0
                AND msg_id > #{last_message_id}
                ORDER BY msg_id
                LIMIT #{BATCH_SIZE}
            SQL

            break if messages.empty?

            last_message_id = messages[-1]["id"]

            create_posts(messages, total: total_messages, offset: offset) do |m|
                next if post_id_from_imported_post_id("pm-#{m["id"]}")

                # drafts and deleted conversations were not imported
                topic = topic_lookup_from_imported_post_id("pm-t-#{m["msg_topic_id"]}")
                next unless topic

                user_id = user_id_from_imported_user_id(m["msg_author_id"]) || Discourse::SYSTEM_USER_ID

                {
                    id: "pm-#{m["id"]}",
                    topic_id: topic[:topic_id],
                    user_id: user_id,
                    created_at: Time.zone.at(m["msg_date"]),
                    raw: clean_up(m["msg_post"], user_id),
                }
            end
        end
    end

    # Discourse always lets the creator in and re-adds anyone who posts (PostCreator#ensure_in_allowed_users),
    # so members who had left a conversation, and the system user, get access back; restore IPB's participants
    def sync_private_message_participants
        puts "", "syncing private message participants..."

        participants = Hash.new { |h, k| h[k] = [] }
        mysql_query(<<~SQL).each { |row| participants[row["topic_id"]] << row["user_id"] }
            SELECT map_topic_id AS topic_id, map_user_id AS user_id
            FROM #{TABLE_PREFIX}core_message_topic_user_map
            WHERE map_user_active = 1
        SQL

        removed = 0
        participants.each do |mt_id, member_ids|
            topic = topic_lookup_from_imported_post_id("pm-t-#{mt_id}")
            next unless topic

            user_ids = member_ids.map { |id| user_id_from_imported_user_id(id) }.compact
            next if user_ids.empty?

            removed += TopicAllowedUser.where(topic_id: topic[:topic_id]).where.not(user_id: user_ids).delete_all
        end

        puts "#{removed} participants removed"
    end

    # Once everything is imported: links clean_up left on an IPB path (their target was imported later) get
    # their Discourse URL, and links whose text is an old forum URL become the bare Discourse URL, which
    # Discourse shows as the topic title (inline) or a onebox (alone on its line)
    def fix_internal_links
        puts "", "fixing internal links..."

        hosts = OLD_BASE_URLS.map { |host| Regexp.escape(host) }.join("|")
        posts = Post
            .joins("JOIN post_custom_fields f ON f.post_id = posts.id AND f.name = 'import_id'")
            .where("posts.raw ~ ?", "\\]\\(/(topic|forum|profile|blogs)/|\\[[^]]*(#{hosts})")
        total = posts.count
        fixed = 0
        start_time = Time.now

        posts.find_each.with_index do |post, index|
            # link text may hold one level of brackets ("[TUTO#2] …", "[…]")
            raw = post.raw.gsub(/(?<!!)\[((?:\\.|[^\[\]\\]|\[[^\[\]]*\])*)\]\(([^)\s]+)\)/) do
                link, text, target = $&, $1, $2
                url = target.match?(IPB_CONTENT_PATH) ? discourse_url_for(target) : target
                next link unless url&.match?(%r{\A/(?:t|c|u|tag)/})

                ipb_path(text.gsub(/\\(.)/, '\1')) ? "#{Discourse.base_url}#{url}" : "[#{text}](#{url})"
            end

            if raw != post.raw
                post.update_columns(raw: raw)
                post.rebake!
                fixed += 1
            end
            print_status(index + 1, total, start_time)
        end

        puts "", "#{fixed} posts fixed"
    end

    # Old IPB URLs are reduced by PERMALINK_NORMALIZATIONS to "topic/<tid>", "comment/<pid>", "forum/<id>",
    # "profile/<member_id>", "blog-entry/<id>", "blog-comment/<id>" and "blog/<id>", which point to the imported records
    # (a blog to its owner's profile)
    def create_permalinks
        puts "", "creating permalinks..."

        SiteSetting.permalink_normalizations =
            (SiteSetting.permalink_normalizations.split("|") | PERMALINK_NORMALIZATIONS).join("|")

        rows = []

        CategoryCustomField.where(name: "import_id").pluck(:value, :category_id).each do |id, category_id|
            rows << { url: "forum/#{id}", category_id: category_id }
        end

        UserCustomField.where(name: "import_id").pluck(:value, :user_id).each do |id, user_id|
            rows << { url: "profile/#{id}", user_id: user_id }
        end

        first_post_ids = first_post_topic_ids.invert
        PostCustomField
            .where(name: "import_id")
            .joins(:post)
            .pluck(:value, :post_id, "posts.topic_id")
            .each do |id, post_id, topic_id|
                if (tid = id[/\At-(\d+)\z/, 1])
                    rows << { url: "topic/#{tid}", topic_id: topic_id }
                    rows << { url: "comment/#{first_post_ids[tid.to_i]}", post_id: post_id } if first_post_ids[tid.to_i]
                elsif id.match?(/\A\d+\z/)
                    rows << { url: "comment/#{id}", post_id: post_id }
                elsif (entry_id = id[/\Ab-(\d+)\z/, 1])
                    rows << { url: "blog-entry/#{entry_id}", topic_id: topic_id }
                elsif (comment_id = id[/\Abc-(\d+)\z/, 1])
                    rows << { url: "blog-comment/#{comment_id}", post_id: post_id }
                end
            end

        blog_owners.each { |blog_id, user_id| rows << { url: "blog/#{blog_id}", user_id: user_id } }

        # insert_all needs the same keys on every row; it skips URLs that already have a permalink
        blank = { topic_id: nil, post_id: nil, category_id: nil, user_id: nil }
        rows.each_slice(BATCH_SIZE) { |slice| Permalink.insert_all(slice.map { |row| blank.merge(row) }) }
        puts "#{rows.size} permalinks processed"
    end

    # Content by deleted members or guests (author 0 or not imported) goes to one anonymized account per
    # original name, shaped like Discourse's UserAnonymizer output: "anonNNNNNNNN", no profile, no email,
    # no way to log in. Only a digest of the name is kept, to find the same account again on re-runs.
    def anonymous_user_id(author_name)
        key = Digest::SHA1.hexdigest(author_name.to_s.encode("utf-8", "utf-8", invalid: :replace, undef: :replace, replace: "").strip.downcase)
        @anonymous_users ||= {}
        @anonymous_users[key] ||= UserCustomField.find_by(name: "import_anon_key", value: key)&.user_id || create_anonymous_user(key)
    end

    def create_anonymous_user(key)
        username = nil
        username = "anon#{SecureRandom.random_number(100_000_000)}" while username.nil? || User.where(username_lower: username).exists?

        user = User.create!(
            username: username,
            email: "#{username}#{UserAnonymizer::EMAIL_SUFFIX}",
            password: SecureRandom.hex,
            trust_level: TrustLevel[0],
            active: true,
            import_mode: true,
        )
        user.user_option.update!(
            email_digests: false,
            email_level: UserOption.email_level_types[:never],
            email_messages_level: UserOption.email_level_types[:never],
        )
        user.custom_fields["import_anon_key"] = key
        user.save_custom_fields
        user.id
    end

    def staff_guardian
        @_staff_guardian ||= Guardian.new(Discourse.system_user)
    end

    # Converts IPB HTML to Discourse Markdown. Discourse-specific text (quote/details BBCode,
    # mentions, emoji codes, upload markdown, onebox URLs) goes through placeholders so
    # ReverseMarkdown neither escapes it nor reflows it
    def clean_up(raw, user_id = -1)
        return if raw.nil?

        raw.encode!("utf-8", "utf-8", invalid: :replace, undef: :replace, replace: "")

        begin
            Regexp.timeout = 5
            raw.gsub!(%r{<(.+)>&nbsp;</\1>}, "\n\n")
        rescue Regexp::TimeoutError => e
            puts "Regex Timeout Error while processing text: #{raw[0..100]}..."
            return
        end

        @placeholders = []
        doc = Nokogiri::HTML5.fragment(raw)

        # innermost first, so outer blocks carry the already converted inner ones
        doc.css("blockquote.ipsQuote").reverse_each do |bq|
            bq.css(".ipsQuote_citation").each(&:remove)
            header = quote_header(bq)
            open_tag = header.present? ? %{[quote="#{header}"]} : "[quote]"
            wrap_block(bq, bq.at_css(".ipsQuote_contents") || bq, open_tag, "[/quote]")
        end

        doc.css("div.ipsSpoiler").reverse_each do |spoiler|
            title = spoiler.at_css(".ipsSpoiler_header")&.text.to_s.gsub(/[[:space:]]+/, " ").strip.delete('"').presence || "Spoiler"
            wrap_block(spoiler, spoiler.at_css(".ipsSpoiler_contents") || spoiler, %{[details="#{title}"]}, "[/details]")
        end

        doc.css("a[data-mentionid]").each do |a|
            user = User.find_by(id: user_id_from_imported_user_id(a["data-mentionid"]))
            replace_with_text(a, user ? placeholder("@#{user.username}") : a.text)
        end

        doc.css("img").each do |img|
            next unless img.key?("data-emoticon") || img["src"].to_s.include?("emoticons/")

            text = emoticon_text(img["alt"].to_s.strip)
            text.present? ? replace_with_text(img, placeholder(text)) : img.remove
        end

        # thumbnails are wrapped in a link to the full-size file: upload the link target once
        doc.css("a").each do |a|
            fileid = a["data-fileid"] || a.at_css("img[data-fileid]")&.[]("data-fileid")
            next unless fileid || local_upload_path(a["href"]) || a["href"].to_s.match?(/attachment\.php\?id=\d+/)

            markdown = upload_markdown(a["href"], fileid, user_id)
            replace_with_text(a, placeholder(markdown)) if markdown
        end

        doc.css("video").each do |video|
            source = video.at_css("source")
            markdown = source && upload_markdown(source["data-video-src"].presence || source["src"], nil, user_id)
            markdown ? replace_with_text(video, placeholder("\n#{markdown}\n")) : video.remove
        end

        doc.css("img").each do |img|
            src = CGI.unescapeHTML(img["data-src"].presence || img["src"].to_s)
            img.remove_attribute("data-src")

            if src.match?(%r{\A(?:https?:)?//}i) && !ipb_path(src)
                img["src"] = src.start_with?("//") ? "https:#{src}" : src
                img.remove_attribute("alt") if img["alt"].to_s.include?("spacer.png")
            elsif (markdown = upload_markdown(src, img["data-fileid"], user_id))
                replace_with_text(img, placeholder(markdown))
            else
                img.remove
            end
        end

        doc.css("iframe").each do |iframe|
            url = embed_url(iframe["data-embed-src"].presence || iframe["src"])
            url ? replace_with_text(iframe, placeholder("\n\n#{url}\n\n")) : iframe.remove
        end

        # internal links point to the Discourse equivalent, or to the IPB path that a permalink
        # redirects; other "<___base_url___>" links are unwrapped to keep their text
        doc.css("a[href]").each do |a|
            path = ipb_path(a["href"])
            next unless path || a["href"].start_with?("<")

            url = path && (discourse_url_for(path) || (path if path.match?(IPB_CONTENT_PATH)))
            if url
                a["href"] = url
            else
                a.replace(a.children)
            end
        end

        markdown = ReverseMarkdown.convert(doc.to_html).gsub("&nbsp;", " ")
        markdown.gsub(/IPBPH(\d+)X/) { @placeholders[$1.to_i] }
    end

    def placeholder(text)
        @placeholders << text
        "IPBPH#{@placeholders.size - 1}X"
    end

    def replace_with_text(node, text)
        node.replace(Nokogiri::XML::Text.new(text, node.document))
    end

    def wrap_block(node, contents, open_tag, close_tag)
        node.replace("<p>#{placeholder(open_tag)}</p>#{contents.inner_html}<p>#{placeholder(close_tag)}</p>")
    end

    def quote_header(bq)
        comment_id = bq["data-ipsquote-contentcommentid"]
        post_id =
            case bq["data-ipsquote-contentclass"]
            when "forums_Topic" then post_id_from_imported_pid(comment_id)
            when "blog_Entry" then post_id_from_imported_post_id("bc-#{comment_id}")
            end
        post = Post.find_by(id: post_id) if post_id
        return "#{post.user.username}, post:#{post.post_number}, topic:#{post.topic_id}" if post&.user

        user = User.find_by(id: user_id_from_imported_user_id(bq["data-ipsquote-userid"]))
        (user&.username || bq["data-ipsquote-username"].to_s).delete('"')
    end

    # Codes mapped in EMOTICON_EMOJIS / EMOTICON_SET_EMOJIS become that Discourse emoji; other ":name:"
    # codes become the Discourse emoji of the same name, or a custom emoji created from the IPB image;
    # remaining codes (";)", ":P"...) stay as typed and Discourse's shortcuts handle them
    def emoticon_text(alt)
        emojis = Array(EMOTICON_EMOJIS[alt] || EMOTICON_SET_EMOJIS[emoticon_sets[alt]])
        return emojis.map { |emoji| ":#{emoji}:" }.join if emojis.any? && emojis.all? { |emoji| Emoji.exists?(emoji) }

        name = alt[/\A:([\w+-]+):\z/, 1]&.downcase
        return alt unless name
        return ":#{name}:" if Emoji.exists?(name) || custom_emoji?(name, alt)

        alt
    end

    # IPB emoticon code => name of its set ("Crabe", "Mort de rire"...) in the default language
    def emoticon_sets
        @emoticon_sets ||= mysql_query(<<~SQL).to_h { |row| [row["typed"].encode("utf-8", "utf-8"), row["set_name"].to_s.encode("utf-8", "utf-8")] }
            SELECT e.typed, w.word_default AS set_name
            FROM #{TABLE_PREFIX}core_emoticons e
            LEFT JOIN #{TABLE_PREFIX}core_sys_lang_words w
                ON w.word_key = CONCAT('core_emoticon_group_', e.emo_set)
                AND w.lang_id = (SELECT lang_id FROM #{TABLE_PREFIX}core_sys_lang WHERE lang_default = 1)
        SQL
    end

    def custom_emoji?(name, typed)
        @custom_emojis ||= {}
        return @custom_emojis[name] if @custom_emojis.key?(name)

        @custom_emojis[name] = CustomEmoji.exists?(name: name) || create_custom_emoji(name, typed)
    end

    def create_custom_emoji(name, typed)
        row = mysql_query("SELECT image, image_2x FROM #{TABLE_PREFIX}core_emoticons WHERE typed = '#{@client.escape(typed)}' LIMIT 1").first
        image = row && (row["image_2x"].presence || row["image"])
        path = image && File.join(UPLOADS_DIR, image)
        return false unless path && File.exist?(path)

        upload = create_upload(Discourse::SYSTEM_USER_ID, path, "#{name}#{File.extname(path)}")
        return false unless upload&.persisted?

        CustomEmoji.create!(name: name, upload: upload)
        Emoji.clear_cache
        true
    rescue StandardError => e
        puts "Error creating custom emoji #{name}: #{e.message}"
        false
    end

    # Path of an internal IPB URL relative to the forum root (e.g. "/topic/12-slug/"), nil for external URLs
    def ipb_path(url)
        url = CGI.unescapeHTML(url.to_s.strip)
        hosts = OLD_BASE_URLS.map { |host| Regexp.escape(host) }.join("|")

        path =
            if url.start_with?("<___base_url___>")
                url.delete_prefix("<___base_url___>")
            elsif (match = url.match(%r{\A(?:https?:)?//(?:www\.)?(?:#{hosts})(/.*)?\z}i))
                match[1].to_s
            end
        return unless path

        "/#{path.delete_prefix("/").delete_prefix("index.php?").delete_prefix("/")}".sub(%r{\A/forums/(?=(?:topic|forum|profile|blogs)/)}, "/")
    end

    def discourse_url_for(path)
        if (topic_id = path[%r{\A/topic/(\d+)}, 1])
            comment_id = path[/[?&#]comment[=-](\d+)/, 1]
            post = Post.find_by(id: post_id_from_imported_pid(comment_id)) if comment_id
            return post.url if post

            topic = topic_lookup_from_imported_post_id("t-#{topic_id}")
            Topic.find_by(id: topic[:topic_id])&.relative_url if topic
        elsif (forum_id = path[%r{\A/forum/(\d+)}, 1])
            Category.find_by(id: category_id_from_imported_category_id(forum_id))&.url
        elsif (member_id = path[%r{\A/profile/(\d+)}, 1])
            User.find_by(id: user_id_from_imported_user_id(member_id))&.relative_url
        elsif (entry_id = path[%r{\A/blogs/entry/(\d+)}, 1])
            comment_id = path[/[?&#]comment[=-](\d+)/, 1]
            post = Post.find_by(id: post_id_from_imported_post_id("bc-#{comment_id}")) if comment_id
            return post.url if post

            topic = topic_lookup_from_imported_post_id("b-#{entry_id}")
            Topic.find_by(id: topic[:topic_id])&.relative_url if topic
        elsif (blog_id = path[%r{\A/blogs/blog/(\d+)}, 1])
            User.find_by(id: blog_owners[blog_id.to_i])&.relative_url
        end
    end

    def embed_url(src)
        src = CGI.unescapeHTML(src.to_s)

        if src.include?("controller=embed") && (match = src.match(/[?&]url=([^&]+)/))
            url = CGI.unescape(match[1])
            url.match?(/\Ahttps?%3A/i) ? CGI.unescape(url) : url
        elsif (match = src.match(%r{youtube(?:-nocookie)?\.com/embed/([^?&/]+)}))
            "https://www.youtube.com/watch?v=#{match[1]}"
        elsif (path = ipb_path(src))
            url = discourse_url_for(path)
            "#{Discourse.base_url}#{url}" if url
        elsif src.match?(%r{\A(?:https?:)?//}i)
            src.start_with?("//") ? "https:#{src}" : src
        end
    end

    # Every IPB storage area ("<fileStore.core_Attachment>", "<fileStore.core_Emoticons>"...) is the uploads dir
    def local_upload_path(url)
        url = CGI.unescapeHTML(url.to_s).sub(/[?#].*\z/m, "")
        relative =
            if (match = url.match(%r{\A<fileStore\.\w+>/(.+)}))
                match[1]
            elsif (match = ipb_path(url)&.match(%r{\A/uploads/(.+)}))
                match[1]
            end

        return unless relative

        relative =
            begin
                URI.decode_uri_component(relative)
            rescue ArgumentError
                relative
            end
        File.join(UPLOADS_DIR, relative)
    end

    def upload_markdown(url, fileid, user_id)
        attach_id = fileid.presence || url.to_s[/attachment\.php\?id=(\d+)/, 1]
        upload, filename = (attach_id && upload_attachment(attach_id.to_i, user_id)) || upload_local_file(local_upload_path(url), user_id)
        html_for_upload(upload, filename) if upload
    end

    # Files referenced by path get their original name from core_attachments when they are attachments,
    # otherwise the IPB hash is stripped from the stored name ("image.png.<md5>.png" => "image.png")
    def upload_local_file(path, user_id)
        return unless path && File.exist?(path)

        relative = path.delete_prefix("#{UPLOADS_DIR}/")
        row = mysql_query("SELECT attach_id FROM #{TABLE_PREFIX}core_attachments WHERE attach_location = '#{@client.escape(relative)}' LIMIT 1").first
        return upload_attachment(row["attach_id"], user_id) if row

        filename = File.basename(path).sub(/\.\h{32}(?=\.\w+\z)/, "")
        upload = create_upload(user_id, path, filename)
        [upload, filename] if upload&.persisted?
    rescue StandardError => e
        puts "Error uploading #{path}: #{e.message}"
        nil
    end

    def mysql_query(sql)
        begin
        @client.query(sql)
        rescue Mysql2::Error => e
        puts "MySQL Query Error: #{e.message}"
        []
        end
    end

    def mysql_count(sql)
        mysql_query(sql).first&.[]("count").to_i
    end

    # Opening posts are imported as "t-<tid>", so a raw pid only matches replies
    def post_id_from_imported_pid(pid)
        post_id_from_imported_post_id(pid) ||
            ((tid = first_post_topic_ids[pid.to_i]) && post_id_from_imported_post_id("t-#{tid}"))
    end

    def first_post_topic_ids
        @first_post_topic_ids ||= mysql_query(<<~SQL).to_h { |row| [row["pid"].to_i, row["topic_id"].to_i] }
            SELECT pid, topic_id FROM #{TABLE_PREFIX}forums_posts WHERE new_topic = 1
        SQL
    end

    # Uploads the file in place: attach_location is a hashed name, so the original
    # filename (with the stored extension if it has none) is passed separately
    def upload_attachment(attach_id, user_id)
        result = mysql_query("SELECT attach_file, attach_location FROM #{TABLE_PREFIX}core_attachments WHERE attach_id = #{attach_id}").first
        return unless result

        path = File.join(UPLOADS_DIR, result["attach_location"])
        return unless File.exist?(path)

        filename = result["attach_file"].encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "")
        filename = "#{filename}#{File.extname(result["attach_location"])}" if File.extname(filename).length <= 1

        upload = create_upload(user_id, path, filename)
        [upload, filename] if upload&.persisted?
    rescue StandardError => e
        puts "Error uploading attachment #{attach_id}: #{e.message}"
        nil
    end
end

ImportScripts::IPBoard4.new.execute