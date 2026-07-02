# File operations for course materials deliberately live in this small module.
# Every public operation derives the active user's material root from the app
# and accepts relative paths only. Directory deletion is not supported: an
# accidental recursive delete should be impossible here.

ullme_safe_relative_material_path = function(path) {
  restore.point("ullme_safe_relative_material_path")
  path = gsub("\\\\", "/", paste0(path)[1])
  !is.na(path) && nzchar(path) &&
    !grepl("^/|^[A-Za-z]:|(^|/)\\.\\.(/|$)", path)
}


.ullme_temp_root = function(app=getApp()) {
  main_dir = ullme_main_dir(app=app)
  root = file.path(main_dir, "temp")
  if (!dir.exists(root) &&
      !dir.create(root, recursive=TRUE, showWarnings=FALSE)) {
    stop("Could not create the uLLMe temporary-directory root.")
  }
  normalizePath(root, winslash="/", mustWork=TRUE)
}


ullme_tempdir = function(pattern=".ullme-", app=getApp()) {
  root = .ullme_temp_root(app=app)
  pattern = paste0(pattern)[1]
  if (is.na(pattern) || !nzchar(pattern)) pattern = ".ullme-"
  pattern = gsub("[^A-Za-z0-9._-]+", "_", pattern)
  candidate = tempfile(pattern=pattern, tmpdir=root)
  if (!dir.create(candidate, recursive=FALSE, showWarnings=FALSE)) {
    stop("Could not create an uLLMe temporary directory.")
  }
  candidate = normalizePath(candidate, winslash="/", mustWork=TRUE)
  if (!.ullme_material_path_is_within(candidate, root)) {
    stop("The temporary directory was not created below the uLLMe temp root.")
  }
  candidate
}


ullme_remove_tempdir = function(temp_dir, app=getApp()) {
  restore.point("ulme_remove_tempdir")
  root = .ullme_temp_root(app=app)
  temp_dir = paste0(temp_dir)[1]
  if (is.na(temp_dir) || !nzchar(temp_dir)) {
    stop("temp_dir must not be empty.")
  }
  is_absolute = grepl("^[A-Za-z]:[/\\\\]|^[/\\\\]{2}|^/", temp_dir)
  if (!is_absolute) stop("temp_dir must be an absolute path.")
  if (!dir.exists(temp_dir)) return(invisible(FALSE))
  link = Sys.readlink(temp_dir)
  if (length(link) == 1 && !is.na(link) && nzchar(link)) {
    stop("Refusing to remove a symbolic-link temporary directory.")
  }
  target = normalizePath(temp_dir, winslash="/", mustWork=TRUE)
  if (!.ullme_material_path_is_within(target, root)) {
    stop("Refusing to remove a directory outside the uLLMe temp root.")
  }
  if (!has.substr(target, "/temp/")) {
    stop("Refusing to remove a directory outside the uLLMe temp root.")
  }

  unlink(target, recursive=TRUE, force=FALSE)
  if (file.exists(target) || dir.exists(target)) {
    stop("Could not remove the uLLMe temporary directory.")
  }
  invisible(TRUE)
}


.ullme_user_material_dir = function(app=getApp()) {
  if (is.null(app)) stop("An active app is required for material file operations.")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  .ullme_material_root(file.path(course_dir, "materials"))
}

.ullme_material_root = function(material_dir) {
  material_dir = paste0(material_dir)[1]
  if (is.na(material_dir) || !nzchar(material_dir) || !dir.exists(material_dir)) {
    stop("The material directory does not exist.")
  }
  normalizePath(material_dir, winslash="/", mustWork=TRUE)
}


.ullme_material_relative_path = function(path) {
  path = gsub("\\\\", "/", paste0(path)[1])
  if (is.na(path) || !nzchar(path) || grepl("^/|^[A-Za-z]:", path)) {
    stop("Material paths must be non-empty relative paths.")
  }
  parts = strsplit(path, "/", fixed=TRUE)[[1]]
  if (length(parts) == 0 || any(!nzchar(parts)) || any(parts %in% c(".", ".."))) {
    stop("Material paths must not contain empty, '.' or '..' components.")
  }
  if (any(grepl("[<>:\"|?*[:cntrl:]]", parts)) ||
      any(grepl("[. ]$", parts))) {
    stop("The material path contains characters that are unsafe on common filesystems.")
  }
  reserved = grepl(
    "^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\\..*)?$",
    parts,
    ignore.case=TRUE
  )
  if (any(reserved)) stop("The material path uses a reserved filename.")
  paste(parts, collapse="/")
}


