# frozen_string_literal: true
desc 'add global_id for all post without one'
task 'custom:add-global-id' => :environment do
  require 'parallel'
  require 'securerandom'
  Parallel.each(Post.all, progress: "Posts") do |post|
    if post.global_id.blank?
      post.update_column(:global_id, SecureRandom.alphanumeric(SiteSetting.discourse_global_id_length))
    end
  end

end

# rake custom:export-users > users.json
# rake custom:export-users > /shared/users.json
desc "Export all users without sensitive data"
task "custom:export-users" => :environment do
  require 'json'

  a = []
  User.find_each(batch_size: 100_000)  do |user|
    payload = {  id: user.id, username: user.username, name: user.name,
                 admin:user.admin, moderator:user.moderator, trust_level: user.trust_level,
                 avatar_template: user.avatar_template, title: user.title,
                 groups: user.groups.map{|i| i.name}, locale: user.locale,
                 silenced_till: user.silenced_till , staged: user.staged, active: user.active,
                 created_at:user.created_at.to_i, updated_at:user.updated_at.to_i }
    a.push payload
  end
  puts a.to_json
end
