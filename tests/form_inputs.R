library(ullme)

main = tempfile("ullme-form-inputs-main-")
course_dir = file.path(
  main, "teachers", "alice", "courses", "SS26", "demo"
)
dir.create(course_dir, recursive=TRUE)

app = new.env(parent=emptyenv())
app$glob = list(main_dir=main)
app$userid = "alice"
app$role = "teacher"
app$semester = "SS26"
app$courseid = "demo"
app$user_dir = file.path(main, "users", "alice")

base_time = Sys.time() - 100
course_paths = vapply(seq_len(4), function(index) {
  path = ullme_store_form_input_at(
    paste("Course instruction", index),
    "instance_builder",
    "course",
    course_dir=course_dir,
    app=app
  )
  Sys.setFileTime(path, base_time + index)
  path
}, character(1))
user_paths = vapply(seq_len(4), function(index) {
  path = ullme_store_form_input_at(
    paste("Personal instruction", index),
    "instance_builder",
    "user",
    course_dir=course_dir,
    app=app
  )
  Sys.setFileTime(path, base_time + index)
  path
}, character(1))

duplicate = ullme_store_form_input_at(
  "Course instruction 4",
  "instance_builder",
  "course",
  course_dir=course_dir,
  app=app
)
stopifnot(
  identical(normalizePath(duplicate), normalizePath(course_paths[[4]])),
  length(list.files(dirname(duplicate), pattern="\\.txt$")) == 4L
)

choices = ullme_form_input_choices(
  "instance_builder",
  course_dir=course_dir,
  app=app
)
stopifnot(
  length(choices$course) == 3L,
  length(choices$user) == 3L,
  length(choices$recent) == 5L,
  identical(choices$default, "Course instruction 4"),
  identical(choices$course[[1]]$text, "Course instruction 4"),
  identical(choices$user[[1]]$text, "Personal instruction 4")
)

unlink(main, recursive=TRUE)
