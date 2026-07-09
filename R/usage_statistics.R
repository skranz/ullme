ullme_usage_statistics_dir = function(app=getApp()) {
  file.path(
    app$glob$main_dir,
    "teachers",
    ullme_clean_user_name(app$teacherid %||% app$userid),
    "usage_statistics"
  )
}


ullme_usage_source_dir = function(app=getApp()) {
  file.path(app$glob$main_dir, "session_stats")
}


ullme_usage_manifest_columns = function() {
  c(
    "source_file", "size", "mtime", "teacher_match", "status",
    "message", "course_keys", "updated_at"
  )
}


ullme_usage_empty_manifest = function() {
  data.frame(
    source_file=character(),
    size=numeric(),
    mtime=numeric(),
    teacher_match=logical(),
    status=character(),
    message=character(),
    course_keys=character(),
    updated_at=character(),
    stringsAsFactors=FALSE
  )
}


ullme_usage_summary_columns = function() {
  dimensions = c(
    "day", "semester", "courseid", "tutorid", "model", "error"
  )
  metrics = c(
    "requests", "replies", "errors", "sessions",
    "input_token_sum", "input_token_n",
    "output_token_sum", "output_token_n",
    "thinking_token_sum", "thinking_token_n",
    "ttf_ms_sum", "ttf_ms_n",
    "total_sec_sum", "total_sec_n"
  )
  c(dimensions, metrics)
}


ullme_usage_empty_summary = function() {
  columns = ullme_usage_summary_columns()
  result = as.data.frame(
    setNames(replicate(length(columns), character(), simplify=FALSE), columns),
    stringsAsFactors=FALSE
  )
  numeric_columns = setdiff(
    columns,
    c("day", "semester", "courseid", "tutorid", "model", "error")
  )
  for (name in numeric_columns) result[[name]] = numeric()
  result
}


ullme_usage_normalize_logical = function(value) {
  value %in% c(TRUE, "TRUE", "true", "1", 1)
}


ullme_usage_read_csv = function(path, empty=NULL) {
  backup = paste0(path, ".previous")
  if (!file.exists(path) && file.exists(backup)) {
    file.rename(backup, path)
  }
  if (!file.exists(path) || isTRUE(file.info(path)$size == 0)) {
    return(empty)
  }
  tryCatch(
    utils::read.csv(
      path,
      stringsAsFactors=FALSE,
      check.names=FALSE,
      na.strings=c("NA")
    ),
    error=function(e) empty
  )
}


ullme_usage_read_manifest = function(directory) {
  path = file.path(directory, "source_manifest.csv")
  manifest = ullme_usage_read_csv(path, ullme_usage_empty_manifest())
  for (name in ullme_usage_manifest_columns()) {
    if (!name %in% names(manifest)) manifest[[name]] = NA
  }
  manifest = manifest[, ullme_usage_manifest_columns(), drop=FALSE]
  manifest$source_file = as.character(manifest$source_file)
  manifest$size = suppressWarnings(as.numeric(manifest$size))
  manifest$mtime = suppressWarnings(as.numeric(manifest$mtime))
  manifest$teacher_match =
    ullme_usage_normalize_logical(manifest$teacher_match)
  manifest$status = as.character(manifest$status)
  manifest$message = as.character(manifest$message)
  manifest$course_keys = as.character(manifest$course_keys)
  manifest$updated_at = as.character(manifest$updated_at)
  manifest
}


ullme_usage_write_csv = function(value, path) {
  directory = dirname(path)
  dir.create(directory, recursive=TRUE, showWarnings=FALSE)
  temporary = tempfile(
    paste0(".", basename(path), "-"),
    tmpdir=directory,
    fileext=".tmp"
  )
  utils::write.csv(
    value,
    temporary,
    row.names=FALSE,
    na=""
  )
  backup = paste0(path, ".previous")
  if (file.exists(backup) && !file.remove(backup)) {
    stop("Could not remove the previous statistics backup.")
  }
  if (file.exists(path) && !file.rename(path, backup)) {
    if (file.exists(temporary)) file.remove(temporary)
    stop("Could not prepare the previous statistics file for replacement.")
  }
  if (!file.rename(temporary, path)) {
    if (file.exists(backup)) file.rename(backup, path)
    if (file.exists(temporary)) file.remove(temporary)
    stop("Could not replace the statistics file.")
  }
  if (file.exists(backup) && !file.remove(backup)) {
    stop("Could not remove the previous statistics backup.")
  }
  invisible(path)
}


