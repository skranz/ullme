library(ullme)

test_main_dir = tempfile("ullme-studio-main-")
dir.create(test_main_dir, recursive=TRUE)
cleanup_app = new.env(parent=emptyenv())
cleanup_app$glob = list(main_dir=test_main_dir)
root = ullme_tempdir(pattern=".ullme-studio-check-", app=cleanup_app)
course_dir = file.path(root, "teachers", "alice", "courses", "WS2526", "micro")
dir.create(file.path(course_dir, "materials", "ps"), recursive=TRUE)
dir.create(file.path(course_dir, "materials", "background"), recursive=TRUE)
writeLines(
  c("courseid: micro", "coursename: Microeconomics", "times: []"),
  file.path(course_dir, "course.yaml")
)
writeLines("problem", file.path(course_dir, "materials", "ps", "ps1.pdf"))
writeLines("source", file.path(course_dir, "materials", "ps", "ps1.tex"))
writeLines("solution", file.path(course_dir, "materials", "ps", "ps1_sol.pdf"))
writeLines("# Lecture notes", file.path(course_dir, "materials", "background", "lecture_notes.md"))

app = new.env(parent=emptyenv())
app$glob = list(main_dir=root)
app$userid = "alice"
app$role = "teacher"
app$allowed_roles = "teacher"
app$semester = "WS2526"
app$courseid = "micro"
app$user_dir = file.path(root, "users", "alice")
app$pending_changes = list()
app$change_results = list()
app$organization_proposals = list()
dir.create(app$user_dir, recursive=TRUE)

records = ullme_course_file_records(course_dir)
stopifnot(
  any(vapply(records, function(x) x$path == "course.yaml", logical(1))),
  any(vapply(
    records,
    function(x) x$path == "materials/background/lecture_notes.md" && x$editable,
    logical(1)
  ))
)

proposal = ullme_propose_course_organization(app=app)
proposed_ids = vapply(proposal$indexes, function(x) x$oid, character(1))
stopifnot(all(c("ps", "ps_sol", "script") %in% proposed_ids))
ps = proposal$indexes[[match("ps", proposed_ids)]]
stopifnot(
  length(ps$value$objects) == 1L,
  length(ps$value$objects[[1]]$files) == 2L
)

settings = ullme_default_user_settings()
settings$agent_tools$approval$write_object_indexes = "allow"
dir.create(dirname(ullme_user_settings_path(app)), recursive=TRUE, showWarnings=FALSE)
writeLines(ullme_user_settings_yaml(settings), ullme_user_settings_path(app))
applied = ullme_handle_organization_apply(proposal$token, app=app)
stopifnot(
  applied$ok,
  file.exists(file.path(course_dir, "objects", "ps.yaml")),
  file.exists(file.path(course_dir, "objects", "ps_sol.yaml"))
)

organization = ullme_course_organization_payload(course_dir)
stopifnot(
  length(organization$indexes) >= 3L,
  !"ps/ps1.pdf" %in% unlist(organization$unassigned)
)
ullme_remove_tempdir(root, app=cleanup_app)
