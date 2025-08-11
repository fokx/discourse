# frozen_string_literal: true
desc "add external_id for all topics and posts"
task "custom:add-external-id", [:override_existing] => :environment do |task, args|
  # use `rake 'custom:add-external-id[1]'` to override topics and posts' existing external_id
  # ensure the first post inside topic has the same external_id with the topic
  require "parallel"
  require "securerandom"
  Parallel.each(Post.all, progress: "Posts") do |post|
    if args[:override_existing].present? || post.external_id.blank?
      post.update_column(:external_id, SecureRandom.alphanumeric(SiteSetting.external_id_length))
      if post.post_number == 1
        topic = Topic.find(post.topic_id)
        topic.update_column(:external_id, post.external_id)
      end
    end
  end
end

# rake custom:export-users > users.json
# rake custom:export-users > /home/discourse/public-export/users.json
desc "Export all users without sensitive data"
task "custom:export-users" => :environment do
  require "json"

  a = []
  User.find_each(batch_size: 100_000) do |user|
    payload = {
      id: user.id,
      username: user.username,
      name: user.name,
      admin: user.admin,
      moderator: user.moderator,
      trust_level: user.trust_level,
      avatar_template: user.avatar_template,
      title: user.title,
      groups: user.groups.map { |i| i.name },
      locale: user.locale,
      silenced_till: user.silenced_till,
      staged: user.staged,
      active: user.active,
      created_at: user.created_at.to_i,
      updated_at: user.updated_at.to_i,
    }
    a.push payload
  end
  puts a.to_json
end

# rake "custom:export-posts[0,/home/discourse/public-export/posts.json]"
desc "Export posts data from non-restricted categories"
task "custom:export-posts", %i[min_id output_file] => :environment do |_, args|
  require "json"

  min_id = (args[:min_id] || 0).to_i
  output_file = args[:output_file]

  puts "Exporting posts with ID > #{min_id}..."

  base_scope =
    Post
      .joins(:topic)
      .joins("JOIN categories c ON c.id = topics.category_id")
      .where("NOT c.read_restricted")
      .where("topics.deleted_at IS NULL")
      .where("posts.deleted_at IS NULL")
      .where(post_type: 1)
      .where(hidden: false)
      .where("posts.id > ?", min_id)

  # Count without the selected columns
  total = base_scope.count
  puts "Found #{total} posts to export"

  posts_data = []

  # Now add the select and order for the actual data retrieval
  scope =
    base_scope.select(
      "posts.id, posts.raw, posts.cooked, posts.post_number,
                  posts.topic_id, posts.user_id, posts.created_at,
                  posts.updated_at, posts.reply_to_post_number,
                  posts.reply_to_user_id, posts.reply_count,
                  topics.like_count, topics.word_count",
    ).order("posts.id ASC")

  progress = 0

  scope.find_each(batch_size: 1000) do |post|
    posts_data << {
      id: post.id,
      raw: post.raw,
      cooked: post.cooked,
      post_number: post.post_number,
      topic_id: post.topic_id,
      user_id: post.user_id,
      created_at: post.created_at,
      updated_at: post.updated_at,
      reply_to_post_number: post.reply_to_post_number,
      reply_to_user_id: post.reply_to_user_id,
      reply_count: post.reply_count,
      like_count: post.like_count,
      word_count: post.word_count,
    }

    progress += 1
    puts "Processed #{progress}/#{total} posts" if progress % 1000 == 0
  end

  result = posts_data.to_json

  if output_file
    File.write(output_file, result)
    puts "Exported data to #{output_file}"
  else
    puts result
  end

  puts "Export completed. Total posts: #{posts_data.size}"
end

# rake "custom:export-likes[0,/home/discourse/public-export/likes.json]"
desc "Export post likes data from non-restricted categories"
task "custom:export-likes", %i[min_id output_file] => :environment do |_, args|
  require "json"

  min_id = (args[:min_id] || 0).to_i
  output_file = args[:output_file]

  puts "Exporting post likes with ID > #{min_id}..."

  # First, get the qualifying post IDs
  qualifying_posts =
    Post
      .joins(:topic)
      .joins("JOIN categories c ON c.id = topics.category_id")
      .where("NOT c.read_restricted")
      .where("topics.deleted_at IS NULL")
      .where("posts.deleted_at IS NULL")
      .where(post_type: 1)
      .where(hidden: false)
      .pluck(:id)

  puts "Found #{qualifying_posts.size} qualifying posts"

  # Now get the likes for these posts
  base_scope =
    PostAction
      .where(post_action_type_id: 2) # 2 is the 'like' action type
      .where(deleted_at: nil)
      .where("id > ?", min_id)
      .where(post_id: qualifying_posts)

  # Count total likes that match criteria
  total = base_scope.count
  puts "Found #{total} likes to export"

  # Exit early if nothing to export
  if total == 0
    puts "No likes to export."
    return
  end

  # Get the data with ordering
  likes_scope = base_scope.select(:id, :post_id, :user_id, :created_at).order(id: :asc)

  likes_data = []
  progress = 0

  # Process in batches to avoid memory issues
  likes_scope.find_each(batch_size: 1000) do |like|
    likes_data << { post_id: like.post_id, user_id: like.user_id, created_at: like.created_at }

    progress += 1
    puts "Processed #{progress}/#{total} likes" if progress % 1000 == 0
  end

  result = likes_data.to_json

  if output_file
    File.write(output_file, result)
    puts "Exported data to #{output_file}"
  else
    puts result
  end

  puts "Export completed. Total likes: #{likes_data.size}"
