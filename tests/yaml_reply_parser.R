library(ullme)

yaml_text = paste(
  "course_docs: {}",
  "instances:",
  "  - instanceid: ps1",
  "    label: Problem Set 1",
  "    docs: {}",
  sep="\n"
)

direct = ullme_parse_yaml_reply(
  yaml_text,
  required_fields=c("course_docs", "instances")
)
delimited = ullme_parse_yaml_reply(
  paste("thinking", "BEGIN", yaml_text, "END", "trailing", sep="\n"),
  required_fields=c("course_docs", "instances"),
  header_line="BEGIN",
  footer_line="END"
)
fenced = ullme_parse_yaml_reply(
  paste("Some prose", "```yaml", yaml_text, "```", "Done", sep="\n"),
  required_fields=c("course_docs", "instances")
)
trimmed = ullme_parse_yaml_reply(
  paste("Reasoning leaked", yaml_text, "This is trailing prose.", sep="\n"),
  required_fields=c("course_docs", "instances")
)
missing = ullme_parse_yaml_reply(
  "course_docs: {}",
  required_fields=c("course_docs", "instances")
)

stopifnot(
  direct$ok,
  identical(direct$source, "direct"),
  delimited$ok,
  identical(delimited$source, "delimited"),
  fenced$ok,
  identical(fenced$source, "fence"),
  trimmed$ok,
  identical(trimmed$source, "trimmed"),
  !missing$ok,
  grepl("missing required field: instances", missing$message, fixed=TRUE)
)
