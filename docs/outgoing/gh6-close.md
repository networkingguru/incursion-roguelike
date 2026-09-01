# Close comment for networkingguru/incursion-roguelike issue #6

Status: DRAFTED 2026-08-31. Brian has read this text. NOT YET POSTED --
waiting on his explicit go. Post as a comment, then close the issue as
completed.

Command when approved:
    gh issue comment 6 -R networkingguru/incursion-roguelike -F docs/outgoing/gh6-close.md
(strip this header block first -- post only the text below the line)

---

Closing this as fixed.

Both defects behind it were fixed and shipped: the module digest mismatch (a `Registry` member declared only in debug builds, so the developer and shipping binaries stamped different memory layouts), and the packaging shape (a bare executable inside a plain folder, which Gatekeeper cannot approve for launch and which a notarisation ticket cannot be stapled to — it is now a real `Incursion.app` with its own stapled ticket).

The packaging gate now asks the binary for its own save-layout stamp and compares it against the module's, assesses a **quarantined** copy of the bundle, and asserts that the signature survives a run. All three would have failed on what originally shipped.

@earchibald — thanks again for the report. It caught a defect that made the download useless for everyone and would not have surfaced from testing here. If the current release still stops at the title screen for you, reopen this and I will dig back in.

Written with AI assistance (Claude); reviewed by me.
