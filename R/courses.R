ullme_semester = function(date=Sys.Date()) {
  restore.point("ullme_semester")
  date = as.Date(date)
  year = as.integer(format(date, "%Y"))
  month = as.integer(format(date, "%m"))

  if (month >= 4 && month <= 9) {
    return(sprintf("SS%02d", year %% 100))
  }
  if (month >= 10) {
    return(sprintf("WS%02d%02d", year %% 100, (year + 1) %% 100))
  }
  sprintf("WS%02d%02d", (year - 1) %% 100, year %% 100)
}


ullme_semester_sequence = function(center=ullme_semester(), before=3, after=4) {
  restore.point("ullme_semester_sequence")
  center_index = ullme_semester_index(center)
  indexes = seq.int(center_index - before, center_index + after)
  vapply(indexes, ullme_semester_from_index, character(1), USE.NAMES=FALSE)
}


ullme_semester_index = function(semester) {
  restore.point("ullme_semester_index")
  semester = toupper(paste0(semester)[1])
  if (grepl("^SS[0-9]{2}$", semester)) {
    year = as.integer(substr(semester, 3, 4))
    return(year * 2)
  }
  if (grepl("^WS[0-9]{4}$", semester)) {
    year = as.integer(substr(semester, 3, 4))
    return(year * 2 + 1)
  }
  stop("semester must use abbreviations like SS25 or WS2526.")
}


ullme_semester_from_index = function(index) {
  restore.point("ullme_semester_from_index")
  year = index %/% 2
  if (index %% 2 == 0) {
    return(sprintf("SS%02d", year %% 100))
  }
  sprintf("WS%02d%02d", year %% 100, (year + 1) %% 100)
}


ullme_courses_dir = function(main_dir, userid, role, semester) {
  restore.point("ullme_courses_dir")
  role = ullme_normalize_role(role)
  if (!role %in% c("teacher", "student")) return(character(0))
  file.path(ullme_role_user_dir(main_dir=main_dir, userid=userid, role=role), "courses", semester)
}


ullme_user_courseids = function(main_dir, userid, role, semester) {
  restore.point("ullme_user_courseids")
  course_dir = ullme_courses_dir(
    main_dir=main_dir,
    userid=userid,
    role=role,
    semester=semester
  )
  if (length(course_dir) == 0 || !dir.exists(course_dir)) return(character(0))

  entries = list.files(course_dir, full.names=TRUE, no..=TRUE)
  entries = entries[dir.exists(entries)]
  sort(basename(entries))
}


ullme_course_dir = function(main_dir, userid, role, semester, courseid) {
  restore.point("ullme_course_dir")
  courseid = ullme_clean_courseid(courseid)
  file.path(
    ullme_courses_dir(main_dir=main_dir, userid=userid, role=role, semester=semester),
    courseid
  )
}


ullme_clean_courseid = function(courseid) {
  restore.point("ullme_clean_courseid")
  courseid = paste0(courseid)[1]
  courseid = gsub("[^A-Za-z0-9_-]+", "_", courseid)
  courseid = gsub("^_+|_+$", "", courseid)
  if (!nzchar(courseid)) stop("courseid must not be empty.")
  if (!grepl("^[A-Za-z][A-Za-z0-9_-]*$", courseid)) {
    stop("courseid must start with a letter and contain only letters, numbers, underscores, or hyphens.")
  }
  courseid
}


ullme_course_material_categories = function() {
  restore.point("ullme_course_material_categories")
  c("general", "slides", "ps", "quiz", "background")
}


ullme_course_material_dir = function(course_dir, category) {
  restore.point("ullme_course_material_dir")
  category = paste0(category)[1]
  if (!category %in% ullme_course_material_categories()) stop("Invalid material category.")
  file.path(course_dir, "materials", category)
}


