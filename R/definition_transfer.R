ullme_definition_import_root = function(app=getApp()) {
  restore.point("ullme_definition_import_root")
  path = file.path(app$cur_session_dir, "definition_imports")
  dir.create(path, recursive=TRUE, showWarnings=FALSE)
  path
}


ullme_definition_import_token = function() {
  restore.point("ullme_definition_import_token")
  paste0(
    "import_",
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "_",
    sprintf("%08d", sample.int(99999999L, 1))
  )
}


ullme_definition_target_exists = function(kind, definitionid, source, app=getApp()) {
  restore.point("ullme_definition_target_exists")
  target = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  dir.exists(target) || file.exists(target)
}


ullme_handle_definition_import_upload = function(id, value, app=getApp(), ...) {
  restore.point("ullme_handle_definition_import_upload")
  if (!identical(app$role, "teacher") || is.null(value) || NROW(value) == 0) {
    return(invisible(NULL))
  }
  kind = sub("^ullme_definition_import_", "", paste0(id)[1])
  kind = tryCatch(ullme_definition_kind(kind), error=function(e) NULL)
  if (is.null(kind)) return(invisible(NULL))

  preview = tryCatch(
    ullme_prepare_definition_import(kind=kind, value=value, app=app),
    error=function(e) list(kind=kind, error=conditionMessage(e))
  )
  callJS(
    .fun="window.ullme.openDefinitionImportPreview",
    .args=list(preview),
    .app=app
  )
  callJS(
    .fun="window.ullme.definitionImportComplete",
    .args=list(paste0(id)[1]),
    .app=app
  )
  invisible(preview)
}


