# Agent rules for this repository

## Git

1. Never commit or push without Luke's explicit permission, given for that
   specific commit or push. Staging is fine; committing is not.
2. Never add co-author trailers, "Generated with" lines, session tags, or any
   other attribution to commits or pull requests.
3. Commit messages lean toward title-only: one short line. Detail belongs in
   a changelog or the README, not in the commit message.

## Project notes

* The app is called "rdo" (display name). The Xcode project, Swift package,
  targets and bundle id keep the working name PhoneList; do not rename them.
* Build and test on this machine; the phone is deployed from Luke's laptop
  via Xcode (see README, Build).
* `swift build` and `./test.sh` must pass before asking to commit.
* Regenerate the demo with `scripts/record_demo.sh` when the UI changes.
