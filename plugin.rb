# frozen_string_literal: true

# name: discourse-signup-guard
# about: Stops bot signups with a checked signup question and a hidden trap field
# version: 0.1.0
# authors: RamSet

enabled_site_setting :signup_guard_enabled

register_asset "stylesheets/signup-guard.scss"

after_initialize do
  module ::SignupGuard
    TRAP_FIELD_NAME = "leave this empty"

    def self.normalize(value)
      value.to_s.unicode_normalize(:nfkc).strip.downcase.squeeze(" ")
    end

    def self.trap_field_id
      UserField.where("LOWER(TRIM(name)) = ?", TRAP_FIELD_NAME).pick(:id)
    end

    def self.accepted_answers
      SiteSetting.signup_guard_accepted_answers.split("|").map { |a| normalize(a) }.reject(&:blank?)
    end

    # Returns :trap, :wrong_answer or nil (let the signup through).
    # Fails open when the plugin is not fully set up, so a bad setting never closes signups.
    def self.verdict(user_fields)
      values = user_fields.respond_to?(:[]) && !user_fields.is_a?(String) ? user_fields : {}

      trap_id = trap_field_id
      return :trap if trap_id && values[trap_id.to_s].to_s.strip.present?

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
        # Same answer core gives a failed honeypot: looks like success, creates nothing.
        render json: {
                 success: true,
                 active: false,
                 message: I18n.t("login.activate_email", email: params[:email]),
               }
      when :wrong_answer
        Rails.logger.warn("[signup-guard] wrong answer ip=#{request.remote_ip}")
        render json: { success: false, message: I18n.t("signup_guard.wrong_answer") }
      end
    end
  end

  reloadable_patch { UsersController.prepend(SignupGuard::UsersControllerExtension) }
end
