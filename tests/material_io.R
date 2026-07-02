library(ullme)

test_main_dir = tempfile("ullme-material-io-main-")
dir.create(test_main_dir, recursive=TRUE)
cleanup_app = new.env(parent=emptyenv())
cleanup_app$glob = list(main_dir=test_main_dir)
root = ullme_tempdir(pattern=".ullme-material-io-", app=cleanup_app)
course_dir = file.path(
  root, "teachers", "alice", "courses", "SS26", "demo"
)
material_dir = file.path(course_dir, "materials")
outside_dir = file.path(root, "outside")
dir.create(file.path(material_dir, "general"), recursive=TRUE)
dir.create(file.path(material_dir, "slides"), recursive=TRUE)
dir.create(outside_dir, recursive=TRUE)

writeLines("source", file.path(material_dir, "general", "source.txt"))
writeLines("outside", file.path(outside_dir, "sentinel.txt"))

app = new.env(parent=emptyenv())
app$glob = list(main_dir=root)
app$userid = "alice"
app$role = "teacher"
app$semester = "SS26"
app$courseid = "demo"
if (!exists("ullme_active_course_dir", mode="function")) {
  ullme_active_course_dir = function(app) course_dir
}

create_material_directory("general/week_01", app=app)
stopifnot(dir.exists(file.path(material_dir, "general", "week_01")))

copy_material_file(
  "general/source.txt",
  "general/week_01/source.txt",
  app=app
)
stopifnot(
  file.exists(file.path(material_dir, "general", "source.txt")),
  file.exists(file.path(material_dir, "general", "week_01", "source.txt"))
)

move_material_file(
  "general/week_01/source.txt",
  "slides/source.txt",
  app=app
)
stopifnot(
  !file.exists(file.path(material_dir, "general", "week_01", "source.txt")),
  file.exists(file.path(material_dir, "slides", "source.txt"))
)

delete_material_file("slides/source.txt", app=app)
stopifnot(!file.exists(file.path(material_dir, "slides", "source.txt")))

expect_material_error = function(expression) {
  failed = inherits(try(force(expression), silent=TRUE), "try-error")
  stopifnot(failed)
}

expect_material_error(
  delete_material_file("../outside/sentinel.txt", app=app)
)
expect_material_error(
  copy_material_file(
    "general/source.txt",
    "../outside/copied.txt",
    app=app
  )
)
expect_material_error(
  move_material_file(
    "general/source.txt",
    normalizePath(file.path(outside_dir, "moved.txt"), winslash="/", mustWork=FALSE),
    app=app
  )
)
expect_material_error(delete_material_file("general/week_01", app=app))
expect_material_error(create_material_directory("general/NUL", app=app))
stopifnot(
  file.exists(file.path(outside_dir, "sentinel.txt")),
  file.exists(file.path(material_dir, "general", "source.txt"))
)

link_path = file.path(material_dir, "general", "outside-link.txt")
link_created = suppressWarnings(file.symlink(
  file.path(outside_dir, "sentinel.txt"),
  link_path
))
if (isTRUE(link_created)) {
  expect_material_error(delete_material_file("general/outside-link.txt", app=app))
  stopifnot(file.exists(file.path(outside_dir, "sentinel.txt")))
  file.remove(link_path)
}

tree = ullme_material_tree(material_dir)
tree_paths = vapply(tree, function(record) record$path, character(1))
stopifnot(
  "general" %in% tree_paths,
  "general/week_01" %in% tree_paths,
  "general/source.txt" %in% tree_paths
)

writeLines("move one", file.path(material_dir, "general", "one.txt"))
writeLines("move two", file.path(material_dir, "general", "two.txt"))
ullme_apply_material_file_operation(
  "move",
  c("general/one.txt", "general/two.txt"),
  "slides",
  app=app
)
stopifnot(
  file.exists(file.path(material_dir, "slides", "one.txt")),
  file.exists(file.path(material_dir, "slides", "two.txt"))
)
ullme_remove_tempdir(root, app=cleanup_app)
