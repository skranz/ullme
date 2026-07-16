ullme_text_file_extensions = function() {
  c(
    "txt", "md", "markdown", "yaml", "yml", "json", "jsonl", "csv", "tsv",
    "r", "rmd", "qmd", "py", "js", "css", "html", "htm", "xml", "tex",
    "bib", "toml", "ini", "cfg", "sql", "sh", "ps1", "gitignore"
  )
}


ullme_file_is_text = function(path, max_probe=8192L) {
  extension = tolower(tools::file_ext(path))
  if (extension %in% ullme_text_file_extensions()) return(TRUE)
  if (extension %in% c(
    "pdf", "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff",
    "zip", "7z", "rar", "gz", "bz2", "xz", "doc", "docx", "ppt", "pptx",
    "xls", "xlsx", "odt", "ods", "mp3", "wav", "ogg", "mp4", "webm"
  )) return(FALSE)
  size = file.info(path)$size
  if (is.na(size) || size == 0) return(TRUE)
  connection = file(path, open="rb")
  on.exit(close(connection), add=TRUE)
  bytes = readBin(connection, what="raw", n=min(as.integer(size), max_probe))
  !any(bytes == as.raw(0))
}


ullme_course_file_records = function(course_dir, max_files=2500L,
                                      max_edit_bytes=2 * 1024^2) {
  if (!dir.exists(course_dir)) return(list())
  relative = list.files(
    course_dir,
    recursive=TRUE,
    full.names=FALSE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=FALSE
  )
  relative = sort(gsub("\\\\", "/", relative))
  relative = relative[!grepl("(^|/)\\.ullme-", relative)]
  relative = head(relative, max_files)
  lapply(relative, function(path) {
    full_path = file.path(course_dir, path)
    size = unname(file.info(full_path)$size)
    text = ullme_file_is_text(full_path)
    list(
      path=path,
      name=basename(path),
      directory=gsub("\\\\", "/", dirname(path)),
      extension=tolower(tools::file_ext(path)),
      size=if (is.na(size)) NULL else size,
      text=text,
      editable=text && !is.na(size) && size <= max_edit_bytes
    )
  })
}


ullme_active_course_file_path = function(path, app=getApp(),
                                          must_exist=TRUE) {
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  path = gsub("\\\\", "/", paste0(path)[1])
  if (!ullme_safe_relative_material_path(path)) stop("Invalid course file path.")
  target = normalizePath(file.path(course_dir, path), winslash="/", mustWork=FALSE)
  root = normalizePath(course_dir, winslash="/", mustWork=TRUE)
  if (!ullme_path_is_within(target, root, allow_root=FALSE)) {
    stop("The requested file is outside the active course.")
  }
  if (isTRUE(must_exist) && (!file.exists(target) || dir.exists(target))) {
    stop("The requested course file does not exist.")
  }
  target
}


ullme_course_file_payload = function(path, app=getApp(), content=NULL,
                                      notice=NULL, error=NULL,
                                      draft=FALSE) {
  target = ullme_active_course_file_path(path, app=app, must_exist=!isTRUE(draft))
  exists = file.exists(target) && !dir.exists(target)
  size = if (exists) unname(file.info(target)$size) else 0
  text = !exists || ullme_file_is_text(target)
  editable = identical(app$role, "teacher") && text && size <= 2 * 1024^2
  if (is.null(content) && exists && text && size <= 2 * 1024^2) {
    content = paste(readLines(target, warn=FALSE, encoding="UTF-8"), collapse="\n")
  }
  list(
    path=gsub("\\\\", "/", paste0(path)[1]),
    name=basename(path),
    content=content %||% "",
    text=text,
    editable=editable,
    exists=exists,
    draft=isTRUE(draft),
    base_hash=if (exists) ullme_path_hash(target) else NA_character_,
    notice=notice,
    error=error
  )
}


ullme_send_course_file = function(path, app=getApp(), content=NULL,
                                   notice=NULL, error=NULL, draft=FALSE) {
  payload = ullme_course_file_payload(
    path=path,
    app=app,
    content=content,
    notice=notice,
    error=error,
    draft=draft
  )
  callJS(
    .fun="window.ullme.openCourseFile",
    .args=list(payload),
    .app=app
  )
  invisible(payload)
}


