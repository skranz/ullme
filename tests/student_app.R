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
  "shown_text: 'Welcome to Tutor A.'",
  "default_personality: Be helpful.",
  "docs_per_instance: {}",
  "docs_per_course: {}",
  "allowed_tools: []",
  "allowed_student_customization: []",
  "start_node: answer",
  "nodes:",
  "  answer:",
  "    prompt: '{{input}}'",
  "prompt_fragments:",
  "  init_prompt: 'Help the student. {{personality}}'"
), file.path(tutor_dir, "tutor.yml"))
writeLines(c(
  "course_docs: {}",
  "instances:",
  "  - instanceid: instance_a",
  "    label: Practice instance A",
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
  isTRUE(app$adapt_mathjax),
  identical(app$global$teacherid, "teacher_a"),
  identical(app$global$courseid, "course_a"),
  identical(app$global$tutorid, "tutor_a"),
  identical(app$global$instanceid, "instance_a"),
  identical(app$teacherid, "teacher_a"),
  identical(app$courseid, "course_a")
)
tutors = ullme_student_tutors(app=app)
stopifnot(identical(
  tutors[[1]]$instances[[1]]$label,
  "Practice instance A"
))

configured_app = studentApp(
  main_dir=main_dir,
  userid="student_config",
  teacherid="teacher_a",
  courseid="course_a",
  api_provider="fake",
  stream_backend="custom",
  catch_chat_errors=FALSE,
  chat_debug=TRUE,
  sync_chat=TRUE,
  enable_ai_tools=FALSE,
  show_chat_thinking=TRUE
)
stopifnot(
  identical(configured_app$stream_backend, "custom"),
  identical(configured_app$catch_chat_errors, FALSE),
  identical(configured_app$chat_debug, TRUE),
  identical(configured_app$sync_chat, TRUE),
  identical(configured_app$enable_ai_tools, FALSE),
  identical(configured_app$show_chat_thinking, TRUE)
)
configured_app$student_tutors = list(
  ullme_student_tutor_definition("tutor_a", app=configured_app)
)
configured_app$tutorid = "tutor_a"
configured_app$instanceid = "instance_a"
stopifnot(grepl(
  "Help the student.",
  ullme_custom_stream_system_prompt(app=configured_app),
  fixed=TRUE
))
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
  grepl("ullme_student_theme_select", ui, fixed=TRUE),
  grepl(
    "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js",
    ui,
    fixed=TRUE
  ),
  grepl("ullme-student-workspace", ui, fixed=TRUE),
  grepl("id=\"ullme_camera_btn\"", ui, fixed=TRUE),
  grepl("id=\"ullme_camera_upload\"", ui, fixed=TRUE),
  grepl("capture=\"environment\"", ui, fixed=TRUE),
  !grepl("ullme_student_sidebar_toggle", ui, fixed=TRUE),
  !grepl("ullme-chat.css", ui, fixed=TRUE),
  grepl("ullme-chat.js", ui, fixed=TRUE),
  !grepl("ullme-teacher.js", ui, fixed=TRUE),
  !grepl("ullme-usage.js", ui, fixed=TRUE),
  !grepl("ullme-tutors.js", ui, fixed=TRUE)
)

student_css = paste(
  readLines("inst/www/ullme-student.css", warn=FALSE, encoding="UTF-8"),
  collapse="\n"
)
student_js = paste(
  readLines("inst/www/ullme-student.js", warn=FALSE, encoding="UTF-8"),
  collapse="\n"
)
stopifnot(
  grepl("--ullme-viewport-height", student_css, fixed=TRUE),
  grepl("env(safe-area-inset-bottom)", student_css, fixed=TRUE),
  grepl(":root[data-ullme-theme=\"dark\"]", student_css, fixed=TRUE),
  grepl("window.visualViewport", student_js, fixed=TRUE),
  grepl("prefersNativeCameraCapture()", student_js, fixed=TRUE),
  grepl("cameraInput.click()", student_js, fixed=TRUE),
  grepl("openCamera(cameraDialog, cameraVideo)", student_js, fixed=TRUE),
  grepl("navigator.mediaDevices.getUserMedia", student_js, fixed=TRUE),
  grepl("captureCameraPhoto", student_js, fixed=TRUE),
  grepl("ullme-color-theme", student_js, fixed=TRUE)
)

for (path in file.path("inst", "ai_tutors", "ps_tutor_en.yml")) {
  prompt = yaml::read_yaml(path, eval.expr=FALSE)$prompt_fragments$init_prompt
  stopifnot(
    grepl("Use `\\( ... \\)`", prompt, fixed=TRUE),
    grepl("\\[ ... \\]", prompt, fixed=TRUE)
  )
}

teacher_tutor_js = paste(
  readLines("inst/www/ullme-tutors.js", warn=FALSE, encoding="UTF-8"),
  collapse="\n"
)
stopifnot(
  grepl("ullme_tutor_shown_text", teacher_tutor_js, fixed=TRUE),
  grepl("shown_text: valueOf", teacher_tutor_js, fixed=TRUE),
  !grepl('{ id: "prompt", label: "Prompt" }', teacher_tutor_js, fixed=TRUE),
  !grepl('{ id: "config", label: "Config" }', teacher_tutor_js, fixed=TRUE)
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
  url_search=paste0("?sem=", semester, "&tutor=tutor_a&inst=instance_a")
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
  identical(url_app$semester, semester),
  identical(url_app$tutorid, "tutor_a"),
  identical(url_app$instanceid, "instance_a"),
  is.null(url_app$global$semester),
  is.null(url_app$global$tutorid),
  is.null(url_app$global$instanceid),
  isTRUE(url_app$allow_semester_switch),
  isTRUE(url_app$allow_tutor_switch),
  isTRUE(url_app$allow_instance_switch),
  identical(
    ullme_default_course_semester(
      main_dir=main_dir,
      teacherid="teacher_a",
      courseid="course_a",
      date=Sys.Date()
    ),
    semester
  )
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
  identical(student_context$semesters, as.list(semester)),
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
  length(sent_messages) >= 1L,
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

unlink(main_dir, recursive=TRUE)