ullme_init_course_material_dirs = function(course_dir, app=NULL) {
  restore.point("ullme_init_course_material_dirs")
  categories = ullme_course_material_categories()
  legacy_changes = list()
  for (category in categories) {
    target_dir = ullme_course_material_dir(course_dir=course_dir, category=category)
    dir.create(target_dir, recursive=TRUE, showWarnings=FALSE)

    legacy_dir = file.path(course_dir, category)
    if (!dir.exists(legacy_dir)) next
    files = list.files(legacy_dir, recursive=TRUE, full.names=FALSE, no..=TRUE)
    files = files[!dir.exists(file.path(legacy_dir, files))]
    for (file in files) {
      target = file.path(target_dir, file)
      dir.create(dirname(target), recursive=TRUE, showWarnings=FALSE)
      if (!file.exists(target)) {
        source = file.path(legacy_dir, file)
        if (!is.null(app) && identical(app$role, "teacher")) {
          legacy_changes[[length(legacy_changes) + 1L]] =
            ullme_change_copy(source, target, overwrite=FALSE)
        } else {
          file.copy(source, target)
        }
      }
    }
  }
  if (length(legacy_changes) > 0) {
    operation = ullme_new_change(
      action="material_migration",
      summary=paste0("Migrate ", length(legacy_changes), " legacy material file",
                     if (length(legacy_changes) == 1) "" else "s"),
      origin="ui",
      changes=legacy_changes,
      app=app
    )
    ullme_submit_change(operation, app=app)
  }
  invisible(file.path(course_dir, "materials"))
}


ullme_course_yaml_path = function(course_dir) {
  restore.point("ullme_course_yaml_path")
  file.path(course_dir, "course.yaml")
}


ullme_default_course = function(courseid="", coursename="") {
  restore.point("ullme_default_course")
  list(
    courseid = paste0(courseid)[1],
    coursename = paste0(coursename)[1],
    times = list()
  )
}


ullme_make_course = function(main_dir, userid, role, semester, courseid, coursename="") {
  restore.point("ullme_make_course")
  courseid = ullme_clean_courseid(courseid)
  course_dir = ullme_course_dir(
    main_dir=main_dir,
    userid=userid,
    role=role,
    semester=semester,
    courseid=courseid
  )
  dir.create(course_dir, recursive=TRUE, showWarnings=FALSE)
  ullme_init_course_material_dirs(course_dir=course_dir)
  course = ullme_default_course(courseid=courseid, coursename=coursename)
  if (!file.exists(ullme_course_yaml_path(course_dir))) {
    ullme_write_course_yaml(course_dir=course_dir, course=course)
  }
  invisible(course_dir)
}


ullme_read_course_yaml = function(course_dir) {
  restore.point("ullme_read_course_yaml")
  path = ullme_course_yaml_path(course_dir)
  if (!file.exists(path)) return(ullme_default_course())
  ullme_require_yaml()
  course = yaml::read_yaml(path)
  ullme_normalize_course(course)
}


ullme_write_course_yaml = function(course_dir, course) {
  restore.point("ullme_write_course_yaml")
  ullme_require_yaml()
  course = ullme_normalize_course(course)
  yaml::write_yaml(course, ullme_course_yaml_path(course_dir))
  invisible(course)
}


ullme_normalize_course = function(course) {
  restore.point("ullme_normalize_course")
  if (is.null(course)) course = list()
  course$courseid = paste0(course$courseid %||% "")[1]
  course$coursename = paste0(course$coursename %||% "")[1]
  times = course$times
  if (is.null(times)) times = list()
  if (is.data.frame(times)) times = split(times, seq_len(NROW(times)))
  times = lapply(times, function(time) {
    list(
      weekday = paste0(time$weekday %||% "")[1],
      start = paste0(time$start %||% "")[1],
      end = paste0(time$end %||% "")[1]
    )
  })
  course$times = times[seq_len(min(length(times), 3))]
  course
}


`%||%` = function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}


ullme_require_yaml = function() {
  restore.point("ullme_require_yaml")
  if (!requireNamespace("yaml", quietly=TRUE)) {
    stop("Package 'yaml' is required for course.yaml files.")
  }
  invisible(TRUE)
}


ullme_course_summary = function(app) {
  restore.point("ullme_course_summary")
  if (is.null(app$courseid) || !nzchar(app$courseid)) return(NULL)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir) || !dir.exists(course_dir)) return(NULL)
  if (identical(app$role, "teacher")) {
    ullme_init_course_material_dirs(course_dir=course_dir, app=app)
  }
  list(
    course = ullme_read_course_yaml(course_dir),
    material = ullme_course_material_files(course_dir)
  )
}


