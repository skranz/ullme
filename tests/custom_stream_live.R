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

# Edit these paths/model if needed before running.
api_key_file = Sys.getenv(
  "NVIDIA_API_KEY_FILE",
  unset="C:/libraries/ullme/nvidia_api_key.txt"
)
model = Sys.getenv(
  "ULLME_TEST_MODEL",
  unset="mistralai/mistral-small-4-119b-2603"
)
extra_variants = identical(Sys.getenv("ULLME_TEST_EXTRA_VARIANTS"), "true")
image_path = file.path("tests", "test_image.png")
question = paste(
  "You are receiving an actual image attachment.",
  "Briefly describe what is visible in the image.",
  "If you cannot inspect it, say exactly that."
)

if (!file.exists(api_key_file)) {
  stop("Set api_key_file at the top of this script.")
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
image_base64 = gsub("[[:space:]]", "", jsonlite::base64_enc(image_bytes))
image_url = paste0(
  "data:image/png;base64,",
  image_base64
)
api_key = ullme_api_key(api_key_file, required=TRUE)
base_url = ullme_nvidia_base_url()

send_body = function(label, body) {
  cat("\n--- ", label, " ---\n", sep="")
  message_types = vapply(body$messages, function(message) {
    content = message$content
    if (!is.list(content)) return("text")
    paste(vapply(content, function(part) part$type %||% "unknown", character(1)),
          collapse=",")
  }, character(1))
  cat("messages: ", length(body$messages),
      "; content: ", paste(message_types, collapse=" | "),
      "; tools: ", length(body$tools %||% list()), "\n", sep="")
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
    return(invisible(""))
  }
  parsed = jsonlite::fromJSON(body_text, simplifyVector=FALSE)
  message = parsed$choices[[1]]$message
  text = paste0(message$content %||% "", collapse="")
  if (!nzchar(text) && length(message$tool_calls %||% list())) {
    text = paste0(
      "[model returned tool_calls: ",
      paste(vapply(
        message$tool_calls,
        function(call) paste0(call$`function`$name %||% "")[1],
        character(1)
      ), collapse=", "),
      "]"
    )
  }
  cat(text, "\n", sep="")
  invisible(text)
}

send_variant = function(label, image_part) {
  send_body(label, list(
    model=model,
    messages=list(
      list(
        role="user",
        content=list(
          list(type="text", text=question),
          image_part
        )
      )
    ),
    temperature=0.2,
    max_tokens=500,
    stream=FALSE
  ))
}

send_custom_body = function(label, enable_ai_tools=FALSE) {
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
  send_body(label, body)
}

cat("Model: ", model, "\n", sep="")
cat("Image bytes: ", length(image_bytes), "\n", sep="")

standard = send_variant(
  "standard image_url",
  list(type="image_url", image_url=list(url=image_url))
)

custom_no_tools = send_custom_body(
  "custom backend body no tools",
  enable_ai_tools=FALSE
)

custom_with_tools = tryCatch(
  send_custom_body(
    "custom backend body with tools",
    enable_ai_tools=TRUE
  ),
  error=function(e) {
    cat("custom backend body with tools failed: ", conditionMessage(e), "\n", sep="")
    ""
  }
)

if (isTRUE(extra_variants)) {
image_url_string = send_variant(
  "image_url string",
  list(type="image_url", image_url=image_url)
)

nvidia_bare_base64 = send_variant(
  "nvidia bare base64 image_url",
  list(type="image_url", image_url=list(url=image_base64))
)

alternative = tryCatch(
  send_variant(
    "alternative input_image",
    list(type="input_image", image_url=image_url)
  ),
  error=function(e) {
    cat("alternative input_image failed: ", conditionMessage(e), "\n", sep="")
    ""
  }
)

alternative_object = tryCatch(
  send_variant(
    "alternative input_image object",
    list(type="input_image", image_url=list(url=image_url))
  ),
  error=function(e) {
    cat("alternative input_image object failed: ", conditionMessage(e), "\n", sep="")
    ""
  }
)
}

cat("\nDone.\n")
