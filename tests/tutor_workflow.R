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
