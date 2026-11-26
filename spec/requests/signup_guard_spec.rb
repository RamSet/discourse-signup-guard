# frozen_string_literal: true

RSpec.describe "Signup guard" do
  fab!(:question) { Fabricate(:user_field, name: "What grows in an orchard?", requirement: "on_signup") }
  fab!(:trap) { Fabricate(:user_field, name: "Leave this empty", requirement: "optional") }

  before do
    SiteSetting.signup_guard_enabled = true
    SiteSetting.signup_guard_question_field_id = question.id
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

  it "pretends success and creates nothing when the trap is filled" do
    body = signup(question.id.to_s => "apples", trap.id.to_s => "http://spam.example")
    expect(body["success"]).to eq(true)
    expect(User.find_by(username: "newperson")).to be_nil
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
