# Script conventions

Every script in this repo follows the same shape so it is predictable to run and safe to schedule:

- Header comment: purpose, usage, and exit codes for SQL scripts. Nothing else in the header.
- Thresholds as `DEFINE` variables at the top of SQL scripts, with defaults noted in the comment.
- No hard-coded hostnames, SIDs, service names, credentials, or paths. Examples use placeholders like `$ORACLE_SID`, `<SERVICE_NAME>`, and `<BACKUP_LOCATION>`.
- SQL scripts are read-only. RMAN scripts are a different category: a backup script writes backup pieces, and a restore or recover command changes the target database. Every RMAN file says so in its header, and nothing here runs a restore or a recover against a database you care about. Test restores go to an isolated host.
- RMAN files are templates, not turnkey jobs. Read them, replace the placeholders, and check the commands against your backup policy before running them.
- Exit code 0 on success; non-zero on failure or threshold breach, documented per script.
- Output is plain text, readable in a terminal and greppable in logs.

New scripts should add a usage example to the README.
