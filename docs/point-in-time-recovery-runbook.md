# Point-in-time recovery runbook

Point-in-time recovery (PITR) exists for the damage that is already done: a table dropped, a batch job that updated the wrong rows, a logical error discovered hours later. It recovers the database, or part of it, to a moment before the damage. Everything after that moment is lost in the recovered copy, which is why the first step is always to confirm the target moment, not to start restoring.

## Before you touch anything

1. Confirm the target. Get the time, or better the system change number (SCN), of the last good state, and confirm it with whoever owns the data. Recovering to the wrong moment destroys good work for nothing.
2. Take a fresh backup if the database still allows it. Once recovery opens with `RESETLOGS`, the old incarnation's logs are no longer the path forward. A fresh backup preserves the current state as a fallback.
3. Confirm the recovery window. The backup and the archived logs must cover the target moment continuously. A gap in the archived logs caps recovery at the gap, and no command crosses a gap.
4. Tell the stakeholders. PITR means downtime and data loss after the target moment. Nobody should learn that from the outage channel.

## Choose the scope

Not every PITR is a whole-database recovery. Pick the smallest scope that fixes the damage:

| Damage | First choice | Why |
|---|---|---|
| One dropped table, recycle bin intact | Flashback Drop (`FLASHBACK TABLE ... TO BEFORE DROP`) | No restore at all; the table is still in the recycle bin |
| One table, recycle bin purged or disabled | Tablespace point-in-time recovery (TSPITR) | Recovers only the affected tablespace; the rest of the database keeps running |
| Bad data across many tables, or a dropped schema | Database PITR | Recovers the whole database to the target moment |
| Recent logical error, flashback logs available | Flashback Database | Rewinds the database without a restore, but only as far back as the flashback logs reach |

Flashback Drop needs the recycle bin enabled, and Flashback Database needs Enterprise Edition with flashback logging enabled before the damage happened. Neither helps if it was not set up in advance. The rest of this runbook covers the two restore-based options.

## Database PITR, step by step

The outline uses RMAN against the target database. Replace `<TARGET_TIME>` with the confirmed time, or use `UNTIL SCN <SCN>` if the SCN is known. Times are less precise than SCNs; prefer the SCN when it exists.

1. Shut the database down and mount it. Recovery to a point in time requires the database mounted, not open:
   - `SHUTDOWN IMMEDIATE;`
   - `STARTUP MOUNT;`
2. Restore and recover to the target moment:
   - `RESTORE DATABASE UNTIL TIME '<TARGET_TIME>';`
   - `RECOVER DATABASE UNTIL TIME '<TARGET_TIME>';`
   RMAN restores the datafiles from backup and then applies archived logs up to, but not past, the target.
3. Open with `RESETLOGS`:
   - `ALTER DATABASE OPEN RESETLOGS;`
   This starts a new database incarnation. Everything after the target moment in the old incarnation is no longer reachable by normal recovery. That is the point of the fresh backup in the preparation step.
4. Verify before handing the database back:
   - Confirm the damaged object is back, or the bad data is gone.
   - Check that the database is open and accepting connections.
   - Run the readiness check (`sql/recovery_readiness.sql`) to confirm the recovered database is in ARCHIVELOG mode and its backup state is known.
5. Back it up immediately. A freshly recovered database with no new backup is one incident away from having no recovery path at all. Take a full backup before declaring the incident closed.

## Tablespace PITR (TSPITR), outline

TSPITR recovers one tablespace to an earlier point while the rest of the database stays open. RMAN builds an auxiliary instance, restores the tablespace there, recovers it to the target time, then moves the recovered datafiles back. The outline:

1. Identify the tablespace and confirm no object in it depends on objects outside it (a constraint or trigger crossing the boundary blocks TSPITR, and RMAN reports the dependency).
2. Run the recovery, in outline form: `RECOVER TABLESPACE <TABLESPACE_NAME> UNTIL TIME '<TARGET_TIME>' AUXILIARY DESTINATION '<AUX_LOCATION>';`
3. RMAN handles the auxiliary instance, the restore, and the import of the recovered tablespace. Check its output for dependency errors before assuming success.
4. Verify the recovered objects, then back up the tablespace.

TSPITR is the right default when the damage is contained, because it avoids the downtime and data loss of a whole-database recovery. It is also the option with the most prerequisites, so check dependencies early.

## When there is an archived log gap

Recovery stops at the gap. The choices, in order of preference:

1. Find the missing logs. Check the log backup destination, the standby if one exists, and any second copy of the archivelogs. A gap that can be filled is not a gap.
2. Recover to the gap point and accept the data loss after it, if the business agrees. This is still a PITR, only to an earlier moment than planned.
3. If neither works, restore the most recent full backup without rolling forward. That is a restore to the backup moment, and everything after it is gone.

Say plainly which outcome happened. A recovery to an earlier moment presented as a recovery to the planned moment will be discovered, and it will be discovered at the worst time.

## After every PITR

- A new full backup, before anything else.
- A note of what happened: target moment, actual recovery moment, incarnation change, verification result, and the new backup. If the same damage happens again, the next runbook run starts from evidence instead of memory.
- A review of how the damage happened. PITR fixes data; it does not fix the process that damaged it. Access controls, change review, and a second pair of eyes on destructive statements belong in that review.

## Illustrative lab example

A fictional lab database, ORCLLAB, with a table dropped at 14:32:

- Last good state confirmed: 14:30, SCN 1842100.
- Fresh backup taken of the current (damaged) state, for fallback.
- Database mounted; `RESTORE DATABASE UNTIL SCN 1842100;` then `RECOVER DATABASE UNTIL SCN 1842100;`
- Opened with `RESETLOGS`; table confirmed present with its 14:30 contents.
- Full backup taken immediately; incident note written.

This is an illustrative walkthrough, not a captured recovery. Times, SCNs, and row counts are fictional.
