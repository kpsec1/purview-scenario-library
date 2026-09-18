---
part: "design"
parent: "information-protection/auto-label-eu-personal-data-sharepoint"
---
## 1. Problem statement

`scenarios/information-protection/auto-label-confidential-sharepoint/` ships a working
auto-labeling pattern, but its default condition set, U.S. Social Security Number (SSN) and
Credit Card Number, is a U.S.-centric starter kit. Its own `reviews.md` (Red Team finding 4) and
`README.md` §2 already flag this explicitly: a tenant whose regulated population is EU/UK-only
gets materially weaker real-world coverage from that default than its GDPR framing implies, since
SSN simply does not appear in EU/UK personal data. That sibling scenario deferred the fix to a
follow-up (`PROGRESS.md`, "Follow-ups discovered while building the Information Protection
auto-labeling scenario") rather than guessing at EU-appropriate sensitive information types (SITs)
without grounding them first. This scenario is that follow-up: the same auto-labeling mechanism,
re-pointed at Microsoft's built-in EU/UK-region SITs, with the SIT list itself parameterized so a
buyer can localize further to only the member states they actually operate in.

## 2. Design goals

1. Apply the **Confidential** label (parameterizable, same dependency pattern as the sibling
   scenario) automatically to SharePoint/OneDrive content containing EU/UK personal identifiers, 
   national ID numbers, the EU Social-Security-or-equivalent family, and EU-format debit card
   numbers, going forward and across the existing backlog, without requiring any user action.
2. Do not hard-code a single country's identifier the way the sibling scenario hard-codes U.S.
   SSN. Default to Microsoft's built-in **EU-wide bundle SITs** (which internally OR-match across
   every EU member state's own national ID/SSN/passport/driver's-license entity, see §4), but
   make the exact SIT name list a script parameter so a buyer whose regulated population is, say,
   Germany-and-France-only can swap in just `'Germany Identity Card Number'` and `'France Social
   Security Number'` instead of matching all 26 countries' formats, directly resolving the
   "localizing sensitive information type selection by data-residency/jurisdiction" follow-up this
   scenario was scoped from.
3. Preserve every override-safety and staged-rollout guarantee the sibling scenario already
   established (never override a manual label; only override a lower-priority auto-applied/default
   label; simulation-mode-first): this scenario changes *which* SITs the rule matches, not the
   label-priority or rollout model, which are already correct.
4. Idempotent and re-runnable: running the deploy script twice must not create duplicate policies
   or rules.
5. Ship "off" by default: simulation mode first, matching `AGENTS.md` §4.

## 3. Why a second scenario, not a parameter on the sibling scenario

The sibling scenario's policy and rule names, `README.md` prose, and `reviews.md` findings are all
written specifically around the U.S. SSN + Credit Card Number condition set. Retrofitting it to be
region-generic in place would mean either (a) silently changing what an already-reviewed,
already-shipped scenario matches, breaking any buyer who deployed it expecting U.S. coverage, or
(b) adding enough conditional prose/parameters to cover both regions that the README stops reading
as the clean, niche format `AGENTS.md` §4 requires. A second, sibling scenario folder, same
policy family, same architecture, different (and parameterized) SIT list and policy/rule names, 
keeps both scenarios independently deployable, independently rollback-able, and independently
readable, matching the precedent already set by
`scenarios/information-protection/auto-label-confidential-exchange/` (a sibling by *location*,
not by *SIT set*, but the same "don't overload one scenario with two purposes" principle).

## 4. Sensitive information type selection, grounding

