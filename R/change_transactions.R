ullme_change_history_dir = function(app=getApp()) {
  file.path(app$user_dir, "change_history")
}


ullme_change_backup_root = function(app=getApp()) {
  file.path(ullme_change_history_dir(app=app), "backups")
}


ullme_change_id = function() {
  id = paste0(
    format(Sys.time(), "%Y%m%dT%H%M%OS3"),
    "_",
    sprintf("%08d", sample.int(99999999L, 1))
  )
  gsub("[^0-9A-Za-z_]+", "", id)
}


ullme_change_write = function(target, content) {
  list(type="write_text", target=target, content=paste0(content, collapse="\n"))
}


ullme_change_copy = function(source, target, overwrite=FALSE) {
  list(type="copy_path", source=source, target=target, overwrite=isTRUE(overwrite))
}


ullme_change_delete = function(target) {
  list(type="delete_path", target=target)
}


ullme_new_change = function(action, summary, changes, origin="agent",
                             details=list(), app=getApp()) {
  if (!is.list(changes) || length(changes) == 0) stop("A change must contain at least one file operation.")
  list(
    id=ullme_change_id(),
    created_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
    userid=app$userid,
    role=app$role,
    semester=app$semester %||% "",
    courseid=app$courseid %||% "",
    action=paste0(action)[1],
    summary=paste0(summary)[1],
    origin=paste0(origin)[1],
    details=details,
    changes=changes,
    status="prepared"
  )
}


ullme_normalize_absolute_path = function(path, mustWork=FALSE) {
  path = paste0(path)[1]
  if (is.na(path) || !nzchar(path)) stop("File path must not be empty.")
  normalizePath(path, winslash="/", mustWork=mustWork)
}


ullme_path_is_within = function(path, root, allow_root=FALSE) {
  path = ullme_normalize_absolute_path(path, mustWork=FALSE)
  root = ullme_normalize_absolute_path(root, mustWork=FALSE)
  if (identical(.Platform$OS.type, "windows")) {
    path = tolower(path)
    root = tolower(root)
  }
  identical(path, root) && isTRUE(allow_root) || startsWith(path, paste0(root, "/"))
}


ullme_authorized_write_roots = function(app=getApp()) {
  roots = c(
    app$user_dir,
    ullme_role_user_dir(app$glob$main_dir, app$userid, "teacher")
  )
  unique(vapply(
    roots,
    ullme_normalize_absolute_path,
    character(1),
    mustWork=FALSE,
    USE.NAMES=FALSE
  ))
}


ullme_assert_authorized_target = function(path, app=getApp()) {
  path = ullme_normalize_absolute_path(path, mustWork=FALSE)
  roots = ullme_authorized_write_roots(app=app)
  allowed = any(vapply(roots, function(root) {
    ullme_path_is_within(path, root, allow_root=FALSE)
  }, logical(1)))
  if (!allowed) stop("The requested file is outside the current user's editable directories.")
  path
}


ullme_path_hash = function(path) {
  if (!file.exists(path) && !dir.exists(path)) return(NA_character_)
  if (!dir.exists(path)) return(unname(tools::md5sum(path))[[1]])
  files = list.files(
    path, recursive=TRUE, full.names=FALSE, all.files=TRUE,
    no..=TRUE, include.dirs=FALSE
  )
  files = sort(gsub("\\\\", "/", files))
  if (length(files) == 0) return("directory:empty")
  hashes = unname(tools::md5sum(file.path(path, files)))
  paste(paste(files, hashes, sep="="), collapse="|")
}


ullme_copy_path = function(source, target, overwrite=FALSE) {
  if (!file.exists(source) && !dir.exists(source)) stop("Copy source does not exist.")
  if ((file.exists(target) || dir.exists(target)) && !isTRUE(overwrite)) {
    stop("Copy target already exists.")
  }
  if (file.exists(target) || dir.exists(target)) unlink(target, recursive=TRUE)
  dir.create(dirname(target), recursive=TRUE, showWarnings=FALSE)
  if (!dir.exists(source)) {
    if (!file.copy(source, target, overwrite=FALSE, copy.mode=TRUE, copy.date=TRUE)) {
      stop("Could not copy file.")
    }
    return(invisible(TRUE))
  }
  dir.create(target, recursive=TRUE, showWarnings=FALSE)
  files = list.files(
    source, recursive=TRUE, full.names=FALSE, all.files=TRUE,
    no..=TRUE, include.dirs=FALSE
  )
  for (file in files) {
    from = file.path(source, file)
    to = file.path(target, file)
    dir.create(dirname(to), recursive=TRUE, showWarnings=FALSE)
    if (!file.copy(from, to, overwrite=FALSE, copy.mode=TRUE, copy.date=TRUE)) {
      stop("Could not copy ", file, ".")
    }
  }
  invisible(TRUE)
}


