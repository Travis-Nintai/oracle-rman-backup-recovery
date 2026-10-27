-- ============================================================================
-- recovery_readiness.sql
--
-- Purpose:
--   Answers one question before an incident does: could this database
--   actually be recovered right now? Checks ARCHIVELOG mode, fast
--   recovery area pressure, the most recent full datafile backup, which
--   datafiles appear in an available backup set, and whether controlfile
--   autobackup is configured.
--
-- Usage:
--   sqlplus / as sysdba @recovery_readiness.sql
--
--   To change the thresholds, edit the DEFINE lines below. The full
--   backup window default is 7 days, which fits a weekly full plus daily
--   incremental pattern. Tighten it if the backup policy demands a
--   fresher full backup.
--
-- Exit code:
--   0 - ARCHIVELOG mode on, a full backup inside the window, every
--       datafile covered by an available backup set, FRA below critical
--   2 - any of those checks fails
--
-- Notes:
--   Read-only. History depth depends on CONTROL_FILE_RECORD_KEEP_TIME,
--   since this reads the control-file-based V$ views, not a recovery
--   catalog. V$BACKUP_SET has no STATUS column, so availability is
--   checked through V$BACKUP_PIECE (STATUS 'A' means available).
--   A clean report here means the pieces exist, not that they restore.
--   Run docs/restore-validation-workflow.md on a schedule for that.
--   Reviewed; not executed against a live Oracle instance.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF

-- ----------------------------------------------------------------------------
-- Thresholds. Edit to match local backup policy.
-- ----------------------------------------------------------------------------
DEFINE full_backup_max_age_days = 7
DEFINE fra_warn_pct = 80
DEFINE fra_crit_pct = 95

PROMPT
PROMPT === 1. Database recovery mode ===
COLUMN log_mode      FORMAT A12 HEADING 'LOG MODE'
COLUMN flashback_on  FORMAT A12 HEADING 'FLASHBACK'
COLUMN force_logging FORMAT A12 HEADING 'FORCE LOGGING'

SELECT log_mode,
       flashback_on,
       force_logging
  FROM v$database;

PROMPT
PROMPT === 2. Fast recovery area ===
COLUMN name           FORMAT A40 HEADING 'FRA LOCATION'
COLUMN space_limit_mb FORMAT 999,999,990 HEADING 'LIMIT MB'
COLUMN space_used_mb  FORMAT 999,999,990 HEADING 'USED MB'
COLUMN reclaimable_mb FORMAT 999,999,990 HEADING 'RECLAIMABLE MB'
COLUMN pct_used       FORMAT 990.0 HEADING 'PCT USED'

SELECT name,
       ROUND(space_limit / 1024 / 1024)      AS space_limit_mb,
       ROUND(space_used / 1024 / 1024)       AS space_used_mb,
       ROUND(space_reclaimable / 1024 / 1024) AS reclaimable_mb,
       CASE WHEN space_limit = 0 THEN 0
            ELSE ROUND(space_used / space_limit * 100, 1)
       END                                    AS pct_used
  FROM v$recovery_file_dest;

PROMPT
PROMPT === 3. Most recent full datafile backup ===
PROMPT (V$BACKUP_SET BACKUP_TYPE 'D' means a full or level 0 backup;
PROMPT  'I' is incremental, 'L' is archived logs.)
COLUMN latest_full FORMAT A16 HEADING 'LATEST FULL'
COLUMN days_ago    FORMAT 9990.0 HEADING 'DAYS AGO'

SELECT TO_CHAR(MAX(completion_time), 'YYYY-MM-DD HH24:MI') AS latest_full,
       ROUND(SYSDATE - MAX(completion_time), 1)            AS days_ago
  FROM v$backup_set
 WHERE backup_type = 'D';

PROMPT
PROMPT === 4. Datafile backup coverage ===
PROMPT (Datafiles appearing in at least one backup set that still has an
PROMPT  available backup piece, compared with datafiles in the database.)
COLUMN total_files   FORMAT 9999 HEADING 'TOTAL FILES'
COLUMN covered_files FORMAT 9999 HEADING 'COVERED FILES'
COLUMN missing_files FORMAT 9999 HEADING 'MISSING FILES'

SELECT (SELECT COUNT(*) FROM v$datafile) AS total_files,
       COUNT(DISTINCT df.file#)          AS covered_files,
       (SELECT COUNT(*) FROM v$datafile)
         - COUNT(DISTINCT df.file#)      AS missing_files
  FROM v$backup_datafile df
 WHERE EXISTS (SELECT 1
                 FROM v$backup_set bs
                 JOIN v$backup_piece bp
                   ON bp.set_stamp = bs.set_stamp
                  AND bp.set_count = bs.set_count
                WHERE bs.set_stamp = df.set_stamp
                  AND bs.set_count = df.set_count
                  AND bp.status = 'A');

PROMPT
PROMPT === 5. Controlfile autobackup configuration ===
COLUMN conf_name  FORMAT A30 HEADING 'SETTING'
COLUMN conf_value FORMAT A20 HEADING 'VALUE'

SELECT name  AS conf_name,
       value AS conf_value
  FROM v$rman_configuration
 WHERE name LIKE '%AUTOBACKUP%';

PROMPT
PROMPT === Verdict ===

COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE
         WHEN (SELECT log_mode FROM v$database) <> 'ARCHIVELOG' THEN 2
         WHEN (SELECT MAX(completion_time)
                 FROM v$backup_set
                WHERE backup_type = 'D') IS NULL THEN 2
         WHEN (SELECT MAX(completion_time)
                 FROM v$backup_set
                WHERE backup_type = 'D') < SYSDATE - &full_backup_max_age_days THEN 2
         WHEN (SELECT COUNT(DISTINCT df.file#)
                 FROM v$backup_datafile df
                WHERE EXISTS (SELECT 1
                                FROM v$backup_set bs
                                JOIN v$backup_piece bp
                                  ON bp.set_stamp = bs.set_stamp
                                 AND bp.set_count = bs.set_count
                               WHERE bs.set_stamp = df.set_stamp
                                 AND bs.set_count = df.set_count
                                 AND bp.status = 'A'))
              < (SELECT COUNT(*) FROM v$datafile) THEN 2
         WHEN EXISTS (SELECT 1
                        FROM v$recovery_file_dest
                       WHERE space_limit > 0
                         AND space_used / space_limit * 100 >= &fra_crit_pct) THEN 2
         ELSE 0
       END AS exit_code
  FROM dual;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = recovery ready, 2 = a check failed)
PROMPT A clean report means the pieces exist. It does not prove they restore.
EXIT &v_exit_code
