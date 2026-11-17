# The jog display is driven over its WD port, and is off until the user turns it on

2026-11-16. The LC6000's jog display takes images over its own WD port after a host hello (#121, #165). The protocol was worked out from captures, so Settings' "Show the deck on the jog display" stays off until a hardware check passes (#165): while it's off, nothing reaches either port, not even the hello, and a test guards that. The app still renders and previews every deck in Diagnostics either way, so the display can be checked without risk.
