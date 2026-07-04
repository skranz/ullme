# Document conversion and format selection for course materials.

ullme_pandoc_format_table = function() {
  data.frame(
    extension=c("md", "markdown", "txt", "html", "htm", "tex", "latex",
                "rst", "org", "docx", "odt", "epub", "rtf", "pptx"),
    pandoc=c("markdown", "markdown", "plain", "html", "html", "latex", "latex",
             "rst", "org", "docx", "odt", "epub", "rtf", "pptx"),
    input=rep(TRUE, 14),
    output=c(TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, TRUE, TRUE,
             TRUE, TRUE, TRUE, TRUE),
    free_text=c(rep(TRUE, 9), rep(FALSE, 5)),
    stringsAsFactors=FALSE
  )
}

ullme_document_input_formats = function() {
  table = ullme_pandoc_format_table()
  unique(table$extension[table$input])
}

ullme_document_output_formats = function() {
  table = ullme_pandoc_format_table()
  unique(table$extension[table$output])
}

ullme_document_candidate_formats = function() {
  unique(c(ullme_document_input_formats(), "pdf"))
}

ullme_normalize_document_format = function(format, direction=c("input", "output")) {
  direction = match.arg(direction)
  format = tolower(sub("^\\.", "", trimws(paste0(format)[1])))
  table = ullme_pandoc_format_table()
  keep = table$extension == format & table[[direction]]
  if (!any(keep)) stop("Unsupported document ", direction, " format: ", format)
  row = table[which(keep)[1], , drop=FALSE]
  list(extension=row$extension[[1]], pandoc=row$pandoc[[1]])
}

ullme_tutor_file_types = function(file_types=NULL) {
  requested = tolower(sub(
    "^\\.", "",
    trimws(paste0(unlist(file_types %||% list(), use.names=FALSE)))
  ))
  requested = unique(requested[nzchar(requested)])
  if (!length(requested)) return(ullme_document_candidate_formats())
  requested
}

ullme_preferred_document_formats = function(file_types=NULL) {
  ullme_tutor_file_types(file_types)
}

ullme_preferred_document_file = function(paths, file_types=NULL) {
  paths = paste0(unlist(paths %||% list(), use.names=FALSE))
  paths = paths[nzchar(paths)]
  if (!length(paths)) return(character(0))
  formats = tolower(tools::file_ext(paths))
  priorities = ullme_preferred_document_formats(file_types)
  requested = paste0(unlist(file_types %||% list(), use.names=FALSE))
  if (length(requested)) {
    keep = formats %in% priorities
    paths = paths[keep]
    formats = formats[keep]
    if (!length(paths)) return(character(0))
  }
  rank = match(formats, priorities)
  rank[is.na(rank)] = length(priorities) + 1L
  paths[order(rank, tolower(paths))][[1]]
}

ullme_preferred_conversion_format = function(file_types=NULL,
                                              source_format=NULL) {
  preferred = ullme_preferred_document_formats(file_types)
  preferred = preferred[preferred %in% ullme_document_output_formats()]
  source_format = tolower(paste0(source_format %||% "")[1])
  preferred = preferred[preferred != source_format]
  if (length(preferred)) return(preferred[[1]])
  if (length(unlist(file_types %||% list(), use.names=FALSE))) {
    stop("The Tutor role has no allowed file type that can be produced by conversion.")
  }
  "md"
}

ullme_conversion_media_name = function(path) {
  name = basename(paste0(path)[1])
  name = ullme_transliterate_german(name)
  name = gsub("\\.", "_", name)
  name = gsub("[<>:\"/\\\\|?*[:cntrl:]]+", "_", name)
  name = sub("[ ]+$", "", name)
  if (!nzchar(name)) name = "document"
  paste0("figures--", name)
}

