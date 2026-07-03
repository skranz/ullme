library(ullme)

args = commandArgs(trailingOnly=TRUE)
if (!length(args)) {
  stop("Pass a test main_dir as the first argument.")
}
main_dir = normalizePath(args[[1]], winslash="/", mustWork=FALSE)
port = if (length(args) >= 2L) as.integer(args[[2]]) else 8766L
course_dir = file.path(
  main_dir, "teachers", "alice", "courses", "SS26", "demo"
)
material_dir = file.path(course_dir, "materials", "ps")
tutor_dir = file.path(course_dir, "ai_tutors", "ps_tutor_en")
dir.create(file.path(material_dir, "week1"), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(material_dir, "week2"), recursive=TRUE, showWarnings=FALSE)
dir.create(tutor_dir, recursive=TRUE, showWarnings=FALSE)

writeLines(
  "# Exercise 1\n\nExplain a binding price ceiling.",
  file.path(material_dir, "week1", "exercise-01.md")
)
writeLines(
  "# Solution 1\n\nQuantity demanded exceeds quantity supplied.",
  file.path(material_dir, "week1", "exercise-01-solution.md")
)
writeLines(
  "# Exercise 2\n\nDiscuss an externality.",
  file.path(material_dir, "week2", "exercise-02.md")
)
writeLines(
  "# Solution 2\n\nA Pigouvian tax can address it.",
  file.path(material_dir, "week2", "exercise-02-solution.md")
)
file.copy(
  system.file("ai_tutors", "ps_tutor_en.yml", package="ullme"),
  file.path(tutor_dir, "tutor.yml"),
  overwrite=TRUE
)

app = teacherApp(main_dir, userid="alice", api_provider="fake")
app$semester = "SS26"
app$courseid = "demo"
ullme_store_form_input_at(
  "One worksheet per week. Match files ending in -solution.",
  "instance_builder",
  "course",
  course_dir=course_dir,
  app=app
)
ullme_store_form_input_at(
  "One problem set per subfolder in ps; solutions contain Lösung.",
  "instance_builder",
  "course",
  course_dir=course_dir,
  app=app
)
ullme_store_form_input_at(
  "Create instances from matching exercise and answer documents.",
  "instance_builder",
  "user",
  course_dir=course_dir,
  app=app
)
viewApp(app, port=port, launch.browser=FALSE)
