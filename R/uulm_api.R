
example = function() {
  library(ullme)
  prompt="Explain in two sentences why demand curves usually slope downward."
  api_key_file="C:/libraries/ullme/local_key.txt"
  config = ullme_api_config(
    api_provider="uulm_api",
    api_key_file=api_key_file
  )
  request = httr2::request(paste0(config$base_url, "/chat/completions")) |>
    httr2::req_headers(
      Authorization=paste("Bearer", config$credentials())
    ) |>
    httr2::req_body_json(list(
      model=config$model,
      messages=list(list(role="user", content=prompt)),
      stream=FALSE
    )) |>
    httr2::req_timeout(seconds=180)
  response = httr2::req_perform(request)
  body = httr2::resp_body_json(response, simplifyVector=FALSE)
  result = paste0(body$choices[[1]]$message$content %||% "", collapse="")
  cat(result, "\n")
  invisible(result)
}


ullme_uulm_api_base_url = function() {
  restore.point("ullme_uulm_api_base_url")
  "https://api.orthos.uni-ulm.de/v1"
}


ullme_uulm_api_default_model = function() {
  restore.point("ullme_uulm_api_default_model")
  "google/gemma-4-12B-it"
}



