library(ullme)

root = tempfile("ullme-pdf-convert-test-")
dir.create(root)
source = file.path(root, "source.pdf")
output = file.path(root, "source.txt")
writeBin(charToRaw("%PDF-fake"), source)

fake_runner = function(command, args, stdout, stderr) {
  stopifnot(
    file.exists(command),
    identical(args[1:2], c("-enc", "UTF-8")),
    isTRUE(stdout),
    isTRUE(stderr)
  )
  writeLines("PDF text", output, useBytes=TRUE)
  character(0)
}

result = ullme_convert_pdf_to_text(
  source=source,
  output=output,
  command=file.path(R.home("bin"), "R.exe"),
  runner=fake_runner
)
stopifnot(
  identical(result$from, "pdf"),
  identical(result$to, "txt"),
  identical(readLines(output, warn=FALSE), "PDF text")
)

ullme_remove_checked_directory(
  root,
  root=dirname(root),
  expected_name=basename(root),
  label="PDF conversion test directory"
)