ullme_course_material_files = function(course_dir) {
  restore.point("ullme_course_material_files")
  categories = ullme_course_material_categories()
  names(categories) = categories
  lapply(categories, function(category) {
    dir = ullme_course_material_dir(course_dir=course_dir, category=category)
    if (!dir.exists(dir)) return(character(0))
    files = list.files(dir, recursive=TRUE, full.names=FALSE, no..=TRUE)
    paths = file.path(dir, files)
    files = files[file.exists(paths) & !dir.exists(paths)]
    sort(gsub("\\\\", "/", files))
  })
}


ullme_save_course_settings = function(app, course) {
  restore.point("ullme_save_course_settings")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(NULL)
  course$courseid = app$courseid
  course = ullme_normalize_course(course)
  content = trimws(yaml::as.yaml(course))
  if (!identical(app$role, "teacher")) {
    return(ullme_write_course_yaml(course_dir=course_dir, course=course))
  }
  validation = ullme_validate_course_yaml(content)
  ullme_validation_stop(validation)
  operation = ullme_new_change(
    action="course_settings",
    summary=paste0("Update settings for course ", app$courseid),
    origin="ui",
    details=list(courseid=app$courseid),
    changes=list(ullme_change_write(ullme_course_yaml_path(course_dir), content)),
    app=app
  )
  ullme_submit_change(operation, app=app)
}


ullme_active_course_dir = function(app=getApp()) {
  restore.point("ullme_active_course_dir")
  if (is.null(app$courseid) || !nzchar(app$courseid)) return(NULL)
  course_dir = ullme_course_dir(
    main_dir=app$glob$main_dir,
    userid=app$userid,
    role=app$role,
    semester=app$semester,
    courseid=app$courseid
  )
  if (!dir.exists(course_dir)) return(NULL)
  course_dir
}


ullme_store_material_uploads = function(app, value, category,
                                         destination=category) {
  restore.point("ullme_store_material_uploads")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir) || is.null(value) || NROW(value) == 0) return(character(0))
  material_dir = file.path(course_dir, "materials")
  destination = .ullme_material_relative_path(destination)
  destination_category = strsplit(destination, "/", fixed=TRUE)[[1]][[1]]
  if (!identical(destination_category, category)) {
    stop("The upload destination does not match its material category.")
  }
  target_dir = .ullme_material_path(
    material_dir,
    destination,
    must_exist=TRUE
  )
  if (!dir.exists(target_dir)) stop("The upload destination is not a directory.")
  upload_tree = app$material_upload_tree
  tree_files = if (
    is.list(upload_tree) &&
    identical(upload_tree$destination, destination)
  ) upload_tree$files else character(0)

  if (identical(app$role, "teacher")) {
    stage = ullme_tempdir(pattern=".ullme-material-upload-", app=app)
    on.exit(ullme_remove_tempdir(stage, app=app), add=TRUE)
    changes = list()
    stored = character(0)
    for (i in seq_len(NROW(value))) {
      upload_name = basename(value$name[[i]])
      name = if (upload_name %in% names(tree_files)) {
        unname(tree_files[[upload_name]])
      } else {
        ullme_clean_file_name(upload_name)
      }
      source = value$datapath[[i]]
      relative_target = paste(destination, name, sep="/")
      if (tolower(tools::file_ext(name)) == "zip") {
        extract_dir = file.path(stage, paste0("zip_", i))
        dir.create(extract_dir, recursive=TRUE, showWarnings=FALSE)
        entries = ullme_unzip_material(source=source, target_dir=extract_dir)
        for (entry in entries) {
          from = file.path(extract_dir, entry)
          if (!file.exists(from) || dir.exists(from)) next
          entry_target = paste(dirname(relative_target), entry, sep="/")
          changes[[length(changes) + 1L]] = ullme_change_copy(
            from,
            .ullme_material_path(material_dir, entry_target),
            overwrite=TRUE
          )
          stored = c(stored, sub(paste0("^", destination, "/"), "", entry_target))
        }
      } else {
        changes[[length(changes) + 1L]] = ullme_change_copy(
          source,
          .ullme_material_path(material_dir, relative_target),
          overwrite=TRUE
        )
        stored = c(stored, name)
      }
    }
    if (length(changes) == 0) return(character(0))
    operation = ullme_new_change(
      action="material_upload",
      summary=paste0("Upload ", length(changes), " material file",
                     if (length(changes) == 1) "" else "s", " to ", category),
      origin="ui",
      details=list(
        courseid=app$courseid,
        category=category,
        destination=destination
      ),
      changes=changes,
      app=app
    )
    result = ullme_submit_change(operation, app=app)
    if (!isTRUE(result$ok)) stop(result$message %||% "Could not store uploaded materials.")
    return(invisible(stored))
  }

  stored = character(0)
  for (i in seq_len(NROW(value))) {
    upload_name = basename(value$name[[i]])
    name = if (upload_name %in% names(tree_files)) {
      unname(tree_files[[upload_name]])
    } else {
      ullme_clean_file_name(upload_name)
    }
    source = value$datapath[[i]]
    relative_target = paste(destination, name, sep="/")
    target = .ullme_material_path(material_dir, relative_target)
    dir.create(dirname(target), recursive=TRUE, showWarnings=FALSE)
    if (tolower(tools::file_ext(name)) == "zip") {
      entries = ullme_unzip_material(source=source, target_dir=dirname(target))
      stored = c(stored, file.path(dirname(name), entries))
    } else {
      file.copy(source, target, overwrite=TRUE)
      stored = c(stored, name)
    }
  }
  invisible(stored)
}