end

# rake "custom:export-topics[0,/home/discourse/public-export/topics.json]"
desc "Export topics data from non-restricted categories"
task "custom:export-topics", %i[min_id output_file] => :environment do |_, args|
  require "json"

  min_id = (args[:min_id] || 0).to_i
  output_file = args[:output_file]

  puts "Exporting topics with ID > #{min_id}..."

  # Create base scope for the query
  base_scope =
    Topic
      .joins(:category)
      .where("NOT categories.read_restricted")
      .where("topics.deleted_at IS NULL")
      .where(archetype: "regular")
      .where("topics.id > ?", min_id)

  # Count records without including all the selected fields
  total = base_scope.count
  puts "Found #{total} topics to export"

  # Exit early if nothing to export
  if total == 0
    puts "No topics to export."
    return
  end

  topics_data = []
  progress = 0

  # Process in batches to avoid memory issues
  base_scope
    .includes(:tags)
    .order(id: :asc)
    .find_each(batch_size: 1000) do |topic|
      # Get tags as a comma-separated string
      topics_data << {
        id: topic.id,
        category_name: topic.category.name,
        category_id: topic.category_id,
        title: topic.title,
        excerpt: topic.excerpt,
        created_at: topic.created_at,
        last_posted_at: topic.last_posted_at,
        updated_at: topic.updated_at,
        views: topic.views,
        posts_count: topic.posts_count,
        like_count: topic.like_count,
        user_id: topic.user_id,
        last_post_user_id: topic.last_post_user_id,
        tags: topic.tags.map { |i| i.name },
      }

      progress += 1
      puts "Processed #{progress}/#{total} topics" if progress % 1000 == 0
    end

  result = topics_data.to_json

  if output_file
    File.write(output_file, result)
    puts "Exported data to #{output_file}"
  else
    puts result
  end

  puts "Export completed. Total topics: #{topics_data.size}"
end

# rake "custom:export-all[0,/home/discourse/public-export]"
desc "Export all data (topics, posts, likes, users) from non-restricted categories"
task "custom:export-all", %i[min_id output_dir] => :environment do |_, args|
  min_id = args[:min_id] || 0
  output_dir = args[:output_dir] || "/home/discourse/public-export"

  # Ensure output directory exists
  FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

  # Define output file paths
  topics_file = File.join(output_dir, "topics.json")
  posts_file = File.join(output_dir, "posts.json")
  likes_file = File.join(output_dir, "likes.json")
  users_file = File.join(output_dir, "users.json")

  puts "Beginning export of all data to #{output_dir}..."

  # Export topics
  puts "\n=== Exporting Topics ==="
  Rake::Task["custom:export-topics"].invoke(min_id, topics_file)
  Rake::Task["custom:export-topics"].reenable

  # Export posts
  puts "\n=== Exporting Posts ==="
  Rake::Task["custom:export-posts"].invoke(min_id, posts_file)
  Rake::Task["custom:export-posts"].reenable

  # Export likes
  puts "\n=== Exporting Likes ==="
  Rake::Task["custom:export-likes"].invoke(min_id, likes_file)
  Rake::Task["custom:export-likes"].reenable

  # Export users
  puts "\n=== Exporting Users ==="
  # Redirect stdout to file since the users task prints to stdout
  original_stdout = $stdout
  File.open(users_file, "w") do |f|
    $stdout = f
    Rake::Task["custom:export-users"].invoke
    Rake::Task["custom:export-users"].reenable
  end
  $stdout = original_stdout

  puts "\n=== Export Complete ==="
  puts "Topics exported to: #{topics_file}"
  puts "Posts exported to: #{posts_file}"
  puts "Likes exported to: #{likes_file}"
  puts "Users exported to: #{users_file}"
end
