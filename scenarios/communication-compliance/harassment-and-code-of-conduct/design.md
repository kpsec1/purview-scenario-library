# Design — Harassment & Code-of-Conduct Detection

## 1. Problem statement

An organization needs to detect workplace harassment and code-of-conduct violations across its
communication channels (Exchange, Teams, Viva Engage) and route matches to trained reviewers for
triage and remediation — with privacy controls that keep the program defensible rather than
surveillance. Microsoft Purview Communication Compliance is the native control, but its policy
management is **portal-first** (Microsoft explicitly states PowerShell isn't supported for creating
and managing CC policies), and the trainable classifiers that carry harassment detection are not
exposed through the documented cmdlet surface. The design problem is therefore not "script the whole
policy" — it's "make as much of this as-code as the supported surfaces honestly allow, and capture the
rest as a diffable source of truth."

## 2. Design goals

1. **Honest split of surfaces.** Deploy via PowerShell only what the documented `SupervisoryReview`
   cmdlets genuinely support (policy shell, reviewers, keyword rule with reviewee/direction/sampling);
   configure the classifiers + locations in the portal (Microsoft's supported surface) and capture
   them in a versioned reference manifest.
2. **A keyword rule that is real, working automation** — not a placeholder — using the documented
   `-Condition` filter syntax, so the code-of-conduct lexicon half is genuinely deployable and
   reconcilable as code.
3. **Idempotent and re-runnable** (`AGENTS.md` §4): locate policy/rule by name, `Set-*` if present
   else `New-*`.
4. **A working dry-run despite the platform.** `-WhatIf` is non-functional in S&C PowerShell, so ship
   a custom `-DryRun` that prints every mutating cmdlet and runs none.
5. **Privacy by default.** Keep pseudonymization on; document disabling it as an explicit HR/Legal
   decision, never a default.

## 3. Why this two-part design (and not "script everything" or "portal only")

- **Script everything** is impossible and would require fabricating classifier parameters that don't
  exist in the documented cmdlet surface — a direct violation of `AGENTS.md` §4 (no invented
  cmdlets/parameters). The `-AdvancedRule` parameter is undocumented; guessing its shape for
  classifiers would be fabrication.
- **Portal only** would abandon the library's "working automation code" promise for the parts that
  *are* scriptable (the policy shell, reviewers, and — importantly — the keyword-lexicon rule, which
  many conduct/regulatory programs rely on alongside classifiers).
- **The two-part split** matches how Microsoft's own product boundary actually falls, mirrors this
  library's established precedent for portal-first policy surfaces (the Insider Risk Management
  scenario ships a portal reference manifest plus scriptable adjacent automation), and gives the buyer
  a genuinely re-runnable keyword/workflow deployment plus a diffable record of the portal half.

## 4. What is scriptable vs. portal — the surface boundary

| Element | Surface | Why |
|---|---|---|
| Policy object + reviewers | **Script** (`New-/Set-SupervisoryReviewPolicyV2`) | Documented params `-Name`/`-Reviewers`/`-Enabled` |
| Keyword/phrase rule (reviewees, direction, sampling) | **Script** (`New-/Set-SupervisoryReviewRule -Condition -SamplingRate`) | Documented `-Condition` syntax covers Reviewee/Direction/word-match |
| Trainable classifiers (Targeted harassment/Threat/Discrimination) | **Portal** | No documented classifier parameter on the rule cmdlet |
| Location selection (Exchange/Teams/Viva Engage) | **Portal** (VERIFY `-ContentSources`) | Not a documented policy/rule parameter |
| Filter email blasts, content-safety LLM classifiers, pseudonymization | **Portal** | Global/policy settings not in the cmdlet surface |

The reference manifest (`deploy/policy/inappropriate-text-portal-reference.json`) is the versioned
record of the portal column, so the whole control — both halves — is reviewable in one place even
though only one half is script-applied.

## 5. Idempotency and the `-Condition` builder

Idempotency is get-then-branch: `Get-SupervisoryReviewPolicyV2 -Identity <name>` → `Set-*` if found
else `New-*`; same for the rule via `Get-SupervisoryReviewRule -Policy <name>` filtered by rule name.
The rule `-Condition` is assembled from the config's reviewees, directions, and keyword lexicon into
Microsoft's documented filter grammar:

```
( ((Reviewee:g1) -OR (Reviewee:g2)) -AND ((Direction:Inbound) -OR (Direction:Internal)) -AND ((term one) -OR (term two)) )
```

Each condition *type* is OR-joined internally and the types are AND-joined, wrapped in an outer
parenthesis — matching Microsoft's own `New-SupervisoryReviewRule` example
(`((trade) -OR (insider trading))`). Phrases with spaces are inserted bare (not quoted), per that
example. The builder refuses to run if the lexicon still contains `PLACEHOLDER` entries, so the sample
can't be deployed unmodified.

## 6. Privacy and reviewer trust model

Communication Compliance is privacy-by-design: usernames are pseudonymized by default, investigators
are opted in by an admin, and role-based access separates who configures policies (Admins) from who
sees message content (Investigators) vs. metadata (Analysts) vs. reports (Viewers). This scenario
preserves all of that: the script only assigns reviewers (who must already hold the Analyst/
Investigator role and an EXO mailbox); it never elevates anyone, never disables pseudonymization, and
never grants content access. Admin units are noted as the lever to scope investigators to a region/
department where legal segregation requires it.

## 7. Non-goals

- **Scripting the trainable classifiers or locations** — portal-only by Microsoft's surface (§4);
  fabricating parameters is out of the question.
- **Regulatory-supervision variant** (SEC/FINRA financial-conduct classifiers, percentage sampling
  for broker communications) — a natural sibling scenario using the same engine with the
  regulatory-compliance template and classifiers; see `PROGRESS.md`.
- **Copilot/Enterprise-AI-app communication supervision** — the same solution now covers Microsoft 365
  Copilot interactions; a separate scenario.
- **Role-group provisioning** — assigning users into the CC role groups is a prerequisite handled in
  the portal (Settings → Roles and groups); this scenario documents it but does not script it.
- **Alert/case-management automation** (Power Automate remediation flows, CSV history export
  pipelines) — operationally documented, not scripted here.
- **Third-party channel connectors** (WhatsApp, Bloomberg, etc.) — separate connector setup, out of
  scope.
