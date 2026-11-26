# frozen_string_literal: true

RSpec.describe "Signup guard" do
  fab!(:question) { Fabricate(:user_field, name: "What grows in an orchard?", requirement: "on_signup") }
  fab!(:trap) { Fabricate(:user_field, name: "Verification phrase (2)", requirement: "optional") }

  before do
    SiteSetting.signup_guard_enabled = true
    SiteSetting.signup_guard_question_field_id = question.id
    SiteSetting.signup_guard_trap_field_id = trap.id
    SiteSetting.signup_guard_accepted_answers = "apples|trees"
  end

  def signup(user_fields)
    get "/session/hp.json"
    hp = response.parsed_body
    post "/u.json",
         params: {
           name: "New Person",
           username: "newperson",
           email: "newperson@example.com",
           password: "a-very-strong-password-123",
           password_confirmation: hp["value"],
           challenge: hp["challenge"].reverse,
           user_fields: user_fields,
         }
    response.parsed_body
  end

  it "creates the account on a right answer (positive control)" do
    body = signup(question.id.to_s => "  Apples ")
    expect(body["success"]).to eq(true)
    expect(User.find_by(username: "newperson")).to be_present
  end

  it "refuses a wrong answer and says so" do
    body = signup(question.id.to_s => "bananas")
    expect(body["success"]).to eq(false)
    expect(body["message"]).to eq(I18n.t("signup_guard.wrong_answer"))
    expect(User.find_by(username: "newperson")).to be_nil
  end

  it "gives a plain error and creates nothing when the trap is filled" do
    body = signup(question.id.to_s => "apples", trap.id.to_s => "http://spam.example")
    expect(body["success"]).to eq(false)
    expect(body["message"]).to eq(I18n.t("signup_guard.generic_error"))
    expect(User.find_by(username: "newperson")).to be_nil
  end

  it "blocks nothing on a filled trap unless told to" do
    signup(question.id.to_s => "apples", trap.id.to_s => "x")
    expect(ScreenedEmail.count).to eq(0)
    expect(ScreenedIpAddress.count).to eq(0)
  end

  it "blocks the email and the IP on a filled trap when both are switched on" do
    SiteSetting.signup_guard_trap_blocks_email = true
    SiteSetting.signup_guard_trap_blocks_ip = true
    signup(question.id.to_s => "apples", trap.id.to_s => "x")
    expect(ScreenedEmail.should_block?("newperson@example.com")).to eq(true)
    expect(ScreenedIpAddress.should_block?("127.0.0.1")).to eq(true)
  end

  it "blocks nothing on a wrong answer" do
    SiteSetting.signup_guard_trap_blocks_email = true
    SiteSetting.signup_guard_trap_blocks_ip = true
    signup(question.id.to_s => "bananas")
    expect(ScreenedEmail.count).to eq(0)
    expect(ScreenedIpAddress.count).to eq(0)
  end

  it "builds the hiding CSS from the trap field's name" do
    expect(SignupGuard.trap_css).to include(".user-field.user-field-verification-phrase-2{")
  end

  it "lets signups through when the plugin is off" do
    SiteSetting.signup_guard_enabled = false
    signup(question.id.to_s => "bananas")
    expect(User.find_by(username: "newperson")).to be_present
  end

  it "does not close signups when no answers are set" do
    SiteSetting.signup_guard_accepted_answers = ""
    signup(question.id.to_s => "anything")
    expect(User.find_by(username: "newperson")).to be_present
  end
end