ullme_rewrite_extracted_media_paths = function(output, absolute_media,
                                                relative_media) {
  if (!file.exists(output) || !ullme_file_is_text(output)) return(invisible(FALSE))
  text = paste(readLines(output, warn=FALSE, encoding="UTF-8"), collapse="\n")
  absolute = gsub("\\\\", "/", normalizePath(
    absolute_media, winslash="/", mustWork=FALSE
  ))
  variants = unique(c(
    absolute,
    utils::URLencode(absolute, reserved=FALSE),
    paste0("file:///", absolute)
  ))
  for (variant in variants[nzchar(variants)]) {
    text = gsub(variant, relative_media, text, fixed=TRUE)
  }
  writeLines(text, output, useBytes=TRUE)
  invisible(TRUE)
}

ullme_convert_document = function(source, to, output, from=NULL,
                                   media_dir=NULL, converter=NULL) {
  source = normalizePath(source, winslash="/", mustWork=TRUE)
  if (dir.exists(source)) stop("Document conversion accepts files only.")
  input = ullme_normalize_document_format(
    from %||% tools::file_ext(source), "input"
  )
  target = ullme_normalize_document_format(to, "output")
  output = normalizePath(output, winslash="/", mustWork=FALSE)
  dir.create(dirname(output), recursive=TRUE, showWarnings=FALSE)
  args = c("--wrap=none", paste0("--resource-path=", dirname(source)))
  relative_media = NULL
  if (!is.null(media_dir) && nzchar(paste0(media_dir)[1])) {
    media_dir = normalizePath(media_dir, winslash="/", mustWork=FALSE)
    dir.create(media_dir, recursive=TRUE, showWarnings=FALSE)
    args = c(args, paste0("--extract-media=", media_dir))
    relative_media = basename(media_dir)
  }
  if (is.null(converter)) {
    if (!requireNamespace("pandoc", quietly=TRUE)) {
      stop("Package 'pandoc' is required for document conversion.")
    }
    converter = pandoc::pandoc_convert
  }
  converter(
    file=source,
    from=input$pandoc,
    to=target$pandoc,
    output=output,
    standalone=target$extension %in% c("html", "docx", "odt", "epub", "rtf", "pptx"),
    args=args
  )
  if (!file.exists(output)) stop("Pandoc did not create the converted document.")
  if (!is.null(relative_media)) {
    ullme_rewrite_extracted_media_paths(output, media_dir, relative_media)
  }
  list(source=source, output=output, from=input$extension, to=target$extension,
       media_dir=if (!is.null(media_dir) && dir.exists(media_dir)) media_dir else NULL)
}

ullme_tutor_doc_spec_for_path = function(definition, path) {
  specs = c(
    ullme_normalize_tutor_doc_specs(definition$docs_per_instance),
    ullme_normalize_tutor_doc_specs(definition$docs_per_course)
  )
  if (!length(specs)) return(NULL)
  path = gsub("\\\\", "/", paste0(path)[1])
  matches = Filter(function(spec) {
    directory = gsub("\\\\", "/", paste0(spec$pref_doc_dir %||% "")[1])
    nzchar(directory) &&
      (identical(path, directory) || startsWith(path, paste0(directory, "/")))
  }, specs)
  if (length(matches)) matches[[1]] else NULL
}

ullme_material_conversion_paths = function(paths) {
  paths = paste0(unlist(paths %||% list(), use.names=FALSE))
  if (length(paths) == 1L) paths = unlist(strsplit(paths, "[,\r\n]+"))
  unique(trimws(paths[nzchar(trimws(paths))]))
}

