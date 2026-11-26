# frozen_string_literal: true

# name: discourse-signup-guard
# about: Stops bot signups with a checked signup question and a hidden trap field
# version: 0.1.0
# authors: RamSet

enabled_site_setting :signup_guard_enabled

after_initialize do
  module ::SignupGuard
    def self.normalize(value)
      value.to_s.unicode_normalize(:nfkc).strip.downcase.squeeze(" ")
    end

    # CSS that moves the trap field off screen. Discourse gives each signup field a class
    # built from its name, so the class is rebuilt here the same way and escaped.
    # Off screen rather than display:none, which some bots skip.
    def self.trap_css
      name = UserField.where(id: SiteSetting.signup_guard_trap_field_id).pick(:name)
      return "" if name.blank?

      slug = name.gsub(/\s+/, "-").gsub(%r{[!"\#\$%&'()*+,./:;<=>?@\[\\\]^`{|}~]}, "").downcase
      return "" if slug.blank?

      css_class = "user-field-#{slug}".gsub(/[^a-zA-Z0-9_-]/) { |c| "\\#{c.ord.to_s(16)} " }
      "<style>.user-field.#{css_class}{position:absolute!important;left:-9999px!important;" \
        "width:1px;height:1px;overflow:hidden}</style>"
    end

    def self.accepted_answers
      SiteSetting.signup_guard_accepted_answers.split("|").map { |a| normalize(a) }.reject(&:blank?)
    end

    # Returns :trap, :wrong_answer or nil (let the signup through).
    # Fails open when the plugin is not fully set up, so a bad setting never closes signups.
    def self.verdict(user_fields)
      values = user_fields.respond_to?(:[]) && !user_fields.is_a?(String) ? user_fields : {}

      trap_id = SiteSetting.signup_guard_trap_field_id
      return :trap if trap_id > 0 && values[trap_id.to_s].to_s.strip.present?

      question_id = SiteSetting.signup_guard_question_field_id
      answers = accepted_answers
      return nil if question_id <= 0 || answers.empty? || !UserField.exists?(id: question_id)

      answers.include?(normalize(values[question_id.to_s])) ? nil : :wrong_answer
    end
  end

  module ::SignupGuard::UsersControllerExtension
    extend ActiveSupport::Concern

    prepended { before_action :signup_guard_check, only: [:create] }

    private

    def signup_guard_check
      return if !SiteSetting.signup_guard_enabled
      return if is_api? && current_user&.admin?

      case SignupGuard.verdict(params[:user_fields])
      when :trap
        Rails.logger.warn("[signup-guard] trap filled ip=#{request.remote_ip}")
        # A plain error that does not say which field caused it.
        render json: { success: false, message: I18n.t("signup_guard.generic_error") }
      when :wrong_answer
        Rails.logger.warn("[signup-guard] wrong answer ip=#{request.remote_ip}")
        render json: { success: false, message: I18n.t("signup_guard.wrong_answer") }
      end
    end
  end

  register_html_builder("server:before-head-close") do
    SiteSetting.signup_guard_trap_field_id > 0 ? SignupGuard.trap_css : ""
  end

  reloadable_patch { UsersController.prepend(SignupGuard::UsersControllerExtension) }
end
