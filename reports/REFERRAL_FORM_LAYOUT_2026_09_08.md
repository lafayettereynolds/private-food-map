# Referral form layout

Uses the existing settings template, semantic colors, primary action and entry
rows. Registration now has separate label, full-width 16px input, explanatory
copy and a 44px action. Empty/busy states disable submission; trimmed input is
sent through the existing prepareRegistration capability. Feedback is live.
No reward, authentication, attribution or account permissions changed.

Browser probe passed at 375/402 light/dark; verified nonoverlap, input font,
action size, blank disable, pending disable and success feedback. Preview:
/tmp/tastemap-referral-375-light.png. Uses stubbed logged-out state, no real
registration or referral mutation performed.

Core: shared settings/button tokens; Food: existing gift glyph, no new assets;
canonical settings hierarchy preserved. No SwiftUI-default regression.
Build/install blocked by unrelated in-progress directory adapter errors:
browserPrivateDirectory missing; directory bridge method union mismatch;
chooseContacts parameter mismatch. No new Simulator install claimed.
