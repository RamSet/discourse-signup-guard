# discourse-signup-guard

A small Discourse plugin that stops bot signups in two ways:

- **A checked signup question.** You pick a required user field and list the answers that pass. A wrong answer is refused with a visible message.
- **A hidden trap field.** A user field named `Leave this empty` is moved off screen. If it arrives filled, the signup gets the same fake "check your email" reply Discourse core gives a failed honeypot, and no account is created.

It is server-side only. Discourse already draws admin-created user fields on the signup form, so the plugin adds no signup-form code of its own. It only checks what the form sends back.

## Status: untested

**This plugin has not been run on a live Discourse yet.** The hooks were read from Discourse `2026.12.0-latest` source, and a request spec is included, but neither has been executed. Please try it on a staging copy first, or install it with the setting off (the default) and follow the test steps below.

## Install

On a standard Docker install, add the clone line under `hooks: after_code:` in `containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/RamSet/discourse-signup-guard.git
```

Then rebuild. The forum is down for a few minutes while this runs:

```
cd /var/discourse && ./launcher rebuild app
```

The plugin installs switched off and changes nothing until it is set up.

## Set up

1. Admin → Customize → User Fields: add a **text** field holding your question. Make it required at signup.
2. Add a second **text** field named exactly `Leave this empty`. Optional, shown at signup, not shown on the profile, not editable.
3. Admin → Settings, search `signup guard`:
   - `signup guard question field id`: the number in the question field's edit URL.
   - `signup guard accepted answers`: every answer that should pass. Case and extra spaces are ignored.
   - `signup guard enabled`: turn on last.

Pick a question a real user of your product can answer but that is not answered on your homepage. An obvious question is answered by any bot that uses a language model.

## Test it after turning it on

Open the signup form in a private window and try three signups. Watch `/logs` for lines starting with `[signup-guard]`.

| Try | Expected |
| --- | --- |
| Right answer, trap empty | Account is created as usual |
| Wrong answer | "That is not the right answer to the signup question", no account |
| Right answer, trap filled (fill it from browser dev tools) | Looks like success, no account, a `trap filled` log line |

Also check that the `Leave this empty` field is not visible on the signup form.

## What it does not do

- It does not stop bots driven by a language model that can read and answer the question.
- It does not check invited users or accounts created by an admin through the API.
- If the question field or the accepted answers are not set, it lets signups through, so a wrong setting cannot close registration.

## Turn it off

Untick `signup guard enabled`. To remove it, delete the clone line from `app.yml` and rebuild.

## Run the spec

From a Discourse development checkout with this plugin in `plugins/`:

```
LOAD_PLUGINS=1 bin/rspec plugins/discourse-signup-guard/spec
```