ullme_prepare_definition_import = function(kind, value, app=getApp(),
                                            max_upload_mb=25,
                                            max_entries=250,
                                            max_unpacked_mb=50) {
  restore.point("ullme_prepare_definition_import")
  kind = ullme_definition_kind(kind)
  if (NROW(value) != 1L) stop("Choose exactly one definition file.")
  source_file = value$datapath[[1]]
  original_name = ullme_clean_file_name(value$name[[1]])
  size = suppressWarnings(as.numeric(value$size[[1]]))
  if (!is.na(size) && size > max_upload_mb * 1024^2) {
    stop("The import file exceeds the ", max_upload_mb, " MB limit.")
  }

  token = ullme_definition_import_token()
  import_root = file.path(ullme_definition_import_root(app=app), token)
  dir.create(import_root, recursive=TRUE, showWarnings=FALSE)
  on_error = TRUE
  on.exit(if (on_error && dir.exists(import_root)) unlink(import_root, recursive=TRUE), add=TRUE)

  if (identical(kind, "tutor")) {
    if (!tolower(tools::file_ext(original_name)) %in% c("yaml", "yml")) {
      stop("AI Tutor imports must be YAML files.")
    }
    content = paste(readLines(source_file, warn=FALSE, encoding="UTF-8"), collapse="\n")
    parsed = tryCatch(
      yaml::yaml.load(content, eval.expr=FALSE),
      error=function(e) stop("Invalid Tutor YAML: ", conditionMessage(e))
    )
    if (!is.list(parsed)) stop("Tutor YAML must contain a mapping.")
    definitionid = ullme_clean_definition_id(parsed$tutorid %||% "")
    ullme_validate_definition_content(
      kind="tutor",
      definitionid=definitionid,
      file="tutor.yaml",
      content=content
    )
    definition_dir = file.path(import_root, "definition")
    dir.create(definition_dir, recursive=TRUE, showWarnings=FALSE)
    writeLines(content, file.path(definition_dir, "tutor.yaml"), useBytes=TRUE)
    label = paste0(parsed$label %||% parsed$name %||% definitionid)[1]
  } else {
    if (!identical(tolower(tools::file_ext(original_name)), "zip")) {
      stop("Skill imports must be ZIP files.")
    }
    archive = utils::unzip(source_file, list=TRUE)
    if (NROW(archive) == 0) stop("The Skill ZIP is empty.")
    if (NROW(archive) > max_entries) {
      stop("The Skill ZIP contains more than ", max_entries, " entries.")
    }
    names = gsub("\\\\", "/", archive$Name)
    unsafe = grepl("^/|^[A-Za-z]:|(^|/)\\.\\.(/|$)", names)
    if (any(unsafe)) stop("The Skill ZIP contains unsafe paths.")
    lengths = suppressWarnings(as.numeric(archive$Length))
    if (sum(lengths, na.rm=TRUE) > max_unpacked_mb * 1024^2) {
      stop("The unpacked Skill exceeds the ", max_unpacked_mb, " MB limit.")
    }

    meaningful = !grepl("(^|/)__MACOSX(/|$)", names) & !grepl("/$", names)
    names = names[meaningful]
    if (length(names) == 0) stop("The Skill ZIP contains no files.")
    skill_dirs = dirname(names[tolower(basename(names)) == "skill.md"])
    yaml_dirs = dirname(names[tolower(basename(names)) == "ullme.yaml"])
    definition_bases = intersect(skill_dirs, yaml_dirs)
    if (length(definition_bases) != 1L) {
      stop("The Skill ZIP must contain one directory with SKILL.md and ullme.yaml.")
    }
    definition_base = definition_bases[[1]]
    if (!identical(definition_base, ".") &&
        any(!startsWith(names, paste0(definition_base, "/")))) {
      stop("All Skill files must be inside the same definition directory.")
    }

    raw_dir = file.path(import_root, "raw")
    dir.create(raw_dir, recursive=TRUE, showWarnings=FALSE)
    utils::unzip(source_file, exdir=raw_dir)
    definition_dir = if (identical(definition_base, ".")) {
      raw_dir
    } else {
      file.path(raw_dir, definition_base)
    }
    metadata_path = file.path(definition_dir, "ullme.yaml")
    skill_path = file.path(definition_dir, "SKILL.md")
    metadata = tryCatch(
      yaml::read_yaml(metadata_path, eval.expr=FALSE),
      error=function(e) stop("Invalid ullme.yaml: ", conditionMessage(e))
    )
    if (!is.list(metadata)) stop("ullme.yaml must contain a mapping.")
    definitionid = ullme_clean_definition_id(metadata$skillid %||% "")
    ullme_validate_definition_content(
      kind="skill",
      definitionid=definitionid,
      file="ullme.yaml",
      content=paste(readLines(metadata_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
    )
    ullme_validate_definition_content(
      kind="skill",
      definitionid=definitionid,
      file="SKILL.md",
      content=paste(readLines(skill_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
    )
    label = paste0(metadata$label %||% metadata$name %||% definitionid)[1]
  }

  files = list.files(
    definition_dir,
    recursive=TRUE,
    full.names=FALSE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=FALSE
  )
  files = sort(gsub("\\\\", "/", files))
  record = list(
    token=token,
    kind=kind,
    id=definitionid,
    label=label,
    definition_dir=definition_dir,
    import_root=import_root,
    files=files
  )
  app$definition_imports[[token]] = record
  on_error = FALSE

  has_course = identical(kind, "tutor") && !is.null(ullme_active_course_dir(app=app))
  list(
    token=token,
    kind=kind,
    id=definitionid,
    label=label,
    files=as.list(files),
    targets=as.list(c("personal", if (has_course) "course")),
    conflicts=list(
      personal=ullme_definition_target_exists(
        kind=kind,
        definitionid=definitionid,
        source="personal",
        app=app
      ),
      course=has_course && ullme_definition_target_exists(
        kind=kind,
        definitionid=definitionid,
        source="course",
        app=app
      )
    ),
    error=NULL
  )
}


ullme_apply_definition_import = function(token, target_source="personal",
                                          replace=FALSE, app=getApp()) {
  restore.point("ullme_apply_definition_import")
  if (!identical(app$role, "teacher")) stop("Only teachers can import definitions.")
  token = paste0(token)[1]
  record = app$definition_imports[[token]]
  if (is.null(record)) stop("This import preview has expired. Upload the file again.")
  kind = record$kind
  definitionid = record$id
  target_source = paste0(target_source)[1]
  allowed = if (identical(kind, "tutor")) c("personal", "course") else "personal"
  if (!target_source %in% allowed) stop("Invalid import destination.")
  if (identical(target_source, "course") && is.null(ullme_active_course_dir(app=app))) {
    stop("Select a course before importing a course-local Tutor.")
  }

  target_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=target_source,
    app=app
  )
  conflict = dir.exists(target_dir) || file.exists(target_dir)
  if (conflict && !isTRUE(replace)) {
    stop("A complete definition already exists at this destination.")
  }

  operation = ullme_new_change(
    action="definition_import",
    summary=paste0(if (conflict) "Replace " else "Import ", target_source, " ",
                   kind, " definition ", definitionid),
    origin="ui",
    details=list(kind=kind, definitionid=definitionid, source=target_source),
    changes=list(ullme_change_copy(
      source=record$definition_dir,
      target=target_dir,
      overwrite=conflict && isTRUE(replace)
    )),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not import the definition.")
  imported = ullme_definition_metadata_at(
    kind=kind,
    definitionid=definitionid,
    source=target_source,
    app=app
  )
  if (is.null(imported)) {
    stop("The imported definition failed validation after copying.")
  }

  if (dir.exists(record$import_root)) unlink(record$import_root, recursive=TRUE)
  app$definition_imports[[token]] = NULL
  list(
    kind=kind,
    id=definitionid,
    source=target_source,
    notice=if (conflict) "Definition replaced from import." else "Definition imported."
  )
}


ullme_prepare_definition_download = function(kind, definitionid, source, app=getApp()) {
  restore.point("ullme_prepare_definition_download")
  if (!identical(app$role, "teacher")) stop("Only teachers can download definitions.")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  source = paste0(source)[1]
  metadata = ullme_definition_metadata_at(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  if (is.null(metadata)) stop("The definition does not exist.")
  definition_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  dir.create(app$definition_downloads_dir, recursive=TRUE, showWarnings=FALSE)

  if (identical(kind, "tutor")) {
    filename = paste0(definitionid, ".yaml")
    target = file.path(app$definition_downloads_dir, filename)
    if (!file.copy(file.path(definition_dir, "tutor.yaml"), target, overwrite=TRUE)) {
      stop("Could not prepare the Tutor YAML download.")
    }
  } else {
    filename = paste0(definitionid, ".zip")
    target = file.path(app$definition_downloads_dir, filename)
    if (file.exists(target)) unlink(target)
    files = list.files(
      definition_dir,
      recursive=TRUE,
      full.names=FALSE,
      all.files=TRUE,
      no..=TRUE,
      include.dirs=FALSE
    )
    if (length(files) == 0) stop("The Skill definition contains no files.")
    old_dir = setwd(definition_dir)
    on.exit(setwd(old_dir), add=TRUE)
    utils::zip(zipfile=target, files=files, flags="-r9X")
    if (!file.exists(target)) stop("Could not prepare the Skill ZIP download.")
  }

  url = paste0(
    "ullme-definition-downloads/",
    utils::URLencode(filename, reserved=TRUE)
  )
  callJS(
    .fun="window.ullme.downloadDefinition",
    .args=list(url, filename),
    .app=app
  )
  invisible(list(url=url, filename=filename, path=target))
}
