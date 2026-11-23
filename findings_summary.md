# Findings and Limitations

## Fictional result (spoilers)

- **Fatal event:** gunshot `5003`, 2026-12-04 21:15:00.000 UTC, `.45 ACP`, Main Hall. The fictional independent laboratory report `LAB-2026-451` links the recovered weapon `Pistol_45ACP` and Viktor Hale's fatal injury. **This association comes from forensic evidence, not a guess based on which shot occurred last.**
- **Provisional suspect:** Adrian Cross. An independently recorded pre-edit specimen points to his synthetic DNA-profile identifier on the .45 pistol; the camera and most recent access claim put him in the Main Hall at the fatal shot. A separate audit export ties a later identity/time alteration to his assigned account and camera footage shows him at the Control Room around the edit time.
- **Falsely accused:** Nora Vale. A live-grip report on `Pistol_9mm` claimed she touched it at 21:14:58.500, but a camera observation of her in the Archive Room at the same time is corroborated by access and locked-door logs. A prototype scanner's current row also falsely displays her as the owner of a profile originally associated with Adrian.
- **Earlier confrontation:** two early 9mm shots were recorded, with witness context consistent with a defensive account. Neither the audio record nor the lab report can, by itself, establish justified self-defense.
- **Motive:** a threat-message source linked to Adrian is marked source-verified, supporting a possible revenge hypothesis. A message alone cannot prove intent.

## Precisely what the evidence proves—and does not prove

| Observation | Supported interpretation | Unsupported leap |
| --- | --- | --- |
| 40-second gap after the last scream | The final recorded shot occurred later | The shooter necessarily acted in revenge |
| Smart-grip sensor names Nora but camera sees her elsewhere | The live-touch claim is inconsistent with separate location evidence | Fingerprint material was definitely cloned or planted |
| Scanner processed time precedes collection time | Data quality/timing anomaly | This alone proves malicious SQL injection |
| Pre-edit export and external audit disagree with the scanner row | An independently reported edit to identity/time fields | The whole database, audit service or hardware is inherently immutable |
| Weapon sample is associated with Adrian | Contact/association with the sampled item under the story's assumptions | He necessarily fired the fatal shot |
| Adrian is near the weapon, crime scene and editing console | Several mutually reinforcing leads make him the principal person of interest | An infallible proof of guilt or courtroom-standard attribution |

## Technical techniques

- **Window functions:** `LAG`, rolling `MAX`, and `ROW_NUMBER` for event intervals and latest-known access state.
- **Spatiotemporal joins:** verified camera observation within 2 seconds of a smart-grip claim or fatal shot; latest access record and recent door-state evidence.
- **Forensic provenance:** baseline scanner data independently exported before an edit, plus a separately captured change audit. These systems are trusted as **assumptions of the fictional case**, not invulnerable facts.
- **Evidence-constrained CTEs:** the fatal event is anchored to a laboratory report; identity, presence, and editing evidence converge before identifying a principal person of interest.
- **Checks:** `verification.sql` tests the core story invariants, so future edits to the demo data cannot silently break the solution.

## Important engineering boundaries

1. The prototype 'DNA-like' scanner is a **fictional** facility device, not a claim that real-world DNA identification from a hand touch is instantaneous. `SHA2()` is used here only to make stable synthetic profile tokens.
2. A live fingerprint **sensor assertion** is not the same as latent fingerprint evidence. A reported touch time is a system reading, subject to malfunction or manipulation.
3. Audio sensing cannot reliably establish exact ammunition caliber, motive, culpability or a victim's cause of death; the separate lab report supplies assumed corroboration.
4. Access records and door locks are not absolute guarantees of physical presence; camera corroboration matters, and real deployments would need clock synchronization and access-route coverage.
5. The scanner's database-side `raw_dna_hash` can also be edited. The project compares it to a simulated separately captured signed export; the independence/integrity of that export is a **precondition**.
6. An `actor_suspect_id` in an audit trail is an **account attribution**, not biometric proof of the human at the keyboard. The camera assists but cannot eliminate all alternative explanations.
7. The findings are constructed from deterministic fictional data. They illustrate a sound investigation workflow; they are not a security assessment or demonstration of an exploit against a real system.
8. This case uses no open-source intelligence collection and is therefore **not an OSINT case study**.

## Reproducibility

Run `schema.sql`, `data.sql`, `verification.sql`, then `investigation.sql` using MySQL 8.0.16+. Both setup files are safe to rerun: the schema creates tables only when missing, and the seeded data is left unchanged on a repeated import. The new dedicated schema is `shinichi_forensic_demo_v2`; this leaves the earlier `shinichi_forensic_db` and unrelated databases untouched. Expected output: fourteen `PASS` checks. Investigate any failure before publishing results. This design deliberately has no automatic data reset or destructive cleanup.

## Non-destructive rerun behavior

The project uses a dedicated v2 schema and an installation marker. `schema.sql` never drops existing data tables. `data.sql` uses a transaction and checks that the seed has not already been applied. A second successful run returns `ALREADY_SEEDED_NO_CHANGES`. Existing contents are preserved; if tables are unexpectedly nonempty, the seed refuses to proceed. The only `DROP` commands concern the temporary helper stored procedure, not user data or evidence tables.

## Validation scope

A portable SQLite-based logic harness (`tests/test_case_logic.py`) checked 6 inquiry statements and 14 invariant checks against the complete synthetic dataset, all passing in the local offline run. It does not execute MySQL-specific DDL or the stored-procedure loader. Verify the database setup and safe repeated import against a real MySQL 8.0.16+ instance before claiming MySQL integration testing is complete.
