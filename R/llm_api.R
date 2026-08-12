
ullme_api_provider = function(provider) {
  restore.point("ullme_api_provider")
  provider = tolower(trimws(paste0(provider)[1]))
  match.arg(provider, c("fake", "nvidia", "uulm_api"))
}


ullme_api_key = function(api_key_file, required=TRUE) {
  restore.point("ullme_api_key")
  path = paste0(api_key_file %||% "")[1]
  if (!nzchar(path)) {
    if (isTRUE(required)) stop("api_key_file is required for this API provider.")
    return("")
  }
  path = path.expand(path)
  if (!file.exists(path) || dir.exists(path)) {
    stop("The API key file does not exist.")
  }
  key = trimws(paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse=""))
  if (!nzchar(key)) stop("The API key file is empty.")
  key
}


ullme_api_credentials_file = function(api_key_file, required=TRUE) {
  restore.point("ullme_api_credentials_file")
  force(api_key_file)
  force(required)
  function() ullme_api_key(api_key_file, required=required)
}


ullme_api_config = function(api_provider="fake", api_key_file=NULL,
                            api_model=NULL, api_base_url=NULL) {
  restore.point("ullme_api_config")
  provider = ullme_api_provider(api_provider)
  if (identical(provider, "nvidia")) {
    base_url = paste0(api_base_url %||% ullme_nvidia_base_url())[1]
    model = paste0(api_model %||% ullme_nvidia_default_model())[1]
    if (!length(ullme_nvidia_resolve_model(
      model,
      ullme_nvidia_preferred_models()
    ))) {
      stop("api_model is not in the configured NVIDIA model allowlist.")
    }
    credentials = ullme_api_credentials_file(api_key_file, required=TRUE)
  } else if (identical(provider, "uulm_api")) {
    base_url = paste0(api_base_url %||% ullme_uulm_api_base_url())[1]
    model = paste0(api_model %||% ullme_uulm_api_default_model())[1]
    ullme_api_key(api_key_file, required=TRUE)
    credentials = ullme_api_credentials_file(api_key_file, required=TRUE)
  } else {
    base_url = ""
    model = paste0(api_model %||% "fake")[1]
    credentials = NULL
  }
  if (provider != "fake" && !grepl("^https?://", base_url, ignore.case=TRUE)) {
    stop("api_base_url must be an HTTP or HTTPS URL.")
  }
  if (!nzchar(model)) stop("api_model must not be empty.")
  list(
    provider=provider,
    base_url=sub("/+$", "", base_url),
    model=model,
    model_supplied=!is.null(api_model),
    api_key_file=api_key_file,
    credentials=credentials
  )
}


ullme_api_models = function(config, timeout=15, image_and_text=FALSE) {
  restore.point("ullme_api_models")
  if (identical(config$provider, "fake")) return("fake")
  request = httr2::request(paste0(sub("/+$", "", config$base_url), "/models"))
  if (!is.null(config$credentials)) {
    request = httr2::req_headers(
      request,
      Authorization=paste("Bearer", config$credentials())
    )
  }
  response = httr2::req_perform(
    httr2::req_timeout(request, seconds=timeout)
  )
  body = httr2::resp_body_json(response, simplifyVector=FALSE)
  records = body$data %||% list()
  ids = vapply(records, function(record) paste0(record$id %||% "")[1], character(1))
  ids = sort(unique(ids[nzchar(ids)]))
  if (identical(config$provider, "nvidia")) {
    return(ullme_nvidia_available_models(
      ids,
      image_and_text=image_and_text
    ))
  }
  unique(c(config$model, ids))
}


ullme_model_id = function(model, app=getApp()) {
  restore.point("ullme_model_id")
  model = trimws(paste0(model %||% app$api_config$model)[1])
  if (!nzchar(model) || !grepl("^[A-Za-z0-9][A-Za-z0-9._:/+-]*$", model)) {
    stop("Invalid model ID.")
  }
  available = app$api_models %||% app$api_config$model
  if (length(available) > 0 && !model %in% available) {
    stop("The selected model is not in the provider's model catalog.")
  }
  model
}