ullme_material_conversion_paths_for_mode = function(
    paths, mode=c(
      "docx-md", "tex-md", "all-md", "pdf-txt",
      "all-md-txt", "all-overwrite"
    )) {
  mode = match.arg(
    paste0(mode %||% "")[1],
    c(
      "docx-md", "tex-md", "all-md", "pdf-txt",
      "all-md-txt", "all-overwrite"
    )
  )
  paths = ullme_material_conversion_paths(paths)
  formats = tolower(tools::file_ext(paths))
  mixed_formats = c("docx", "pdf")
  keep = switch(
    mode,
    "docx-md"=formats == "docx",
    "tex-md"=formats == "tex",
    "all-md"=formats %in% setdiff(ullme_document_input_formats(), "md"),
    "pdf-txt"=formats == "pdf",
    "all-md-txt"=formats %in% mixed_formats,
    "all-overwrite"=formats %in% mixed_formats
  )
  selected = paths[keep]
  if (!length(selected)) {
    label = switch(
      mode,
      "docx-md"="DOCX",
      "tex-md"="TeX",
      "all-md"="Pandoc-readable",
      "pdf-txt"="PDF",
      "all-md-txt"="DOCX or PDF",
      "all-overwrite"="DOCX or PDF"
    )
    target = if (identical(mode, "pdf-txt")) {
      "plain text"
    } else if (mode %in% c("all-md-txt", "all-overwrite")) {
      "Markdown or plain text"
    } else {
      "Markdown"
    }
    stop("None of the selected files are ", label,
         " documents that can be converted to ", target, ".")
  }
  selected
}


ullme_resolve_material_conversion_paths = function(material_dir, paths) {
  requested = ullme_material_conversion_paths(paths)
  requested = gsub("\\\\", "/", requested)
  requested = sub("^materials/", "", requested, ignore.case=TRUE)
  available = ullme_material_tree(material_dir)
  available = vapply(
    available[vapply(
      available,
      function(record) identical(record$type, "file"),
      logical(1)
    )],
    function(record) paste0(record$path)[1],
    character(1)
  )
  requested_keys = if (identical(.Platform$OS.type, "windows")) {
    tolower(requested)
  } else requested
  available_keys = if (identical(.Platform$OS.type, "windows")) {
    tolower(available)
  } else available
  matched = match(requested_keys, available_keys)
  if (anyNA(matched)) {
    missing = requested[which(is.na(matched))[[1]]]
    stop("The selected material file no longer exists: ", missing,
         ". Refresh the Materials pane and try again.")
  }
  unique(available[matched])
}


