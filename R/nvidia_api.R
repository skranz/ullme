ullme_nvidia_base_url = function() {
  restore.point("ullme_nvidia_base_url")
  "https://integrate.api.nvidia.com/v1"
}


ullme_nvidia_default_model = function() {
  restore.point("ullme_nvidia_default_model")
  "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"
}


ullme_nvidia_preferred_model_specs = function() {
  restore.point("ullme_nvidia_preferred_model_specs")
  list(
    list(id="mistralai/mistral-small-4-119b-2603", image_and_text=TRUE),
    list(id="nvidia/nemotron-3-nano-30b-a3b", image_and_text=TRUE),
    list(id="nvidia/nemotron-3-ultra-550b-a55b", image_and_text=FALSE),
    list(
      id="nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
      image_and_text=TRUE
    ),
    list(id="google/gemma-4-31b-it", image_and_text=TRUE),
    list(id="minimaxai/minimax-m3", image_and_text=TRUE),
    list(id="z-ai/glm-5.2", image_and_text=FALSE),
    list(id="qwen/qwen3.5-122b-a10b", image_and_text=TRUE),
    list(id="stepfun-ai/step-3.7-flash", image_and_text=TRUE)
  )
}


ullme_nvidia_preferred_models = function(image_and_text=FALSE) {
  restore.point("ullme_nvidia_preferred_models")
  specs = ullme_nvidia_preferred_model_specs()
  if (isTRUE(image_and_text)) {
    specs = Filter(function(spec) isTRUE(spec$image_and_text), specs)
  }
  vapply(specs, `[[`, character(1), "id")
}


ullme_nvidia_model_match_key = function(model, basename_only=FALSE) {
  restore.point("ullme_nvidia_model_match_key")
  model = tolower(trimws(paste0(model)[1]))
  if (isTRUE(basename_only)) model = sub("^.*/", "", model)
  gsub("[^a-z0-9]+", "", model)
}


ullme_nvidia_model_matches = function(available, preferred) {
  restore.point("ullme_nvidia_model_matches")
  full_available = ullme_nvidia_model_match_key(available)
  base_available = ullme_nvidia_model_match_key(available, basename_only=TRUE)
  full_preferred = ullme_nvidia_model_match_key(preferred)
  base_preferred = ullme_nvidia_model_match_key(preferred, basename_only=TRUE)
  identical(full_available, full_preferred) ||
    identical(base_available, base_preferred) ||
    startsWith(base_available, base_preferred)
}


ullme_nvidia_available_models = function(available_models,
                                          image_and_text=FALSE) {
  restore.point("ullme_nvidia_available_models")
  available = unique(paste0(unlist(
    available_models %||% list(),
    use.names=FALSE
  )))
  available = available[nzchar(available)]
  preferred = ullme_nvidia_preferred_models(
    image_and_text=image_and_text
  )
  matched = character(0)
  for (wanted in preferred) {
    hits = available[vapply(
      available,
      ullme_nvidia_model_matches,
      logical(1),
      preferred=wanted
    )]
    if (length(hits)) matched = c(matched, sort(hits)[[1]])
  }
  unique(matched)
}


ullme_nvidia_resolve_model = function(model, available_models) {
  restore.point("ullme_nvidia_resolve_model")
  hits = available_models[vapply(
    available_models,
    ullme_nvidia_model_matches,
    logical(1),
    preferred=model
  )]
  if (length(hits)) hits[[1]] else character(0)
}


ullme_nvidia_text_to_speech_models = function() {
  restore.point("ullme_nvidia_text_to_speech_models")
  "nvidia/magpie-tts-zeroshot"
}


ullme_nvidia_speech_to_text_models = function() {
  restore.point("ullme_nvidia_speech_to_text_models")
  "nvidia/nemotron-voicechat"
}


ullme_text_to_speech_models = function(provider="nvidia") {
  restore.point("ullme_text_to_speech_models")
  provider = tolower(trimws(paste0(provider)[1]))
  if (identical(provider, "nvidia")) {
    return(ullme_nvidia_text_to_speech_models())
  }
  character(0)
}


ullme_speech_to_text_models = function(provider="nvidia") {
  restore.point("ullme_speech_to_text_models")
  provider = tolower(trimws(paste0(provider)[1]))
  if (identical(provider, "nvidia")) {
    return(ullme_nvidia_speech_to_text_models())
  }
  character(0)
}


ullme_local_base_url = function() {
  restore.point("ullme_local_base_url")
  "http://127.0.0.1:8000/v1"
}


ullme_nvidia_chat_profile = function(model, task_profile="") {
  restore.point("ullme_nvidia_chat_profile")
  model = tolower(paste0(model)[1])
  task_profile = tolower(paste0(task_profile %||% "")[1])
  if (identical(task_profile, "instance_builder") &&
      grepl("nemotron", model, fixed=TRUE)) {
    return(list(
      max_tokens=8192,
      api_args=list(
        chat_template_kwargs=list(enable_thinking=TRUE),
        reasoning_budget=4096
      )
    ))
  }
  if (ullme_nvidia_model_matches(model, "google/gemma-4-31b-it")) {
    return(list(
      max_tokens=16384,
      api_args=list(
        chat_template_kwargs=list(enable_thinking=FALSE)
      )
    ))
  }
  if (grepl("nemotron", model, fixed=TRUE)) {
    return(list(
      max_tokens=16384,
      api_args=list(
        chat_template_kwargs=list(enable_thinking=TRUE),
        reasoning_budget=16384
      )
    ))
  }
  list(max_tokens=16384, api_args=list())
}


ullme_nvidia_chat = function(model=ullme_nvidia_default_model(),
                              api_key_file,
                              base_url=ullme_nvidia_base_url(),
                              system_prompt=NULL,
                              task_profile="") {
  restore.point("ullme_nvidia_chat")
  profile = ullme_nvidia_chat_profile(model, task_profile=task_profile)
  ellmer::chat_openai_compatible(
    base_url=sub("/+$", "", base_url),
    name="NVIDIA NIM",
    system_prompt=system_prompt,
    credentials=ullme_api_credentials_file(api_key_file, required=TRUE),
    model=model,
    params=ellmer::params(
      temperature=1,
      top_p=0.95,
      max_tokens=profile$max_tokens
    ),
    api_args=profile$api_args,
    preserve_thinking=FALSE,
    echo="none"
  )
}


ullme_api_chat = function(config, model=config$model, system_prompt=NULL,
                           task_profile="") {
  restore.point("ullme_api_chat")
  if (identical(config$provider, "fake")) return(NULL)
  if (identical(config$provider, "nvidia")) {
    return(ullme_nvidia_chat(
      model=model,
      api_key_file=config$api_key_file,
      base_url=config$base_url,
      system_prompt=system_prompt,
      task_profile=task_profile
    ))
  }
  ellmer::chat_openai_compatible(
    base_url=config$base_url,
    name="Local OpenAI-compatible API",
    system_prompt=system_prompt,
    credentials=config$credentials,
    model=model,
    echo="none"
  )
}