ullme_usage_lock_acquire = function(directory, stale_seconds=600) {
  dir.create(directory, recursive=TRUE, showWarnings=FALSE)
  lock = file.path(directory, ".aggregation-lock")
  if (dir.exists(lock)) {
    age = as.numeric(difftime(
      Sys.time(),
      file.info(lock)$mtime,
      units="secs"
    ))
    if (!is.na(age) && age > stale_seconds) {
      ullme_usage_lock_release(lock)
    }
  }
  if (!dir.create(lock, showWarnings=FALSE)) return(NULL)
  lock
}


ullme_usage_lock_release = function(lock) {
  if (!is.null(lock) && dir.exists(lock)) {
    ullme_remove_checked_directory(
      directory=lock,
      root=dirname(lock),
      expected_name=".aggregation-lock",
      label="usage statistics lock directory"
    )
  }
  invisible(TRUE)
}


ullme_usage_source_files = function(source_dir) {
  if (!dir.exists(source_dir)) return(character())
  sort(list.files(
    source_dir,
    pattern="^[A-Za-z0-9]{16}[.]csv$",
    full.names=TRUE
  ))
}


ullme_usage_file_record = function(path) {
  info = file.info(path)
  data.frame(
    source_file=basename(path),
    path=path,
    size=as.numeric(info$size),
    mtime=as.numeric(info$mtime),
    stringsAsFactors=FALSE
  )
}


ullme_usage_course_key = function(semester, courseid) {
  paste0(semester, "::", courseid)
}


ullme_usage_split_course_keys = function(value) {
  if (is.null(value) || !length(value) || is.na(value[[1]])) {
    return(character())
  }
  value = paste0(value[[1]])
  if (!nzchar(value)) return(character())
  unique(strsplit(value, ";", fixed=TRUE)[[1]])
}


ullme_usage_course_slug = function(course_key) {
  slug = gsub("[^A-Za-z0-9._-]+", "_", course_key)
  gsub("^_+|_+$", "", slug)
}


ullme_usage_cache_path = function(state, source_file) {
  file.path(state$cache_dir, source_file)
}


ullme_usage_course_path = function(state, course_key) {
  file.path(
    state$courses_dir,
    paste0(ullme_usage_course_slug(course_key), ".csv")
  )
}


