library(ullme)

definition_path = file.path("inst", "ai_tutors", "ps_tutor_en.yml")
stopifnot(!any(grepl(
  "_old\\.ya?ml$",
  basename(ullme_ai_tutor_template_paths()),
  ignore.case=TRUE
)))
yaml_content = paste(
  readLines(definition_path, warn=FALSE, encoding="UTF-8"),
  collapse="\n"
)
validation = ullme_validate_tutor_yaml(
  "ps_tutor_en", yaml_content
)
stopifnot(validation$ok)
stopifnot(identical(
  ullme_render_prompt_once("{{input}}", list(input="{{literal}}")),
  "{{literal}}"
))
stopifnot(identical(
  ullme_render_prompt_once("{{output.later}}", list(), strict=FALSE),
  "{{output.later}}"
))

invalid = sub(
  "start_node: switch_image",
  "start_node: missing_node",
  yaml_content,
  fixed=TRUE
)
invalid_validation = ullme_validate_tutor_yaml(
  "ps_tutor_en", invalid
)
stopifnot(
  !invalid_validation$ok,
  any(grepl(
    "start_node does not name",
    unlist(invalid_validation$errors),
    fixed=TRUE
  ))
)

invalid_parallel = sub(
  "n_parallel: 3",
  "n_parallel: invalid",
  yaml_content,
  fixed=TRUE
)
invalid_parallel_validation = ullme_validate_tutor_yaml(
  "ps_tutor_en", invalid_parallel
)
stopifnot(!invalid_parallel_validation$ok)

definition = yaml::yaml.load(yaml_content, eval.expr=FALSE)
tutor = ullme_normalize_ai_tutor_definition(
  definition, "ps_tutor_en", "course"
)
stopifnot(
  identical(tutor$start_node, "switch_image"),
  isTRUE(tutor$show_final_output),
  length(tutor$nodes) == 8L,
  identical(tutor$nodes$switch_image$switch_to$`TRUE`, "describe_image"),
  identical(tutor$nodes$describe_image[["next"]], "switch_found_exercise"),
  identical(tutor$nodes$switch_found_exercise$n_parallel, 3L),
  identical(tutor$nodes$switch_found_exercise$add_to_history, FALSE)
)
stopifnot(identical(
  ullme_tutor_workflow_vote(
    list(" OK ", "ok", "other"),
    tutor$nodes$switch_found_exercise
  ),
  "ok"
))

main_dir = tempfile("ullme-workflow-")
semester = ullme_semester()
course_dir = file.path(
  main_dir, "teachers", "teacher_a", "courses", semester, "course_a"
)
tutor_dir = file.path(course_dir, "ai_tutors", "ps_tutor_en")
dir.create(tutor_dir, recursive=TRUE)
file.copy(definition_path, file.path(tutor_dir, "tutor.yml"))
writeLines(
  c("course_docs: {}", "instances:", "  - instanceid: ps1", "    docs: {}"),
  file.path(tutor_dir, "instances.yml")
)
app = studentApp(
  main_dir=main_dir,
  userid="student_a",
  teacherid="teacher_a",
  courseid="course_a",
  tutorid="ps_tutor_en",
  instanceid="ps1",
  api_provider="fake",
  chat_debug=TRUE
)
ullme_student_select_context(app=app)
selected = ullme_student_selected_tutor(app=app)

# Durable pre/post-call messages are emitted in order, and node-specific output
# placeholders resolve without requiring compile-time path analysis.
shown_tutor = selected
shown_tutor$start_node = "general"
shown_tutor$nodes$general$show_before = "Starting: {{input}}"
shown_tutor$nodes$general$waiting_message = "Working on {{input}}"
shown_tutor$nodes$general$show_after = "First result:\n{{output}}"
shown_tutor$nodes$safety_review$prompt = paste(
  "Earlier: {{output.general}}",
  "Missing: {{output.not_run}}",
  sep="\n"
)
shown = ullme_tutor_workflow_new(
  tutor=shown_tutor, input="a durable test", model="fake", app=app
)
shown_events = character(0)
workflow_warnings = character(0)
shown_result = withCallingHandlers(
  ullme_await_promise(
    ullme_tutor_workflow_advance(
      shown,
      on_show=function(text, node, when) {
        shown_events <<- c(shown_events, paste(when, node, text, sep="|"))
      },
      on_waiting=function(text, node) {
        shown_events <<- c(shown_events, paste("waiting", node, text, sep="|"))
      }
    ),
    seconds=5
  ),
  warning=function(warning) {
    workflow_warnings <<- c(workflow_warnings, conditionMessage(warning))
    invokeRestart("muffleWarning")
  }
)
stopifnot(
  startsWith(shown_events[[1]], "before|general|Starting:"),
  startsWith(shown_events[[2]], "waiting|general|Working"),
  startsWith(shown_events[[3]], "after|general|First result:"),
  grepl("Fake AI answer", shown_events[[3]], fixed=TRUE),
  grepl("output.not_run not available", shown_result$text, fixed=TRUE),
  identical(shown_result$state$node_outputs$general,
            shown_result$state$internal_history[[1]]$output),
  any(grepl("output.not_run not available", workflow_warnings, fixed=TRUE)),
  identical(
    ullme_tutor_workflow_append_text("First", "Second"),
    "First\n\nSecond"
  )
)

