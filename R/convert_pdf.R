# PDF-to-text conversion using the pdftotext executable.

ullme_pdftotext_executable = function(command="pdftotext") {
  command = trimws(paste0(command %||% "")[1])
  if (!nzchar(command)) command = "pdftotext"
  executable = if (file.exists(command) && !dir.exists(command)) {
    command
  } else {
    Sys.which(command)
  }
  if (!nzchar(executable)) {
    stop("Could not find 'pdftotext' on the system PATH.")
  }
  normalizePath(executable, winslash="/", mustWork=TRUE)
}


ullme_convert_pdf_to_text = function(source, output, command="pdftotext",
                                      runner=system2) {
  source = normalizePath(source, winslash="/", mustWork=TRUE)
  if (dir.exists(source)) stop("PDF conversion accepts files only.")
  if (!identical(tolower(tools::file_ext(source)), "pdf")) {
    stop("PDF-to-text conversion requires a PDF source file.")
  }
  output = normalizePath(output, winslash="/", mustWork=FALSE)
  if (!identical(tolower(tools::file_ext(output)), "txt")) {
    stop("PDF-to-text conversion requires a .txt output file.")
  }
  dir.create(dirname(output), recursive=TRUE, showWarnings=FALSE)
  executable = ullme_pdftotext_executable(command)
  messages = runner(
    executable,
    args=c("-enc", "UTF-8", shQuote(source), shQuote(output)),
    stdout=TRUE,
    stderr=TRUE
  )
  status = attr(messages, "status")
  if (is.null(status)) status = 0L
  if (!identical(as.integer(status), 0L)) {
    detail = trimws(paste(messages, collapse="\n"))
    stop(
      "pdftotext failed",
      if (nzchar(detail)) paste0(": ", detail) else "."
    )
  }
  if (!file.exists(output)) stop("pdftotext did not create the converted text file.")
  list(source=source, output=output, from="pdf", to="txt", media_dir=NULL)
}
