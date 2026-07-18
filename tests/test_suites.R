if (requireNamespace("pkgload", quietly=TRUE)) {
  pkgload::load_all(".", quiet=TRUE)
} else {
  library(ullme)
  # Exercise the development implementation before package installation.
  source(file.path("R", "run_tests.R"))
  source(file.path("R", "test_suites.R"))
}

test_main_root = file.path(tempdir(), "ullme_main")
dir.create(test_main_root, recursive=TRUE, showWarnings=FALSE)
root = tempfile("ullme-test-suites-", tmpdir=test_main_root)
dir.create(root, recursive=TRUE)
on.exit(unlink(root, recursive=TRUE, force=TRUE), add=TRUE)
app = new.env(parent=emptyenv())
app$glob = list(main_dir=root)
app$userid = "alice"
app$role = "teacher"
app$allowed_roles = "teacher"
app$semester = "SS26"
app$courseid = "course"
app$user_dir = file.path(root, "users", "alice")
app$pending_changes = list()
dir.create(app$user_dir, recursive=TRUE)
dir.create(file.path(root, "teachers", "alice"), recursive=TRUE)
course_dir = file.path(root, "teachers", "alice", "courses", "SS26", "course")
test_dir = file.path(course_dir, "tests", "suite1")
dir.create(file.path(course_dir, "materials"), recursive=TRUE)
dir.create(file.path(test_dir, "instance_inputs", "week1", "input1"), recursive=TRUE)

writeLines(c(
  "tutorid: demo", "lang: en", "label: Demo", "description: Test Tutor",
  "shown_text: Welcome", "default_personality: Helpful",
  "docs_per_instance: {}", "docs_per_course: {}", "allowed_tools: []",
  "allowed_student_customization: []", "start_node: answer", "nodes:",
  "  answer:", "    prompt: Answer the student briefly.", "prompt_fragments:",
  "  init_prompt: Help the student."
), file.path(test_dir, "tutor.yml"))
writeLines(c(
  "course_docs: []", "instances:", "- instanceid: week1", "  label: Week 1",
  "  docs: {}"
), file.path(test_dir, "instances.yml"))
writeLines(c(
  "schema_version: 1", "suite:", "  id: suite1", "  label: Demo suite",
  "  source_tutor: demo", "materials_dir: ../../materials", "run_base: no",
  "models: [fake-model]", "api: fake", "batch_size: 1", "timeout_seconds: 30"
), file.path(test_dir, "tests.yml"))
writeLines(c("test_variant:", "  label: Baseline"),
           file.path(test_dir, "tutor_var_baseline.yml"))
writeLines("Please explain the first step.",
           file.path(test_dir, "instance_inputs", "week1", "input1", "input.md"))

stopifnot(
  identical(ullme_clean_test_suite_id("suite_1"), "suite_1"),
  inherits(try(ullme_clean_test_suite_id("../bad"), silent=TRUE), "try-error")
)

record = ullme_test_suite_record(test_dir)
stopifnot(
  identical(record$id, "suite1"),
  identical(record$label, "suite1"),
  length(record$instances) == 1L,
  length(record$variants) == 1L,
  identical(record$variants[[1]]$id, "base"),
  isTRUE(record$variants[[1]]$base),
  length(record$inputs) == 1L,
  identical(record$inputs[[1]]$text, "Please explain the first step.")
)

# The real base is protected, while node-mode editing stores only the selected
# node in an ordinary variant and can
# return it to the unchanged Tutor snapshot.
stopifnot(inherits(try(
  ullme_save_test_suite_variant("suite1", "base", "Base", "", app=app),
  silent=TRUE
), "try-error"))
writeLines(c("test_variant:", "  label: Concise"),
           file.path(test_dir, "tutor_var_concise.yml"))
ullme_save_test_suite_variant_node(
  "suite1", "concise", "answer", "prompt: A variant-specific answer.", app=app
)
record = ullme_test_suite_record(test_dir)
stopifnot(
  length(record$variants) == 2L,
  identical(record$variants[[2]]$modified_nodes, list("answer")),
  grepl("variant-specific", record$variants[[2]]$node_yaml$answer, fixed=TRUE)
)
ullme_save_test_suite_variant_node(
  "suite1", "concise", "answer", action="revert", app=app
)
record = ullme_test_suite_record(test_dir)
stopifnot(length(record$variants[[2]]$modified_nodes) == 0L)
ullme_delete_test_suite_variant("suite1", "concise", app=app)
stopifnot(!file.exists(file.path(test_dir, "tutor_var_concise.yml")))
stopifnot(inherits(try(
  ullme_delete_test_suite_variant("suite1", "base", app=app), silent=TRUE
), "try-error"))

