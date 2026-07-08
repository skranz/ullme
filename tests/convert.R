library(ullme)

stopifnot(
  identical(
    ullme_preferred_document_file(
      c("ps/topic.pdf", "ps/topic.docx"),
      c("md", "tex", "pdf")
    ),
    "ps/topic.pdf"
  ),
  identical(
    ullme_preferred_document_file(
      c("ps/topic.pdf", "ps/topic.docx", "ps/topic.md"),
      c("md", "tex", "pdf")
    ),
    "ps/topic.md"
  ),
  identical(
    ullme_preferred_conversion_format(c("md", "tex", "pdf"), "docx"),
    "md"
  ),
  identical(
    ullme_conversion_media_name("ps/sub/umwelt ps1.md"),
    "figures--umwelt ps1_md"
  ),
  identical(
    ullme_conversion_media_name("ps/sub/topic.v2.final.md"),
    "figures--topic_v2_final_md"
  ),
  identical(
    ullme_material_conversion_paths_for_mode(
      c("ps/topic.docx", "ps/topic.tex", "ps/topic.pdf"),
      "docx-md"
    ),
    "ps/topic.docx"
  ),
  identical(
    ullme_material_conversion_paths_for_mode(
      c("ps/topic.docx", "ps/topic.tex", "ps/topic.pdf", "ps/notes.md"),
      "all-md"
    ),
    c("ps/topic.docx", "ps/topic.tex")
  ),
  identical(
    ullme_material_conversion_paths(
      "ps/Uebung_1/Uebungsskript_1.docx"
    ),
    "ps/Uebung_1/Uebungsskript_1.docx"
  ),
  identical(
    ullme_material_conversion_paths_for_mode(
      c("ps/topic.docx", "ps/topic.pdf"),
      "pdf-txt"
    ),
    "ps/topic.pdf"
  ),
  identical(
    ullme_material_conversion_paths_for_mode(
      c(
        "ps/topic.docx", "ps/topic.pdf", "ps/notes.md", "ps/notes.txt",
        "ps/source.tex", "ps/page.html", "ps/data.xlsx"
      ),
      "all-md-txt"
    ),
    c("ps/topic.docx", "ps/topic.pdf")
  ),
  identical(
    ullme_material_conversion_paths_for_mode(
      c(
        "ps/topic.docx", "ps/topic.pdf", "ps/notes.md", "ps/notes.txt",
        "ps/source.tex"
      ),
      "all-overwrite"
    ),
    c("ps/topic.docx", "ps/topic.pdf")
  ),
  identical(
    ullme_tutor_file_key("ps/week1/problem.docx", "ps", "ps"),
    "week1_problem"
  ),
  identical(
    ullme_tutor_file_key("ps/week2/problem_solution.docx", "solution", "ps"),
    "week2_problem"
  )
)

root = tempfile("ullme-convert-test-")
dir.create(root)
source = file.path(root, "umwelt ps1.docx")
writeBin(charToRaw("fake docx"), source)
output = file.path(root, "umwelt ps1.md")
media = file.path(root, "figures--umwelt ps1_md")

fake_converter = function(file, from, to, output, standalone, args) {
  media_arg = args[startsWith(args, "--extract-media=")]
  media_path = sub("^--extract-media=", "", media_arg)
  dir.create(file.path(media_path, "media"), recursive=TRUE)
  writeBin(as.raw(c(1, 2, 3)), file.path(media_path, "media", "image1.png"))
  writeLines(
    paste0("![figure](", gsub("\\\\", "/", media_path), "/media/image1.png)"),
    output,
    useBytes=TRUE
  )
}

result = ullme_convert_document(
  source=source,
  to="md",
  output=output,
  media_dir=media,
  converter=fake_converter
)
stopifnot(
  identical(result$from, "docx"),
  identical(result$to, "md"),
  file.exists(output),
  file.exists(file.path(media, "media", "image1.png")),
  grepl(
    "figures--umwelt ps1_md/media/image1.png",
    paste(readLines(output, warn=FALSE), collapse="\n"),
    fixed=TRUE
  )
)