ullme_unzip_material = function(source, target_dir) {
  restore.point("ullme_unzip_material")
  entries = utils::unzip(source, list=TRUE)$Name
  entries = gsub("\\\\", "/", entries)
  unsafe = grepl("^/|^[A-Za-z]:|(^|/)\\.\\.(/|$)", entries)
  if (any(unsafe)) stop("ZIP contains unsafe paths.")
  utils::unzip(source, exdir=target_dir)
  entries[!grepl("/$", entries)]
}


ullme_delete_material_file = function(app, category, path) {
  restore.point("ullme_delete_material_file")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(FALSE)
  category = paste0(category)[1]
  if (is.na(category) || !category %in% ullme_course_material_categories()) return(FALSE)
  relative = gsub("\\\\", "/", file.path(category, paste0(path)[1]))
  tryCatch(
    delete_material_file(relative, app=app),
    error=function(e) FALSE
  )
}


ullme_create_teacher_course = function(courseid, coursename="", times=NULL,
                                        app=getApp()) {
  courseid = ullme_clean_courseid(courseid)
  target = ullme_course_dir(
    main_dir=app$glob$main_dir,
    userid=app$userid,
    role="teacher",
    semester=app$semester,
    courseid=courseid
  )
  if (dir.exists(target) || file.exists(target)) stop("A course with this ID already exists.")

  stage = ullme_tempdir(pattern=".ullme-course-create-", app=app)
  on.exit(ullme_remove_tempdir(stage, app=app), add=TRUE)
  ullme_init_course_material_dirs(stage)
  course = ullme_normalize_course(list(
    courseid=courseid,
    coursename=paste0(coursename)[1],
    times=times
  ))
  content = trimws(yaml::as.yaml(course))
  ullme_validation_stop(ullme_validate_course_yaml(content))
  writeLines(content, ullme_course_yaml_path(stage), useBytes=TRUE)

  operation = ullme_new_change(
    action="course_create",
    summary=paste0("Create course ", courseid),
    origin="ui",
    details=list(courseid=courseid, semester=app$semester),
    changes=list(ullme_change_copy(stage, target, overwrite=FALSE)),
    app=app
  )
  ullme_submit_change(operation, app=app)
}


ullme_selected_courseid = function(courseids, preferred=NULL) {
  restore.point("ullme_selected_courseid")
  courseids = paste0(courseids)
  preferred = paste0(preferred)[1]
  if (is.na(preferred)) preferred = ""
  if (length(courseids) == 0) return("")
  if (nzchar(preferred) && preferred %in% courseids) {
    return(preferred)
  }
  courseids[[1]]
}