ui = htmltools::renderTags(ullme_test_suites_ui())
ui_html = paste(ui$head, ui$html, collapse="\n")
node_ui = htmltools::renderTags(ullme_test_variant_node_editor_ui())
node_ui_html = paste(node_ui$head, node_ui$html, collapse="\n")
nav = htmltools::renderTags(ullme_studio_navigation_ui())
nav_html = paste(nav$head, nav$html, collapse="\n")
stopifnot(
  grepl('id="ullme_test_suites_panel"', ui_html, fixed=TRUE),
  grepl('id="ullme_tests_workspace"', ui_html, fixed=TRUE),
  grepl('id="ullme_test_input_upload"', ui_html, fixed=TRUE),
  grepl('id="ullme_test_variant_node_yaml"', node_ui_html, fixed=TRUE),
  grepl('id="ullme_test_variant_node_field"', node_ui_html, fixed=TRUE),
  !grepl("Quality assurance", ui_html, fixed=TRUE),
  grepl('data-studio-view="tests"', nav_html, fixed=TRUE),
  grepl("New Test Suite", nav_html, fixed=TRUE)
)

preflight = ullme_test_suite_preflight(test_dir)
stopifnot(
  identical(preflight$case_count, 1L),
  identical(preflight$variants, 1L),
  identical(preflight$inputs, 1L),
  identical(preflight$models, 1L)
)

status_path = file.path(test_dir, ".ullme-run-status.yml")
ullme_test_suite_write_status(status_path, "running", c("one", "two"))
status = ullme_test_suite_status(test_dir)
stopifnot(identical(status$state, "running"), length(status$messages) == 2L)

# Closing a TeacherApp session explicitly terminates its supervised Test Suite
# workers instead of leaving RStudio to wait on their process handles.
killed = FALSE
fake_process = list(
  is_alive=function() TRUE,
  kill=function() killed <<- TRUE
)
app$test_suite_processes = list(suite1=fake_process)
stopifnot(identical(ullme_stop_test_suite_processes(app=app), 1L))
stopifnot(
  isTRUE(killed),
  length(app$test_suite_processes) == 0L,
  identical(ullme_test_suite_status(test_dir)$state, "error")
)

# The GUI contract remains a thin layer around the canonical runner.
records = ullme_run_tests(test_dir)
stopifnot(length(records) == 1L, records[[1]]$status %in% c("completed", "waiting_for_user"))

if (requireNamespace("pkgload", quietly=TRUE) && requireNamespace("callr", quietly=TRUE)) {
  Sys.sleep(1.1)
  worker = get("ullme_test_suite_worker_bootstrap", envir=asNamespace("ullme"))
  background_status = file.path(test_dir, ".ullme-background-status.yml")
  process = callr::r_bg(
    worker,
    args=list(test_dir=test_dir, options=list(just_variants="baseline"),
              status_path=background_status,
              development_root=normalizePath(".", winslash="/")),
    package=FALSE, supervise=TRUE,
    stdout=file.path(test_dir, ".ullme-background.log"),
    stderr=file.path(test_dir, ".ullme-background-error.log")
  )
  process$wait(timeout=30000)
  stopifnot(process$get_exit_status() == 0L)
  if (!file.exists(background_status)) {
    output_log = file.path(test_dir, ".ullme-background.log")
    error_log = file.path(test_dir, ".ullme-background-error.log")
    stop(
      "Background worker did not create its status file. stdout: ",
      paste(if (file.exists(output_log)) readLines(output_log, warn=FALSE) else "", collapse="\n"),
      " stderr: ", paste(if (file.exists(error_log)) readLines(error_log, warn=FALSE) else "", collapse="\n")
    )
  }
  background_value = yaml::read_yaml(background_status, eval.expr=FALSE)
  stopifnot(identical(background_value$state, "completed"))
}

result_dir = file.path(test_dir, "results", "results_2026-07-18_120000")
dir.create(result_dir, recursive=TRUE)
yaml::write_yaml(list(
  schema_version=1L,
  test=list(variant_id="baseline", variant_label="Baseline", model="fake-model",
            api="fake", instance_id="week1", input_id="input1", status="completed"),
  execution=list(duration_seconds=0.5),
  input=list(text="Hello", media_count=0L, media=list()),
  response=list(final_output="Hi", error_message="", node_count=1L,
                nodes=list(list(node_id="answer", output="Hi", duration_seconds=0.5)))
), file.path(result_dir, "baseline__fake-model__week1__input1.yml"))

runs = ullme_test_suite_result_runs(test_dir)
stopifnot(length(runs) >= 2L, sum(vapply(runs, `[[`, integer(1), "completed")) >= 1L)

# Result payload path validation is covered without requiring a full app.
stopifnot(inherits(
  try(ullme_test_suite_result_payload("suite1", "../bad", app=new.env()), silent=TRUE),
  "try-error"
))

delete_dir = file.path(course_dir, "tests", "delete_me")
dir.create(delete_dir, recursive=TRUE)
writeLines("schema_version: 1", file.path(delete_dir, "tests.yml"))
ullme_delete_test_suite("delete_me", app=app)
stopifnot(!dir.exists(delete_dir))

cat("Test Suite backend checks passed.\n")
