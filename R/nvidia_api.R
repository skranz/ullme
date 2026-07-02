ullme_nvidia_base_url = function() {
  "https://integrate.api.nvidia.com/v1"
}


ullme_nvidia_default_model = function() {
  "nvidia/nemotron-3-ultra-550b-a55b"
}


ullme_local_base_url = function() {
  "http://127.0.0.1:8000/v1"
}


ullme_nvidia_chat = function(model=ullme_nvidia_default_model(),
                              api_key_file,
                              base_url=ullme_nvidia_base_url(),
                              system_prompt=NULL) {
  ellmer::chat_openai_compatible(
    base_url=sub("/+$", "", base_url),
    name="NVIDIA NIM",
    system_prompt=system_prompt,
    credentials=ullme_api_credentials_file(api_key_file, required=TRUE),
    model=model,
    params=ellmer::params(
      temperature=1,
      top_p=0.95,
      max_tokens=16384
    ),
    api_args=list(
      chat_template_kwargs=list(enable_thinking=TRUE),
      reasoning_budget=16384
    ),
    preserve_thinking=FALSE,
    echo="none"
  )
}


ullme_api_chat = function(config, model=config$model, system_prompt=NULL) {
  if (identical(config$provider, "fake")) return(NULL)
  if (identical(config$provider, "nvidia")) {
    return(ullme_nvidia_chat(
      model=model,
      api_key_file=config$api_key_file,
      base_url=config$base_url,
      system_prompt=system_prompt
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