no_image = ullme_tutor_workflow_new(
  tutor=selected,
  input="Can I get a hint?",
  uploads=list(),
  conversation=list(),
  model="fake",
  app=app
)
result = ullme_await_promise(
  ullme_tutor_workflow_advance(no_image),
  seconds=5
)
debug_calls = list.files(
  file.path(main_dir, "debug_session"),
  pattern="^[0-9]{3}-.*[.]txt$",
  full.names=TRUE
)
debug_calls = debug_calls[basename(debug_calls) != "000-session.txt"]
stopifnot(
  length(debug_calls) >= 1L,
  any(vapply(debug_calls, function(path) {
    content = paste(readLines(path, warn=FALSE), collapse="\n")
    grepl("instanceid: ps1", content, fixed=TRUE) &&
      grepl("===== SYSTEM PROMPT =====", content, fixed=TRUE) &&
      grepl("===== PROMPT =====", content, fixed=TRUE) &&
      grepl("===== ANSWER =====", content, fixed=TRUE)
  }, logical(1)))
)
stopifnot(
  identical(result$status, "completed"),
  identical(result$node, "safety_review"),
  grepl("Fake AI answer", result$text, fixed=TRUE),
  any(vapply(
    result$state$internal_history,
    function(item) identical(item$node, "general"),
    logical(1)
  )),
  !any(vapply(
    result$state$internal_history,
    function(item) identical(item$node, "safety_review"),
    logical(1)
  ))
)

waiting = ullme_tutor_workflow_new(
  tutor=selected,
  input="[uploaded image]",
  uploads=list(list(id="image_1")),
  conversation=list(),
  model="fake",
  app=app
)
waiting$node = "ask_for_exercise_number"
paused = ullme_tutor_workflow_advance(waiting)
stopifnot(
  identical(paused$status, "waiting"),
  identical(paused$node, "ask_for_exercise_number"),
  grepl("exercise", paused$text, ignore.case=TRUE)
)
ullme_tutor_workflow_resume(
  paused$state,
  input="It is exercise 3(b).",
  conversation=list(list(role="assistant", text=paused$text))
)
resumed = ullme_await_promise(
  ullme_tutor_workflow_advance(paused$state),
  seconds=5
)
stopifnot(
  identical(resumed$status, "completed"),
  grepl(
    "It is exercise 3(b).",
    ullme_tutor_workflow_history_text(resumed$state),
    fixed=TRUE
  )
)

sent = list()
app$session = new.env(parent=emptyenv())
app$session$sendCustomMessage = function(type, message) {
  sent[[length(sent) + 1L]] <<- list(type=type, message=message)
}
display_tutor = shown_tutor
display_tutor$nodes$safety_review$prompt = "Final: {{output.general}}"
app$student_tutors[[1]] = display_tutor
durable_task = ullme_handle_student_tutor_submit(
  text="Show progress.",
  model="fake",
  clientMessageId="durable_student",
  assistantMessageId="durable_assistant",
  app=app
)
ullme_await_promise(durable_task, seconds=5)
durable_reply = app$student_live_messages[[2]]$text
stopifnot(
  grepl("Starting: Show progress.", durable_reply, fixed=TRUE),
  grepl("First result:", durable_reply, fixed=TRUE),
  grepl("Final:", durable_reply, fixed=TRUE)
)
app$student_live_messages = list()
app$student_pending_workflow = NULL
suppressed_tutor = display_tutor
suppressed_tutor$show_final_output = FALSE
app$student_tutors[[1]] = suppressed_tutor
suppressed_task = ullme_handle_student_tutor_submit(
  text="Hide the terminal output.",
  model="fake",
  clientMessageId="suppressed_student",
  assistantMessageId="suppressed_assistant",
  app=app
)
ullme_await_promise(suppressed_task, seconds=5)
suppressed_reply = app$student_live_messages[[2]]$text
stopifnot(
  grepl("Starting: Hide the terminal output.", suppressed_reply, fixed=TRUE),
  grepl("First result:", suppressed_reply, fixed=TRUE),
  !grepl("Final:", suppressed_reply, fixed=TRUE)
)
app$student_live_messages = list()
app$student_pending_workflow = NULL
sent = list()
app$student_tutors[[1]] = selected
app$student_tutors[[1]]$start_node = "ask_for_exercise_number"
ullme_handle_student_tutor_submit(
  text="Please inspect this.",
  model="fake",
  uploads=list(list(id="image_2")),
  clientMessageId="student_1",
  assistantMessageId="assistant_1",
  app=app
)
stopifnot(
  is.environment(app$student_pending_workflow),
  length(app$student_live_messages) == 2L,
  identical(app$student_live_messages[[2]]$role, "assistant")
)
resume_task = ullme_handle_student_tutor_submit(
  text="It is exercise 4(a).",
  model="fake",
  uploads=list(),
  clientMessageId="student_2",
  assistantMessageId="assistant_2",
  app=app
)
resumed_submission = ullme_await_promise(resume_task, seconds=5)
stopifnot(
  is.null(app$student_pending_workflow),
  length(app$student_live_messages) == 4L,
  !isTRUE(app$chat_response_active),
  length(sent) > 0L
)

unlink(main_dir, recursive=TRUE)

cat("Tutor workflow checks passed\n")