ullme_usage_normalize_source = function(path, teacherid) {
  value = utils::read.csv(
    path,
    stringsAsFactors=FALSE,
    check.names=FALSE,
    na.strings=c("NA")
  )
  required = c("date", "teacherid", "courseid", "tutorid", "model")
  missing = setdiff(required, names(value))
  if (length(missing)) {
    stop("Missing columns: ", paste(missing, collapse=", "))
  }
  if (!"semester" %in% names(value)) value$semester = "unknown"
  if (!"error" %in% names(value)) value$error = ""
  for (name in c("input_token", "output_token", "thinking_token")) {
    if (!name %in% names(value)) value[[name]] = NA_real_
  }
  if (!"ttf_ms" %in% names(value)) {
    if ("seconds_until_output" %in% names(value)) {
      value$ttf_ms =
        suppressWarnings(as.numeric(value$seconds_until_output)) * 1000
    } else {
      value$ttf_ms = NA_real_
    }
  }
  if (!"total_sec" %in% names(value)) value$total_sec = NA_real_
  teacher = as.character(value$teacherid)
  keep = !is.na(teacher) & teacher == teacherid
  value = value[keep, , drop=FALSE]
  if (!NROW(value)) {
    return(data.frame(
      source_file=character(),
      day=character(),
      semester=character(),
      courseid=character(),
      tutorid=character(),
      model=character(),
      input_token=numeric(),
      output_token=numeric(),
      thinking_token=numeric(),
      ttf_ms=numeric(),
      total_sec=numeric(),
      error=character(),
      stringsAsFactors=FALSE
    ))
  }
  text_column = function(name, fallback="unknown") {
    result = as.character(value[[name]])
    result[is.na(result) | !nzchar(trimws(result))] = fallback
    result
  }
  day = substr(as.character(value$date), 1, 10)
  valid_day = grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", day)
  day[!valid_day] = "unknown"
  result = data.frame(
    source_file=basename(path),
    day=day,
    semester=text_column("semester"),
    courseid=text_column("courseid"),
    tutorid=text_column("tutorid"),
    model=text_column("model"),
    input_token=suppressWarnings(as.numeric(value$input_token)),
    output_token=suppressWarnings(as.numeric(value$output_token)),
    thinking_token=suppressWarnings(as.numeric(value$thinking_token)),
    ttf_ms=suppressWarnings(as.numeric(value$ttf_ms)),
    total_sec=suppressWarnings(as.numeric(value$total_sec)),
    error=as.character(value$error),
    stringsAsFactors=FALSE
  )
  result$error[is.na(result$error)] = ""
  result
}


ullme_usage_numeric_metrics = function() {
  c("input_token", "output_token", "thinking_token", "ttf_ms", "total_sec")
}


ullme_usage_aggregate_records = function(records) {
  if (is.null(records) || !NROW(records)) return(ullme_usage_empty_summary())
  dimensions = c(
    "day", "semester", "courseid", "tutorid", "model", "error"
  )
  for (name in dimensions) {
    records[[name]] = as.character(records[[name]])
    records[[name]][is.na(records[[name]])] = ""
  }
  group_key = do.call(
    paste,
    c(records[dimensions], list(sep="\034"))
  )
  groups = split(seq_len(NROW(records)), group_key)
  rows = lapply(groups, function(index) {
    first = records[index[[1]], , drop=FALSE]
    row = as.list(first[1, dimensions, drop=FALSE])
    row$requests = length(index)
    row$replies = sum(!nzchar(records$error[index]))
    row$errors = row$requests - row$replies
    row$sessions = length(unique(records$source_file[index]))
    for (name in ullme_usage_numeric_metrics()) {
      values = suppressWarnings(as.numeric(records[[name]][index]))
      observed = !is.na(values)
      row[[paste0(name, "_sum")]] =
        if (any(observed)) sum(values[observed]) else 0
      row[[paste0(name, "_n")]] = sum(observed)
    }
    as.data.frame(row, stringsAsFactors=FALSE)
  })
  result = do.call(rbind, rows)
  result = result[, ullme_usage_summary_columns(), drop=FALSE]
  numeric_columns = setdiff(names(result), dimensions)
  for (name in numeric_columns) {
    result[[name]] = suppressWarnings(as.numeric(result[[name]]))
  }
  order_index = do.call(order, result[dimensions])
  rownames(result) = NULL
  result[order_index, , drop=FALSE]
}


ullme_usage_manifest_upsert = function(manifest, record) {
  keep = manifest$source_file != record$source_file[[1]]
  manifest = manifest[keep, , drop=FALSE]
  result = rbind(manifest, record[, ullme_usage_manifest_columns(), drop=FALSE])
  result[order(result$source_file), , drop=FALSE]
}


