library(ullme)

main_dir = tempfile("ullme-student-app-")
semester = ullme_semester()
course_dir = file.path(
  main_dir, "teachers", "teacher_a", "courses", semester, "course_a"
)
tutor_dir = file.path(course_dir, "ai_tutors", "tutor_a")
dir.create(tutor_dir, recursive=TRUE)
writeLines(c(
  "tutorid: tutor_a",
  "enabled: true",
  "label: Tutor A",
  "description: Test tutor",
  "system_prompt: 'Help the student. {{personality}}'",
  "shown_text: 'Welcome to Tutor A.'",
  "default_personality: Be helpful.",
  "docs_per_instance: {}",
  "docs_per_course: {}",
  "allowed_tools: []",
  "allowed_student_customization: []"
), file.path(tutor_dir, "tutor.yml"))
writeLines(c(
  "course_docs: {}",
  "instances:",
  "  - instanceid: instance_a",
  "    docs: {}"
), file.path(tutor_dir, "instances.yml"))

app = studentApp(
  main_dir=main_dir,
  userid="student_a",
  teacherid="teacher_a",
  courseid="course_a",
  tutorid="tutor_a",
  instanceid="instance_a",
  api_provider="fake"
)

stopifnot(
  identical(app$global, app$glob),
  identical(app$login_check, "none"),
  isTRUE(app$is.authenticated),
  isTRUE(app$never_save_chats),
  is.null(ullme_ai_interactions_dir(app=app)),
  identical(app$global$userid, "student_a"),
  identical(app$global$teacherid, "teacher_a"),
  identical(app$global$courseid, "course_a"),
  identical(app$global$tutorid, "tutor_a"),
  identical(app$global$instanceid, "instance_a"),
  identical(app$teacherid, "teacher_a"),
  identical(app$courseid, "course_a")
)
stopifnot(
  "ullme_submit_chat_event" %in% names(app$eventList),
  "ullme_cancel_chat_event" %in% names(app$eventList),
  "ullme_student_context_event" %in% names(app$eventList),
  !"ullme_material_delete_event" %in% names(app$eventList),
  !"ullme_ai_tutor_save_event" %in% names(app$eventList)
)

rendered_ui = htmltools::renderTags(app$ui)
ui = paste(rendered_ui$head, rendered_ui$html, collapse="")
stopifnot(
  grepl("ullme-student.css", ui, fixed=TRUE),
  grepl("ullme-student.js", ui, fixed=TRUE),
  grepl(
    "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js",
    ui,
    fixed=TRUE
  ),
  grepl("ullme_student_pane_resizer", ui, fixed=TRUE),
  !grepl("ullme_student_sidebar_toggle", ui, fixed=TRUE),
  !grepl("ullme-chat.css", ui, fixed=TRUE),
  grepl("ullme-chat.js", ui, fixed=TRUE),
  !grepl("ullme-teacher.js", ui, fixed=TRUE),
  !grepl("ullme-usage.js", ui, fixed=TRUE),
  !grepl("ullme-tutors.js", ui, fixed=TRUE)
)

for (path in file.path(
  "inst", "ai_tutors", c("ps_tutor_en.yml", "ps_tutor_de.yml")
)) {
  prompt = yaml::read_yaml(path, eval.expr=FALSE)$system_prompt
  stopifnot(
    grepl("MathJax", prompt, fixed=TRUE),
    grepl("$$ ... $$", prompt, fixed=TRUE)
  )
}

teacher_tutor_js = paste(
  readLines("inst/www/ullme-tutors.js", warn=FALSE, encoding="UTF-8"),
  collapse="\n"
)
stopifnot(
  grepl("ullme_tutor_shown_text", teacher_tutor_js, fixed=TRUE),
  grepl("shown_text: valueOf", teacher_tutor_js, fixed=TRUE)
)

fixed_session = new.env(parent=emptyenv())
fixed_session$clientData = list(
  url_search=paste0(
    "?teacherid=other_teacher&courseid=other_course",
    "&tutorid=other_tutor&instanceid=other_instance"
  )
)
ullme_student_resolve_parameters(session=fixed_session, app=app)
stopifnot(
  identical(app$teacherid, "teacher_a"),
  identical(app$courseid, "course_a"),
  identical(app$tutorid, "tutor_a"),
  identical(app$instanceid, "instance_a")
)

url_session = new.env(parent=emptyenv())
url_session$clientData = list(
  url_search="?tutorid=tutor_a&instanceid=instance_a"
)
url_app = studentApp(
  main_dir=main_dir,
  userid="student_b",
  teacherid="teacher_a",
  courseid="course_a",
  api_provider="fake"
)
ullme_student_resolve_parameters(session=url_session, app=url_app)

stopifnot(
  identical(url_app$teacherid, "teacher_a"),
  identical(url_app$courseid, "course_a"),
  identical(url_app$tutorid, "tutor_a"),
  identical(url_app$instanceid, "instance_a"),
  is.null(url_app$global$tutorid),
  is.null(url_app$global$instanceid),
  !isTRUE(url_app$allow_tutor_switch),
  !isTRUE(url_app$allow_instance_switch)
)

switch_app = studentApp(
  main_dir=main_dir,
  userid="student_c",
  teacherid="teacher_a",
  courseid="course_a",
  api_provider="fake"
)
empty_session = new.env(parent=emptyenv())
empty_session$clientData = list(url_search="")
ullme_student_resolve_parameters(session=empty_session, app=switch_app)
ullme_student_select_context(app=switch_app)
student_context = ullme_student_context_for_js(app=switch_app)

stopifnot(
  isTRUE(switch_app$allow_tutor_switch),
  isTRUE(switch_app$allow_instance_switch),
  identical(switch_app$tutorid, "tutor_a"),
  identical(switch_app$instanceid, "instance_a"),
  identical(student_context$tutors[[1]]$shown_text, "Welcome to Tutor A."),
  grepl("Welcome to Tutor A.", student_context$tutors[[1]]$shown_html, fixed=TRUE)
)

error_app = studentApp(
  main_dir=main_dir,
  userid="student_error",
  teacherid="teacher_a",
  courseid="course_a",
  api_provider="fake"
)
ullme_student_resolve_parameters(session=empty_session, app=error_app)
ullme_student_select_context(app=error_app)
error_app$tutorid = "missing_tutor"
error_app$api_config$provider = "local"
error_app$api_config$model = "local-model"
error_app$api_config$base_url = "http://127.0.0.1:1/v1"
error_app$api_models = "local-model"
sent_messages = list()
error_app$session = new.env(parent=emptyenv())
error_app$session$sendCustomMessage = function(type, message) {
  sent_messages[[length(sent_messages) + 1L]] <<- list(
    type=type,
    message=message
  )
}
ullme_handle_chat_submit_safe(
  id="ullme_submit_chat",
  text="hello",
  model="local-model",
  assistantMessageId="assistant_error_test",
  app=error_app
)
stopifnot(
  length(sent_messages) >= 2L,
  any(vapply(sent_messages, function(record) {
    args = record$message$args
    length(args) >= 7L &&
      isTRUE(args[[6]]) &&
      grepl("could not start", args[[7]], fixed=TRUE)
  }, logical(1)))
)

missing_app = studentApp(
  main_dir=main_dir,
  userid="student_d",
  api_provider="fake"
)
missing_result = try(
  ullme_student_resolve_parameters(session=empty_session, app=missing_app),
  silent=TRUE
)
stopifnot(inherits(missing_result, "try-error"))

ullme_remove_checked_directory(
  main_dir,
  root=dirname(main_dir),
  expected_name=basename(main_dir),
  label="student app test directory"
)
