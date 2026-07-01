library(ullme)

stopifnot(
  identical(
    ullme_nvidia_default_model(),
    "nvidia/nemotron-3-ultra-550b-a55b"
  ),
  identical(
    ullme_render_prompt(
      "A {{first}} B {{second}}",
      list(first="$5\\path", second="ok")
    ),
    "A $5\\path B ok"
  )
)

key_file = tempfile("ullme-test-key-")
writeLines("dummy-secret", key_file)
config = ullme_api_config(
  api_provider="nvidia",
  api_key_file=key_file
)
stopifnot(
  config$provider == "nvidia",
  config$model == ullme_nvidia_default_model(),
  identical(config$credentials(), "dummy-secret")
)
unlink(key_file)

registry = ullme_tool_registry()
stopifnot(all(c(
  "list_ai_tutors",
  "list_skills",
  "read_course_file",
  "rewrite_course_text_file",
  "write_object_index"
) %in% names(registry)))

stopifnot(
  inherits(ullme_definition_rewrite_type(), "ellmer::TypeObject"),
  inherits(ullme_organization_response_type(), "ellmer::TypeObject")
)