Microsoft Purview's built-in SIT catalog includes both **per-country** entities (e.g. "Germany
Identity Card Number", "France Social Security Number", one per EU member state) and a small set
of **EU-wide grouping SITs** that internally match across every member state's own entity under
one selectable name, confirmed as genuinely selectable, distinct SIT objects (not just a
documentation grouping) by Microsoft's own "these SITs can't be copied" exclusion list, which
names them individually alongside ordinary built-in SITs [[1]](#references):

| EU-wide SIT (as titled in Microsoft's canonical entity-definitions index) | Matches (per that SIT's own definition page) |
|---|---|
| **EU national identification number** | The OR of 26 per-country national ID entities (Austria Identity Card, Belgium National Number, ... U.K. National Insurance Number) [[2]](#references) |
| **EU Social Security Number (SSN) or Equivalent ID** | The OR of 12 per-country SSN-equivalent entities (Austria, Belgium, Croatia, Czech, Denmark, Finland, France, Germany, Greece, Hungary, Spain, Sweden) [[3]](#references) |
| **EU debit card number** | A single, region-wide 16-19-digit pattern with checksum + card/expiry keyword corroboration, not a per-country bundle, the direct EU-format analog of the sibling scenario's "Credit Card Number" SIT [[4]](#references) |

This scenario's default condition set is these three, OR-combined, `mincount = 1` each, the
direct EU/UK analog of the sibling scenario's SSN + Credit Card Number pair (one identity SIT
family, one financial SIT), not an attempt at exhaustive EU personal-data coverage (name, address,
and health-data SITs exist separately and are out of scope here, same "starter set, not
jurisdiction-complete" framing the sibling scenario's `README.md` §2 already uses).

**Deliberately not defaulted to, but now available as an opt-in bundle:** "EU passport number" and
"EU driver's license number" (also real, confirmed EU-wide bundle SITs
[[5]](#references)[[6]](#references)), omitted from the *default* set because passport/driver's-
license numbers are lower-frequency in day-to-day SharePoint/OneDrive business content than
national-ID and payment-card numbers, not because they're any less real. A buyer whose estate is
travel-document- or HR-record-heavy can add both with `-IncludeTravelDocumentSits` (§5) instead of
retyping the full `-SensitiveInfoTypeName` list by hand.

**Bundle-membership grounding (fetched directly, 2026-09-09), and why the three EU-wide bundles
this scenario can reference are not interchangeable in coverage:**

| Bundle | Member entities | Count | Notes |
|---|---|---|---|
| EU national identification number (default) | Austria, Belgium, Bulgaria, Croatia, Cyprus, Czech Republic, Denmark, Estonia, Finland, France, Germany, Greece, Hungary, Ireland, Italy, Latvia, Lithuania, Luxembourg, Malta, Netherlands, Portugal, Romania, Slovakia, Slovenia, Spain, U.K. | 26 | No Poland or Sweden entity exists in this bundle |
| EU passport number (opt-in) | Austria, Belgium, Bulgaria, Croatia, Cyprus, Czech, Denmark, Estonia, Finland, France, Germany, Greece, Hungary, Ireland, Italy, Latvia, Lithuania, Malta, Poland, Portugal, Romania, Slovakia, Slovenia, Spain, Sweden, **U.S./U.K. passport number** (one combined entity) [[5]](#references) | 26 | No standalone Luxembourg or Netherlands entity. U.K. passport coverage is **not** a standalone entity, it is bundled with U.S. passport numbers as a single entity, per Microsoft's own bundle index page |
| EU driver's license number (opt-in) | Austria, Belgium, Bulgaria, Croatia, Cyprus, Czech, Denmark, Estonia, Finland, France, Germany, Greece, Hungary, Ireland, Italy, Latvia, Lithuania, Luxemburg, Malta, Netherlands, Poland, Portugal, Romania, Slovakia, Slovenia, Spain, Sweden, U.K. [[6]](#references) | 28 | All 27 EU member states plus a standalone U.K. entity, the most complete of the three bundles |

**Real consequence of the U.K./U.S. passport merge:** a buyer who enables `-IncludeTravelDocumentSits`
specifically to add U.K. passport-number detection also enables U.S. passport-number detection as
an inseparable side effect, there is no way to select one without the other via this bundle SIT.
A buyer who needs U.K.-only passport detection without U.S. false positives would need to build a
custom SIT or accept the combined entity's broader match surface; this scenario does not attempt
that narrower control (`-SensitiveInfoTypeName` still accepts a fully custom list if a buyer builds
one). Flagged as a Red Team-relevant finding in `reviews.md` round 2 and `README.md` §11, not
silently absorbed into the "just enable the bundle" framing.

**Per-country checksum/confidence detail for both opt-in bundles is now tabled below**, to the same
depth as the default national-ID bundle, closing the follow-up this scenario originally deferred
(fetching 25-28 more individual Microsoft Learn entity-definition pages per bundle, one round of
grounding per bundle, fetched directly on 2026-09-09).

**Per-country checksum-strength reference, all 26 members of the "EU national identification
number" bundle.** `reviews.md` (Red Team finding 1) flagged that the bundle's per-country entities
don't carry equal detection confidence, but the original build only grounded two representative
examples (France: no checksum; Belgium: yes). This table closes that gap with all 26, each fetched
directly from its own Microsoft Learn entity-definition page rather than inferred from the two
examples:

| Country | Entity (as titled by Microsoft) | Checksum | Highest documented confidence | Notes |
|---|---|---|---|---|
| Austria | Austria identity card | No (`Not applicable`) | Medium (75) |, |
| Belgium | Belgium national number | **Yes** | Medium (75) |, |
| Bulgaria | Bulgaria uniform civil number | **Yes** | High (85) |, |
| Croatia | Croatia identity card number | No | Medium (75) |, |
| Cyprus | Cyprus identity card | No (`Not applicable`) | Medium (75) |, |
| Czech Republic | Czech personal identity number | **Yes** | High (85) | Checksum required on both the legacy 9-digit and current 10-digit formats |
| Denmark | Denmark personal identification number | **Yes** | Medium (75) |, |
| Estonia | Estonia personal identification code | **Yes** | High (85) |, |
| Finland | Finland national ID | **Yes** | High (85) |, |
| France | France national ID card (CNI) | No | Low (65) | Lowest documented confidence in the bundle |
| Germany | Germany identity card number | **Yes**, post-2010 format only | High (85) | Pre-November-2010 10-digit format matches on regex only, no checksum function documented |
| Greece | Greece national ID card | No | High (85) | High confidence here comes from pattern+keyword, not checksum |
| Hungary | Hungary personal identification number | **Yes** | High (85) |, |
| Ireland | Ireland personal public service (PPS) number | **Yes** | High (85) | Checksum applies to both the pre-2013 and current formats |
| Italy | Italy fiscal code | **Yes** | High (85) |, |
| Latvia | Latvia personal code | **Yes** | High (85) | Checksum applies to both the legacy hyphenated and current formats |
| Lithuania | Lithuania personal code | **Yes** | High (85) |, |
| Luxembourg | Luxembourg National Identification Number (Natural persons) | **Yes** | High (85) |, |
| Malta | Malta identity card number | No (`Not applicable`) | Medium (75) |, |
| Netherlands | Netherlands citizens service (BSN) number | **Yes** | High (85) |, |
| Portugal | Portugal citizen card number | **Yes** | High (85) |, |
| Romania | Romania personal numeric code (CNP) | **Yes** | High (85) |, |
| Slovakia | Slovakia personal number | **Yes** | High (85) |, |
| Slovenia | Slovenia Unique Master Citizen Number | **Yes** | High (85) |, |
| Spain | Spain DNI | **Yes** | High (85) |, |
| U.K. | U.K. national insurance number (NINO) | No | High (85) | High confidence here comes from pattern+keyword, not checksum |

**19 of 26 members (73%) are checksum-validated; 7 are pattern-only** (Austria, Croatia, Cyprus,
France, Greece, Malta, U.K.). Two of the 19 (Germany, and to a lesser extent the dual-format
countries noted above) only guarantee the checksum on a subset of the formats they match, treat
Germany's pre-2010 10-digit path as effectively pattern-only for false-positive planning purposes.
The 7 pattern-only countries carry the bundle's highest false-positive risk and are the first
candidates to exclude via the `-SensitiveInfoTypeName` localization mechanism (§5) for a tenant that
doesn't operate in those markets, see `README.md` §8's KPI guidance and §11.

**Per-country checksum-strength reference, all 26 members of the opt-in "EU passport number"
bundle**, each fetched directly from its own Microsoft Learn entity-definition page (2026-09-09):

| Country | Format | Checksum | Highest documented confidence | Notes |
|---|---|---|---|---|
| Austria | 1 letter + 7 digits | No (`Not applicable`) | High (85) |, |
| Belgium | 2 letters + 6 digits | No (`Not applicable`) | High (85) |, |
| Bulgaria | 9 digits | No | High (85) |, |
| Croatia | 9 digits | No | High (85) |, |
| Cyprus | 1 letter + 6-8 digits | No | High (85) |, |
| Czech Republic | 8 digits | No | High (85) |, |
| Denmark | 9 digits | No | High (85) |, |
| Estonia | 1 letter + 7 digits | No | High (85) |, |
| Finland | 2 letters + 7 digits | No | High (85) |, |
| France | 2 digits + 2 letters + 5 digits | No | High (85) | Matched via a function (`Func_fr_passport`), not a plain regex, but still not checksum-validated |
| Germany | 9-11 chars, letter-set-restricted | **Yes** | High (85) | Checksum path requires DLP engine ≥ 15.20.4570.0; below that version the entity falls back to a 75-confidence, non-checksum pattern match, see `README.md` §11 |
| Greece | 2 letters + 7 digits | No | High (85) |, |
| Hungary | 2 letters + 6-7 digits | No | High (85) |, |
| Ireland | 2 alphanumeric + 7 digits | No | High (85) |, |
| Italy | 2 alphanumeric + 7 digits | No (`Not applicable`) | High (85) |, |
| Latvia | 2 alphanumeric + 7 digits | No | High (85) |, |
| Lithuania | 8 alphanumeric | No (`Not applicable`) | High (85) |, |
| Malta | 7 digits | No | High (85) |, |
| Poland | 2 letters + 7 digits | **Yes** | High (85) | Checksum-validated function (`Func_polish_passport_number_v2`); confidence tiers at 85/75/65 depending on which of checksum+keyword+date corroborate |
| Portugal | 1 letter + 6 digits | No | High (85) |, |
| Romania | 8 or 9 digits | No | High (85) |, |
| Slovakia | 8-9 alphanumeric | No | High (85) |, |
| Slovenia | "P" + 1 letter + 7 digits | No | High (85) |, |
| Spain | 8-9 alphanumeric | No (`Not applicable`) | High (85) |, |
| Sweden | 8 digits | No | High (85) |, |
| U.S./U.K. passport number | 1 alphanumeric + 8 digits | No | High (85) | Combined entity, see §4 above; matches both U.S. and U.K. formats |

**Only 2 of 26 members (8%) are checksum-validated** (Germany, Poland), a materially weaker
validation profile than the default national-ID bundle's 73%. Every entity in this bundle reaches
the same 85-confidence ceiling regardless of checksum status (the non-checksum entities earn High
confidence from pattern + keyword + a nearby issue/expiry date, not from a weaker structural match),
so a buyer cannot distinguish "checksum-backed, high-confidence passport match" from "9-digit
pattern near the word 'passport'" by confidence level alone, see `README.md` §11 for the
false-positive-planning consequence.

**Per-country checksum-strength reference, all 28 members of the opt-in "EU driver's license
number" bundle**, each fetched directly from its own Microsoft Learn entity-definition page
(2026-09-09):

| Country | Format | Checksum | Highest documented confidence | Notes |
|---|---|---|---|---|
| Austria | 8 digits | No | Medium (75) |, |
| Belgium | 10 digits | No | Medium (75) |, |
| Bulgaria | 9 digits | No | Medium (75) |, |
| Croatia | 8 digits | No | Medium (75) |, |
| Cyprus | 12 digits | No | Medium (75) |, |
| Czech Republic | "E" + 1 letter + 6 digits | No | Medium (75) |, |
| Denmark | 8 digits | No | Medium (75) |, |
| Estonia | "ET" + 6 digits | No | Medium (75) |, |
| Finland | 6 digits + hyphen + 3 digits + 1 alphanumeric | No | Medium (75) |, |
| France | 12 digits | No | Medium (75) | Matched via a function (`Func_french_drivers_license`) that discounts French phone-number-shaped false positives, not a checksum |
| Germany | 11 alphanumeric | **Yes** | Medium (75) | Checksum required for a match at all (single-tier definition, no non-checksum fallback pattern documented, unlike the German passport entity) |
| Greece | 9 digits | No | Medium (75) |, |
| Hungary | 2 letters + 6 digits | No | Medium (75) |, |
| Ireland | 6 digits + 4 letters | No | Medium (75) |, |
| Italy | 1 letter + 8 alphanumeric + 1 letter | No | Medium (75) |, |
| Latvia | 3 letters + 6 digits | No | Medium (75) |, |
| Lithuania | 8 digits | No | Medium (75) |, |
| Luxembourg | 6 digits | No | Medium (75) |, |
| Malta | 2 alphanumeric + 3 digits + 3 digits | No | Medium (75) |, |
| Netherlands | 10 digits | No | Medium (75) |, |
| Poland | 11 or 14 digits with 2 slashes | No | Medium (75) |, |
| Portugal | 2 letters/1 letter + 5-8 digits, hyphenated | No | Medium (75) |, |
| Romania | 1 alphanumeric + 8 digits | No | Medium (75) |, |
| Slovakia | 1 alphanumeric + 7 digits | No | Medium (75) |, |
| Slovenia | 9 digits | No | Medium (75) |, |
| Spain | 8 digits + 1 alphanumeric | **Yes** | High (85) | Two checksum functions (citizen/foreigner formats); 85 with a keyword nearby, 75 (checksum only, no keyword) otherwise, the only driver's-license entity in this bundle that reaches High confidence |
| Sweden | 6 digits + hyphen + 4 digits | No | Medium (75) |, |
| U.K. | 18-character composite (name-derived + DOB-encoded + check letters) | **Yes** | Medium (75) | Checksum required for a match at all; 75 with a keyword nearby, 65 (checksum only) otherwise |

**Only 3 of 28 members (11%) are checksum-validated** (Germany, Spain, U.K.). Unlike the passport
bundle, this bundle's own top confidence tier for 25 of its 28 members is capped at Medium (75), 
Microsoft's own entity definitions for this SIT family document no High-confidence (85) tier at all
for the non-checksum countries, only a single medium-confidence pattern-plus-keyword rule. Spain and
the U.K. are the only two members that can reach a stronger evidentiary combination (checksum +
keyword), and only Spain reaches 85.

**Cross-bundle takeaway (Red Team-relevant, see `reviews.md` round 3):** the three EU-wide bundles
this scenario can reference carry sharply different validation strength, 73% checksum-validated for
the *default* national-ID bundle, but only 8% (passport) and 11% (driver's license) for the two
*opt-in* bundles. A buyer who enables `-IncludeTravelDocumentSits` should not assume the same
false-positive profile as the default condition set; §5's per-country `-SensitiveInfoTypeName`
narrowing is proportionally more valuable for these two bundles than for the default one.

**VERIFY (pilot tenant, before production reliance):** the exact, byte-precise capitalization of
these three SIT names as they must be passed to `-ContentContainsSensitiveInformation` /
`New-DlpComplianceRule`. Microsoft's own Learn pages render the same SIT with inconsistent casing
across pages (the bundle index page titles it lowercase, "EU national identification number"; the
canonical numbered entity-definitions list titles it the same way; other pages sentence-case only
the leading word), this build could not find a single authoritative, byte-exact string to cite
with certainty, the same class of gap already flagged for the sibling scenario's own SIT names
(`auto-label-confidential-sharepoint/README.md` did not need this VERIFY because "U.S. Social
Security Number (SSN)" and "Credit Card Number" both matched their citation exactly, but this
scenario's EU SIT names carry that risk and it would be dishonest to imply otherwise). The deploy
script (`deploy/New-EuPersonalDataAutoLabelPolicy.ps1`) resolves each configured name via
`Get-DlpSensitiveInformationType` before referencing it in a rule and fails clearly, listing the
closest available matches, rather than silently creating a rule with zero real matches if a name is
off by case or punctuation, see `README.md` §11.

## 5. Localization parameter, `-SensitiveInfoTypeName`

`deploy/New-EuPersonalDataAutoLabelPolicy.ps1` accepts `-SensitiveInfoTypeName` as a `string[]`,
defaulting to the three EU-wide SITs in §4. A buyer who wants to localize further passes their own
list, either a subset of per-country entities (e.g. only the member states they operate in, for
tighter false-positive control and a clearer per-jurisdiction legal-basis mapping than "matches
somewhere in the EU"), or a superset including passport/driver's-license SITs, or entirely
different SITs for a non-EU region this scenario's name doesn't target (the parameter itself is
region-agnostic; only the *default value* is EU/UK-specific). This is the concrete mechanism that
resolves the sibling scenario's own deferred localization follow-up, and its existence is
cross-referenced back into `auto-label-confidential-sharepoint/README.md` §11 so a reader of either
scenario finds the other.

**`-IncludeTravelDocumentSits` is a separate, additive mechanism, not a replacement for
`-SensitiveInfoTypeName`.** Where `-SensitiveInfoTypeName` replaces the entire condition list
(for narrowing to specific member states, per §4/§5), `-IncludeTravelDocumentSits` appends the two
opt-in bundle SITs (§4) to whatever list is already in effect, the default three-SIT set, or a
caller's own narrowed override, so a buyer localizing to Germany + France can still opt into
travel-document coverage for those same two countries' passport/driver's-license formats without
having to spell out the bundle names by hand.

## 6. Policy architecture

Identical shape to the sibling scenario (`auto-label-confidential-sharepoint/design.md` §4): one
auto-labeling policy, two rules (one per workload, `New-AutoSensitivityLabelRule -Workload` is
single-valued per call [[7]](#references)), both rules sharing the same SIT condition set and
target label.

| Rule | Workload | Condition | Action |
|---|---|---|---|
| `AutoLabel-EuPersonalData-SharePoint` | SharePoint | Content contains any of `-SensitiveInfoTypeName` (default: EU national identification number, EU Social Security Number (SSN) or Equivalent ID, EU debit card number), count ≥ 1 | Apply `Confidential` label |
| `AutoLabel-EuPersonalData-OneDrive` | OneDriveForBusiness | Same | Same |

```mermaid
flowchart TD
    A[SharePoint / OneDrive file] --> B{Any configured EU/UK<br/>SIT present, count >= 1?}
    B -- No --> Z[No action]
    B -- Yes --> C{Site on the<br/>exclusion list?}
    C -- Yes --> Z
    C -- No --> D{Existing label priority<br/>vs. Confidential}
    D -- Unlabeled --> E[Apply Confidential]
    D -- Manual, any priority --> F[Leave as-is]
    D -- Auto/default, lower priority --> E
    D -- Auto/default/manual,<br/>higher or equal priority --> F
```

Policy-level settings, override semantics, exclusion mechanism, and rollout staging are all
inherited unchanged from the sibling scenario's design (`auto-label-confidential-sharepoint/
design.md` §4, §6), this scenario changes the SIT condition set and adds the localization
parameter; it does not re-derive any of the already-reviewed rollout/override design.

## 7. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Default SITs | EU national identification number, EU Social Security Number (SSN) or Equivalent ID, EU debit card number | §4, direct EU/UK analog of the sibling's identity+financial pair, grounded against Microsoft's canonical entity-definitions index |
| Localization mechanism | `-SensitiveInfoTypeName string[]` parameter, resolved via `Get-DlpSensitiveInformationType` at deploy time | §5, turns "swap the SIT list for your jurisdiction" from README prose (the sibling's approach) into an actual script parameter |
| Name validation | Deploy script resolves every configured SIT name against `Get-DlpSensitiveInformationType` and fails clearly (listing near-matches) rather than silently deploying a zero-match rule | Directly mitigates the casing-uncertainty VERIFY in §4 rather than shipping a rule that might silently match nothing |
| Passport/driver's-license SITs | Available via `-SensitiveInfoTypeName` directly, or additively via the `-IncludeTravelDocumentSits` opt-in switch | §4, lower day-to-day frequency in business documents than ID/payment identifiers; a buyer's own data inventory should drive adding them, not this scenario's default. The switch exists so opting in doesn't require retyping the full SIT list, and so the U.S./U.K. passport-merge gotcha (§4) is surfaced at the call site, not just in prose |
| Label, override behavior, exclusion mechanism, rollout mode | Unchanged from the sibling scenario | §6, already reviewed and correct; this scenario's scope is the SIT set, not the rollout/override model |

## 8. Non-goals

- This scenario does not author or publish the `Confidential` sensitivity label, same
  prerequisite-dependency pattern as the sibling scenario (`README.md` §3).
- This scenario does not cover Exchange (email), scoped to SharePoint/OneDrive at-rest content,
  matching the sibling scenario's own scope split with
  `auto-label-confidential-exchange/`. The EU-personal-data Exchange variant is now built as
  `scenarios/information-protection/auto-label-eu-personal-data-exchange/`, see that scenario's
  `design.md` for why it is a third, sibling scenario rather than a parameter on this one.
- This scenario does not attempt EU personal-data-category completeness (names, physical
  addresses, health data, biometric data are all "personal data" under GDPR Article 4(1) but are
  covered by entirely separate SIT/named-entity families), see §4's explicit starter-set framing.
- This scenario does not implement per-country legal-basis or retention-period differentiation
  (GDPR is a single regulation, but a France-only vs. Germany-only deployment might have different
  internal data-handling procedures downstream of the label), that is a policy/process decision
  for the buyer's compliance team, out of scope for a labeling-mechanism scenario.

## References

1. Create custom sensitive information types, "These SITs can't be copied" (lists the EU-wide
   bundle SITs individually, confirming each is a real, selectable, standalone SIT object), 
   <https://learn.microsoft.com/purview/sit-create-a-custom-sensitive-information-type#before-you-begin>
2. EU national identification number entity definition (26-country membership list), 
   <https://learn.microsoft.com/purview/sit-defn-eu-national-identification-number>
3. EU Social Security Number (SSN) or Equivalent ID entity definition (12-country membership
   list), <https://learn.microsoft.com/purview/sit-defn-eu-social-security-number-equivalent-identification>
4. EU debit card number entity definition (single region-wide pattern, checksum, keyword
   corroboration, Entity id `0e9b3178-9678-47dd-a509-37222ca96b42`), 
   <https://learn.microsoft.com/purview/sit-defn-eu-debit-card-number>
5. EU passport number entity definition, <https://learn.microsoft.com/purview/sit-defn-eu-passport-number>
6. EU drivers license number entity definition, <https://learn.microsoft.com/purview/sit-defn-eu-drivers-license-number>
7. New-AutoSensitivityLabelRule reference (`-Workload` single-valued), 
   <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule>
8. Austria identity card entity definition, <https://learn.microsoft.com/purview/sit-defn-austria-identity-card>
9. Belgium national number entity definition, <https://learn.microsoft.com/purview/sit-defn-belgium-national-number>
10. Bulgaria uniform civil number entity definition, <https://learn.microsoft.com/purview/sit-defn-bulgaria-uniform-civil-number>
11. Croatia identity card number entity definition, <https://learn.microsoft.com/purview/sit-defn-croatia-identity-card-number>
12. Cyprus identity card entity definition, <https://learn.microsoft.com/purview/sit-defn-cyprus-identity-card>
13. Czech personal identity number entity definition, <https://learn.microsoft.com/purview/sit-defn-czech-personal-identity-number>
14. Denmark personal identification number entity definition, <https://learn.microsoft.com/purview/sit-defn-denmark-personal-identification-number>
15. Estonia personal identification code entity definition, <https://learn.microsoft.com/purview/sit-defn-estonia-personal-identification-code>
16. Finland national ID entity definition, <https://learn.microsoft.com/purview/sit-defn-finland-national-id>
17. France national ID card (CNI) entity definition, <https://learn.microsoft.com/purview/sit-defn-france-national-id-card>
18. Germany identity card number entity definition, <https://learn.microsoft.com/purview/sit-defn-germany-identity-card-number>
19. Greece national ID card entity definition, <https://learn.microsoft.com/purview/sit-defn-greece-national-id-card>
20. Hungary personal identification number entity definition, <https://learn.microsoft.com/purview/sit-defn-hungary-personal-identification-number>
21. Ireland personal public service (PPS) number entity definition, <https://learn.microsoft.com/purview/sit-defn-ireland-personal-public-service-number>
22. Italy fiscal code entity definition, <https://learn.microsoft.com/purview/sit-defn-italy-fiscal-code>
23. Latvia personal code entity definition, <https://learn.microsoft.com/purview/sit-defn-latvia-personal-code>
24. Lithuania personal code entity definition, <https://learn.microsoft.com/purview/sit-defn-lithuania-personal-code>
25. Luxembourg National Identification Number (Natural persons) entity definition, <https://learn.microsoft.com/purview/sit-defn-luxemburg-national-identification-number-natural-persons>
26. Malta identity card number entity definition, <https://learn.microsoft.com/purview/sit-defn-malta-identity-card-number>
27. Netherlands citizens service (BSN) number entity definition, <https://learn.microsoft.com/purview/sit-defn-netherlands-citizens-service-number>
28. Portugal citizen card number entity definition, <https://learn.microsoft.com/purview/sit-defn-portugal-citizen-card-number>
29. Romania personal numeric code (CNP) entity definition, <https://learn.microsoft.com/purview/sit-defn-romania-personal-numeric-code>
30. Slovakia personal number entity definition, <https://learn.microsoft.com/purview/sit-defn-slovakia-personal-number>
31. Slovenia Unique Master Citizen Number entity definition, <https://learn.microsoft.com/purview/sit-defn-slovenia-unique-master-citizen-number>
32. Spain DNI entity definition, <https://learn.microsoft.com/purview/sit-defn-spain-dni>
33. U.K. national insurance number (NINO) entity definition, <https://learn.microsoft.com/purview/sit-defn-uk-national-insurance-number>
