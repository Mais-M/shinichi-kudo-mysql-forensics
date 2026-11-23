-- The Shinichi Kudo Protocol | dataset-level invariant checks
-- Expected: all fourteen status cells = PASS. Run after data.sql.
USE shinichi_forensic_demo_v2;

SELECT '01 ambient noise exactly 2700' AS check_name,
  IF((SELECT COUNT(*) FROM acoustic_events WHERE event_type = 'AMBIENT') = 2700,
     'PASS', 'FAIL') AS status
UNION ALL
SELECT '02 exactly 3 gunshots',
  IF((SELECT COUNT(*) FROM acoustic_events WHERE event_type = 'GUNSHOT') = 3, 'PASS', 'FAIL')
UNION ALL
SELECT '03 fatal event is lab-linked to Viktor',
  IF((SELECT COUNT(*) FROM ballistics_evidence b
      JOIN suspects s ON s.suspect_id = b.victim_id
      WHERE b.gunshot_event_id = 5003 AND b.injury_outcome = 'FATAL'
        AND b.lab_match_status = 'CONFIRMED' AND s.full_name = 'Viktor Hale') = 1,
     'PASS','FAIL')
UNION ALL
SELECT '04 40.000 sec since last scream',
  IF((SELECT TIMESTAMPDIFF(MICROSECOND,
       (SELECT MAX(event_time) FROM acoustic_events WHERE event_type = 'SCREAM'),
       (SELECT event_time FROM acoustic_events WHERE event_id = 5003))) = 40000000,
     'PASS','FAIL')
UNION ALL
SELECT '05 spoofed touch registered at correct time',
  IF((SELECT COUNT(*) FROM fingerprint_sensors
      WHERE touch_id = 9001 AND object_name = 'Pistol_9mm'
        AND matched_suspect_id = 2
        AND touch_time = '2026-12-04 21:14:58.500') = 1,
     'PASS','FAIL')
UNION ALL
SELECT '06 Nora independently observed in Archive',
  IF((SELECT COUNT(*) FROM camera_observations
      WHERE suspect_id = 2 AND room_name = 'Archive Room'
        AND observed_time = '2026-12-04 21:14:58.500'
        AND image_verified = TRUE) = 1,
     'PASS','FAIL')
UNION ALL
SELECT '07 Archive locked at fatal shot',
  IF((SELECT ds.door_state FROM door_state_logs ds
      WHERE ds.room_name = 'Archive Room'
        AND ds.event_time <= '2026-12-04 21:15:00.000'
      ORDER BY ds.event_time DESC LIMIT 1) = 'LOCKED', 'PASS','FAIL')
UNION ALL
SELECT '08 scanner identity + timestamp changed',
  IF((SELECT COUNT(*) FROM dna_scanner_logs d
      JOIN scanner_integrity_exports ex ON ex.scan_id = d.scan_id
      WHERE d.scan_id = 9001 AND ex.integrity_verified = TRUE
        AND d.matched_suspect_id = 2 AND ex.original_matched_suspect_id = 3
        AND d.scan_processed_time < d.sample_collected_time
        AND d.scan_processed_time <> ex.original_processed_time
        AND d.raw_dna_hash = ex.sealed_raw_dna_hash) = 1,
     'PASS','FAIL')
UNION ALL
SELECT '09 exactly 2 verified independent edits',
  IF((SELECT COUNT(*) FROM scanner_audit_events
      WHERE scan_id = 9001 AND actor_suspect_id = 3
        AND integrity_verified = TRUE) = 2, 'PASS','FAIL')
UNION ALL
SELECT '10 Adrian seen in Main Hall near fatal shot',
  IF((SELECT COUNT(*) FROM camera_observations
      WHERE suspect_id = 3 AND room_name = 'Main Hall'
        AND image_verified = TRUE
        AND ABS(TIMESTAMPDIFF(MICROSECOND, observed_time,
              '2026-12-04 21:15:00.000')) <= 2000000) >= 1,
      'PASS','FAIL')
UNION ALL
SELECT '11 safe installation marker',
  IF((SELECT COUNT(*) FROM project_installation
      WHERE install_id = 1 AND project_code = 'shinichi-kudo-forensics-safe-v2'
        AND schema_version = 2 AND seeded_at IS NOT NULL) = 1, 'PASS','FAIL')
UNION ALL
SELECT '12 all 11 evidence tables present',
  IF((SELECT COUNT(*) FROM information_schema.tables
      WHERE table_schema = DATABASE()
        AND table_name IN ('suspects','access_logs','acoustic_events',
          'door_state_logs','camera_observations','fingerprint_sensors',
          'dna_scanner_logs','scanner_integrity_exports',
          'scanner_audit_events','ballistics_evidence','investigative_leads')) = 11,
     'PASS','FAIL')
UNION ALL
SELECT '13 edited scan has external audit and baseline',
  IF((SELECT COUNT(*) FROM dna_scanner_logs d
      JOIN scanner_integrity_exports ex ON ex.scan_id = d.scan_id
      WHERE d.scan_id = 9001 AND ex.integrity_verified = TRUE
        AND d.raw_dna_hash = ex.sealed_raw_dna_hash
        AND d.matched_suspect_id <> ex.original_matched_suspect_id
        AND EXISTS (
          SELECT 1 FROM scanner_audit_events a
          WHERE a.scan_id = d.scan_id AND a.integrity_verified = TRUE
            AND a.field_name = 'matched_suspect_id'
        )) = 1, 'PASS','FAIL')
UNION ALL
SELECT '14 six actors, one fatal shot, one planted claim',
  IF((SELECT COUNT(*) FROM suspects) = 6
     AND (SELECT COUNT(*) FROM ballistics_evidence WHERE injury_outcome = 'FATAL') = 1
     AND (SELECT COUNT(*) FROM fingerprint_sensors WHERE object_name = 'Pistol_9mm'
          AND matched_suspect_id = 2 AND touch_time = '2026-12-04 21:14:58.500') = 1,
     'PASS','FAIL');
