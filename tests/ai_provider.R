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

test_main_dir = tempfile("ullme-ai-provider-main-")
dir.create(test_main_dir, recursive=TRUE)
cleanup_app = new.env(parent=emptyenv())
cleanup_app$glob = list(main_dir=test_main_dir)
test_dir = ullme_tempdir(pattern=".ullme-ai-provider-", app=cleanup_app)
key_file = file.path(test_dir, "api-key.txt")
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
ullme_remove_tempdir(test_dir, app=cleanup_app)

registry = ullme_tool_registry()
stopifnot(all(c(
  "list_ai_tutors",
  "list_skills",
  "read_course_file",
  "rewrite_course_text_file"
) %in% names(registry)))

stopifnot(
  inherits(ullme_definition_rewrite_type(), "ellmer::TypeObject")
)