ullme_chat_model_for_uploads = function(model=NULL, has_uploads=FALSE,
                                        app=getApp()) {
  restore.point("ullme_chat_model_for_uploads")
  selected = trimws(paste0(model %||% app$api_config$model)[1])
  if (!isTRUE(has_uploads) ||
      !identical(app$api_config$provider, "nvidia") ||
      ullme_nvidia_model_supports_images(selected)) {
    return(selected)
  }
  fallback = ullme_nvidia_image_model(
    app$api_models %||% app$api_config$model,
    preferred=app$api_config$model
  )
  if (!length(fallback)) return(selected)
  ullme_chat_debug(
    app,
    "chat image upload switching model from ", selected,
    " to ", fallback
  )
  fallback[[1]]
}


ullme_model_label = function(model) {
  restore.point("ullme_model_label")
  label = sub("^.*/", "", model)
  if (nchar(label) > 42) paste0(substr(label, 1, 39), "...") else label
}


ullme_model_catalog_payload = function(app=getApp()) {
  restore.point("ullme_model_catalog_payload")
  models = app$api_models %||% app$api_config$model
  list(
    provider=app$api_config$provider,
    default=app$api_config$model,
    models=lapply(models, function(model) {
      list(id=model, label=ullme_model_label(model))
    }),
    error=app$api_models_error %||% NULL
  )
}


ullme_send_model_catalog = function(app=getApp()) {
  restore.point("ullme_send_model_catalog")
  callJS(
    .fun="window.ullme.updateModelCatalog",
    .args=list(ullme_model_catalog_payload(app=app)),
    .app=app
  )
  invisible(TRUE)
}


ullme_refresh_model_catalog = function(app=getApp()) {
  restore.point("ullme_refresh_model_catalog")
  app$api_models = app$api_config$model
  app$api_models_error = NULL
  if (isTRUE(app$allow_model_selection) &&
      !identical(app$api_config$provider, "fake")) {
    discovered = tryCatch(
      ullme_api_models(app$api_config),
      error=function(e) {
        app$api_models_error = ullme_safe_ai_error(e, app$api_config)
        app$api_config$model
      }
    )
    if (length(discovered)) {
      requested = app$api_config$model
      app$api_models = discovered
      resolved = if (
        identical(app$api_config$provider, "nvidia")
      ) ullme_nvidia_resolve_model(requested, discovered) else
        discovered[discovered == requested]
      app$api_config$model = if (
        isTRUE(app$api_config$model_supplied) &&
        length(resolved)
      ) resolved[[1]] else discovered[[1]]
    }
  }
  ullme_send_model_catalog(app=app)
  invisible(app$api_models)
}


ullme_safe_ai_error = function(error, config=NULL) {
  restore.point("ullme_safe_ai_error")
  message = tryCatch(
    conditionMessage(error),
    error=function(e) paste0(error, collapse=" ")
  )
  key = tryCatch(
    if (is.null(config) || is.null(config$credentials)) "" else config$credentials(),
    error=function(e) ""
  )
  if (nzchar(key)) message = gsub(key, "[API key]", message, fixed=TRUE)
  lower = tolower(message)
  if (grepl("401|unauthori|invalid api key|authentication", lower)) {
    provider = paste0(config$provider %||% "The model provider")[1]
    return(paste0(provider, " rejected the API credentials. Check api_key_file."))
  }
  if (grepl("429|rate.?limit|too many requests", lower)) {
    return("The model provider is rate-limiting requests. Please try again shortly.")
  }
  if (grepl("timeout|timed out", lower)) {
    return("The model provider did not respond in time.")
  }
  if (grepl("model", lower) && grepl("not found|unknown|invalid", lower)) {
    return("The selected model is not available from this provider.")
  }
  message
}