.ullme_material_path_is_within = function(path, root, allow_root=FALSE) {
  path = normalizePath(path, winslash="/", mustWork=FALSE)
  root = normalizePath(root, winslash="/", mustWork=TRUE)
  if (identical(.Platform$OS.type, "windows")) {
    path = tolower(path)
    root = tolower(root)
  }
  (isTRUE(allow_root) && identical(path, root)) ||
    startsWith(path, paste0(root, "/"))
}


.ullme_material_existing_ancestor = function(path) {
  ancestor = path
  while (!file.exists(ancestor) && !dir.exists(ancestor)) {
    parent = dirname(ancestor)
    if (identical(parent, ancestor)) stop("Could not resolve the material path.")
    ancestor = parent
  }
  ancestor
}


.ullme_material_path = function(material_dir, path, must_exist=FALSE) {
  root = .ullme_material_root(material_dir)
  relative = .ullme_material_relative_path(path)
  candidate = file.path(root, relative)
  current = root
  for (part in strsplit(relative, "/", fixed=TRUE)[[1]]) {
    current = file.path(current, part)
    link = Sys.readlink(current)
    if (length(link) == 1 && !is.na(link) && nzchar(link)) {
      stop("Material operations do not follow symbolic links.")
    }
    if (!file.exists(current) && !dir.exists(current)) break
  }
  exists = file.exists(candidate) || dir.exists(candidate)

  if (exists) {
    resolved = normalizePath(candidate, winslash="/", mustWork=TRUE)
    if (!.ullme_material_path_is_within(resolved, root)) {
      stop("The requested path resolves outside the material directory.")
    }
    return(resolved)
  }

  if (isTRUE(must_exist)) stop("The requested material path does not exist.")
  ancestor = normalizePath(
    .ullme_material_existing_ancestor(candidate),
    winslash="/",
    mustWork=TRUE
  )
  if (!.ullme_material_path_is_within(ancestor, root, allow_root=TRUE)) {
    stop("The requested path has a parent outside the material directory.")
  }
  candidate = normalizePath(candidate, winslash="/", mustWork=FALSE)
  if (!.ullme_material_path_is_within(candidate, root)) {
    stop("The requested path is outside the material directory.")
  }
  candidate
}


.ullme_material_file = function(material_dir, path) {
  target = .ullme_material_path(material_dir, path, must_exist=TRUE)
  if (dir.exists(target)) stop("This operation accepts files only, not directories.")
  target
}


delete_material_file = function(path, app=getApp()) {
  .ullme_delete_material_file(.ullme_user_material_dir(app), path)
}


.ullme_delete_material_file = function(material_dir, path) {
  target = .ullme_material_file(material_dir, path)
  if (!file.remove(target)) stop("Could not delete the material file.")
  if (file.exists(target) || dir.exists(target)) {
    stop("The material file still exists after the delete operation.")
  }
  invisible(TRUE)
}


move_material_file = function(source, destination, app=getApp()) {
  .ullme_move_material_file(
    .ullme_user_material_dir(app),
    source,
    destination
  )
}


.ullme_move_material_file = function(material_dir, source, destination) {
  source_path = .ullme_material_file(material_dir, source)
  destination_path = .ullme_material_path(material_dir, destination)
  if (file.exists(destination_path) || dir.exists(destination_path)) {
    stop("The move destination already exists.")
  }
  dir.create(dirname(destination_path), recursive=TRUE, showWarnings=FALSE)
  if (!file.rename(source_path, destination_path)) {
    stop("Could not move the material file.")
  }
  invisible(TRUE)
}


copy_material_file = function(source, destination, app=getApp()) {
  .ullme_copy_material_file(
    .ullme_user_material_dir(app),
    source,
    destination
  )
}


.ullme_copy_material_file = function(material_dir, source, destination) {
  source_path = .ullme_material_file(material_dir, source)
  destination_path = .ullme_material_path(material_dir, destination)
  if (file.exists(destination_path) || dir.exists(destination_path)) {
    stop("The copy destination already exists.")
  }
  dir.create(dirname(destination_path), recursive=TRUE, showWarnings=FALSE)
  copied = file.copy(
    source_path,
    destination_path,
    overwrite=FALSE,
    copy.mode=TRUE,
    copy.date=TRUE
  )
  if (!isTRUE(copied)) stop("Could not copy the material file.")
  invisible(TRUE)
}