main = tempfile("ullme-convert-main-")
dir.create(main)
cleanup_app = new.env(parent=emptyenv())
cleanup_app$glob = list(main_dir=main)
managed_root = ullme_tempdir(pattern=".ullme-convert-managed-", app=cleanup_app)
course_dir = file.path(
  managed_root, "teachers", "alice", "courses", "SS26", "demo"
)
dir.create(file.path(course_dir, "materials", "ps", "week1"), recursive=TRUE)
dir.create(file.path(course_dir, "ai_tutors", "pstutor"), recursive=TRUE)
writeBin(
  charToRaw("fake docx"),
  file.path(course_dir, "materials", "ps", "week1", "umwelt ps1.docx")
)
writeLines(c(
  "tutorid: pstutor",
  "lang: de",
  "label: PS Tutor",
  "description: Test",
  "system_prompt: Test",
  "default_personality: Friendly",
  "docs_per_instance:",
  "  ps:",
  "    file_types: [md, tex, pdf]",
  "    pref_doc_dir: ps",
  "docs_per_course: {}",
  "allowed_tools: []",
  "allowed_student_customization: []"
), file.path(course_dir, "ai_tutors", "pstutor", "tutor.yml"))
app = new.env(parent=emptyenv())
app$glob = list(main_dir=managed_root)
app$userid = "alice"
app$role = "teacher"
app$semester = "SS26"
app$courseid = "demo"
app$user_dir = file.path(managed_root, "users", "alice")
app$pending_changes = list()
dir.create(app$user_dir, recursive=TRUE)
converted = ullme_convert_material_files(
  paths="ps/week1/umwelt ps1.docx",
  to="preferred",
  tutorid="pstutor",
  origin="ui",
  app=app,
  converter=fake_converter
)
stopifnot(
  converted$ok,
  file.exists(file.path(
    course_dir, "materials", "ps", "week1", "umwelt ps1.md"
  )),
  file.exists(file.path(
    course_dir, "materials", "ps", "week1",
    "figures--umwelt ps1_md", "media", "image1.png"
  ))
)

skipped = ullme_convert_material_files(
  paths="ps/week1/umwelt ps1.docx",
  to="md",
  origin="ui",
  skip_existing=TRUE,
  app=app,
  converter=function(...) stop("Existing destination should have been skipped.")
)
stopifnot(
  skipped$ok,
  length(skipped$converted) == 0L,
  length(skipped$skipped) == 1L
)

overwrite_converter = function(file, from, to, output, standalone, args) {
  writeLines("overwritten Markdown", output, useBytes=TRUE)
}
overwritten = ullme_convert_material_files(
  paths="ps/week1/umwelt ps1.docx",
  to="md",
  origin="ui",
  overwrite=TRUE,
  app=app,
  converter=overwrite_converter
)
stopifnot(
  overwritten$ok,
  identical(
    readLines(file.path(
      course_dir, "materials", "ps", "week1", "umwelt ps1.md"
    ), warn=FALSE),
    "overwritten Markdown"
  )
)

writeBin(
  charToRaw("%PDF-fake"),
  file.path(course_dir, "materials", "ps", "week1", "appendix.pdf")
)
fake_pdf_converter = function(source, output) {
  writeLines("converted PDF text", output, useBytes=TRUE)
  list(source=source, output=output, from="pdf", to="txt", media_dir=NULL)
}
pdf_converted = ullme_convert_material_files(
  paths="ps/week1/appendix.pdf",
  to="txt",
  origin="ui",
  app=app,
  pdf_converter=fake_pdf_converter
)
stopifnot(
  pdf_converted$ok,
  identical(
    readLines(file.path(
      course_dir, "materials", "ps", "week1", "appendix.txt"
    ), warn=FALSE),
    "converted PDF text"
  )
)

writeBin(
  charToRaw("fake docx"),
  file.path(course_dir, "materials", "ps", "week1", "mixed.docx")
)
writeBin(
  charToRaw("%PDF-fake"),
  file.path(course_dir, "materials", "ps", "week1", "mixed-pdf.pdf")
)
mixed = ullme_convert_material_files(
  paths=c(
    "ps/week1/mixed.docx",
    "ps/week1/mixed-pdf.pdf"
  ),
  to="md-txt",
  origin="ui",
  app=app,
  converter=overwrite_converter,
  pdf_converter=fake_pdf_converter
)
stopifnot(
  mixed$ok,
  file.exists(file.path(
    course_dir, "materials", "ps", "week1", "mixed.md"
  )),
  file.exists(file.path(
    course_dir, "materials", "ps", "week1", "mixed-pdf.txt"
  ))
)

ullme_remove_checked_directory(
  root,
  root=dirname(root),
  expected_name=basename(root),
  label="conversion test directory"
)
ullme_remove_tempdir(managed_root, app=cleanup_app)
