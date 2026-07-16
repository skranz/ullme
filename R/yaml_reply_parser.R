ullme_yaml_reply_line_index = function(lines, marker) {
  marker = trimws(paste0(marker %||% "")[1])
  if (!nzchar(marker)) return(integer(0))
  which(trimws(lines) == marker)
}


ullme_yaml_reply_regex_escape = function(value) {
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", paste0(value), perl=TRUE)
}


ullme_yaml_reply_fenced_blocks = function(text) {
  blocks = regmatches(
    text,
    gregexpr(
      "```(?:yaml|yml)?[[:space:]]*\\r?\\n[\\s\\S]*?```",
      text,
      perl=TRUE,
      ignore.case=TRUE
    )
  )[[1]]
  if (!length(blocks) || identical(blocks, "")) return(character(0))
  vapply(blocks, function(block) {
    block = sub(
      "^```(?:yaml|yml)?[[:space:]]*\\r?\\n",
      "",
      block,
      perl=TRUE,
      ignore.case=TRUE
    )
    sub("\\r?\\n?```[[:space:]]*$", "", block, perl=TRUE)
  }, character(1))
}


ullme_yaml_reply_candidates = function(text, required_fields,
                                        header_line=NULL,
                                        footer_line=NULL) {
  text = trimws(paste0(text %||% "", collapse="\n"))
  if (!nzchar(text)) return(list())
  candidates = list()
  add = function(value, source) {
    value = trimws(paste0(value, collapse="\n"))
    if (nzchar(value)) {
      candidates[[length(candidates) + 1L]] <<- list(
        text=value,
        source=source
      )
    }
  }
  lines = strsplit(text, "\\r?\\n", perl=TRUE)[[1]]
  headers = ullme_yaml_reply_line_index(lines, header_line)
  footers = ullme_yaml_reply_line_index(lines, footer_line)
  if (length(headers)) {
    for (header in headers) {
      following = footers[footers > header]
      if (length(following)) {
        footer = following[[1]]
        if (footer > header + 1L) {
          add(lines[(header + 1L):(footer - 1L)], "delimited")
        }
      } else if (header < length(lines)) {
        add(lines[(header + 1L):length(lines)], "after-header")
      }
    }
  }
  for (block in ullme_yaml_reply_fenced_blocks(text)) add(block, "fence")
  add(text, "direct")

  fields = unique(trimws(paste0(required_fields %||% character(0))))
  fields = fields[nzchar(fields)]
  if (length(fields)) {
    escaped = vapply(fields, ullme_yaml_reply_regex_escape, character(1))
    starts = grep(
      paste0("^(?:", paste(escaped, collapse="|"), "):[[:space:]]*"),
      lines,
      perl=TRUE
    )
    for (start in starts) {
      later_top_level = which(
        seq_along(lines) > start &
          grepl("^[^[:space:]#][^:]*", lines)
      )
      ends = unique(c(
        length(lines),
        rev(later_top_level - 1L)
      ))
      ends = ends[ends >= start]
      for (end in ends) add(lines[start:end], "trimmed")
    }
  }
  keys = vapply(candidates, function(candidate) candidate$text, character(1))
  candidates[!duplicated(keys)]
}


ullme_parse_yaml_reply = function(text, required_fields,
                                   header_line=NULL,
                                   footer_line=NULL,
                                   label="AI YAML reply") {
  required_fields = unique(trimws(paste0(required_fields %||% character(0))))
  required_fields = required_fields[nzchar(required_fields)]
  candidates = ullme_yaml_reply_candidates(
    text=text,
    required_fields=required_fields,
    header_line=header_line,
    footer_line=footer_line
  )
  if (!length(candidates)) {
    return(list(
      ok=FALSE,
      value=NULL,
      yaml="",
      source="",
      errors=paste0(label, " is empty."),
      message=paste0(label, " is empty.")
    ))
  }
  errors = character(0)
  for (candidate in candidates) {
    parsed = ullme_parse_yaml_text(candidate$text, label)
    if (!isTRUE(parsed$ok)) {
      errors = c(errors, paste0(unlist(parsed$errors, use.names=FALSE)))
      next
    }
    if (!is.list(parsed$value) || is.null(names(parsed$value))) {
      errors = c(errors, paste0(label, " must contain a YAML mapping."))
      next
    }
    missing = setdiff(required_fields, names(parsed$value))
    if (length(missing)) {
      errors = c(errors, paste0(
        label, " is missing required field",
        if (length(missing) > 1L) "s" else "",
        ": ", paste(missing, collapse=", "), "."
      ))
      next
    }
    return(list(
      ok=TRUE,
      value=parsed$value,
      yaml=candidate$text,
      source=candidate$source,
      errors=character(0),
      message=""
    ))
  }
  errors = unique(errors[nzchar(errors)])
  message = if (length(errors)) tail(errors, 1L) else
    paste0(label, " did not contain valid YAML.")
  list(
    ok=FALSE,
    value=NULL,
    yaml="",
    source="",
    errors=errors,
    message=message
  )
}
