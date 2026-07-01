# Validation, approval, backups, and undo

Read operations are restricted to the current teacher's authorized data.
Agent-originated changes follow the teacher's policy: allow, ask, or deny.

YAML and JSON are checked before writing. Object indexes and definition files
receive additional semantic checks. Managed changes are logged and their prior
contents are backed up in the current user's change-history directory.

The History view can undo a committed change if its target files have not been
modified again. Teacher-information documents are read-only to the assistant;
there is no agent tool for changing them.
