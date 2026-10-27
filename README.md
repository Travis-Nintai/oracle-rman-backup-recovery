# Oracle RMAN Backup and Recovery

A backup you have never restored is a hope, not a plan. This repo is about the second half of that sentence: the backup strategy, the checks that prove a database can actually be recovered, and the runbooks for the day something goes wrong.

It covers the backup and recovery work a senior Oracle DBA owns end to end. Setting a retention policy that matches the business need, taking consistent backups with archived logs, validating that the backups are readable, and recovering to a point in time when the damage is already done. The companion monitoring repo, oracle-dba-toolkit, reports on recent backup jobs. This repo goes further: it asks whether those backups would work, and walks through using them.

## Who it is for

Oracle DBAs who already run backups and want the recovery side to be as routine as the backup side. The material assumes you know your way around RMAN and SQL*Plus and want repeatable checks and runbooks instead of improvising during an incident.

## Layout

```
oracle-rman-backup-recovery/
├── sql/    -- SQL*Plus read-only checks (recovery readiness)
├── rman/   -- RMAN command templates (backup, validation)
└── docs/   -- strategy, validation workflow, recovery runbooks
```

## Scripts and templates

| File | What it does |
|---|---|
| `sql/recovery_readiness.sql` | Read-only recovery readiness report: ARCHIVELOG mode, FRA pressure, latest full backup, datafile backup coverage, controlfile autobackup; exit 2 when a check fails |
| `rman/backup_database.rman` | Template for a full database backup plus archived logs; deletes nothing |
| `rman/validate_restore.rman` | Template for validating backups without restoring: crosscheck, restore validate with logical checking, archivelog validate, need-backup report |

Recovery readiness for the last 7 days of full backups (connect as a privileged user, e.g. `/ as sysdba`):

```
sqlplus / as sysdba @sql/recovery_readiness.sql
```

Thresholds live in the `DEFINE` lines at the top of the script. A clean report means the pieces exist; it does not prove they restore. That proof comes from the validation workflow.

Take a backup with the template (replace `<BACKUP_LOCATION>` first, and read the header before running it):

```
rman TARGET / @rman/backup_database.rman
```

Validate what the backup produced:

```
rman TARGET / @rman/validate_restore.rman
```

## Docs

| Doc | What it covers |
|---|---|
| `docs/backup-strategy.md` | Retention design, full vs incremental, FRA sizing, archiving, and the licensing notes for block change tracking, backup encryption, and Flashback Database |
| `docs/restore-validation-workflow.md` | The validation cadence, how to work a failed validation, and the monthly test restore to an isolated host |
| `docs/point-in-time-recovery-runbook.md` | Choosing the recovery scope, database PITR and TSPITR outlines, archived log gaps, and the steps after every recovery |

Start with `docs/backup-strategy.md` if the retention policy is not written down yet. Start with `docs/point-in-time-recovery-runbook.md` if something is already broken.

## Assumptions

- Oracle 11g or later. The readiness check reads `V$DATABASE`, `V$RECOVERY_FILE_DEST`, `V$BACKUP_SET`, `V$BACKUP_DATAFILE`, and `V$RMAN_CONFIGURATION`.
- The database runs in ARCHIVELOG mode. Without archived logs, point-in-time recovery past the last backup is not possible, and the readiness check says so plainly.
- Database names, hosts, and paths in examples are fictional lab values. Point the scripts at your own environment.
- RMAN itself is included with the database. Features called out in the docs carry their own licensing notes where they apply: block change tracking and Flashback Database need Enterprise Edition, and encrypted backups need the Advanced Security option with a wallet in place.

## Safety notes

- The SQL scripts are read-only. The RMAN templates are not: a backup writes backup pieces, and a restore or recover changes the target database. Read every RMAN file before running it, replace the placeholders, and never test a restore against a database you care about. Test restores go to an isolated host.
- Nothing here is a substitute for your backup policy. Retention, backup windows, and recovery objectives come from the business requirement, not from a template default.
- Never commit credentials, hostnames, or environment-specific connection details alongside these scripts. See `docs/script-conventions.md`.

## Testing

The SQL and RMAN in this repo are syntax and logic reviewed against the documented data dictionary and RMAN command reference. They have not been executed against a live Oracle instance in this environment, and the headers say so. Sample output in the docs is labeled illustrative lab output, not captured results.

## What this demonstrates

Backup and recovery ownership, not just backup scheduling: retention design, recovery readiness reporting, backup validation, and point-in-time recovery runbooks, the work that decides whether an outage ends in a restore or in an explanation.

## Background

Recreated from standard DBA practice for a personal lab portfolio, generic examples, not exports from any production environment. That keeps them safe to share and easy to adapt.
