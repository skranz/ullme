if (file.exists(file.path("R", "custom_stream.R"))) {
  if (!exists("restore.point")) restore.point = function(...) invisible(NULL)
  source(file.path("R", "courses.R"))
  source(file.path("R", "llm_api.R"))
  source(file.path("R", "nvidia_api.R"))
  source(file.path("R", "ai_tools.R"))
  source(file.path("R", "tool_fun.R"))
  source(file.path("R", "teacher_info.R"))
  source(file.path("R", "custom_stream.R"))
} else {
  library(ullme)
}
if (!exists("ullme_chat_debug")) {
  ullme_chat_debug = function(...) invisible(NULL)
}

api_key_file = Sys.getenv(
  "NVIDIA_API_KEY_FILE",
  unset="C:/libraries/ullme/nvidia_api_key.txt"
)
image_path = Sys.getenv("ULLME_TEST_IMAGE", unset=file.path("tests", "test_image.png"))
extra_variants = identical(Sys.getenv("ULLME_TEST_EXTRA_VARIANTS"), "true")

model_env = trimws(Sys.getenv("ULLME_TEST_MODELS", unset=""))
single_model_env = trimws(Sys.getenv("ULLME_TEST_MODEL", unset=""))
models = if (nzchar(model_env)) {
  trimws(strsplit(model_env, ",", fixed=TRUE)[[1]])
} else if (nzchar(single_model_env)) {
  single_model_env
} else {
  c(
    ullme_nvidia_default_model(),
    "nvidia/nemotron-3-nano-30b-a3b",
    "mistralai/mistral-small-4-119b-2603"
  )
}
models = unique(models[nzchar(models)])

question = paste(
  "You are receiving an actual image attachment.",
  "If you can inspect it, start your answer with IMAGE_SEEN:",
  "and briefly describe visible objects, colors, and style.",
  "If you cannot inspect it, start your answer with IMAGE_NOT_SEEN:."
)

if (!file.exists(api_key_file)) {
  stop("Set api_key_file at the top of this script or NVIDIA_API_KEY_FILE.")
}
if (!file.exists(image_path)) {
  stop("Cannot find image_path: ", image_path)
}
if (!requireNamespace("httr2", quietly=TRUE)) {
  stop("This live test requires httr2.")
}
if (!requireNamespace("jsonlite", quietly=TRUE)) {
  stop("This live test requires jsonlite.")
}

image_bytes = readBin(image_path, "raw", file.info(image_path)$size)
image_base64 = ullme_custom_stream_clean_base64(
  jsonlite::base64_enc(image_bytes)
)
image_url = paste0("data:image/png;base64,", image_base64)
api_key = ullme_api_key(api_key_file, required=TRUE)
base_url = ullme_nvidia_base_url()

classify_image_answer = function(text) {
  lower = tolower(paste0(text, collapse=" "))
  if (grepl("image_seen", lower, fixed=TRUE)) return("seen")
  if (grepl("image_not_seen", lower, fixed=TRUE)) return("not_seen")
  refusal = grepl(
    "cannot inspect|can't inspect|unable to inspect|cannot view|can't view|unable to view|cannot see|can't see|unable to see",
    lower
  )
  visual = grepl(
    "portrait|illustration|woman|person|hair|leaf|green|watercolor|image shows|the image shows",
    lower
  )
  if (visual && !refusal) "seen" else if (refusal) "not_seen" else "unclear"
}

shorten = function(text, n=240) {
  text = gsub("[[:space:]]+", " ", paste0(text, collapse=" "))
  if (nchar(text) <= n) text else paste0(substr(text, 1, n - 3), "...")
}

send_body = function(model, label, body) {
  cat("\n--- ", model, " / ", label, " ---\n", sep="")
  message_types = vapply(body$messages, function(message) {
    content = message$content
    if (!is.list(content)) return("text")
    paste(vapply(
      content,
      function(part) part$type %||% "unknown",
      character(1)
    ), collapse=",")
  }, character(1))
  cat(
    "messages: ", length(body$messages),
    "; content: ", paste(message_types, collapse=" | "),
    "; tools: ", length(body$tools %||% list()), "\n",
    sep=""
  )
  response = httr2::request(paste0(base_url, "/chat/completions")) |>
    httr2::req_method("POST") |>
    httr2::req_headers(
      Authorization=paste("Bearer", api_key),
      `Content-Type`="application/json"
    ) |>
    httr2::req_body_json(body, auto_unbox=TRUE) |>
    httr2::req_timeout(90) |>
    httr2::req_error(is_error=function(response) FALSE) |>
    httr2::req_perform()
  status = httr2::resp_status(response)
  body_text = httr2::resp_body_string(response)
  if (status < 200 || status >= 300) {
    cat("HTTP ", status, "\n", body_text, "\n", sep="")
    return(list(label=label, model=model, status=status, text="", result="http_error"))
  }
  parsed = jsonlite::fromJSON(body_text, simplifyVector=FALSE)
  message = parsed$choices[[1]]$message
  text = paste0(message$content %||% "", collapse="")
  result = classify_image_answer(text)
  cat(shorten(text), "\n", sep="")
  list(label=label, model=model, status=status, text=text, result=result)
}

standard_body = function(model) {
  list(
    model=model,
    messages=list(list(
      role="user",
      content=list(
        list(type="text", text=question),
        list(type="image_url", image_url=list(url=image_url))
      )
    )),
    temperature=0.2,
    max_tokens=500,
    stream=FALSE
  )
}

custom_body = function(model, enable_ai_tools=TRUE) {
  app = new.env(parent=emptyenv())
  app$role = "teacher"
  app$enable_ai_tools = isTRUE(enable_ai_tools)
  app$api_config = list(provider="nvidia", model=model)
  app$uploads_dir = tempfile("ullme-custom-live-uploads-")
  messages = ullme_custom_stream_initial_messages(
    input=question,
    system_prompt=NULL,
    uploads=list(list(
      id="live_test",
      name=basename(image_path),
      size=length(image_bytes),
      type="image/png",
      data_url=image_url
    )),
    app=app
  )
  body = ullme_custom_stream_body(
    input=question,
    model=model,
    messages=messages,
    app=app
  )
  body$stream = FALSE
  body$temperature = 0.2
  body$max_tokens = 500
  body
}

cat("Image: ", image_path, "\n", sep="")
cat("Image bytes: ", length(image_bytes), "\n", sep="")
cat("Models: ", paste(models, collapse=", "), "\n", sep="")

results = list()
for (model in models) {
  results[[length(results) + 1L]] =
    send_body(model, "standard image_url", standard_body(model))
  results[[length(results) + 1L]] =
    send_body(model, "custom backend body with tools enabled", custom_body(
      model,
      enable_ai_tools=TRUE
    ))
  if (isTRUE(extra_variants)) {
    body = standard_body(model)
    body$messages[[1]]$content[[2]] =
      list(type="image_url", image_url=image_url)
    results[[length(results) + 1L]] =
      send_body(model, "invalid image_url string check", body)
  }
}

cat("\nSummary:\n")
for (result in results) {
  cat(
    result$model, " | ", result$label, " | ",
    result$result, " | HTTP ", result$status, "\n",
    sep=""
  )
}
cat("\nDone.\n")
