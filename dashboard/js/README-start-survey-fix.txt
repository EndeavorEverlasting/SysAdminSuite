Cybernet survey start button regression found during PR 54 manual validation.

Root cause:
cybernet-os-preflight.js calls syncTutorialVisibility(root), and that function sets the whole cybernet tutorial root to display none unless live mode is active.

Effect:
The Start Cybernet Survey button removes the hidden class, but the inline display none remains, so the wizard does not appear.

Fix:
Do not set display none on the cybernet tutorial root from cybernet-os-preflight.js. Let app.js control tutorial visibility with the hidden class.