ullme_usage_statistics_prepare = function(app=getApp()) {
  directory = ullme_usage_statistics_dir(app=app)
  lock = ullme_usage_lock_acquire(directory)
  if (is.null(lock)) {
    return(list(locked=TRUE, directory=directory))
  }
  source_dir = ullme_usage_source_dir(app=app)
  cache_dir = file.path(directory, "session_cache")
  courses_dir = file.path(directory, "courses")
  dir.create(cache_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(courses_dir, recursive=TRUE, showWarnings=FALSE)
  manifest = ullme_usage_read_manifest(directory)
  files = ullme_usage_source_files(source_dir)
  current = if (length(files)) {
    do.call(rbind, lapply(files, ullme_usage_file_record))
  } else {
    data.frame(
      source_file=character(),
      path=character(),
      size=numeric(),
      mtime=numeric(),
      stringsAsFactors=FALSE
    )
  }
  changed = vapply(seq_len(NROW(current)), function(i) {
    old = match(current$source_file[[i]], manifest$source_file)
    is.na(old) ||
      is.na(manifest$size[[old]]) ||
      is.na(manifest$mtime[[old]]) ||
      !identical(current$size[[i]], manifest$size[[old]]) ||
      abs(current$mtime[[i]] - manifest$mtime[[old]]) > 0.0001
  }, logical(1))
  deleted = setdiff(manifest$source_file, current$source_file)
  affected = unlist(lapply(deleted, function(source_file) {
    row = manifest[manifest$source_file == source_file, , drop=FALSE]
    ullme_usage_split_course_keys(row$course_keys[[1]])
  }), use.names=FALSE)
  state = new.env(parent=emptyenv())
  state$locked = FALSE
  state$lock = lock
  state$directory = directory
  state$cache_dir = cache_dir
  state$courses_dir = courses_dir
  state$teacherid = app$teacherid %||% app$userid
  state$manifest = manifest
  state$current = current
  state$changed = current[changed, , drop=FALSE]
  state$deleted = deleted
  state$affected = unique(affected)
  state$file_index = 0L
  state$course_index = 0L
  state$course_keys = character()
  state$errors = character()
  state$files_processed = 0L
  output_paths = file.path(
    directory,
    c("source_manifest.csv", "teacher_daily.csv", "teacher_totals.csv")
  )
  state$needs_rebuild = !all(file.exists(output_paths))
  expected_keys = unique(unlist(lapply(
    state$manifest$course_keys[state$manifest$teacher_match],
    ullme_usage_split_course_keys
  ), use.names=FALSE))
  missing_course = expected_keys[!file.exists(vapply(
    expected_keys,
    function(key) ullme_usage_course_path(state, key),
    character(1)
  ))]
  if (length(missing_course)) {
    state$needs_rebuild = TRUE
    state$affected = unique(c(state$affected, missing_course))
  }
  state
}


ullme_usage_statistics_process_file = function(state, record) {
  source_file = record$source_file[[1]]
  old = state$manifest[
    state$manifest$source_file == source_file,
    ,
    drop=FALSE
  ]
  old_keys = if (NROW(old)) {
    ullme_usage_split_course_keys(old$course_keys[[1]])
  } else {
    character()
  }
  result = tryCatch({
    rows = ullme_usage_normalize_source(
      record$path[[1]],
      teacherid=state$teacherid
    )
    after = ullme_usage_file_record(record$path[[1]])
    if (!identical(after$size[[1]], record$size[[1]]) ||
        abs(after$mtime[[1]] - record$mtime[[1]]) > 0.0001) {
      stop("The source file changed while it was being read.")
    }
    cache_path = ullme_usage_cache_path(state, source_file)
    if (NROW(rows)) {
      ullme_usage_write_csv(rows, cache_path)
    } else if (file.exists(cache_path)) {
      if (!file.remove(cache_path)) stop("Could not remove the usage cache file.")
    }
    new_keys = if (NROW(rows)) {
      unique(ullme_usage_course_key(rows$semester, rows$courseid))
    } else {
      character()
    }
    manifest_row = data.frame(
      source_file=source_file,
      size=record$size[[1]],
      mtime=record$mtime[[1]],
      teacher_match=length(new_keys) > 0,
      status="ok",
      message="",
      course_keys=paste(new_keys, collapse=";"),
      updated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
      stringsAsFactors=FALSE
    )
    state$manifest = ullme_usage_manifest_upsert(
      state$manifest,
      manifest_row
    )
    state$affected = unique(c(state$affected, old_keys, new_keys))
    TRUE
  }, error=function(e) {
    state$errors = c(
      state$errors,
      paste0(source_file, ": ", conditionMessage(e))
    )
    FALSE
  })
  state$files_processed = state$files_processed + 1L
  invisible(result)
}


ullme_usage_statistics_process_file_batch = function(state, batch_size=25L) {
  count = NROW(state$changed)
  if (state$file_index >= count) return(FALSE)
  indexes = seq.int(
    state$file_index + 1L,
    min(count, state$file_index + as.integer(batch_size))
  )
  for (i in indexes) {
    ullme_usage_statistics_process_file(
      state,
      state$changed[i, , drop=FALSE]
    )
  }
  state$file_index = max(indexes)
  state$file_index < count
}


ullme_usage_statistics_prepare_courses = function(state) {
  for (source_file in state$deleted) {
    cache_path = ullme_usage_cache_path(state, source_file)
    if (file.exists(cache_path) && !file.remove(cache_path)) {
      stop("Could not remove the usage cache file.")
    }
  }
  if (length(state$deleted)) {
    state$manifest = state$manifest[
      !state$manifest$source_file %in% state$deleted,
      ,
      drop=FALSE
    ]
  }
  valid_keys = unique(unlist(lapply(
    state$manifest$course_keys[state$manifest$teacher_match],
    ullme_usage_split_course_keys
  ), use.names=FALSE))
  valid_files = if (length(valid_keys)) {
    basename(vapply(
      valid_keys,
      function(key) ullme_usage_course_path(state, key),
      character(1)
    ))
  } else {
    character()
  }
  existing_files = list.files(
    state$courses_dir,
    pattern="[.]csv$",
    full.names=TRUE
  )
  orphaned = existing_files[!basename(existing_files) %in% valid_files]
  if (length(orphaned) && any(!file.remove(orphaned))) {
    stop("Could not remove an orphaned usage course file.")
  }
  state$course_keys = sort(unique(state$affected[nzchar(state$affected)]))
  state$course_index = 0L
  invisible(state$course_keys)
}


ullme_usage_statistics_rebuild_course = function(state, course_key) {
  matching = vapply(state$manifest$course_keys, function(value) {
    course_key %in% ullme_usage_split_course_keys(value)
  }, logical(1))
  sources = state$manifest$source_file[matching & state$manifest$teacher_match]
  records = lapply(sources, function(source_file) {
    ullme_usage_read_csv(
      ullme_usage_cache_path(state, source_file),
      NULL
    )
  })
  records = Filter(function(value) !is.null(value) && NROW(value), records)
  if (length(records)) {
    records = do.call(rbind, records)
    key = ullme_usage_course_key(records$semester, records$courseid)
    records = records[key == course_key, , drop=FALSE]
  } else {
    records = NULL
  }
  path = ullme_usage_course_path(state, course_key)
  if (is.null(records) || !NROW(records)) {
    if (file.exists(path) && !file.remove(path)) {
      stop("Could not remove the usage course file.")
    }
    return(invisible(FALSE))
  }
  ullme_usage_write_csv(ullme_usage_aggregate_records(records), path)
  invisible(TRUE)
}


ullme_usage_statistics_process_course_batch = function(state, batch_size=5L) {
  count = length(state$course_keys)
  if (state$course_index >= count) return(FALSE)
  indexes = seq.int(
    state$course_index + 1L,
    min(count, state$course_index + as.integer(batch_size))
  )
  for (i in indexes) {
    ullme_usage_statistics_rebuild_course(
      state,
      state$course_keys[[i]]
    )
  }
  state$course_index = max(indexes)
  state$course_index < count
}


ullme_usage_statistics_totals = function(summary, manifest) {
  numeric_sum = function(name) {
    if (!NROW(summary) || !name %in% names(summary)) return(0)
    sum(suppressWarnings(as.numeric(summary[[name]])), na.rm=TRUE)
  }
  ratio = function(sum_name, n_name) {
    count = numeric_sum(n_name)
    if (count <= 0) return(NA_real_)
    numeric_sum(sum_name) / count
  }
  data.frame(
    updated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
    sessions=sum(manifest$teacher_match, na.rm=TRUE),
    requests=numeric_sum("requests"),
    replies=numeric_sum("replies"),
    errors=numeric_sum("errors"),
    input_tokens=numeric_sum("input_token_sum"),
    output_tokens=numeric_sum("output_token_sum"),
    thinking_tokens=numeric_sum("thinking_token_sum"),
    average_ttf_ms=ratio("ttf_ms_sum", "ttf_ms_n"),
    average_total_sec=ratio("total_sec_sum", "total_sec_n"),
    stringsAsFactors=FALSE
  )
}


ullme_usage_statistics_finalize = function(state) {
  course_files = if (dir.exists(state$courses_dir)) {
    list.files(
      state$courses_dir,
      pattern="[.]csv$",
      full.names=TRUE
    )
  } else {
    character()
  }
  summaries = lapply(course_files, function(path) {
    ullme_usage_read_csv(path, NULL)
  })
  summaries = Filter(function(value) !is.null(value) && NROW(value), summaries)
  teacher_daily = if (length(summaries)) {
    result = do.call(rbind, summaries)
    result = result[, ullme_usage_summary_columns(), drop=FALSE]
    rownames(result) = NULL
    result
  } else {
    ullme_usage_empty_summary()
  }
  ullme_usage_write_csv(
    teacher_daily,
    file.path(state$directory, "teacher_daily.csv")
  )
  ullme_usage_write_csv(
    ullme_usage_statistics_totals(teacher_daily, state$manifest),
    file.path(state$directory, "teacher_totals.csv")
  )
  # Commit the source fingerprints last. If an earlier write is interrupted,
  # the old manifest causes the same source files to be processed again.
  ullme_usage_write_csv(
    state$manifest,
    file.path(state$directory, "source_manifest.csv")
  )
  list(
    changed=NROW(state$changed),
    deleted=length(state$deleted),
    errors=state$errors
  )
}


ullme_usage_statistics_update = function(app=getApp()) {
  state = ullme_usage_statistics_prepare(app=app)
  if (isTRUE(state$locked)) {
    return(list(
      status="locked",
      changed=0L,
      deleted=0L,
      errors=character()
    ))
  }
  on.exit(ullme_usage_lock_release(state$lock), add=TRUE)
  if (!NROW(state$changed) &&
      !length(state$deleted) &&
      !isTRUE(state$needs_rebuild)) {
    return(list(
      status="ready",
      changed=0L,
      deleted=0L,
      errors=character()
    ))
  }
  while (ullme_usage_statistics_process_file_batch(state, 100L)) {
    invisible(NULL)
  }
  ullme_usage_statistics_prepare_courses(state)
  while (ullme_usage_statistics_process_course_batch(state, 100L)) {
    invisible(NULL)
  }
  result = ullme_usage_statistics_finalize(state)
  result$status = "ready"
  result
}


ullme_usage_statistics_records_for_js = function(value) {
  if (is.null(value) || !NROW(value)) return(list())
  lapply(seq_len(NROW(value)), function(i) {
    as.list(value[i, , drop=FALSE])
  })
}


ullme_usage_statistics_payload = function(app=getApp(), status="ready",
                                           message="") {
  directory = ullme_usage_statistics_dir(app=app)
  daily = ullme_usage_read_csv(
    file.path(directory, "teacher_daily.csv"),
    ullme_usage_empty_summary()
  )
  totals = ullme_usage_read_csv(
    file.path(directory, "teacher_totals.csv"),
    data.frame()
  )
  totals = if (NROW(totals)) as.list(totals[1, , drop=FALSE]) else list(
    updated_at="",
    sessions=0,
    requests=0,
    replies=0,
    errors=0,
    input_tokens=0,
    output_tokens=0,
    thinking_tokens=0,
    average_ttf_ms=NA_real_,
    average_total_sec=NA_real_
  )
  list(
    status=status,
    message=paste0(message %||% "")[1],
    totals=totals,
    records=ullme_usage_statistics_records_for_js(daily)
  )
}


ullme_send_usage_statistics = function(app=getApp(), status="ready",
                                        message="") {
  callJS(
    .fun="window.ullme.updateUsageStatistics",
    .args=list(ullme_usage_statistics_payload(
      app=app,
      status=status,
      message=message
    )),
    .app=app
  )
  invisible(TRUE)
}


ullme_send_usage_statistics_status = function(app=getApp(),
                                               status="updating",
                                               message="") {
  callJS(
    .fun="window.ullme.updateUsageStatistics",
    .args=list(list(
      status=status,
      message=paste0(message %||% "")[1]
    )),
    .app=app
  )
  invisible(TRUE)
}


ullme_usage_statistics_start_async = function(app=getApp()) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  if (isTRUE(app$usage_statistics_running)) {
    ullme_send_usage_statistics_status(
      app=app,
      status="updating",
      message="Usage statistics are already updating."
    )
    return(invisible(FALSE))
  }
  state = ullme_usage_statistics_prepare(app=app)
  if (isTRUE(state$locked)) {
    ullme_send_usage_statistics_status(
      app=app,
      status="updating",
      message="Another teacher session is updating the statistics."
    )
    return(invisible(FALSE))
  }
  if (!NROW(state$changed) &&
      !length(state$deleted) &&
      !isTRUE(state$needs_rebuild)) {
    ullme_usage_lock_release(state$lock)
    ullme_send_usage_statistics(
      app=app,
      status="ready",
      message="Usage statistics are up to date."
    )
    return(invisible(TRUE))
  }
  app$usage_statistics_running = TRUE
  runner = new.env(parent=emptyenv())
  runner$finish_error = function(error) {
    ullme_usage_lock_release(state$lock)
    app$usage_statistics_running = FALSE
    ullme_send_usage_statistics_status(
      app=app,
      status="error",
      message=conditionMessage(error)
    )
    invisible(FALSE)
  }
  runner$step = function() {
    tryCatch({
      if (state$file_index < NROW(state$changed)) {
        ullme_usage_statistics_process_file_batch(state, 25L)
        ullme_send_usage_statistics_status(
          app=app,
          status="updating",
          message=paste0(
            "Reading changed sessions ",
            state$file_index,
            " / ",
            NROW(state$changed),
            "\u2026"
          )
        )
        later::later(runner$step, delay=0.01)
        return(invisible(NULL))
      }
      if (!length(state$course_keys) && state$course_index == 0L) {
        ullme_usage_statistics_prepare_courses(state)
      }
      if (state$course_index < length(state$course_keys)) {
        ullme_usage_statistics_process_course_batch(state, 5L)
        ullme_send_usage_statistics_status(
          app=app,
          status="updating",
          message=paste0(
            "Updating course summaries ",
            state$course_index,
            " / ",
            length(state$course_keys),
            "\u2026"
          )
        )
        later::later(runner$step, delay=0.01)
        return(invisible(NULL))
      }
      result = ullme_usage_statistics_finalize(state)
      ullme_usage_lock_release(state$lock)
      app$usage_statistics_running = FALSE
      message = paste0(
        "Updated ",
        result$changed,
        " changed session",
        if (result$changed == 1L) "" else "s",
        if (result$deleted) paste0(
          "; removed ", result$deleted, " deleted session",
          if (result$deleted == 1L) "" else "s"
        ) else "",
        if (length(result$errors)) paste0(
          "; ", length(result$errors), " file",
          if (length(result$errors) == 1L) "" else "s",
          " will be retried"
        ) else "",
        "."
      )
      ullme_send_usage_statistics(
        app=app,
        status=if (length(result$errors)) "warning" else "ready",
        message=message
      )
      invisible(TRUE)
    }, error=runner$finish_error)
  }
  ullme_send_usage_statistics_status(
    app=app,
    status="updating",
    message="Checking for new usage sessions\u2026"
  )
  later::later(runner$step, delay=0.01)
  invisible(TRUE)
}


