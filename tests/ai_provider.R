library(ullme)

stopifnot(
  identical(
    ullme_nvidia_default_model(),
    "google/gemma-4-31b-it"
  ),
  identical(
    ullme_render_prompt(
      "A {{first}} B {{second}}",
      list(first="$5\\path", second="ok")
    ),
    "A $5\\path B ok"
  )
)

available_models = c(
  "unlisted/model",
  "nvidia/nemotron-3-ultra-550b-a55b",
  "qwen/qwen3.5-122b-a10b",
  "google/gemma_4_31b_it",
  "mistralai/mistral-small-4-119b-2603",
  "stepfun-ai/step-3.7-flash",
  "minimaxai/minimax-m3"
)
stopifnot(
  identical(
    ullme_nvidia_available_models(available_models),
    c(
      "google/gemma_4_31b_it",
      "minimaxai/minimax-m3",
      "qwen/qwen3.5-122b-a10b",
      "nvidia/nemotron-3-ultra-550b-a55b",
      "stepfun-ai/step-3.7-flash",
      "mistralai/mistral-small-4-119b-2603"
    )
  ),
  identical(
    ullme_nvidia_available_models(available_models, image_and_text=TRUE),
    c(
      "google/gemma_4_31b_it",
      "minimaxai/minimax-m3",
      "qwen/qwen3.5-122b-a10b",
      "stepfun-ai/step-3.7-flash",
      "mistralai/mistral-small-4-119b-2603"
    )
  ),
  identical(
    ullme_nvidia_resolve_model(
      "google/gemma-4-31b-it",
      available_models
    ),
    "google/gemma_4_31b_it"
  ),
  identical(
    ullme_text_to_speech_models(),
    "nvidia/magpie-tts-zeroshot"
  ),
  identical(
    ullme_speech_to_text_models(),
    "nvidia/nemotron-voicechat"
  ),
  identical(
    ullme_nvidia_chat_profile("google/gemma-4-31b-it")$api_args,
    list(chat_template_kwargs=list(enable_thinking=FALSE))
  ),
  is.null(
    ullme_nvidia_chat_profile("google/gemma-4-31b-it")$api_args$reasoning_budget
  ),
  identical(
    ullme_nvidia_chat_profile(
      "nvidia/nemotron-3-ultra-550b-a55b"
    )$api_args$reasoning_budget,
    16384
  ),
  identical(
    ullme_nvidia_chat_profile(
      "nvidia/nemotron-3-nano-30b-a3b",
      task_profile="instance_builder"
    )$api_args$reasoning_budget,
    4096
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
  identical(config$model_supplied, FALSE),
  identical(config$credentials(), "dummy-secret")
)
supplied_config = ullme_api_config(
  api_provider="nvidia",
  api_key_file=key_file,
  api_model="qwen/qwen3.5-122b-a10b"
)
stopifnot(
  identical(supplied_config$model, "qwen/qwen3.5-122b-a10b"),
  identical(supplied_config$model_supplied, TRUE),
  inherits(try(
    ullme_api_config(
      api_provider="nvidia",
      api_key_file=key_file,
      api_model="unlisted/model"
    ),
    silent=TRUE
  ), "try-error")
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