ullme_change_public_record = function(change, main_dir) {
  record = change
  if (identical(record$type, "write_text") &&
      grepl("\\.ya?ml$", record$target, ignore.case=TRUE)) {
    before = if (file.exists(record$target) && !dir.exists(record$target) &&
                 file.info(record$target)$size <= 200 * 1024) {
      paste(readLines(record$target, warn=FALSE, encoding="UTF-8"), collapse="\n")
    } else {
      ""
    }
    after = paste0(record$content %||% "", collapse="\n")
    if (nchar(after, type="bytes") > 200 * 1024) {
      after = paste0(substr(after, 1, 200 * 1024), "\n… preview truncated …")
    }
    record$preview = list(before=before, after=after)
  }
  record$content = NULL
  if (!is.null(record$target)) {
    target = ullme_normalize_absolute_path(record$target, mustWork=FALSE)
    root = ullme_normalize_absolute_path(main_dir, mustWork=FALSE)
    record$target = if (ullme_path_is_within(target, root, allow_root=TRUE)) {
      sub(paste0("^", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", root), "/?"), "", target)
    } else target
  }
  record
}


ullme_prepare_change = function(operation, app=getApp()) {
  if (!identical(operation$userid, app$userid)) stop("Change user does not match the active user.")
  seen = character(0)
  prepared = lapply(seq_along(operation$changes), function(i) {
    change = operation$changes[[i]]
    type = paste0(change$type)[1]
    if (!type %in% c("write_text", "copy_path", "delete_path")) {
      stop("Unsupported change type: ", type)
    }
    change$target = ullme_assert_authorized_target(change$target, app=app)
    key = if (identical(.Platform$OS.type, "windows")) tolower(change$target) else change$target
    if (key %in% seen) stop("A transaction cannot modify the same target twice.")
    seen <<- c(seen, key)
    if (identical(type, "write_text")) {
      if (dir.exists(change$target)) stop("Cannot replace a directory with text.")
      if (grepl("\\.ya?ml$", change$target, ignore.case=TRUE)) {
        result = ullme_validate_yaml_by_path(change$target, change$content, app=app)
        ullme_validation_stop(result)
        change$warnings = unique(c(
          unlist(change$warnings %||% list(), use.names=FALSE),
          unlist(result$warnings %||% list(), use.names=FALSE)
        ))
      }
    }
    if (identical(type, "copy_path")) {
      change$source = ullme_normalize_absolute_path(change$source, mustWork=TRUE)
      if ((file.exists(change$target) || dir.exists(change$target)) && !isTRUE(change$overwrite)) {
        stop("Copy target already exists: ", basename(change$target))
      }
    }
    if (identical(type, "delete_path") &&
        !file.exists(change$target) && !dir.exists(change$target)) {
      stop("Delete target no longer exists: ", basename(change$target))
    }
    change$before_exists = file.exists(change$target) || dir.exists(change$target)
    change$before_hash = ullme_path_hash(change$target)
    change
  })
  operation$changes = prepared
  operation$status = "validated"
  operation
}


ullme_operation_payload = function(operation, app=getApp()) {
  list(
    id=operation$id,
    action=operation$action,
    summary=operation$summary,
    origin=operation$origin,
    courseid=operation$courseid,
    changes=lapply(operation$changes, ullme_change_public_record, main_dir=app$glob$main_dir)
  )
}


ullme_submit_change = function(operation, app=getApp()) {
  operation = ullme_prepare_change(operation, app=app)
  policy = if (identical(operation$origin, "agent")) {
    ullme_agent_approval_policy(operation$action, app=app)
  } else {
    "allow"
  }
  operation$approval_policy = policy
  if (identical(policy, "deny")) {
    operation$status = "denied"
    return(list(ok=FALSE, status="denied", id=operation$id,
                message="This action is disabled in the user's agent-tool settings."))
  }
  if (identical(policy, "ask")) {
    if (is.null(app$pending_changes)) app$pending_changes = list()
    app$pending_changes[[operation$id]] = operation
    callJS(
      .fun="window.ullme.openChangeApproval",
      .args=list(ullme_operation_payload(operation, app=app)),
      .app=app
    )
    return(list(ok=TRUE, status="pending_approval", id=operation$id,
                message="The proposed change is waiting for user approval."))
  }
  ullme_commit_change(operation, approved_by="policy", app=app)
}


ullme_backup_change_targets = function(operation, backup_dir) {
  before_dir = file.path(backup_dir, "before")
  dir.create(before_dir, recursive=TRUE, showWarnings=FALSE)
  for (i in seq_along(operation$changes)) {
    change = operation$changes[[i]]
    if (!isTRUE(change$before_exists)) next
    target = file.path(before_dir, sprintf("%04d", i))
    ullme_copy_path(change$target, target)
    operation$changes[[i]]$backup = gsub("\\\\", "/", file.path("before", sprintf("%04d", i)))
  }
  operation
}


ullme_apply_change_entry = function(change) {
  if (identical(change$type, "write_text")) {
    dir.create(dirname(change$target), recursive=TRUE, showWarnings=FALSE)
    temp = tempfile(".ullme-write-", tmpdir=dirname(change$target))
    on.exit(if (file.exists(temp)) unlink(temp), add=TRUE)
    writeLines(change$content, temp, useBytes=TRUE)
    if (file.exists(change$target)) unlink(change$target)
    if (!file.rename(temp, change$target)) {
      if (!file.copy(temp, change$target, overwrite=FALSE)) stop("Could not write ", basename(change$target), ".")
    }
  } else if (identical(change$type, "copy_path")) {
    ullme_copy_path(change$source, change$target, overwrite=isTRUE(change$overwrite))
  } else if (identical(change$type, "delete_path")) {
    unlink(change$target, recursive=TRUE)
    if (file.exists(change$target) || dir.exists(change$target)) stop("Could not delete ", basename(change$target), ".")
  }
  invisible(TRUE)
}


ullme_restore_change_targets = function(operation, backup_dir) {
  for (i in rev(seq_along(operation$changes))) {
    change = operation$changes[[i]]
    if (file.exists(change$target) || dir.exists(change$target)) unlink(change$target, recursive=TRUE)
    if (isTRUE(change$before_exists)) {
      backup = file.path(backup_dir, change$backup)
      ullme_copy_path(backup, change$target)
    }
  }
  invisible(TRUE)
}


ullme_manifest_path = function(operation_id, app=getApp()) {
  file.path(ullme_change_backup_root(app=app), operation_id, "manifest.yaml")
}


ullme_write_change_manifest = function(operation, backup_dir, app=getApp()) {
  manifest = operation
  manifest$changes = lapply(manifest$changes, function(change) {
    change$content = NULL
    change$source = if (!is.null(change$source)) {
      ullme_change_public_record(list(target=change$source), app$glob$main_dir)$target
    } else NULL
    change$target = ullme_change_public_record(list(target=change$target), app$glob$main_dir)$target
    change
  })
  yaml::write_yaml(manifest, file.path(backup_dir, "manifest.yaml"))
  ullme_append_change_index(manifest, app=app)
  invisible(manifest)
}


ullme_append_change_index = function(operation, app=getApp()) {
  history_dir = ullme_change_history_dir(app=app)
  dir.create(history_dir, recursive=TRUE, showWarnings=FALSE)
  path = file.path(history_dir, "index.yaml")
  index = if (file.exists(path)) {
    tryCatch(yaml::read_yaml(path, eval.expr=FALSE), error=function(e) list())
  } else list()
  if (!is.list(index)) index = list()
  entry = list(
    id=operation$id,
    committed_at=operation$committed_at %||% operation$created_at,
    action=operation$action,
    summary=operation$summary,
    origin=operation$origin,
    status=operation$status,
    courseid=operation$courseid %||% ""
  )
  index = c(list(entry), index)
  yaml::write_yaml(index[seq_len(min(length(index), 1000L))], path)

  if (requireNamespace("jsonlite", quietly=TRUE)) {
    line = jsonlite::toJSON(entry, auto_unbox=TRUE, null="null")
    cat(paste0(line, "\n"), file=file.path(history_dir, "log.jsonl"), append=TRUE)
  }
  invisible(entry)
}


ullme_commit_change = function(operation, approved_by="user", app=getApp()) {
  lock = ullme_acquire_change_lock(app=app)
  on.exit(ullme_release_change_lock(lock), add=TRUE)
  for (change in operation$changes) {
    current_exists = file.exists(change$target) || dir.exists(change$target)
    current_hash = ullme_path_hash(change$target)
    if (!identical(current_exists, isTRUE(change$before_exists)) ||
        (current_exists && !identical(current_hash, paste0(change$before_hash)[1]))) {
      stop("The proposed change is stale because ", basename(change$target),
           " changed after validation.")
    }
  }
  backup_dir = file.path(ullme_change_backup_root(app=app), operation$id)
  if (dir.exists(backup_dir) || file.exists(backup_dir)) stop("Change ID already exists.")
  dir.create(backup_dir, recursive=TRUE, showWarnings=FALSE)
  operation = ullme_backup_change_targets(operation, backup_dir)
  operation$approved_by = approved_by
  operation$committed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")

  error = NULL
  tryCatch({
    for (i in seq_along(operation$changes)) {
      ullme_apply_change_entry(operation$changes[[i]])
      operation$changes[[i]]$after_exists =
        file.exists(operation$changes[[i]]$target) || dir.exists(operation$changes[[i]]$target)
      operation$changes[[i]]$after_hash = ullme_path_hash(operation$changes[[i]]$target)
    }
  }, error=function(e) {
    error <<- e
  })

  if (!is.null(error)) {
    rollback_error = tryCatch({
      ullme_restore_change_targets(operation, backup_dir)
      NULL
    }, error=function(e) e)
    operation$status = if (is.null(rollback_error)) "rolled_back" else "rollback_failed"
    operation$error = conditionMessage(error)
    if (!is.null(rollback_error)) operation$rollback_error = conditionMessage(rollback_error)
    ullme_write_change_manifest(operation, backup_dir, app=app)
    stop("Change failed", if (is.null(rollback_error)) " and was rolled back: " else
      " and rollback also failed: ", conditionMessage(error))
  }

  operation$status = "committed"
  ullme_write_change_manifest(operation, backup_dir, app=app)
  list(ok=TRUE, status="committed", id=operation$id,
       message=operation$summary, operation=operation)
}


ullme_acquire_change_lock = function(app=getApp(), attempts=50L) {
  history_dir = ullme_change_history_dir(app=app)
  dir.create(history_dir, recursive=TRUE, showWarnings=FALSE)
  lock = file.path(history_dir, ".write-lock")
  for (i in seq_len(max(1L, as.integer(attempts)))) {
    if (dir.create(lock, showWarnings=FALSE)) return(lock)
    Sys.sleep(0.02)
  }
  stop("Another file change is currently being committed. Please try again.")
}


ullme_release_change_lock = function(lock) {
  if (!is.null(lock) && dir.exists(lock)) unlink(lock, recursive=TRUE)
  invisible(TRUE)
}


ullme_handle_change_approval = function(operation_id=NULL, approved=FALSE,
                                         app=getApp(), ...) {
  operation_id = paste0(operation_id)[1]
  operation = app$pending_changes[[operation_id]]
  if (is.null(operation)) return(invisible(FALSE))
  app$pending_changes[[operation_id]] = NULL
  age = suppressWarnings(difftime(
    Sys.time(),
    as.POSIXct(operation$created_at, format="%Y-%m-%dT%H:%M:%OS%z"),
    units="mins"
  ))
  if (isTRUE(!is.na(age) && age > 30)) {
    approved = FALSE
  }
  result = if (isTRUE(approved)) {
    tryCatch(
      ullme_commit_change(operation, approved_by="user", app=app),
      error=function(e) list(ok=FALSE, status="error", message=conditionMessage(e))
    )
  } else {
    list(ok=FALSE, status="rejected", id=operation_id, message="The proposed change was rejected.")
  }
  public_result = list(
    ok=isTRUE(result$ok),
    status=result$status %||% if (isTRUE(result$ok)) "committed" else "error",
    operation_id=result$id %||% operation_id,
    message=result$message %||% ""
  )
  if (is.null(app$change_results)) app$change_results = list()
  app$change_results[[operation_id]] = public_result
  proposal_token = operation$details$proposal_token %||% ""
  if (isTRUE(public_result$ok) && nzchar(proposal_token) &&
      !is.null(app$organization_proposals)) {
    app$organization_proposals[[proposal_token]] = NULL
  }
  callJS(
    .fun="window.ullme.changeApprovalComplete",
    .args=list(public_result),
    .app=app
  )
  if (isTRUE(result$ok)) {
    ullme_send_course_state(app=app)
  }
  invisible(public_result)
}


ullme_change_history = function(app=getApp(), limit=50L) {
  path = file.path(ullme_change_history_dir(app=app), "index.yaml")
  if (!file.exists(path)) return(list())
  index = tryCatch(yaml::read_yaml(path, eval.expr=FALSE), error=function(e) list())
  if (!is.list(index)) return(list())
  index[seq_len(min(length(index), max(0L, as.integer(limit))))]
}


ullme_resolve_manifest_target = function(path, app=getApp()) {
  path = paste0(path)[1]
  if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) return(ullme_assert_authorized_target(path, app=app))
  ullme_assert_authorized_target(file.path(app$glob$main_dir, path), app=app)
}


ullme_prepare_undo = function(operation_id="last", origin="agent", app=getApp()) {
  history = ullme_change_history(app=app, limit=1000L)
  if (identical(operation_id, "last")) {
    committed = Filter(function(x) identical(x$status, "committed"), history)
    if (length(committed) == 0) stop("There is no committed change to undo.")
    operation_id = committed[[1]]$id
  }
  path = ullme_manifest_path(operation_id, app=app)
  if (!file.exists(path)) stop("The selected change is no longer available.")
  manifest = yaml::read_yaml(path, eval.expr=FALSE)
  if (!identical(manifest$status, "committed")) stop("Only committed changes can be undone.")

  backup_dir = dirname(path)
  inverse = list()
  for (change in rev(manifest$changes)) {
    target = ullme_resolve_manifest_target(change$target, app=app)
    current_exists = file.exists(target) || dir.exists(target)
    current_hash = ullme_path_hash(target)
    expected_exists = isTRUE(change$after_exists)
    expected_hash = paste0(change$after_hash %||% NA_character_)[1]
    if (!identical(current_exists, expected_exists) ||
        (current_exists && !identical(current_hash, expected_hash))) {
      stop("Cannot undo because ", basename(target), " changed after the selected operation.")
    }
    if (isTRUE(change$before_exists)) {
      source = file.path(backup_dir, change$backup)
      inverse[[length(inverse) + 1L]] = ullme_change_copy(source, target, overwrite=TRUE)
    } else if (current_exists) {
      inverse[[length(inverse) + 1L]] = ullme_change_delete(target)
    }
  }
  if (length(inverse) == 0) stop("The selected change has nothing to undo.")
  ullme_new_change(
    action="undo",
    summary=paste0("Undo: ", manifest$summary),
    origin=origin,
    details=list(undoes=operation_id),
    changes=inverse,
    app=app
  )
}


ullme_undo_change = function(operation_id="last", origin="agent", app=getApp()) {
  ullme_submit_change(
    ullme_prepare_undo(operation_id=operation_id, origin=origin, app=app),
    app=app
  )
}


ullme_handle_change_undo = function(operation_id="last", app=getApp(), ...) {
  result = tryCatch(
    ullme_undo_change(operation_id=operation_id, origin="ui", app=app),
    error=function(e) list(ok=FALSE, status="error", message=conditionMessage(e))
  )
  callJS(
    .fun="window.ullme.changeUndoComplete",
    .args=list(result, ullme_agent_settings_payload(app=app)),
    .app=app
  )
  if (isTRUE(result$ok)) ullme_send_course_state(app=app)
  invisible(result)
}