create_material_directory = function(path, app=getApp()) {
  .ullme_create_material_directory(.ullme_user_material_dir(app), path)
}


.ullme_create_material_directory = function(material_dir, path) {
  target = .ullme_material_path(material_dir, path)
  if (file.exists(target) || dir.exists(target)) {
    stop("The material directory already exists.")
  }
  if (!dir.create(target, recursive=TRUE, showWarnings=FALSE)) {
    stop("Could not create the material directory.")
  }
  invisible(TRUE)
}


ullme_material_tree = function(material_dir, max_entries=5000L) {
  root = .ullme_material_root(material_dir)
  relative = list.files(
    root,
    recursive=TRUE,
    full.names=FALSE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=TRUE
  )
  relative = unique(gsub("\\\\", "/", relative))
  relative = relative[!grepl("(^|/)\\.ullme-", relative)]
  relative = head(relative, max(0L, as.integer(max_entries)))

  records = lapply(relative, function(path) {
    target = tryCatch(
      .ullme_material_path(root, path, must_exist=TRUE),
      error=function(e) NULL
    )
    if (is.null(target)) return(NULL)
    info = file.info(target)
    modified = info$mtime[[1]]
    list(
      path=path,
      name=basename(path),
      parent=if (identical(dirname(path), ".")) "" else
        gsub("\\\\", "/", dirname(path)),
      type=if (dir.exists(target)) "directory" else "file",
      size=if (dir.exists(target) || is.na(info$size[[1]])) NULL else
        unname(info$size[[1]]),
      modified=if (is.na(modified)) NULL else
        format(modified, "%Y-%m-%dT%H:%M:%S%z")
    )
  })
  Filter(Negate(is.null), records)
}


ullme_apply_material_file_operation = function(action, paths, destination=NULL,
                                                app=getApp()) {
  material_dir = .ullme_user_material_dir(app)
  action = match.arg(paste0(action)[1], c("copy", "move", "delete"))
  paths = unique(vapply(
    paths,
    .ullme_material_relative_path,
    character(1),
    USE.NAMES=FALSE
  ))
  if (length(paths) == 0) stop("Select at least one material file.")

  # Validate every source before performing the first operation.
  invisible(lapply(paths, function(path) .ullme_material_file(material_dir, path)))
  if (identical(action, "delete")) {
    for (path in paths) .ullme_delete_material_file(material_dir, path)
    return(invisible(TRUE))
  }

  destination = .ullme_material_relative_path(destination)
  destination_dir = .ullme_material_path(
    material_dir,
    destination,
    must_exist=TRUE
  )
  if (!dir.exists(destination_dir)) stop("The destination must be a material directory.")
  targets = paste0(destination, "/", basename(paths))
  if (anyDuplicated(if (identical(.Platform$OS.type, "windows")) {
    tolower(targets)
  } else targets)) {
    stop("Two selected files have the same name and cannot share this destination.")
  }
  invisible(lapply(targets, function(path) {
    target = .ullme_material_path(material_dir, path)
    if (file.exists(target) || dir.exists(target)) {
      stop("A file with the same name already exists in the destination.")
    }
    target
  }))

  operation = if (identical(action, "copy")) .ullme_copy_material_file else
    .ullme_move_material_file
  completed = integer(0)
  failure = tryCatch({
    for (i in seq_along(paths)) {
      operation(material_dir, paths[[i]], targets[[i]])
      completed = c(completed, i)
    }
    NULL
  }, error=function(e) e)
  if (!is.null(failure)) {
    rollback_errors = character(0)
    for (i in rev(completed)) {
      rollback_error = tryCatch({
        if (identical(action, "copy")) {
          .ullme_delete_material_file(material_dir, targets[[i]])
        } else {
          .ullme_move_material_file(material_dir, targets[[i]], paths[[i]])
        }
        NULL
      }, error=function(e) conditionMessage(e))
      if (!is.null(rollback_error)) rollback_errors = c(rollback_errors, rollback_error)
    }
    message = conditionMessage(failure)
    if (length(rollback_errors) > 0) {
      message = paste0(
        message,
        " Rollback was incomplete: ",
        paste(unique(rollback_errors), collapse="; ")
      )
    }
    stop(message, call.=FALSE)
  }
  invisible(TRUE)
}