ullme_validate_course_file_content = function(path, content, app=getApp(),
                                               course_dir=ullme_active_course_dir(app=app)) {
  relative = gsub("\\\\", "/", paste0(path)[1])
  if (identical(tolower(relative), "course.yaml")) {
    return(ullme_validate_course_yaml(content))
  }
  tutor_match = regexec(
    "^ai_tutors/([A-Za-z][A-Za-z0-9_-]*)/tutor\\.ya?ml$",
    relative,
    ignore.case=TRUE
  )
  tutor_parts = regmatches(relative, tutor_match)[[1]]
  if (length(tutor_parts) > 1) {
    return(ullme_validate_tutor_yaml(tutor_parts[[2]], content))
  }
  if (grepl("\\.ya?ml$", relative, ignore.case=TRUE)) {
    return(ullme_parse_yaml_text(content, basename(relative)))
  }
  if (grepl("\\.json$", relative, ignore.case=TRUE) &&
      requireNamespace("jsonlite", quietly=TRUE)) {
    parsed = tryCatch(jsonlite::fromJSON(content, simplifyVector=FALSE),
                      error=function(e) e)
    if (inherits(parsed, "error")) {
      return(ullme_validation_result(
        FALSE,
        paste0("JSON syntax error: ", conditionMessage(parsed))
      ))
    }
  }
  ullme_validation_result(value=content)
}


ullme_handle_course_file_open = function(path=NULL, app=getApp(), ...) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  tryCatch(
    ullme_send_course_file(path=path, app=app),
    error=function(e) callJS(
      .fun="window.ullme.courseFileError",
      .args=list(conditionMessage(e)),
      .app=app
    )
  )
  invisible(TRUE)
}


ullme_handle_course_file_save = function(path=NULL, content="", base_hash=NULL,
                                          app=getApp(), ...) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  path = gsub("\\\\", "/", paste0(path)[1])
  content = paste0(content, collapse="\n")
  target = NULL
  result = tryCatch({
    if (nchar(content, type="bytes") > 2 * 1024^2) {
      stop("Text files must be no larger than 2 MB.")
    }
    target = ullme_active_course_file_path(path, app=app, must_exist=FALSE)
    exists = file.exists(target) && !dir.exists(target)
    if (exists && !ullme_file_is_text(target)) {
      stop("Binary course files cannot be edited as text.")
    }
    if (!exists) {
      extension = tolower(tools::file_ext(target))
      if (!extension %in% ullme_text_file_extensions()) {
        stop("New files must use a supported text-file extension.")
      }
    }
    current_hash = if (exists) ullme_path_hash(target) else NA_character_
    expected = base_hash
    if (is.null(expected) || length(expected) == 0) {
      expected = NA_character_
    } else {
      expected = as.character(expected)[1]
    }
    unchanged = (is.na(current_hash) && is.na(expected)) ||
      identical(current_hash, expected)
    if (!isTRUE(unchanged)) {
      stop("This file changed after it was opened. Reopen it before saving.")
    }
    validation = ullme_validate_course_file_content(path, content, app=app)
    ullme_validation_stop(validation)
    change = ullme_change_write(target, content)
    change$warnings = validation$warnings
    operation = ullme_new_change(
      action="course_file_edit",
      summary=paste0("Save course file ", path),
      origin="ui",
      details=list(courseid=app$courseid, path=path),
      changes=list(change),
      app=app
    )
    committed = ullme_submit_change(operation, app=app)
    if (!isTRUE(committed$ok)) stop(committed$message %||% "Could not save the file.")
    ullme_send_course_state(app=app)
    ullme_send_course_file(path=path, app=app, notice=paste0(basename(path), " saved."))
    committed
  }, error=function(e) {
    callJS(
      .fun="window.ullme.courseFileSaveComplete",
      .args=list(list(ok=FALSE, message=conditionMessage(e))),
      .app=app
    )
    NULL
  })
  invisible(result)
}
