# frozen_string_literal: true

require "mysql2"
require "reverse_markdown"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

class ImportScripts::IPBoard4 < ImportScripts::Base
    BATCH_SIZE = 5000
    UPLOADS_DIR = "/path/to/uploads"
    TABLE_PREFIX = ENV["TABLE_PREFIX"] || "ipb_"

    SiteSetting.disable_emails = "non-staff"
    SiteSetting.disable_digest_emails = true

    def initialize
        super

        @client =
        Mysql2::Client.new(
            host: ENV["DB_HOST"] || "localhost",
            username: ENV["DB_USER"] || "root",
            password: ENV["DB_PW"],
            database: ENV["DB_NAME"],
        )

        @client.query("SET character_set_results = binary")
    end

    def execute
        import_users
        import_categories
        import_topics
        import_posts
        import_likes
        import_tags
        import_articles
    end

    def fetch_forum_moderators
        forum_moderators = mysql_query(<<~SQL)
            SELECT DISTINCT m.member_id
            FROM #{TABLE_PREFIX}core_members m
            LEFT JOIN #{TABLE_PREFIX}core_moderators modee ON m.member_id = modee.id
            WHERE modee.type = 'm';
        SQL

        forum_moderators.map { |row| row["member_id"].to_i }
    end

    def fetch_admins
        admin_rows = mysql_query(<<~SQL).to_a
            SELECT row_id, row_id_type FROM #{TABLE_PREFIX}core_admin_permission_rows;
        SQL

        group_admin_ids = []
        member_admin_ids = []

        admin_rows.each do |row|
            if row["row_id_type"] == "group"
                group_admin_ids << row["row_id"].to_i
            elsif row["row_id_type"] == "member"
                member_admin_ids << row["row_id"].to_i
            end
        end

        group_admin_users = mysql_query(<<~SQL)
            SELECT DISTINCT member_id FROM #{TABLE_PREFIX}core_members WHERE member_group_id IN (#{group_admin_ids.join(",")});
        SQL

        (group_admin_users.map { |row| row["member_id"].to_i } + member_admin_ids).uniq
    end

    def import_users
        puts "", "importing users..."

        last_user_id = -1
        about_me_column = "field_11"
        total_users = mysql_query("SELECT COUNT(*) count FROM #{TABLE_PREFIX}core_members").first["count"]
        moderator_ids = fetch_forum_moderators
        admin_ids = fetch_admins

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
                    NULLIF(p.#{about_me_column}, '') AS pp_about_me,
                    m.pp_main_photo
                FROM #{TABLE_PREFIX}core_members AS m
                LEFT JOIN #{TABLE_PREFIX}core_pfields_content AS p ON m.member_id = p.member_id
                WHERE m.member_id > #{last_user_id}
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
                            if u["member_banned"] == 1
                                new_user.update(suspended_at: DateTime.now, suspended_till: 100.years.from_now)
                            elsif u["pp_main_photo"].present?
                                path = File.join(UPLOADS_DIR, u["pp_main_photo"])
                                
                                if File.exist?(path)
                                    begin
                                        upload = create_upload(new_user.id, path, File.basename(path))
                                        if upload.persisted?
                                            new_user.create_user_avatar
                                            new_user.user_avatar.update(custom_upload_id: upload.id)
                                            new_user.update(uploaded_avatar_id: upload.id)
                                        end
                                    rescue StandardError => e
                                        puts "Failed to upload avatar for user #{u["id"]}: #{e.message}"
                                    end
                                end
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
            JOIN #{TABLE_PREFIX}core_sys_lang_words desc_lang 
                ON desc_lang.word_key = CONCAT('forums_forum_', f.id, '_desc')
            LEFT JOIN #{TABLE_PREFIX}forums_forums p
                ON f.parent_id = p.id
            WHERE f.parent_id != -1
        SQL

        parent_categories = categories.select { |c| c["parent_id"] == -1 }
        child_categories = categories.select { |c| c["parent_id"] != -1 }
    
        create_categories(parent_categories) do |c|
        next if category_id_from_imported_category_id(c["id"])
        {
            id: c["id"],
            name: c["category_name"].encode("utf-8", "utf-8"),
            description: clean_up(c["description"]),
            position: c["position"],
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
        }
        end
    end

    def import_topics
        puts "", "importing topics..."
    
        last_topic_id = -1
        total_topics = mysql_query(<<~SQL).first["count"]
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}forums_topics t
            JOIN #{TABLE_PREFIX}forums_posts p ON t.tid = p.topic_id
            WHERE t.topic_close_time = 0
            AND p.pdelete_time = 0
            AND p.new_topic = 1
            AND t.approved = 1
            AND p.queued = 0
        SQL

        puts "Total topics to be imported: #{total_topics}"

        batches(BATCH_SIZE) do |offset|
            topics = mysql_query(<<~SQL).to_a
                SELECT t.tid AS id, t.title, t.state, t.starter_id, t.start_date, t.views, t.forum_id, t.pinned, p.post
                FROM #{TABLE_PREFIX}forums_topics t
                JOIN #{TABLE_PREFIX}forums_posts p ON t.tid = p.topic_id
                WHERE t.topic_close_time = 0
                AND p.pdelete_time = 0
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
                user_id = user_id_from_imported_user_id(t["starter_id"])
                
                if user_id.nil?
                    puts "Skipping topic #{t["id"]} - User ID #{t['starter_id']} not found"
                    next
                end
                {
                    id: "t-#{t["id"]}",
                    title: CGI.unescapeHTML(t["title"].encode("utf-8", "utf-8")),
                    user_id: user_id,
                    created_at: created_at,
                    views: t["views"],
                    category: category_id_from_imported_category_id(t["forum_id"]),
                    pinned_at: t["pinned"] == 1 ? created_at : nil,
                    raw: clean_up(t["post"], user_id),
                    closed: t["state"] != "open"
                }
            end
        end
    end

    def import_posts
        puts "", "importing posts..."
    
        last_post_id = -1
        total_posts = mysql_query(<<~SQL).first["count"]
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}forums_posts
            WHERE new_topic = 0
                AND pdelete_time = 0
                AND queued = 0
        SQL

        puts "Total posts to be imported: #{total_posts}"
    
        batches(BATCH_SIZE) do |offset|
            posts = mysql_query(<<~SQL).to_a
                SELECT pid AS id, author_id, post_date, post, topic_id
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

                user_id = user_id_from_imported_user_id(p["author_id"])

                if user_id.nil?
                    puts "Skipping post #{p["id"]} - User ID #{p["author_id"]} not found"
                    next
                end
    
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

    def import_likes
        puts "", "importing post likes"
    
        last_id = -1
        RateLimiter.disable

        batches(BATCH_SIZE) do |offset|
            likes = mysql_query(<<-SQL).to_a
                SELECT id, member_id AS user_id, type_id AS post_id, rep_date AS created_at
                FROM #{TABLE_PREFIX}core_reputation_index
                WHERE rep_rating = 1
                AND id > #{last_id}
                ORDER BY id
                LIMIT #{BATCH_SIZE}
            SQL

            break if likes.empty?

            last_id = likes[-1]["id"]
        
            likes.each do |like|
                user_id = user_id_from_imported_user_id(like["user_id"])
                next unless user_id

                post_id = post_id_from_imported_post_id(like["post_id"])
                next unless post_id

                user = User.find_by(id: user_id)
                next unless user

                post = Post.find_by(id: post_id)
                next unless post

                next if PostAction.exists?(user_id: user_id, post_id: post_id, post_action_type_id: 2)

                begin
                    PostActionCreator.like(user,post)

                rescue StandardError => e
                    puts "Error importing like for post #{like["post_id"]} by user #{like["user_id"]}: #{e.message}"
                end
            end
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
        total_articles = mysql_query(<<~SQL).first["count"]
            SELECT COUNT(*) AS count
            FROM #{TABLE_PREFIX}cms_custom_database_1
            WHERE record_locked = 0
        SQL

        puts "Total articles to be imported: #{total_articles}"
        articles_category_id = Category.find_by(name: "articles")&.id

        puts "First create a category named articles" if articles_category_id.nil?
        return if articles_category_id.nil?


        batches(BATCH_SIZE) do |offset|
            articles = mysql_query(<<~SQL).to_a
                SELECT primary_id_field AS id, field_1 AS title, member_id, record_publish_date, record_views AS views,
                CONCAT(field_2, '<br><br><hr><br><br>', field_3) AS post
                FROM #{TABLE_PREFIX}cms_custom_database_1
                WHERE record_locked = 0
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
                    raw: clean_up(t["post"], user_id)
                }
            end
        end
    end

    def staff_guardian
        @_staff_guardian ||= Guardian.new(Discourse.system_user)
    end

    def clean_up(raw, user_id = -1)
        return if raw.nil?

        raw.encode!("utf-8", "utf-8", invalid: :replace, undef: :replace, replace: "")

        begin
            raw.encode!("utf-8", "utf-8", invalid: :replace, undef: :replace, replace: "")
            Regexp.timeout = 5
            raw.gsub!(%r{<(.+)>&nbsp;</\1>}, "\n\n")
    
        rescue Regexp::TimeoutError => e
            puts "Regex Timeout Error while processing text: #{raw[0..100]}..."
            return
        end
      
        doc = Nokogiri::HTML5.fragment(raw)

        doc.css("blockquote.ipsBlockquote").each do |bq|
          post_id = post_id_from_imported_post_id(bq["data-cid"])
          if post = Post.find_by(id: post_id)
            bq.replace %{<br>[quote="#{post.user.username},post:#{post.post_number},topic:#{post.topic_id}"]\n#{bq.inner_html}\n[/quote]<br>}
          end
        end

        doc.css("a").each do |a|
            href = a["href"].to_s
            img = a.previous_element if a.previous_element&.name == "img"
            
            if href.start_with?("<___base_url___>/index.php?app=core&module=attach")
                if (match_data = href.match(/attach_id=(\d+)/))
                    attach_id = match_data[1].to_i
                    result = mysql_query("SELECT attach_file, attach_location FROM #{TABLE_PREFIX}core_attachments WHERE attach_id = #{attach_id}").first
        
                    if result
                        original_path = File.join(UPLOADS_DIR, result["attach_location"])
                        directory = File.dirname(original_path)
                        filename = result["attach_file"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

                        extname = File.extname(result["attach_location"])
                        basename = File.basename(result["attach_location"], extname)

                        new_filename = filename if File.extname(filename).length > 1
                        new_filename ||= "#{filename}#{extname}"
                        new_path = File.join(directory, new_filename)

                        if File.exist?(original_path) && !File.exist?(new_path)
                            File.rename(original_path, new_path)
                        end
        
                        if File.exist?(new_path)
                            begin
                                upload = create_upload(user_id, new_path, new_filename)
                                if upload&.persisted?
                                    new_url = html_for_upload(upload, new_filename)
                                    if img
                                        img.replace(new_url)
                                        img.remove_attribute("data-src")
                                        a.remove
                                    else
                                        a.replace("![#{new_filename}](#{new_url})")
                                    end
                                end
                            rescue StandardError => e
                                puts "Error processing attachment link: #{e.message}"
                            end
                        end
                    end
                end
            elsif (match_data = a["href"]&.match(%r{/attachment\.php\?id=(\d+)}))
                attach_id = match_data[1].to_i
        
                result = mysql_query("SELECT attach_file, attach_location FROM #{TABLE_PREFIX}core_attachments WHERE attach_id = #{attach_id}").first
                if result
                    original_path = File.join(UPLOADS_DIR, result["attach_location"])
                    directory = File.dirname(original_path)
                    filename = result["attach_file"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

                    extname = File.extname(result["attach_location"])
                    basename = File.basename(result["attach_location"], extname)

                    new_filename = filename if File.extname(filename).length > 1
                    new_filename ||= "#{filename}#{extname}"
                    new_path = File.join(directory, new_filename)

                    if File.exist?(original_path) && !File.exist?(new_path)
                        File.rename(original_path, new_path)
                    end

                    if File.exist?(new_path)
                        begin
                            upload = create_upload(user_id, new_path, new_filename)
                            if upload&.persisted?
                                new_url = html_for_upload(upload, new_filename)
                                a.replace(new_url)
                            end
                            rescue StandardError => e
                        end
                    end
                end
            elsif(a["href"].to_s.start_with?("<fileStore.core_Attachment>/"))
                filename = File.basename(a["href"].to_s).encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                extracted_path = a["href"].to_s.sub("<fileStore.core_Attachment>/", "")
                path = File.join(UPLOADS_DIR, extracted_path)
                if File.exist?(path)
                    begin
                        upload = create_upload(user_id, path, filename)
                        if upload&.persisted?
                            new_url = html_for_upload(upload, filename)
                            a.replace(new_url)
                        end
                    rescue StandardError => e
                    end
                end
            elsif(a["href"].to_s.start_with?("<"))
                a.remove
            end
        end

        doc.css("img").each do |img|
            img["src"] = img["data-src"]
            img.remove_attribute("data-src")
            if img["src"]&.match(%r{/uploads/imageproxy/([^/]+)$})
                filename = $1
                path = File.join(UPLOADS_DIR, "imageproxy", filename)

                if File.exist?(path)
                    begin
                        upload = create_upload(user_id, path, filename)
                        if upload&.persisted?
                            image_url = html_for_upload(upload, filename)
                            img.replace(image_url)
                        end
                    rescue StandardError => e
                    end
                end
            elsif img["src"].to_s.start_with?("<fileStore.core_Attachment>/")
                filename = File.basename(img["src"].to_s).encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                extracted_path = img["src"].to_s.sub("<fileStore.core_Attachment>/", "")
                path = File.join(UPLOADS_DIR, extracted_path)

                if File.exist?(path)
                    begin
                        upload = create_upload(user_id, path, filename)
                        if upload&.persisted?
                            image_url = html_for_upload(upload, filename)
                            img.replace(image_url)
                        end
                    rescue StandardError => e
                    end
                end
            elsif img["src"]&.match(%r{^uploads/emoticons/(.+)$})
                filename = $1.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                path = File.join(UPLOADS_DIR, "emoticons", filename)
        
                if File.exist?(path)
                    begin
                        upload = create_upload(user_id, path, filename)
                        if upload&.persisted?
                            image_url = html_for_upload(upload, filename)
                            img.replace(image_url)
                        end
                    rescue StandardError => e
                        puts "Error processing emoticon upload: #{e.message}"
                    end
                else
                    puts "File not found: #{path}"
                end
            else
                img.remove
            end
        end

        doc.css("iframe").each do |iframe|
            url = iframe["data-embed-src"] || iframe["src"]
            next unless url
    
            if match = url.match(%r{<___base_url___>/index\.php\?app=core&module=system&controller=embed&url=(.+)$})
                embedded_url = CGI.unescape(CGI.unescapeHTML(CGI.unescape(match[1])))
            elsif url.start_with?("https://www.youtube.com/embed/") or url.start_with?("https://www.youtube-nocookie.com/embed/")
                youtube_id = url.match(%r{/embed/([^?]+)})[1]
                embedded_url = "https://www.youtube.com/watch?v=#{youtube_id}"
            elsif url.match(%r{/topic/(\d+)-.*\?do=embed})
                topic_id = url.match(%r{/topic/(\d+)-.*\?do=embed})[1]
                discourse_topic_id = post_id_from_imported_post_id("t-#{topic_id}")
                if discourse_topic_id
                    embedded_url = "#{Discourse.base_url}/t/topic/#{discourse_topic_id}"
                end
            else
                iframe.replace(url)
            end
            if embedded_url
                parent = iframe.ancestors.to_a.find { |el| el.parent } || iframe
                formatted_url = "\n#{embedded_url.strip}\n"
                if parent && parent.parent
                    parent.content = formatted_url
                else
                    iframe.content = formatted_url
                end
            else 
                parent = iframe.ancestors.to_a.find { |el| el.parent }
                
                if parent && parent.parent
                    parent.remove
                else
                    iframe.remove
                end
            end
        end

        markdown = ReverseMarkdown.convert(doc.to_html)
        markdown
    end

    def mysql_query(sql)
        begin
        @client.query(sql)
        rescue Mysql2::Error => e
        puts "MySQL Query Error: #{e.message}"
        []
        end
    end
end

ImportScripts::IPBoard4.new.execute