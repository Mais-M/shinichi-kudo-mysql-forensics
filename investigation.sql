-- THE SHINICHI KUDO PROTOCOL | MySQL 8.0.16+
-- Execute AFTER schema.sql and data.sql (SAFE v2). Read-only. All timestamps are UTC.
USE shinichi_forensic_demo_v2;

-- ================================================================
-- STEP 1: Reconstruct sound chronology WITHOUT trusting ambient noise.
-- The acoustic sensor's estimated_caliber is ONLY a tentative guess.
-- LAG measures time to preceding relevant event, not necessarily a shot.
-- The last scream is 40.000 s before the final gunshot in this demo.
-- ================================================================
WITH relevant_events AS (
  SELECT event_id, room_name, event_type, estimated_caliber, event_time
  FROM acoustic_events
  WHERE event_type IN ('GUNSHOT', 'SCREAM')
), chronology AS (
  SELECT *,
    LAG(event_time) OVER (ORDER BY event_time, event_id) AS prior_event_time,
    MAX(CASE WHEN event_type = 'SCREAM' THEN event_time END)
      OVER (ORDER BY event_time, event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_scream_time
  FROM relevant_events
)
SELECT event_id, room_name, estimated_caliber, event_time,
  ROUND(TIMESTAMPDIFF(MICROSECOND, prior_event_time, event_time) / 1000000.0, 3)
    AS seconds_since_previous_relevant_event,
  ROUND(TIMESTAMPDIFF(MICROSECOND, prior_scream_time, event_time) / 1000000.0, 3)
    AS seconds_since_last_scream
FROM chronology
WHERE event_type = 'GUNSHOT'
ORDER BY event_time, event_id;

-- Corroborate caliber, weapon and injury outcome with a separate lab report.
-- The two early 9mm shots are CONSISTENT with a survival account; intent
-- cannot be determined by acoustics or ballistics alone.
SELECT a.event_id, a.event_time, a.room_name,
       a.estimated_caliber AS sensor_estimate,
       b.cartridge_caliber AS lab_caliber,
       b.recovered_weapon, b.injury_outcome,
       victim.full_name AS victim_name, b.report_reference
FROM acoustic_events a
JOIN ballistics_evidence b ON b.gunshot_event_id = a.event_id
LEFT JOIN suspects victim ON victim.suspect_id = b.victim_id
ORDER BY a.event_time;

-- ================================================================
-- STEP 2: Test the smart-grip claim against 3 independent signals.
-- IMPORTANT: A contradictory touch is not, alone, proof of HOW it was
-- fabricated. This flags a spoof, system error or compromised record.
-- ================================================================
WITH touch_claims AS (
  SELECT f.touch_id, f.object_name, f.room_name AS reported_room,
         f.matched_suspect_id, f.touch_time,
         s.full_name AS reported_person
  FROM fingerprint_sensors f
  JOIN suspects s ON s.suspect_id = f.matched_suspect_id
  WHERE f.object_name = 'Pistol_9mm'
), other_room_camera AS (
  SELECT t.*, c.room_name AS camera_room, c.observed_time,
    ROW_NUMBER() OVER (
      PARTITION BY t.touch_id
      ORDER BY ABS(TIMESTAMPDIFF(MICROSECOND, c.observed_time, t.touch_time)),
               c.observation_id
    ) AS camera_rank
  FROM touch_claims t
  JOIN camera_observations c
    ON c.suspect_id = t.matched_suspect_id
   AND c.room_name <> t.reported_room
   AND c.image_verified = TRUE
   AND ABS(TIMESTAMPDIFF(MICROSECOND, c.observed_time, t.touch_time)) <= 2000000
), cross_checked AS (
  SELECT cc.*,
    a.room_name AS last_access_room, a.action AS last_access_action,
    (SELECT ds.door_state FROM door_state_logs ds
     WHERE ds.room_name = cc.camera_room AND ds.event_time <= cc.touch_time
     ORDER BY ds.event_time DESC, ds.state_id DESC LIMIT 1)
      AS door_state_at_touch
  FROM other_room_camera cc
  JOIN access_logs a
    ON a.suspect_id = cc.matched_suspect_id
   AND a.log_id = (
     SELECT a2.log_id FROM access_logs a2
     WHERE a2.suspect_id = cc.matched_suspect_id
       AND a2.event_time <= cc.touch_time
     ORDER BY a2.event_time DESC, a2.log_id DESC LIMIT 1
   )
  WHERE cc.camera_rank = 1
)
SELECT touch_id, reported_person, object_name,
       reported_room, touch_time,
       camera_room AS corroborated_room, observed_time,
       last_access_action, last_access_room, door_state_at_touch,
       'CONTRADICTORY LIVE-TOUCH CLAIM; REQUIRES INVESTIGATION' AS assessment
FROM cross_checked
WHERE last_access_action = 'ENTER'
  AND last_access_room = camera_room
  AND door_state_at_touch = 'LOCKED'
ORDER BY touch_time;

-- ================================================================
-- STEP 3: Compare editable scanner row with a separate pre-edit export.
-- A reversed timestamp alone can be clock skew or bad integration;
-- the verified external audit is the direct evidence of record editing.
-- ================================================================
SELECT d.scan_id, d.sample_source,
       displayed.full_name AS displayed_person,
       original.full_name AS originally_matched_person,
       profile_owner.full_name AS sealed_profile_owner,
       d.sample_collected_time, d.scan_processed_time,
       ex.original_processed_time,
       (d.scan_processed_time < d.sample_collected_time) AS impossible_order_flag,
       (d.matched_suspect_id <> ex.original_matched_suspect_id) AS changed_identity_flag,
       (d.scan_processed_time <> ex.original_processed_time) AS changed_time_flag,
       (d.raw_dna_hash <> ex.sealed_raw_dna_hash) AS changed_raw_hash_flag
FROM dna_scanner_logs d
JOIN scanner_integrity_exports ex
  ON ex.scan_id = d.scan_id AND ex.integrity_verified = TRUE
JOIN suspects displayed ON displayed.suspect_id = d.matched_suspect_id
JOIN suspects original ON original.suspect_id = ex.original_matched_suspect_id
JOIN suspects profile_owner ON profile_owner.dna_profile_hash = ex.sealed_raw_dna_hash
WHERE d.scan_processed_time < d.sample_collected_time
   OR d.matched_suspect_id <> ex.original_matched_suspect_id
   OR d.scan_processed_time <> ex.original_processed_time
   OR d.raw_dna_hash <> ex.sealed_raw_dna_hash
ORDER BY d.scan_id;

-- A named account is not automatically the physical operator.
SELECT a.audit_event_id, a.scan_id, a.field_name,
       a.old_value, a.new_value, a.changed_at,
       owner.full_name AS account_owner,
       camera.camera_id AS corroborating_camera,
       camera.room_name AS camera_room,
       a.source_system, a.integrity_verified
FROM scanner_audit_events a
JOIN suspects owner ON owner.suspect_id = a.actor_suspect_id
LEFT JOIN camera_observations camera
  ON camera.suspect_id = a.actor_suspect_id
 AND camera.room_name = 'Control Room'
 AND camera.image_verified = TRUE
 AND ABS(TIMESTAMPDIFF(MICROSECOND, a.changed_at, camera.observed_time)) <= 3000000
WHERE a.integrity_verified = TRUE
ORDER BY a.changed_at;

-- ================================================================
-- STEP 4: Converging evidence -> PRINCIPAL PERSON OF INTEREST.
-- Crucially, the fatal shot is established by medical/ballistic evidence,
-- NOT simply selected as the last gunshot. A DNA match alone proves
-- neither who fired a weapon nor a criminal motive.
-- ================================================================
WITH fatal_shot AS (
  SELECT b.gunshot_event_id, b.recovered_weapon, b.cartridge_caliber,
         b.victim_id, a.room_name, a.event_time AS shot_time,
         b.report_reference
  FROM ballistics_evidence b
  JOIN acoustic_events a ON a.event_id = b.gunshot_event_id
  WHERE b.injury_outcome = 'FATAL'
    AND b.lab_match_status = 'CONFIRMED'
    AND a.event_type = 'GUNSHOT'
), trusted_weapon_sample AS (
  SELECT d.scan_id, d.sample_source,
         d.matched_suspect_id AS framed_person_id,
         owner.suspect_id AS profile_owner_id
  FROM dna_scanner_logs d
  JOIN scanner_integrity_exports ex
    ON ex.scan_id = d.scan_id AND ex.integrity_verified = TRUE
  JOIN suspects owner ON owner.dna_profile_hash = ex.sealed_raw_dna_hash
  WHERE d.sample_source = 'Pistol_45ACP_Grip'
    AND d.raw_dna_hash = ex.sealed_raw_dna_hash
    AND d.matched_suspect_id <> ex.original_matched_suspect_id
    AND owner.suspect_id = ex.original_matched_suspect_id
    AND EXISTS (
      SELECT 1 FROM scanner_audit_events a
      WHERE a.scan_id = d.scan_id
        AND a.field_name = 'matched_suspect_id'
        AND a.integrity_verified = TRUE
    )
), last_access_at_shot AS (
  SELECT fs.gunshot_event_id, al.suspect_id, al.room_name,
         al.action, al.event_time,
         ROW_NUMBER() OVER (
           PARTITION BY fs.gunshot_event_id, al.suspect_id
           ORDER BY al.event_time DESC, al.log_id DESC
         ) AS latest_rank
  FROM fatal_shot fs
  JOIN access_logs al ON al.event_time <= fs.shot_time
), room_camera_at_shot AS (
  SELECT DISTINCT fs.gunshot_event_id, c.suspect_id
  FROM fatal_shot fs
  JOIN camera_observations c
    ON c.room_name = fs.room_name
   AND c.image_verified = TRUE
   AND ABS(TIMESTAMPDIFF(MICROSECOND, c.observed_time, fs.shot_time)) <= 2000000
), audited_console_account AS (
  SELECT DISTINCT a.scan_id, a.actor_suspect_id
  FROM scanner_audit_events a
  JOIN camera_observations c
    ON c.suspect_id = a.actor_suspect_id
   AND c.room_name = 'Control Room'
   AND c.image_verified = TRUE
   AND ABS(TIMESTAMPDIFF(MICROSECOND, c.observed_time, a.changed_at)) <= 3000000
  WHERE a.field_name = 'matched_suspect_id'
    AND a.integrity_verified = TRUE
)
SELECT candidate.full_name AS principal_person_of_interest,
       victim.full_name AS deceased_victim,
       framed.full_name AS falsely_displayed_person,
       fs.room_name AS fatal_shot_room, fs.shot_time,
       fs.cartridge_caliber AS lab_confirmed_caliber,
       fs.recovered_weapon, fs.report_reference,
       'Weapon sample + access + camera + independent edit audit + alibi'
         AS corroboration_summary,
       CASE WHEN motive_lead.verified_source = TRUE
            THEN 'Threat message source verified; motive still provisional'
            ELSE 'No independently verified motive lead' END AS motive_status
FROM fatal_shot fs
JOIN trusted_weapon_sample ws
  ON ws.sample_source = CONCAT(fs.recovered_weapon, '_Grip')
JOIN suspects candidate ON candidate.suspect_id = ws.profile_owner_id
JOIN suspects victim ON victim.suspect_id = fs.victim_id
JOIN suspects framed ON framed.suspect_id = ws.framed_person_id
JOIN last_access_at_shot shooter_access
  ON shooter_access.gunshot_event_id = fs.gunshot_event_id
 AND shooter_access.suspect_id = ws.profile_owner_id
 AND shooter_access.latest_rank = 1
 AND shooter_access.action = 'ENTER'
 AND shooter_access.room_name = fs.room_name
JOIN room_camera_at_shot shooter_camera
  ON shooter_camera.gunshot_event_id = fs.gunshot_event_id
 AND shooter_camera.suspect_id = ws.profile_owner_id
JOIN audited_console_account audit_owner
  ON audit_owner.scan_id = ws.scan_id
 AND audit_owner.actor_suspect_id = ws.profile_owner_id
JOIN last_access_at_shot framed_access
  ON framed_access.gunshot_event_id = fs.gunshot_event_id
 AND framed_access.suspect_id = ws.framed_person_id
 AND framed_access.latest_rank = 1
 AND framed_access.action = 'ENTER'
 AND framed_access.room_name <> fs.room_name
JOIN camera_observations framed_camera
  ON framed_camera.suspect_id = ws.framed_person_id
 AND framed_camera.room_name = framed_access.room_name
 AND framed_camera.image_verified = TRUE
 AND ABS(TIMESTAMPDIFF(MICROSECOND, framed_camera.observed_time, fs.shot_time)) <= 2000000
LEFT JOIN investigative_leads AS motive_lead
  ON motive_lead.suspect_id = candidate.suspect_id
 AND motive_lead.lead_type = 'THREAT_MESSAGE'
 AND motive_lead.verified_source = TRUE
WHERE fs.recovered_weapon = 'Pistol_45ACP'
  AND (
    SELECT ds.door_state FROM door_state_logs ds
    WHERE ds.room_name = framed_access.room_name AND ds.event_time <= fs.shot_time
    ORDER BY ds.event_time DESC, ds.state_id DESC LIMIT 1
  ) = 'LOCKED'
ORDER BY fs.shot_time;

-- CONCLUSION: In this *synthetic scenario*, these independent clues converge
-- on Adrian Cross. This is an investigative lead, not an infallible legal verdict.
