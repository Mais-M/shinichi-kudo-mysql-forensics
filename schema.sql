-- THE SHINICHI KUDO PROTOCOL | SAFE v2 | MySQL 8.0.16+
-- NON-DESTRUCTIVE SCHEMA: no DROP TABLE, TRUNCATE, or DELETE.
-- Creates/uses its OWN isolated demo database. It never selects amitdb
-- or the earlier shinichi_forensic_db database.
-- Safe to re-run: CREATE TABLE IF NOT EXISTS preserves existing rows.
-- This is NOT a migration tool for incompatible custom table definitions.
CREATE DATABASE IF NOT EXISTS shinichi_forensic_demo_v2
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE shinichi_forensic_demo_v2;

-- A single installation marker protects data.sql from filling arbitrary tables
-- and records whether this exact synthetic dataset was already imported.
CREATE TABLE IF NOT EXISTS project_installation (
  install_id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
  project_code VARCHAR(80) NOT NULL,
  schema_version SMALLINT UNSIGNED NOT NULL,
  seeded_at DATETIME(3) NULL,
  CONSTRAINT chk_single_install CHECK (install_id = 1)
) ENGINE=InnoDB;

-- If an installation marker already exists, leave it completely untouched.
-- The seed script will refuse a mismatched marker/schema version.
INSERT INTO project_installation (install_id, project_code, schema_version, seeded_at)
SELECT 1, 'shinichi-kudo-forensics-safe-v2', 2, NULL
WHERE NOT EXISTS (SELECT 1 FROM project_installation WHERE install_id = 1);