ullme_convert_material_files = function(paths, to="", from="", tutorid="",
                                         overwrite=FALSE, origin="ui",
                                         course_dir=NULL, app=getApp(),
                                         converter=NULL, pdf_converter=NULL,
                                         skip_existing=FALSE) {
  if (!identical(app$role, "teacher")) stop("Only teachers can convert course materials.")
  if (is.null(course_dir)) course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  material_dir = .ullme_material_root(file.path(course_dir, "materials"))
  paths = ullme_resolve_material_conversion_paths(material_dir, paths)
  if (!length(paths)) stop("Select at least one material document.")
  definition = NULL
  if (nzchar(paste0(tutorid %||% "")[1])) {
    tutor_path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
    if (!file.exists(tutor_path)) stop("The selected AI Tutor does not exist.")
    definition = yaml::read_yaml(tutor_path, eval.expr=FALSE)
  }

  stage = ullme_tempdir(pattern=".ullme-convert-", app=app)
  keep_stage = FALSE
  on.exit(if (!keep_stage && dir.exists(stage)) {
    ullme_remove_tempdir(stage, app=app)
  }, add=TRUE)
  changes = list()
  converted = list()
  skipped = list()
  targets = character(0)
  for (i in seq_along(paths)) {
    path = .ullme_material_relative_path(paths[[i]])
    source = .ullme_material_file(material_dir, path)
    source_format = tolower(tools::file_ext(source))
    spec = if (is.list(definition)) {
      ullme_tutor_doc_spec_for_path(definition, path)
    } else NULL
    target_format = paste0(to %||% "")[1]
    if (identical(tolower(target_format), "md-txt")) {
      target_format = if (identical(source_format, "pdf")) "txt" else "md"
    } else if (!nzchar(target_format) ||
               identical(tolower(target_format), "preferred")) {
      target_format = ullme_preferred_conversion_format(
        spec$file_types %||% list(), source_format
      )
    }
    target_format = ullme_normalize_document_format(target_format, "output")$extension
    relative_output = paste0(tools::file_path_sans_ext(path), ".", target_format)
    target = .ullme_material_path(material_dir, relative_output)
    if (dir.exists(target)) {
      stop("The converted document path is an existing directory: ", relative_output)
    }
    if (file.exists(target) && !isTRUE(overwrite)) {
      if (isTRUE(skip_existing)) {
        skipped[[length(skipped) + 1L]] = list(
          source=path,
          output=relative_output,
          reason="destination_exists"
        )
        next
      }
      stop("Converted document already exists: ", relative_output)
    }
    stage_dir = file.path(stage, sprintf("%04d", i))
    dir.create(stage_dir, recursive=TRUE, showWarnings=FALSE)
    stage_output = file.path(stage_dir, basename(relative_output))
    media_name = ullme_conversion_media_name(relative_output)
    stage_media = file.path(stage_dir, media_name)
    if (identical(source_format, "pdf")) {
      if (!identical(target_format, "txt")) {
        stop("PDF documents can currently only be converted to plain text.")
      }
      conversion = if (is.null(pdf_converter)) {
        ullme_convert_pdf_to_text(source=source, output=stage_output)
      } else {
        pdf_converter(source=source, output=stage_output)
      }
    } else {
      conversion = ullme_convert_document(
        source=source,
        from=if (nzchar(paste0(from %||% "")[1])) from else NULL,
        to=target_format,
        output=stage_output,
        media_dir=stage_media,
        converter=converter
      )
    }
    changes[[length(changes) + 1L]] = ullme_change_copy(
      stage_output, target, overwrite=isTRUE(overwrite)
    )
    targets = c(targets, target)
    media_files = if (dir.exists(stage_media)) list.files(
      stage_media, recursive=TRUE, full.names=FALSE, all.files=TRUE, no..=TRUE
    ) else character(0)
    media_files = media_files[!dir.exists(file.path(stage_media, media_files))]
    for (media_file in media_files) {
      media_relative = gsub("\\\\", "/", file.path(
        dirname(path), media_name, media_file
      ))
      media_target = .ullme_material_path(material_dir, media_relative)
      changes[[length(changes) + 1L]] = ullme_change_copy(
        file.path(stage_media, media_file), media_target, overwrite=TRUE
      )
      targets = c(targets, media_target)
    }
    converted[[length(converted) + 1L]] = list(
      source=path, output=relative_output, from=conversion$from, to=conversion$to,
      media_dir=if (length(media_files)) gsub("\\\\", "/", file.path(
        dirname(path), media_name
      )) else ""
    )
  }
  keys = if (.Platform$OS.type == "windows") tolower(targets) else targets
  if (anyDuplicated(keys)) {
    stop("The requested conversions would write the same output more than once.")
  }
  if (!length(converted)) {
    return(list(
      ok=TRUE,
      status="committed",
      operation_id="",
      message="No documents needed conversion.",
      converted=converted,
      skipped=skipped
    ))
  }
  operation = ullme_new_change(
    action="convert_materials",
    summary=paste0("Convert ", length(converted), " material document",
                   if (length(converted) == 1L) "" else "s"),
    origin=origin,
    details=list(
      courseid=app$courseid,
      tutorid=tutorid,
      converted=converted,
      skipped=skipped
    ),
    changes=changes,
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (identical(result$status %||% "", "pending_approval")) {
    pending = app$pending_changes[[result$id]]
    pending$cleanup_dir = stage
    app$pending_changes[[result$id]] = pending
    keep_stage = TRUE
  }
  c(ullme_tool_change_result(result), list(
    converted=converted,
    skipped=skipped
  ))
}
