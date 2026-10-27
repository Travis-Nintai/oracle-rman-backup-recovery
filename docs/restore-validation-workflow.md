# Restore validation workflow

Validation answers a narrower question than a test restore, and the distinction matters. Validation checks that the backup pieces are present and readable. A test restore proves the whole chain works: pieces, logs, control file, and the steps a tired person runs at 3 AM. Do both, on different cadences, and never let a clean validation stand in for a restore you have not done.

## Cadence

- After every backup policy change: run validation once, before the new policy is trusted.
- Weekly: run the readiness check (`sql/recovery_readiness.sql`) and the validation template (`rman/validate_restore.rman`).
- Monthly: perform a full test restore to an isolated host.
- After any storage, host, or RMAN configuration change: run validation again, because the pieces may be fine while the path to them is not.

## Step 1: Readiness first

Run the readiness check before validating. It is cheap, read-only, and catches the problems validation cannot: a database that quietly left ARCHIVELOG mode, an FRA at 96 percent, a datafile added last week that no backup has ever covered. Fix readiness failures first. Validating backups for a database that cannot archive is polishing a strategy with a hole in it.

## Step 2: Crosscheck

`CROSSCHECK BACKUP` compares the repository with what is actually on disk or tape and marks missing pieces EXPIRED. Run it before validating, not after a failure, so the validation step tests the pieces that exist rather than failing on pieces that are already known to be gone. Expired pieces are information: find out why they are gone (retention cleanup, storage move, accidental delete) before deciding what to do about them.

## Step 3: Validate

Run `rman/validate_restore.rman`. It restores nothing. `RESTORE DATABASE VALIDATE CHECK LOGICAL` reads every piece a restore would need and reports physical and logical corruption. `RESTORE ARCHIVELOG ALL VALIDATE` does the same for the archived logs recovery depends on. `REPORT NEED BACKUP` lists datafiles outside the retention policy.

Illustrative lab output for a clean run looks like this (not captured results):

```
using channel ORA_DISK_1
List of Datafiles
=================
File Status Marked Corrupt Empty Blocks Blocks Examined High SCN
---- ------ -------------- ------------ --------------- ----------
1    OK     0              0            12800           1842031
2    OK     0              0            6400            1842031
...
Finished restore at 2026-10-26 21:14:03
```

A clean run ends with every file OK and no corrupt blocks. Anything else is a finding, not a warning to file away.

## Step 4: When validation fails

Work the failure, not the symptom:

| Finding | What it usually means | First move |
|---|---|---|
| Piece marked EXPIRED | File moved or deleted outside RMAN | Find out what removed it; if retention cleanup did, confirm the policy; if not, treat it as a storage incident |
| Corrupt blocks reported | Bad media, bad write, or a real data problem | Identify the file and block range; check whether a second copy exists; re-back up after the underlying problem is fixed |
| Missing archived logs | Log backups lagging, or logs deleted before backup | Restore logs from wherever they survive, or accept that recovery stops at the gap (see the PITR runbook) |
| REPORT NEED BACKUP lists files | New datafiles, or backups aged out | Back up the listed files now, then re-run validation |

Never delete the only copy of anything while investigating. A failed validation is the moment the remaining copies matter most.

## Step 5: The test restore

Once a month, restore to an isolated host that is not production and not the backup host. The outline, not a script, because host details vary:

1. Copy or present the backup pieces and archived logs to the test host.
2. Restore the control file from autobackup, then restore the database.
3. Recover to the most recent point the logs allow.
4. Open the test copy (with `RESETLOGS` on the test copy only, never on production) and run a sanity check: row counts on a few known tables, or the application smoke test if one exists.
5. Record the result: how long the restore took, what was missing, what surprised you. Restore time is a measured number after this, not an estimate.

The test copy is disposable. Drop it when the test ends so it can never be mistaken for a real database.

## Step 6: Record it

A validation nobody wrote down did not happen for audit purposes. Keep a short log per run: date, database (lab name only in shared notes), validation result, test restore result, and anything found. The portfolio tracker pattern works here too: one line per run, findings in plain language, follow-ups with owners.

## What validation does not cover

Validation does not check that the application starts against the restored database, that the backup window still fits, or that anyone remembers the restore steps. Those are separate checks, and the test restore is where they surface. Schedule them anyway.
