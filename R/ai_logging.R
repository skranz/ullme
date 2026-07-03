ullme_ai_interactions_dir = function(app=getApp()) {
  if (!isTRUE(app$store_ai_interactions)) return(NULL)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(NULL)
  file.path(course_dir, "ai_interactions")
}


ullme_ai_interaction_start = function(input, visible_text="", model="",
                                       kind="chat", app=getApp()) {
  root = ullme_ai_interactions_dir(app=app)
  if (is.null(root)) return(NULL)
  dir.create(root, recursive=TRUE, showWarnings=FALSE)
  id = paste0(
    format(Sys.time(), "%Y%m%d-%H%M%OS3"),
    "-", sprintf("%06d", sample.int(999999L, 1L))
  )
  id = gsub("[^0-9A-Za-z.-]+", "-", id)
  directory = file.path(root, id)
  dir.create(directory, recursive=FALSE, showWarnings=FALSE)
  writeLines(paste0(input), file.path(directory, "request.txt"), useBytes=TRUE)
  if (nzchar(paste0(visible_text)[1])) {
    writeLines(
      paste0(visible_text),
      file.path(directory, "visible-user-text.txt"),
      useBytes=TRUE
    )
  }
  yaml::write_yaml(list(
    id=id,
    kind=kind,
    model=paste0(model)[1],
    started_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  ), file.path(directory, "metadata.yaml"))
  directory
}


ullme_ai_interaction_finish = function(directory, status="completed",
                                        text="", thinking="", error="") {
  if (is.null(directory) || !dir.exists(directory)) return(invisible(FALSE))
  if (nzchar(paste0(text)[1])) {
    writeLines(paste0(text), file.path(directory, "response.txt"), useBytes=TRUE)
  }
  if (nzchar(paste0(thinking)[1])) {
    writeLines(paste0(thinking), file.path(directory, "thinking.txt"), useBytes=TRUE)
  }
  if (nzchar(paste0(error)[1])) {
    writeLines(paste0(error), file.path(directory, "error.txt"), useBytes=TRUE)
  }
  metadata_path = file.path(directory, "metadata.yaml")
  metadata = tryCatch(
    yaml::read_yaml(metadata_path, eval.expr=FALSE),
    error=function(e) list()
  )
  metadata$status = status
  metadata$finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  yaml::write_yaml(metadata, metadata_path)
  invisible(TRUE)
}
