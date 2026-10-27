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
