ullme_student_tool_registry = function() {
  list(
    list_allowed_files=list(
      description=paste(
        "List the course files and directories exposed to this Tutor.",
        "Each permission reports whether reading and writing are allowed."
      )
    ),
    read_allowed_files=list(
      description=paste(
        "Read one text file exposed to this Tutor.",
        "Use list_allowed_files to discover paths and access permissions first."
      ),
      arguments=list(
        path=list(
          type="string",
          description="File path returned by list_allowed_files.",
          required=TRUE
        )
      )
    )
  )
}

ullme_student_file_permissions = function(app=getApp()) {
  tutor = ullme_student_selected_tutor(app=app)
  if (is.null(tutor)) return(list())
  ullme_normalize_tutor_file_permissions(tutor$file_permissions)
}


ullme_student_permission_roots = function(app=getApp()) {
  course_dir = ullme_student_course_dir(app=app)
  if (is.null(course_dir)) return(list())
  permissions = ullme_student_file_permissions(app=app)
  roots = list()
  for (permission in permissions) {
    main_path = permission$main_path %||% ""
    for (directory in unlist(
      permission$directories %||% list(),
      use.names=FALSE
    )) {
      relative = gsub(
        "\\\\", "/",
        file.path(main_path, directory)
      )
      target = normalizePath(
        file.path(course_dir, relative),
        winslash="/",
        mustWork=FALSE
      )
      course_root = normalizePath(course_dir, winslash="/", mustWork=TRUE)
      if (!ullme_path_is_within(target, course_root, allow_root=FALSE)) next
      roots[[length(roots) + 1L]] = list(
        type=permission$type,
        can_read=permission$type %in% c(
          "read_only", "write_and_read", "read_and_write"
        ),
        can_write=permission$type %in% c(
          "write_and_read", "read_and_write"
        ),
        recursive=isTRUE(permission$recursive),
        extensions=tolower(paste0(unlist(
          permission$extensions %||% list(),
          use.names=FALSE
        ))),
        relative_path=relative,
        target=target,
        course_root=course_root
      )
    }
  }
  roots
}


ullme_student_allowed_file = function(path, require_read=TRUE,
                                       app=getApp()) {
  path = gsub("\\\\", "/", trimws(paste0(path %||% "")[1]))
  if (!ullme_safe_relative_material_path(path)) {
    stop("The requested file path is not a safe relative path.")
  }
  course_dir = ullme_student_course_dir(app=app)
  target = normalizePath(
    file.path(course_dir, path),
    winslash="/",
    mustWork=FALSE
  )
  roots = ullme_student_permission_roots(app=app)
  matches = Filter(function(root) {
    relative_below_root = substring(
      target,
      nchar(root$target) + 2L
    )
    below = ullme_path_is_within(target, root$target, allow_root=FALSE)
    depth_ok = isTRUE(root$recursive) ||
      (!grepl("/", relative_below_root, fixed=TRUE))
    extension = tolower(tools::file_ext(target))
    extension_ok = !length(root$extensions) ||
      extension %in% root$extensions
    below && depth_ok && extension_ok &&
      (!isTRUE(require_read) || isTRUE(root$can_read))
  }, roots)
  if (!length(matches)) {
    stop("This Tutor does not have permission to read that file.")
  }
  if (!file.exists(target) || dir.exists(target)) {
    stop("The requested allowed file does not exist.")
  }
  list(path=path, target=target, permission=matches[[1]])
}


utool_list_allowed_files = function(app=getApp()) {
  roots = ullme_student_permission_roots(app=app)
  permissions = lapply(roots, function(root) {
    files = character(0)
    if (dir.exists(root$target)) {
      candidates = list.files(
        root$target,
        recursive=isTRUE(root$recursive),
        full.names=TRUE,
        include.dirs=FALSE,
        no..=TRUE
      )
      if (length(candidates)) {
        normalized = vapply(
          candidates,
          normalizePath,
          character(1),
          winslash="/",
          mustWork=FALSE
        )
        keep = vapply(
          normalized,
          ullme_path_is_within,
          logical(1),
          root=root$target,
          allow_root=FALSE
        )
        candidates = candidates[keep]
        extensions = tolower(tools::file_ext(candidates))
        if (length(root$extensions)) {
          candidates = candidates[extensions %in% root$extensions]
        }
        files = gsub(
          "\\\\", "/",
          substring(
            normalizePath(
              candidates,
              winslash="/",
              mustWork=FALSE
            ),
            nchar(root$course_root) + 2L
          )
        )
      }
    }
    list(
      directory=root$relative_path,
      can_read=isTRUE(root$can_read),
      can_write=isTRUE(root$can_write),
      recursive=isTRUE(root$recursive),
      extensions=as.list(root$extensions),
      files=as.list(sort(files))
    )
  })
  list(ok=TRUE, permissions=permissions)
}


utool_read_allowed_files = function(path, app=getApp()) {
  allowed = ullme_student_allowed_file(path, require_read=TRUE, app=app)
  size = unname(file.info(allowed$target)$size)
  if (is.na(size) || size > 2 * 1024^2) {
    stop("The requested file is too large to read as Tutor context.")
  }
  list(
    ok=TRUE,
    path=allowed$path,
    can_read=TRUE,
    can_write=isTRUE(allowed$permission$can_write),
    content=paste(
      readLines(allowed$target, warn=FALSE, encoding="UTF-8"),
      collapse="\n"
    )
  )
}