-- DNA hashes are *synthetic profile identifiers*, not real sequenced DNA.
CREATE TABLE IF NOT EXISTS suspects (
  suspect_id INT PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  role_in_event VARCHAR(60) NOT NULL,
  dna_profile_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
  status ENUM('Alive','Deceased') NOT NULL DEFAULT 'Alive'
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS access_logs (
  log_id INT AUTO_INCREMENT PRIMARY KEY,
  suspect_id INT NOT NULL,
  room_name VARCHAR(60) NOT NULL,
  action ENUM('ENTER','EXIT') NOT NULL,
  event_time DATETIME(3) NOT NULL,
  source_device VARCHAR(60) NOT NULL,
  CONSTRAINT fk_access_person FOREIGN KEY (suspect_id) REFERENCES suspects(suspect_id),
  INDEX idx_access_person_time (suspect_id, event_time, log_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS acoustic_events (
  event_id INT AUTO_INCREMENT PRIMARY KEY,
  room_name VARCHAR(60) NOT NULL,
  event_type ENUM('AMBIENT','FOOTSTEPS','ALARM','GLASS_BREAK','SCREAM','GUNSHOT') NOT NULL,
  decibel_level DECIMAL(5,2) NOT NULL,
  estimated_caliber VARCHAR(20) NULL, -- acoustic guess, NOT forensic confirmation
  event_time DATETIME(3) NOT NULL,
  sensor_id VARCHAR(60) NOT NULL,
  CONSTRAINT chk_acoustics_decibels CHECK (decibel_level BETWEEN 0 AND 180),
  INDEX idx_acoustics_type_time (event_type, event_time),
  INDEX idx_acoustics_room_time (room_name, event_time)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS door_state_logs (
  state_id INT AUTO_INCREMENT PRIMARY KEY,
  room_name VARCHAR(60) NOT NULL,
  door_state ENUM('LOCKED','UNLOCKED') NOT NULL,
  event_time DATETIME(3) NOT NULL,
  controller_id VARCHAR(60) NOT NULL,
  INDEX idx_door_room_time (room_name, event_time)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS camera_observations (
  observation_id INT AUTO_INCREMENT PRIMARY KEY,
  suspect_id INT NOT NULL,
  room_name VARCHAR(60) NOT NULL,
  observed_time DATETIME(3) NOT NULL,
  camera_id VARCHAR(60) NOT NULL,
  image_verified BOOLEAN NOT NULL DEFAULT FALSE,
  observation_note VARCHAR(255) NULL,
  CONSTRAINT fk_camera_person FOREIGN KEY (suspect_id) REFERENCES suspects(suspect_id),
  INDEX idx_camera_person_time (suspect_id, observed_time),
  INDEX idx_camera_room_time (room_name, observed_time)
) ENGINE=InnoDB;

-- Live grip/contact-sensor matches; not retrospective latent fingerprint collection.
CREATE TABLE IF NOT EXISTS fingerprint_sensors (
  touch_id INT AUTO_INCREMENT PRIMARY KEY,
  object_name VARCHAR(60) NOT NULL,
  room_name VARCHAR(60) NOT NULL,
  matched_suspect_id INT NOT NULL,
  pressure_newton DECIMAL(6,2) NULL,
  confidence_score DECIMAL(5,2) NOT NULL,
  touch_time DATETIME(3) NOT NULL,
  device_id VARCHAR(60) NOT NULL,
  CONSTRAINT fk_touch_person FOREIGN KEY (matched_suspect_id) REFERENCES suspects(suspect_id),
  CONSTRAINT chk_touch_conf CHECK (confidence_score BETWEEN 0 AND 100),
  INDEX idx_touch_object_time (object_name, touch_time)
) ENGINE=InnoDB;

-- Fictional experimental rapid-profile scanner; not present-day instant DNA testing.
CREATE TABLE IF NOT EXISTS dna_scanner_logs (
  scan_id INT PRIMARY KEY,
  sample_source VARCHAR(80) NOT NULL,
  raw_dna_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  matched_suspect_id INT NOT NULL,
  confidence_score DECIMAL(5,2) NOT NULL,
  sample_collected_time DATETIME(3) NOT NULL,
  scan_processed_time DATETIME(3) NOT NULL,
  scanner_id VARCHAR(60) NOT NULL,
  CONSTRAINT fk_scan_displayed_person FOREIGN KEY (matched_suspect_id) REFERENCES suspects(suspect_id),
  CONSTRAINT chk_scan_conf CHECK (confidence_score BETWEEN 0 AND 100),
  INDEX idx_scan_sample (sample_source)
) ENGINE=InnoDB;

-- A separate, independently captured pre-edit export; trust is simulated.
-- No field inside the compromised database is assumed to be immutable.
CREATE TABLE IF NOT EXISTS scanner_integrity_exports (
  export_id INT AUTO_INCREMENT PRIMARY KEY,
  scan_id INT NOT NULL UNIQUE,
  sealed_raw_dna_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  original_matched_suspect_id INT NOT NULL,
  original_processed_time DATETIME(3) NOT NULL,
  exported_at DATETIME(3) NOT NULL,
  source_system VARCHAR(80) NOT NULL,
  integrity_verified BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_export_scan FOREIGN KEY (scan_id) REFERENCES dna_scanner_logs(scan_id),
  CONSTRAINT fk_export_person FOREIGN KEY (original_matched_suspect_id) REFERENCES suspects(suspect_id)
) ENGINE=InnoDB;

-- Recovered external audit feed; actor_suspect_id indicates *account owner*,
-- NOT verified human operator (credentials may be misused).
CREATE TABLE IF NOT EXISTS scanner_audit_events (
  audit_event_id INT AUTO_INCREMENT PRIMARY KEY,
  scan_id INT NOT NULL,
  actor_suspect_id INT NOT NULL,
  field_name ENUM('matched_suspect_id','scan_processed_time') NOT NULL,
  old_value VARCHAR(100) NOT NULL,
  new_value VARCHAR(100) NOT NULL,
  changed_at DATETIME(3) NOT NULL,
  source_system VARCHAR(80) NOT NULL,
  integrity_verified BOOLEAN NOT NULL DEFAULT FALSE,
  console_device VARCHAR(60) NOT NULL,
  CONSTRAINT fk_audit_scan FOREIGN KEY (scan_id) REFERENCES dna_scanner_logs(scan_id),
  CONSTRAINT fk_audit_account FOREIGN KEY (actor_suspect_id) REFERENCES suspects(suspect_id),
  INDEX idx_audit_scan_time (scan_id, changed_at)
) ENGINE=InnoDB;

-- The fatal-shot designation comes from a fictional medical + ballistic report,
-- never from taking MAX(gunshot_time).
CREATE TABLE IF NOT EXISTS ballistics_evidence (
  evidence_id INT AUTO_INCREMENT PRIMARY KEY,
  gunshot_event_id INT NOT NULL UNIQUE,
  recovered_weapon VARCHAR(60) NOT NULL,
  cartridge_caliber VARCHAR(20) NOT NULL,
  victim_id INT NULL,
  injury_outcome ENUM('FATAL','NON_FATAL','NONE','UNKNOWN') NOT NULL,
  lab_match_status ENUM('CONFIRMED','INCONCLUSIVE') NOT NULL,
  report_reference VARCHAR(80) NOT NULL,
  CONSTRAINT fk_ballistics_gunshot FOREIGN KEY (gunshot_event_id) REFERENCES acoustic_events(event_id),
  CONSTRAINT fk_ballistics_victim FOREIGN KEY (victim_id) REFERENCES suspects(suspect_id),
  INDEX idx_ballistics_fatal (injury_outcome, lab_match_status)
) ENGINE=InnoDB;

-- A verified message source supports a possible motive, not a legal finding.
CREATE TABLE IF NOT EXISTS investigative_leads (
  lead_id INT AUTO_INCREMENT PRIMARY KEY,
  suspect_id INT NOT NULL,
  lead_type ENUM('THREAT_MESSAGE','WITNESS_ACCOUNT','OTHER') NOT NULL,
  source_reference VARCHAR(80) NOT NULL,
  summary_text VARCHAR(255) NOT NULL,
  recorded_at DATETIME(3) NOT NULL,
  verified_source BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_lead_person FOREIGN KEY (suspect_id) REFERENCES suspects(suspect_id)
) ENGINE=InnoDB;
