library(ullme)

args = commandArgs(trailingOnly=TRUE)
if (length(args) < 5L) {
  stop(paste(
    "Usage: Rscript tests/manual_instance_builder.R",
    "<main_dir> <userid> <semester> <courseid> <tutorid>",
    "[guidance] [model] [api_key_file] [allow_changes]",
    sep="\n"
  ))
}

value = function(index, default="") {
  if (length(args) < index || !nzchar(args[[index]])) default else args[[index]]
}

allow_changes = tolower(value(9, "false")) %in% c("true", "1", "yes")
result = ullme_test_instance_builder(
  main_dir=args[[1]],
  userid=args[[2]],
  semester=args[[3]],
  courseid=args[[4]],
  tutorid=args[[5]],
  guidance=value(6),
  model=value(7, "nvidia/nemotron-3-nano-30b-a3b"),
  api_key_file={
    path = value(8)
    if (nzchar(path)) path else NULL
  },
  run=TRUE,
  allow_changes=allow_changes
)

cat(result$answer, "\n")
