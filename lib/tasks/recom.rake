# frozen_string_literal: true
require "csv"

desc "generate recommended topics for a user"
task "recom:su", %i[user_id suppress_output] => :environment do |task, args|
  # unless DiscourseAi::Embeddings.enabled?
  #   puts "Skip because embedding is not enabled"
  #   next
  # end
  semantic_topic_query = DiscourseAi::Embeddings::SemanticTopicQuery.new

  # use `rake 'recom:su[30]'` to run for another user
  user_id = 4668
  user_id = args[:user_id] if args[:user_id].present?

  total_recom_list = Discourse.cache.fetch("recom_topic_ids_#{user_id}")
  if total_recom_list
    if args[:suppress_output].blank?
      puts "Skip because total_recom_list is cached"
      puts "total length: #{total_recom_list.size}"
      # puts total_recom_list.first(100)
    end
    next
  end

  # https://meta.discourse.org/t/how-does-post-tracking-work-in-discourse/115790
  # PostTiming has erroneously large total read time(e.g. 313115630/86h) for topic,
  # so will use TopicUser instead (e.g. 14395859/4h)

  # u = User.find(user_id)
  # post_timing = PostTiming.where(user_id: user_id)
  # topic_times = post_timing.group(:topic_id).sum(:msecs).sort
  # sorted_times = topic_times.sort_by { |_key, value| value }.to_h
  # CSV.open("topic_times_#{user_id}.csv", "wb") do |csv|
  #   csv << ["topic_id", "time_msecs"]
  #   sorted_times.each do |topic_id, msecs|
  #     csv << [topic_id, msecs]
  #   end
  # end
  # puts topic_times

  # topic_user = TopicUser.where(user_id: user_id)
  # topic_view_item = TopicViewItem.where(user_id: user_id)
  # search_log = SearchLog.where(user_id: user_id)

  # puts topic_user.count
  # puts post_timing.count
  # puts topic_view_item.count
  # puts search_log.count
  topic_user =
    TopicUser
      .joins(:topic)
      .where(user_id: user_id)
      .where.not(topics: { archetype: "private_message" })
      .sort_by { |tu| tu.total_msecs_viewed }
      .reverse
  total_recom_list = Set.new
  # CSV.open("topic_user_#{user_id}.csv", "wb") do |csv|
  #   csv << ["topic_id", "total_msecs_viewed"]
  topic_user.each do |tu|
    # csv << [tu.topic_id, tu.total_msecs_viewed]

    t = Topic.find(tu.topic_id)
    # puts "Topic #{tu.topic_id}: #{t.title}, read time: #{ActiveSupport::Duration.build((tu.total_msecs_viewed / 1000.0).round(2)).inspect}"
    related_topics = semantic_topic_query.list_semantic_related_topics(t)
    # puts "Related topics: #{related_topics.topics.pluck(:title)}"
    total_recom_list.merge(related_topics.topics.pluck(:id))
    # puts
  end
  # end

  if args[:suppress_output].blank?
    puts "Total recom list: #{total_recom_list.size}"
    puts "First 100 topics: #{total_recom_list.first(100)}"
  end
  # save total_recom_list to discourse cache
  Discourse.cache.write("recom_topic_ids_#{user_id}", total_recom_list)
end

desc "generate recommended topics for all users concurrently in last_seen_at order"
task "recom:users", [:num_processes] => :environment do |task, args|
  require "parallel"
  num_processes = 2
  progress = 0

  num_processes = args[:num_processes].to_i if args[:num_processes].present?

  Parallel.each(
    User.where("id > 0").order(Arel.sql("last_seen_at DESC NULLS LAST")),
    in_processes: num_processes,
  ) do |u|
    puts "Start for user #{u.id}"
    total_recom_list = Discourse.cache.fetch("recom_topic_ids_#{u.id}")
    unless total_recom_list
      Rake::Task["recom:su"].invoke(u.id)
      Rake::Task["recom:su"].reenable
    end
    GC.start
    progress += 1
    puts "Done for user #{u.id}, Progress: #{progress}"
  end
end
