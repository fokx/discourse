# frozen_string_literal: true

module DiscourseAi
  module Embeddings
    module Strategies
      class Truncation
        TEXT_TO_HTML_TOKEN_RATIO = 3

        def id
          1
        end

        def version
          1
        end

        def prepare_target_text(target, vdef)
          max_length = vdef.max_sequence_length - 2

          prepared_text =
            case target
            when Topic
              topic_truncation(target, vdef.tokenizer, max_length)
            when Post
              post_truncation(target, vdef.tokenizer, max_length)
            when RagDocumentFragment
              vdef.tokenizer.truncate(
                sanitize_utf8(target.fragment),
                max_length,
                strict: SiteSetting.ai_strict_token_counting,
              )
            else
              raise ArgumentError, "Invalid target type"
            end

          return prepared_text if vdef.embed_prompt.blank?

          [sanitize_utf8(vdef.embed_prompt), prepared_text].join(" ")
        end

        def prepare_query_text(text, vdef, asymmetric: false)
          qtext = ""
          if asymmetric && vdef.search_prompt.present?
            qtext = "#{vdef.search_prompt} #{text}"
          else
            qtext = text
          end
          max_length = vdef.max_sequence_length - 2

          vdef.tokenizer.truncate(qtext, max_length, strict: SiteSetting.ai_strict_token_counting)
        end

        private

        def topic_information(topic)
          info = +""

          if topic&.title.present?
            info << topic.title
            info << "\n\n"
          end
          if topic&.category&.name.present?
            info << topic.category.name
            info << "\n\n"
          end
          if SiteSetting.tagging_enabled && topic&.tags.present?
            info << topic.tags.pluck(:name).join(", ")
            info << "\n\n"
          end

          info
        end

        def topic_truncation(topic, tokenizer, max_length)
          @current_topic_id = topic.id

          text = +sanitize_utf8(topic_information(topic))

          if topic&.topic_embed&.embed_content_cache.present?
            embed_text = Nokogiri::HTML5.fragment(topic.topic_embed.embed_content_cache).text
            text << sanitize_utf8(embed_text)
            text << " "
          end

          posts_text = +""
          posts_text_size = 0

          topic.posts.find_each do |post|
            post_cooked_sanitized = sanitize_utf8(post.cooked)
            posts_text_size += tokenizer.size(post_cooked_sanitized)
            posts_text << post_cooked_sanitized
            posts_text << " "
            break if posts_text_size >= max_length

            # Since we will strip all HTML tags before embedding, we can fit more text
            # than the max_length as it will shrink after Nokogiri extracts the text
            break if posts_text_size >= max_length * TEXT_TO_HTML_TOKEN_RATIO
          end

          text << Nokogiri::HTML5.fragment(posts_text).text

          safe_truncate(text, tokenizer, max_length, topic)
          # tokenizer.truncate(text, max_length, strict: SiteSetting.ai_strict_token_counting)
        end

        def post_truncation(post, tokenizer, max_length)
          text = +topic_information(post.topic)

          if post.is_first_post? && post.topic&.topic_embed&.embed_content_cache.present?
            embed_text = Nokogiri::HTML5.fragment(post.topic.topic_embed.embed_content_cache).text
            text << sanitize_utf8(embed_text)
          else
            post_text = Nokogiri::HTML5.fragment(post.cooked).text
            text << sanitize_utf8(post_text)
          end

          tokenizer.truncate(text, max_length, strict: SiteSetting.ai_strict_token_counting)
        end

        def sanitize_utf8_old(text)
          # First try to encode/decode to ensure UTF-8 validity
          cleaned = text.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "�")

          # Then remove any null bytes or other problematic characters
          cleaned.gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")
        end

        def sanitize_utf8(text)
          return "" if text.blank?

          # Round-trip through UTF-16, replacing any undefined / invalid bytes on the way
          text
            .encode("UTF-16LE", "UTF-8", invalid: :replace, undef: :replace, replace: "�")
            .encode("UTF-8", "UTF-16LE")
            .scrub("�") # extra safety – remove any stray half-codepoints
        end

        def safe_truncate(text, tokenizer, max_length, topic)
          tokenizer.truncate(text, max_length, strict: SiteSetting.ai_strict_token_counting)
        rescue Tiktoken::UnicodeError => e
          Rails.logger.warn(
            "[AI-Embeddings] post traunction #{topic.id} #{tokenizer.size(text)} #{max_length} #{e.message} #{text}",
          )
          raise
        end
      end
    end
  end
end
