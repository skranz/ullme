ullme_form_input_id = function(inputid) {
  inputid = tolower(trimws(paste0(inputid)[1]))
  if (!grepl("^[a-z][a-z0-9_-]*$", inputid)) {
    stop("Invalid form input ID.")
  }
  inputid
}


ullme_form_input_scope_dir = function(inputid, scope=c("course", "user"),
                                       course_dir=NULL, app=getApp()) {
  inputid = ullme_form_input_id(inputid)
  scope = match.arg(scope)
  root = if (identical(scope, "course")) {
    course_dir %||% ullme_active_course_dir(app=app)
  } else {
    app$user_dir
  }
  if (is.null(root) || !nzchar(paste0(root)[1])) return(NULL)
  file.path(root, "form_input", inputid)
}


ullme_form_input_files = function(directory) {
  if (is.null(directory) || !dir.exists(directory)) return(character(0))
  files = list.files(
    directory,
    pattern="\\.txt$",
    full.names=TRUE,
    recursive=FALSE
  )
  if (!length(files)) return(character(0))
  info = file.info(files)
  files[order(info$mtime, basename(files), decreasing=TRUE, na.last=TRUE)]
}


ullme_recent_form_inputs = function(inputid, scope=c("course", "user"),
                                     course_dir=NULL, limit=3L,
                                     app=getApp()) {
  scope = match.arg(scope)
  directory = ullme_form_input_scope_dir(
    inputid=inputid,
    scope=scope,
    course_dir=course_dir,
    app=app
  )
  files = ullme_form_input_files(directory)
  if (!length(files)) return(list())
  limit = max(0L, min(20L, as.integer(limit)[1]))
  records = list()
  seen = character(0)
  for (path in files) {
    text = trimws(paste(
      readLines(path, warn=FALSE, encoding="UTF-8"),
      collapse="\n"
    ))
    if (!nzchar(text) || text %in% seen) next
    seen = c(seen, text)
    records[[length(records) + 1L]] = list(
      text=text,
      scope=scope,
      saved_at=format(
        file.info(path)$mtime,
        "%Y-%m-%dT%H:%M:%S%z"
      )
    )
    if (length(records) >= limit) break
  }
  records
}


ullme_form_input_choices = function(inputid, course_dir=NULL, app=getApp()) {
  course = ullme_recent_form_inputs(
    inputid,
    scope="course",
    course_dir=course_dir,
    limit=3L,
    app=app
  )
  user = ullme_recent_form_inputs(
    inputid,
    scope="user",
    course_dir=course_dir,
    limit=3L,
    app=app
  )
  course_text = vapply(course, `[[`, character(1), "text")
  user = Filter(function(record) !record$text %in% course_text, user)
  combined = c(course, user)
  if (length(combined) > 5L) combined = combined[seq_len(5L)]
  list(
    course=unname(course),
    user=unname(user),
    recent=unname(combined),
    default=if (length(course)) {
      course[[1]]$text
    } else if (length(user)) {
      user[[1]]$text
    } else {
      ""
    }
  )
}


ullme_store_form_input_at = function(text, inputid, scope,
                                      course_dir=NULL, app=getApp()) {
  text = trimws(paste0(text, collapse="\n"))
  if (!nzchar(text)) return(NULL)
  directory = ullme_form_input_scope_dir(
    inputid=inputid,
    scope=scope,
    course_dir=course_dir,
    app=app
  )
  if (is.null(directory)) return(NULL)
  dir.create(directory, recursive=TRUE, showWarnings=FALSE)
  files = ullme_form_input_files(directory)
  for (path in files) {
    previous = trimws(paste(
      readLines(path, warn=FALSE, encoding="UTF-8"),
      collapse="\n"
    ))
    if (!identical(previous, text)) next
    try(Sys.setFileTime(path, Sys.time()), silent=TRUE)
    return(path)
  }
  id = paste0(
    format(Sys.time(), "%Y%m%d-%H%M%OS3"),
    "-",
    sprintf("%06d", sample.int(999999L, 1L)),
    ".txt"
  )
  id = gsub("[^0-9A-Za-z.-]+", "-", id)
  path = file.path(directory, id)
  writeLines(enc2utf8(text), path, useBytes=TRUE)
  path
}


ullme_store_form_input = function(text, inputid, course_dir=NULL,
                                   app=getApp()) {
  course_dir = course_dir %||% ullme_active_course_dir(app=app)
  list(
    course=ullme_store_form_input_at(
      text, inputid, "course", course_dir=course_dir, app=app
    ),
    user=ullme_store_form_input_at(
      text, inputid, "user", course_dir=course_dir, app=app
    )
  )
}
