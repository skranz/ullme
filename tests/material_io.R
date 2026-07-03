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

stopifnot(
  identical(
    ullme_transliterate_german(
      c("Übung", "übung", "Ärger", "größe", "Öl", "ẞ")
    ),
    c("Uebung", "uebung", "Aerger", "groesse", "Oel", "SS")
  ),
  identical(
    ullme_clean_file_name("Übung 1 – größere Lösung.pdf"),
    "Uebung_1_-_groessere_Loesung.pdf"
  ),
  identical(
    ullme_clean_relative_upload_path("Übungen/größer/Äpfel.txt"),
    "Uebungen/groesser/Aepfel.txt"
  )
)

folder_tree = ullme_prepare_material_upload_tree(
  tree=list(
    files=list(ullme_folder_1.pdf="Übungsblätter/Woche 1/Übung1.pdf"),
    directories=c("Übungsblätter", "Übungsblätter/Woche 1", "Leerer Ordner")
  ),
  destination="general",
  material_dir=material_dir
)
stopifnot(
  identical(
    unname(folder_tree$files[["ullme_folder_1.pdf"]]),
    "Uebungsblaetter/Woche_1/Uebung1.pdf"
  ),
  dir.exists(file.path(material_dir, "general", "Uebungsblaetter", "Woche_1")),
  dir.exists(file.path(material_dir, "general", "Leerer_Ordner"))
)

student_course_dir = file.path(
  root, "students", "alice", "courses", "SS26", "demo"
)
student_material_dir = file.path(student_course_dir, "materials")
dir.create(file.path(student_material_dir, "general"), recursive=TRUE)
student_app = new.env(parent=emptyenv())
student_app$glob = list(main_dir=root)
student_app$userid = "alice"
student_app$role = "student"
student_app$semester = "SS26"
student_app$courseid = "demo"
student_app$material_upload_tree = ullme_prepare_material_upload_tree(
  tree=list(
    files=list(ullme_folder_1.pdf="Übungsblätter/Woche 1/Übung1.pdf"),
    directories=c("Übungsblätter", "Übungsblätter/Woche 1")
  ),
  destination="general",
  material_dir=student_material_dir
)
folder_upload_source = tempfile()
writeLines("folder upload", folder_upload_source)
ullme_store_material_uploads(
  app=student_app,
  value=data.frame(
    name="ullme_folder_1.pdf",
    datapath=folder_upload_source,
    stringsAsFactors=FALSE
  ),
  category="general",
  destination="general"
)
plain_upload_source = tempfile()
writeLines("plain upload", plain_upload_source)
student_app$material_upload_tree = NULL
ullme_store_material_uploads(
  app=student_app,
  value=data.frame(
    name="Übung1.pdf",
    datapath=plain_upload_source,
    stringsAsFactors=FALSE
  ),
  category="general",
  destination="general"
)
stopifnot(
  file.exists(file.path(
    student_material_dir,
    "general", "Uebungsblaetter", "Woche_1", "Uebung1.pdf"
  )),
  file.exists(file.path(student_material_dir, "general", "Uebung1.pdf"))
)

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
