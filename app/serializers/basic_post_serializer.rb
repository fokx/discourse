# frozen_string_literal: true

# The most basic attributes of a topic that we need to create a link for it.
class BasicPostSerializer < ApplicationSerializer
  attributes :id,
             :name,
             :username,
             :avatar_template,
             :created_at,
             :cooked,
             :cooked_hidden,
             :external_id

  attr_accessor :topic_view

  def name
    object.user && object.user.name
  end

  def username
    object.user && object.user.username
  end

  def avatar_template
    object.user && object.user.avatar_template
  end

  def cooked_hidden
    object.hidden && !scope.is_staff?
  end

  def include_cooked_hidden?
    cooked_hidden
  end

  def include_external_id?
    external_id
  end

  def cooked
    if cooked_hidden
      if scope.current_user && object.user_id == scope.current_user.id
        I18n.t("flagging.you_must_edit", path: "/my/messages")
      else
        I18n.t("flagging.user_must_edit")
      end
    else
      cooked = object.filter_quotes(@parent_post)

      translated_cooked =
        object.get_localization&.cooked if ContentLocalization.show_translated_post?(object, scope)

      translated_cooked || cooked
    end
  end

  def include_name?
    SiteSetting.enable_names?
  end

  def post_custom_fields
    @post_custom_fields ||=
      if @topic_view
        (@topic_view.post_custom_fields || {})[object.id] || {}
      else
        object.custom_fields
      end
  end
end
