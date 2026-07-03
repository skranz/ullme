library(ullme)

main = tempfile("ullme-instance-builder-main-")
dir.create(main)
course_dir = file.path(
  main, "teachers", "alice", "courses", "SS26", "demo"
)
dir.create(file.path(course_dir, "materials", "ps", "week1"), recursive=TRUE)
dir.create(file.path(course_dir, "ai_tutors", "pstutor"), recursive=TRUE)
writeLines("Problem set", file.path(
  course_dir, "materials", "ps", "week1", "sheet.md"
))
writeLines("Solution", file.path(
  course_dir, "materials", "ps", "week1", "sheet_solution.md"
))
writeLines(c(
  "tutorid: pstutor",
  "lang: en",
  "label: Problem Set Tutor",
  "description: Helps with exercises.",
  "instance_guidance: Match files ending in solution.",
  "system_prompt: Help with {{ps}} and {{ps_sol}}.",
  "default_personality: Friendly",
  "docs_per_instance:",
  "  ps:",
  "    descr: problem set",
  "    pref_format: [md, docx, pdf]",
  "    pref_doc_dir: ps",
  "    auto_convert: [docx]",
  "    add_images: true",
  "  ps_sol:",
  "    descr: solution",
  "    pref_format: [md, docx, pdf]",
  "    pref_doc_dir: ps",
  "    auto_convert: [docx]",
  "    add_images: true",
  "docs_per_course: {}",
  "allowed_tools: []",
  "allowed_student_customization: []"
), file.path(course_dir, "ai_tutors", "pstutor", "tutor.yml"))

prompt = ullme_instance_builder_prompt(
  course_dir, "pstutor",
  'Solutions end in "solution".'
)
definition = yaml::read_yaml(file.path(
  course_dir, "ai_tutors", "pstutor", "tutor.yml"
))
suggestions = ullme_suggest_course_ai_tutor_instances(course_dir, definition)
stopifnot(
  identical(suggestions[[1]]$docs$ps[[1]], "ps/week1/sheet.md"),
  identical(
    suggestions[[1]]$docs$ps_sol[[1]],
    "ps/week1/sheet_solution.md"
  ),
  grepl("ps/week1/sheet.md", prompt, fixed=TRUE),
  grepl("ps/week1/sheet_solution.md", prompt, fixed=TRUE),
  grepl("HEURISTIC CANDIDATE ASSIGNMENTS", prompt, fixed=TRUE),
  grepl("rewrite_tutor_instances_yaml", prompt, fixed=TRUE),
  grepl('Solutions end in "solution".', prompt, fixed=TRUE)
)

app = new.env(parent=emptyenv())
app$glob = list(main_dir=main)
app$userid = "alice"
app$role = "teacher"
app$semester = "SS26"
app$courseid = "demo"
app$store_ai_interactions = TRUE
log_dir = ullme_ai_interaction_start(
  prompt, "Make instances", "test-model", "instance_builder", app=app
)
ullme_ai_interaction_finish(
  log_dir, text="Done", thinking="Checked files", status="completed"
)
stopifnot(
  file.exists(file.path(log_dir, "request.txt")),
  file.exists(file.path(log_dir, "response.txt")),
  file.exists(file.path(log_dir, "thinking.txt")),
  identical(
    yaml::read_yaml(file.path(log_dir, "metadata.yaml"))$status,
    "completed"
  )
)

unlink(main, recursive=TRUE)
