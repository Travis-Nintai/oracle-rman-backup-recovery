# Backup strategy

A backup strategy answers three questions before anything breaks: how much data can we afford to lose, how far back must we be able to go, and how long may a restore take. Everything in this repo follows from those answers. The defaults below are starting points for a lab conversation, not recommendations. Set them from the business requirement.

## Prerequisites

None of this works without ARCHIVELOG mode. A database in NOARCHIVELOG mode can only be restored to the moment of its last backup, and only while it is down. The readiness check in `sql/recovery_readiness.sql` fails a NOARCHIVELOG database on purpose: that is a strategy decision being made by accident, and it should be made deliberately or not at all.

Two settings belong on before the first backup runs. Controlfile autobackup (`CONFIGURE CONTROLFILE AUTOBACKUP ON`) means a restore never depends on finding a control file backup by hand. A recovery catalog, or a long enough `CONTROL_FILE_RECORD_KEEP_TIME`, means backup metadata survives longer than the default control file history. Without a catalog, metadata ages out of the control file and old backups become hard to find even though the pieces still exist.

## Full and incremental

A level 0 backup is the base everything else builds on. A level 1 backup after it copies only blocks changed since the last backup at the same or lower level. That is the difference between cumulative and differential incremental backups: a cumulative level 1 copies everything changed since the last level 0, while a differential level 1 copies everything changed since the last level 1 or level 0, whichever is more recent. Differential backups are smaller and faster day to day; cumulative backups make a restore simpler because fewer pieces are involved. Pick one deliberately. A common pattern is a weekly level 0 with daily differential level 1 backups, plus archived logs throughout.

Image copies are the other shape worth knowing. A backup set is RMAN's own format and needs a restore step. An image copy is a byte-for-byte copy of a datafile that can be switched into place. Backup sets compress and are the usual default; image copies restore faster and suit databases where restore time matters more than backup size.

## Retention

RMAN offers two ways to say how long backups must survive. A recovery window (for example, 14 days) keeps everything needed to recover to any point in the window. A redundancy count (for example, 2) keeps the two most recent backups of each file. A recovery window matches a point-in-time recovery requirement directly, which is why it is the usual choice when the business asks "how far back can we go." Redundancy is simpler to reason about when storage is tight. Whichever you configure, `REPORT OBSOLETE` shows what falls outside it, and deleting obsolete backups is a separate decision from taking new ones.

## Where backups live

The fast recovery area (FRA) is the default home for backups, archived logs, and flashback logs, with a size limit the database enforces by deleting obsolete files when space runs short. That self-management is convenient and also the main risk: an FRA that fills up stalls archiving and then stalls the database. Size it from real backup sizes and growth, watch it with the readiness check, and treat 80 percent used as the moment to act, not 100 percent.

Backups to a separate disk location or to tape through a media management layer follow the same strategy, only the channel changes. Tape and cloud destinations need their own restore testing; a backup format you have never restored from is unproven regardless of where it sits.

## Archiving and the logs between backups

Backups alone only restore to the backup moment. Point-in-time recovery between backups depends on the archived logs, so the archiving chain matters as much as the backup job. Archived logs must be backed up too (`BACKUP ... PLUS ARCHIVELOG` in `rman/backup_database.rman`), and the log destination must have room. A gap in the archived log sequence caps recovery at the gap. The PITR runbook covers what to do when that happens.

## Features with licensing notes

A few useful pieces sit behind licenses, and the strategy should name them rather than assume them:

- Block change tracking speeds incremental backups by recording changed blocks instead of scanning every datafile. It needs Enterprise Edition.
- Backup encryption protects backup pieces at rest. It needs the Advanced Security option and a wallet in place before the backup runs, not after.
- Flashback Database, covered in the PITR runbook as an alternative to a restore, needs Enterprise Edition and flashback logs enabled in advance.

Basic RMAN backup, restore, and recovery, including the templates in this repo, are included with the database.

## What a good strategy looks like in practice

It is written down, it names a recovery point objective (how much data loss is acceptable) and a recovery time objective (how long a restore may take), and it is tested on a schedule. The validation workflow doc covers the testing half. A strategy nobody has restored from is a document, not a capability.

## Illustrative lab schedule

The following is an example only, for a small lab database, not a prescription:

- Weekly level 0 backup, Sunday night, plus archived logs.
- Daily differential level 1 backup, plus archived logs.
- Archived log backups twice daily, kept until the next full backup is validated.
- Recovery window of 14 days.
- Restore validation weekly; full test restore monthly.

Change every line of it to fit the real requirement before using it anywhere.
