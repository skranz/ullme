library(ullme)

test_root = file.path(tempdir(), "ullme_main")
dir.create(test_root, recursive=TRUE, showWarnings=FALSE)
main_dir = tempfile("knowledge-tutor-", tmpdir=test_root)
semester = ullme_semester()
course_dir = file.path(
  main_dir, "teachers", "teacher_a", "courses", semester, "course_a"
)
tutor_dir = file.path(course_dir, "ai_tutors", "knowledge_tutor_de")
dir.create(file.path(course_dir, "materials", "scripts"), recursive=TRUE)
dir.create(file.path(course_dir, "materials", "slides"), recursive=TRUE)
dir.create(tutor_dir, recursive=TRUE)
definition = yaml::read_yaml(file.path(
  "inst", "ai_tutors", "knowledge_tutor_de_old.yml"
))
init_prompt = definition$system_prompt
definition$system_prompt = NULL
definition$start_node = "answer"
definition$nodes = list(answer=list(prompt="{{input}}"))
definition$prompt_fragments = list(init_prompt=init_prompt)
yaml::write_yaml(definition, file.path(tutor_dir, "tutor.yml"))
writeLines(
  "Course script",
  file.path(course_dir, "materials", "scripts", "course.md")
)

app = studentApp(
  main_dir=main_dir,
  userid="student_a",
  teacherid="teacher_a",
  courseid="course_a",
  tutorid="knowledge_tutor_de",
  api_provider="fake",
  never_save_chats=FALSE
)
ullme_student_select_context(app=app)
ullme_student_chat_history_init(app=app)

tutor = ullme_student_selected_tutor(app=app)
stopifnot(
  identical(tutor$multiple_instances, FALSE),
  is.null(app$instanceid),
  grepl("[content missing]", ullme_student_system_prompt(app=app), fixed=TRUE)
)
custom_tools = ullme_custom_stream_tools(app=app)
custom_tool_names = vapply(
  custom_tools,
  function(tool) tool$`function`$name,
  character(1)
)
stopifnot(
  setequal(custom_tool_names, c("read_allowed_files", "list_allowed_files")),
  identical(
    custom_tools[[which(custom_tool_names == "read_allowed_files")]]$
      `function`$parameters$required,
    list("path")
  )
)

writeLines(
  "This is the course overview.",
  file.path(course_dir, "materials", "knowledge.md")
)
stopifnot(grepl(
  "This is the course overview.",
  ullme_student_system_prompt(app=app),
  fixed=TRUE
))

listed = utool_list_allowed_files(app=app)
stopifnot(
  listed$ok,
  any(vapply(listed$permissions, function(permission) {
    "materials/scripts/course.md" %in% unlist(permission$files)
  }, logical(1)))
)
read = utool_read_allowed_files("materials/scripts/course.md", app=app)
stopifnot(read$ok, identical(read$content, "Course script"), !read$can_write)
stopifnot(inherits(
  try(
    utool_read_allowed_files("materials/knowledge.md", app=app),
    silent=TRUE
  ),
  "try-error"
))

first_chat = app$student_chat_id
ullme_student_chat_history_append(
  "user", "What is covered?", "user_1", app=app
)
ullme_student_chat_history_append(
  "assistant", "The course overview explains it.", "assistant_1", app=app
)
ullme_student_chat_history_new(app=app)
stopifnot(
  !identical(app$student_chat_id, first_chat),
  length(ullme_student_chat_history_list(app=app)) == 2L
)
ullme_student_chat_history_select(first_chat, app=app)
stopifnot(
  length(app$student_history_messages) == 2L,
  grepl(
    "What is covered?",
    ullme_student_chat_history_transcript(app=app),
    fixed=TRUE
  )
)
stopifnot(ullme_student_chat_history_delete(first_chat, app=app))
stopifnot(
  !identical(app$student_chat_id, first_chat),
  is.null(ullme_student_chat_history_read(first_chat, app=app))
)