ullme_init_teacher_usage_statistics = function(app=getApp()) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  app$usage_statistics_running = FALSE
  ullme_send_usage_statistics(
    app=app,
    status="cached",
    message="Showing cached statistics while checking for updates\u2026"
  )
  later::later(
    function() ullme_usage_statistics_start_async(app=app),
    delay=0.05
  )
  invisible(TRUE)
}


ullme_handle_usage_statistics_refresh = function(app=getApp(), ...) {
  ullme_usage_statistics_start_async(app=app)
}


ullme_usage_statistics_ui = function(app=getApp()) {
  tags$section(
    id="ullme_usage_statistics_panel",
    class=paste(
      "ullme-usage-statistics",
      "ullme-course-content-panel",
      "ullme-course-content-panel-active"
    ),
    `data-course-panel`="usage",
    tags$div(
      class="ullme-usage-dashboard",
      tags$header(
        class="ullme-usage-header",
        tags$div(
          tags$h1("Usage statistics"),
          tags$p(
            "Anonymous Tutor usage across all of your courses and semesters."
          )
        ),
        tags$div(
          class="ullme-usage-header-actions",
          tags$span(
            id="ullme_usage_status",
            class="ullme-usage-status",
            "Loading cached statistics\u2026"
          ),
          tags$button(
            id="ullme_usage_refresh_btn",
            class="ullme-secondary-action",
            type="button",
            "Refresh"
          )
        )
      ),
      tags$div(
        class="ullme-usage-filters",
        tags$label(
          tags$span("Period"),
          tags$select(
            id="ullme_usage_period",
            tags$option(value="all", "All time"),
            tags$option(value="7", "Last 7 days"),
            tags$option(value="30", "Last 30 days"),
            tags$option(value="90", "Last 90 days")
          )
        ),
        tags$label(
          tags$span("Course"),
          tags$select(
            id="ullme_usage_course_filter",
            tags$option(value="", "All courses")
          )
        ),
        tags$label(
          tags$span("Tutor"),
          tags$select(
            id="ullme_usage_tutor_filter",
            tags$option(value="", "All Tutors")
          )
        ),
        tags$label(
          tags$span("Model"),
          tags$select(
            id="ullme_usage_model_filter",
            tags$option(value="", "All models")
          )
        )
      ),
      tags$div(id="ullme_usage_cards", class="ullme-usage-cards"),
      tags$div(
        id="ullme_usage_empty",
        class="ullme-usage-empty",
        "No student usage has been recorded yet."
      ),
      tags$div(
        id="ullme_usage_content",
        class="ullme-usage-content",
        tags$section(
          class="ullme-usage-chart-card ullme-usage-chart-card-wide",
          tags$div(
            class="ullme-usage-card-heading",
            tags$h2("Daily requests"),
            tags$span("Hover for details")
          ),
          tags$div(
            id="ullme_usage_daily_chart",
            class="ullme-usage-daily-chart"
          )
        ),
        tags$div(
          class="ullme-usage-chart-grid",
          tags$section(
            class="ullme-usage-chart-card",
            tags$h2("Courses"),
            tags$div(
              id="ullme_usage_course_chart",
              class="ullme-usage-breakdown"
            )
          ),
          tags$section(
            class="ullme-usage-chart-card",
            tags$h2("Models"),
            tags$div(
              id="ullme_usage_model_chart",
              class="ullme-usage-breakdown"
            )
          ),
          tags$section(
            class="ullme-usage-chart-card",
            tags$h2("Tutors"),
            tags$div(
              id="ullme_usage_tutor_chart",
              class="ullme-usage-breakdown"
            )
          ),
          tags$section(
            class="ullme-usage-chart-card",
            tags$h2("Errors"),
            tags$div(
              id="ullme_usage_error_chart",
              class="ullme-usage-breakdown"
            )
          )
        )
      )
    )
  )
}
