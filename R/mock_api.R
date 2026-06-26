# Dear Codex / AI please don't remove my example functions!
example = function() {
  library(ullme)

  ullme_start_mock_openai_api_job(port = 8124, tool_mode = "always")

  chat = ullme_mock_ellmer_chat(port = 8124)
  chat$register_tool(ullme_mock_time_tool())
  chat$chat("Please call the time tool")
  chat$chat("Hello")

}


if (!exists("restore.point", mode = "function")) {
  restore.point = function(...) invisible(NULL)
}


ullme_mock_openai_api = function(model = "ullme-mock",
                                response_text = NULL,
                                tool_mode = c("auto", "always", "never")) {
  restore.point("ullme_mock_openai_api")
  ullme_mock_require_namespace("plumber")
  ullme_mock_require_namespace("jsonlite")

  tool_mode = match.arg(tool_mode)
  api = plumber::pr()

  api$handle("GET", "/", function() {
    ullme_mock_status(model = model)
  })
  api$handle("GET", "/v1", function() {
    ullme_mock_status(model = model)
  })
  api$handle("GET", "/models", function() {
    ullme_mock_models(model = model)
  })
  api$handle("GET", "/v1/models", function() {
    ullme_mock_models(model = model)
  })

  api$handle("POST", "/chat/completions", function(req, res) {
    body = ullme_mock_request_body(req)
    ullme_mock_chat_handler(
      body = body,
      res = res,
      model = model,
      response_text = response_text,
      tool_mode = tool_mode
    )
  })
  api$handle("POST", "/v1/chat/completions", function(req, res) {
    body = ullme_mock_request_body(req)
    ullme_mock_chat_handler(
      body = body,
      res = res,
      model = model,
      response_text = response_text,
      tool_mode = tool_mode
    )
  })

  api$handle("POST", "/responses", function(req, res) {
    body = ullme_mock_request_body(req)
    ullme_mock_responses_handler(
      body = body,
      res = res,
      model = model,
      response_text = response_text,
      tool_mode = tool_mode
    )
  })
  api$handle("POST", "/v1/responses", function(req, res) {
    body = ullme_mock_request_body(req)
    ullme_mock_responses_handler(
      body = body,
      res = res,
      model = model,
      response_text = response_text,
      tool_mode = tool_mode
    )
  })

  api
}


ullme_run_mock_openai_api = function(port = 8123,
                                    host = "127.0.0.1",
                                    model = "ullme-mock",
                                    response_text = NULL,
                                    tool_mode = c("auto", "always", "never")) {
  restore.point("ullme_run_mock_openai_api")
  tool_mode = match.arg(tool_mode)
  api = ullme_mock_openai_api(
    model = model,
    response_text = response_text,
    tool_mode = tool_mode
  )
  message("Mock OpenAI API: http://", host, ":", port, "/v1")
  message("ellmer chat completions: ellmer::chat_openai_compatible(base_url = \"http://", host, ":", port, "/v1\", model = \"", model, "\", credentials = function() \"mock-key\")")
  api$run(host = host, port = port)
}


ullme_start_mock_openai_api_job = function(port = 8123,
                                          host = "127.0.0.1",
                                          model = "ullme-mock",
                                          response_text = NULL,
                                          tool_mode = c("auto", "always", "never"),
                                          name = "ullme mock OpenAI API",
                                          source_file = file.path(getwd(), "R", "mock_api.R")) {
  restore.point("ullme_start_mock_openai_api_job")
  ullme_mock_require_namespace("rstudioapi")
  if (!rstudioapi::isAvailable()) {
    stop("rstudioapi is installed, but RStudio is not available.")
  }

  tool_mode = match.arg(tool_mode)
  source_file = normalizePath(source_file, winslash = "/", mustWork = FALSE)
  job_file = tempfile("ullme-mock-api-", fileext = ".R")
  source_line = if (file.exists(source_file)) {
    paste0("source(", deparse(source_file), ")")
  } else {
    "library(ullme)"
  }

  code = c(
    "library(restorepoint)",
    source_line,
    "ullme_run_mock_openai_api(",
    paste0("  port = ", as.integer(port), ","),
    paste0("  host = ", deparse(host), ","),
    paste0("  model = ", deparse(model), ","),
    paste0("  response_text = ", deparse(response_text), ","),
    paste0("  tool_mode = ", deparse(tool_mode)),
    ")"
  )
  writeLines(code, job_file, useBytes = TRUE)

  rstudioapi::jobRunScript(
    path = job_file,
    name = name,
    workingDir = getwd(),
    importEnv = FALSE
  )
  invisible(list(
    port = port,
    host = host,
    base_url = paste0("http://", host, ":", port, "/v1"),
    job_file = job_file
  ))
}


ullme_mock_ellmer_chat = function(port = 8123,
                                  host = "127.0.0.1",
                                  model = "ullme-mock",
                                  use_responses_api = FALSE,
                                  stream = NULL,
                                  api_args = list(),
                                  ...) {
  restore.point("ullme_mock_ellmer_chat")
  ullme_mock_require_namespace("ellmer")
  base_url = paste0("http://", host, ":", port, "/v1")
  credentials = function() "mock-key"
  if (!is.null(stream)) {
    api_args = utils::modifyList(list(stream = stream), api_args)
  }

  if (isTRUE(use_responses_api)) {
    return(ellmer::chat_openai(
      base_url = base_url,
      model = model,
      credentials = credentials,
      api_args = api_args,
      ...
    ))
  }

  ellmer::chat_openai_compatible(
    base_url = base_url,
    model = model,
    credentials = credentials,
    api_args = api_args,
    ...
  )
}


ullme_mock_time_tool = function() {
  restore.point("ullme_mock_time_tool")
  ullme_mock_require_namespace("ellmer")
  ellmer::tool(
    function(tz = "UTC") {
      format(Sys.time(), tz = tz, usetz = TRUE)
    },
    name = "get_current_time",
    description = "Returns the current time in the requested time zone.",
    arguments = list(
      tz = ellmer::type_string(
        "Time zone to display the current time in. Defaults to UTC.",
        required = FALSE
      )
    )
  )
}


ullme_mock_weather_tool = function() {
  restore.point("ullme_mock_weather_tool")
  ullme_mock_require_namespace("ellmer")
  ellmer::tool(
    function(cities) {
      raining = c(London = "heavy", Houston = "none", Chicago = "overcast", Ulm = "light")
      temperature = c(London = "cool", Houston = "hot", Chicago = "warm", Ulm = "mild")
      wind = c(London = "strong", Houston = "weak", Chicago = "strong", Ulm = "calm")
      data.frame(
        city = cities,
        raining = unname(raining[cities]),
        temperature = unname(temperature[cities]),
        wind = unname(wind[cities])
      )
    },
    name = "get_weather",
    description = "Reports deterministic mock weather for one or more cities.",
    arguments = list(
      cities = ellmer::type_array(ellmer::type_string(), "City names")
    )
  )
}


ullme_mock_chat_handler = function(body, res, model, response_text, tool_mode) {
  restore.point("ullme_mock_chat_handler")
  tryCatch({
    result = ullme_mock_chat_completion(
      body = body,
      model = model,
      response_text = response_text,
      tool_mode = tool_mode
    )

    if (isTRUE(body$stream)) {
      res$setHeader("Content-Type", "text/event-stream")
      res$setHeader("Cache-Control", "no-cache")
      res$body = ullme_mock_chat_stream(result)
      return(res)
    }

    result
  }, error = function(e) {
    ullme_mock_log_body(body = body, endpoint = "chat/completions")
    ullme_mock_handler_error(e = e, res = res, endpoint = "chat/completions")
  })
}


ullme_mock_responses_handler = function(body, res, model, response_text, tool_mode) {
  restore.point("ullme_mock_responses_handler")
  tryCatch({
    result = ullme_mock_response_completion(
      body = body,
      model = model,
      response_text = response_text,
      tool_mode = tool_mode
    )

    if (isTRUE(body$stream)) {
      res$setHeader("Content-Type", "text/event-stream")
      res$setHeader("Cache-Control", "no-cache")
      res$body = ullme_mock_response_stream(result)
      return(res)
    }

    result
  }, error = function(e) {
    ullme_mock_log_body(body = body, endpoint = "responses")
    ullme_mock_handler_error(e = e, res = res, endpoint = "responses")
  })
}


ullme_mock_log_body = function(body, endpoint) {
  restore.point("ullme_mock_log_body")
  body_str = paste0(capture.output(str(body)), collapse = " ")
  message("ullme mock API body at /", endpoint, ": ", body_str)
}


ullme_mock_handler_error = function(e, res, endpoint) {
  restore.point("ullme_mock_handler_error")
  msg = conditionMessage(e)
  message("ullme mock API error at /", endpoint, ": ", msg)
  res$status = 500
  list(error = msg)
}


ullme_mock_chat_completion = function(body, model, response_text, tool_mode) {
  restore.point("ullme_mock_chat_completion")
  model = ullme_mock_value(body$model, model)
  id = ullme_mock_id("chatcmpl")
  created = as.integer(Sys.time())
  messages = ullme_mock_value(body$messages, list())
  input_text = ullme_mock_latest_text(messages, role = "user")
  tool_text = ullme_mock_latest_text(messages, role = "tool")
  tool = ullme_mock_selected_chat_tool(body = body, tool_mode = tool_mode)

  if (!is.null(tool)) {
    tool_call = ullme_mock_chat_tool_call(tool)
    message = list(
      role = "assistant",
      content = "",
      tool_calls = list(tool_call)
    )
    finish_reason = "tool_calls"
  } else {
    text = ullme_mock_answer_text(
      input_text = input_text,
      tool_text = tool_text,
      response_text = response_text
    )
    message = list(
      role = "assistant",
      content = text
    )
    finish_reason = "stop"
  }

  list(
    id = id,
    object = "chat.completion",
    created = created,
    model = model,
    choices = list(list(
      index = 0,
      message = message,
      finish_reason = finish_reason
    )),
    usage = ullme_mock_chat_usage(messages = messages, message = message)
  )
}


ullme_mock_response_completion = function(body, model, response_text, tool_mode) {
  restore.point("ullme_mock_response_completion")
  model = ullme_mock_value(body$model, model)
  id = ullme_mock_id("resp")
  input = ullme_mock_value(body$input, list())
  input_text = ullme_mock_latest_response_text(input = input)
  tool_text = ullme_mock_latest_response_tool_text(input = input)
  tool = ullme_mock_selected_response_tool(body = body, tool_mode = tool_mode)

  if (!is.null(tool)) {
    output = list(ullme_mock_response_tool_call(tool))
  } else {
    text = ullme_mock_answer_text(
      input_text = input_text,
      tool_text = tool_text,
      response_text = response_text
    )
    output = list(list(
      type = "message",
      id = ullme_mock_id("msg"),
      role = "assistant",
      content = list(list(type = "output_text", text = text))
    ))
  }

  list(
    id = id,
    object = "response",
    created_at = as.integer(Sys.time()),
    status = "completed",
    model = model,
    output = output,
    usage = ullme_mock_response_usage(input = input, output = output)
  )
}


ullme_mock_selected_chat_tool = function(body, tool_mode) {
  restore.point("ullme_mock_selected_chat_tool")
  if (identical(tool_mode, "never")) return(NULL)
  if (ullme_mock_has_tool_result(body$messages)) return(NULL)
  if (identical(body$tool_choice, "none")) return(NULL)

  tools = ullme_mock_value(body$tools, list())
  if (length(tools) == 0) return(NULL)

  if (is.list(body$tool_choice) && !is.null(body$tool_choice$`function`$name)) {
    return(ullme_mock_find_chat_tool(tools, body$tool_choice$`function`$name))
  }

  if (identical(tool_mode, "always")) return(tools[[1]])

  input_text = tolower(ullme_mock_latest_text(body$messages, role = "user"))
  if (grepl("\\b(tool|call|weather|time|date|course)\\b", input_text)) {
    return(tools[[1]])
  }

  NULL
}


ullme_mock_selected_response_tool = function(body, tool_mode) {
  restore.point("ullme_mock_selected_response_tool")
  if (identical(tool_mode, "never")) return(NULL)
  if (ullme_mock_has_response_tool_result(body$input)) return(NULL)
  if (identical(body$tool_choice, "none")) return(NULL)

  tools = ullme_mock_value(body$tools, list())
  if (length(tools) == 0) return(NULL)

  if (is.list(body$tool_choice) && !is.null(body$tool_choice$name)) {
    return(ullme_mock_find_response_tool(tools, body$tool_choice$name))
  }

  if (identical(tool_mode, "always")) return(tools[[1]])

  input_text = tolower(ullme_mock_latest_response_text(body$input))
  if (grepl("\\b(tool|call|weather|time|date|course)\\b", input_text)) {
    return(tools[[1]])
  }

  NULL
}


ullme_mock_chat_tool_call = function(tool) {
  restore.point("ullme_mock_chat_tool_call")
  fn = ullme_mock_first_record(ullme_mock_value(tool$`function`, tool$unction))
  fn = ullme_mock_value(fn, list())
  arguments = ullme_mock_tool_arguments(fn$parameters)
  list(
    id = ullme_mock_id("call"),
    type = "function",
    `function` = list(
      name = ullme_mock_value(fn$name, "mock_tool"),
      arguments = ullme_mock_json(arguments)
    )
  )
}


ullme_mock_response_tool_call = function(tool) {
  restore.point("ullme_mock_response_tool_call")
  tool = ullme_mock_first_record(tool)
  arguments = ullme_mock_tool_arguments(tool$parameters)
  call_id = ullme_mock_id("call")
  list(
    type = "function_call",
    id = call_id,
    call_id = call_id,
    name = ullme_mock_value(tool$name, "mock_tool"),
    arguments = ullme_mock_json(arguments)
  )
}


ullme_mock_answer_text = function(input_text, tool_text, response_text) {
  restore.point("ullme_mock_answer_text")
  if (!is.null(response_text)) return(response_text)
  if (nzchar(tool_text)) {
    return(paste0("Mock assistant used the tool result: ", tool_text))
  }
  if (!nzchar(input_text)) {
    return("Mock assistant response.")
  }
  paste0("Mock assistant response to: ", input_text)
}


ullme_mock_chat_stream = function(result) {
  restore.point("ullme_mock_chat_stream")
  choice = result$choices[[1]]
  chunk = list(
    id = result$id,
    object = "chat.completion.chunk",
    created = result$created,
    model = result$model,
    choices = list(list(
      index = 0,
      delta = choice$message,
      finish_reason = choice$finish_reason
    )),
    usage = result$usage
  )
  paste0(
    "data: ", ullme_mock_json(chunk), "\n\n",
    "data: [DONE]\n\n"
  )
}


ullme_mock_response_stream = function(result) {
  restore.point("ullme_mock_response_stream")
  output = result$output[[1]]
  events = list()

  if (identical(output$type, "message")) {
    text = output$content[[1]]$text
    events[[length(events) + 1]] = list(
      type = "response.output_text.delta",
      item_id = output$id,
      output_index = 0,
      content_index = 0,
      delta = text
    )
  }

  events[[length(events) + 1]] = list(
    type = "response.completed",
    response = result
  )

  lines = vapply(events, function(event) {
    paste0("data: ", ullme_mock_json(event), "\n\n")
  }, character(1))
  paste0(paste0(lines, collapse = ""), "data: [DONE]\n\n")
}


ullme_mock_request_body = function(req) {
  restore.point("ullme_mock_request_body")
  body = req$body
  if (is.list(body) && length(body) > 0) return(ullme_mock_normalize_json(body))
  parsed_body = ullme_mock_parse_json_body(body)
  if (is.list(parsed_body)) return(ullme_mock_normalize_json(parsed_body))

  post_body = req$postBody
  parsed_post_body = ullme_mock_parse_json_body(post_body)
  if (is.list(parsed_post_body)) return(ullme_mock_normalize_json(parsed_post_body))

  list()
}


ullme_mock_normalize_json = function(x) {
  restore.point("ullme_mock_normalize_json")
  if (is.data.frame(x)) {
    rows = lapply(seq_len(NROW(x)), function(i) {
      ullme_mock_normalize_json(as.list(x[i, , drop = FALSE]))
    })
    return(rows)
  }
  if (is.list(x)) {
    out = lapply(x, ullme_mock_normalize_json)
    names(out) = names(x)
    return(out)
  }
  if (length(x) == 1) return(x[[1]])
  x
}


ullme_mock_first_record = function(x) {
  restore.point("ullme_mock_first_record")
  while (is.list(x) && length(x) == 1 && is.null(names(x))) {
    x = x[[1]]
  }
  x
}


ullme_mock_parse_json_body = function(x) {
  restore.point("ullme_mock_parse_json_body")
  if (is.null(x)) return(NULL)
  if (is.raw(x)) x = rawToChar(x)
  if (!is.character(x) || length(x) == 0) return(NULL)

  x = paste0(x, collapse = "")
  x = trimws(x)
  if (!nzchar(x)) return(NULL)

  parsed = tryCatch(
    jsonlite::fromJSON(x, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.character(parsed) && length(parsed) == 1) {
    parsed2 = tryCatch(
      jsonlite::fromJSON(parsed, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.list(parsed2)) return(parsed2)
  }
  if (is.list(parsed)) return(parsed)
  NULL
}


ullme_mock_tool_arguments = function(parameters) {
  restore.point("ullme_mock_tool_arguments")
  parameters = ullme_mock_first_record(parameters)
  properties = parameters$properties
  properties = ullme_mock_first_record(properties)
  if (is.null(properties) || length(properties) == 0) return(list())

  args = lapply(names(properties), function(name) {
    ullme_mock_schema_value(schema = properties[[name]], name = name)
  })
  names(args) = names(properties)
  args
}


ullme_mock_schema_value = function(schema, name = "") {
  restore.point("ullme_mock_schema_value")
  schema = ullme_mock_first_record(schema)
  type = schema$type
  if (is.list(type)) type = type[[1]]
  if (is.character(type) && "null" %in% type && length(type) > 1) {
    type = type[type != "null"][[1]]
  }
  if (!is.null(schema$enum) && length(schema$enum) > 0) {
    return(schema$enum[[1]])
  }

  switch(
    type,
    string = ullme_mock_string_value(name),
    integer = 1L,
    number = 1,
    boolean = TRUE,
    array = list(
      ullme_mock_schema_value(
        schema = ullme_mock_value(schema$items, list(type = "string")),
        name = sub("s$", "", name)
      )
    ),
    object = ullme_mock_tool_arguments(schema),
    ullme_mock_string_value(name)
  )
}


ullme_mock_string_value = function(name) {
  restore.point("ullme_mock_string_value")
  name = tolower(name)
  if (name %in% c("tz", "timezone", "time_zone")) return("UTC")
  if (name %in% c("city", "location", "place")) return("Ulm")
  if (name %in% c("courseid", "course_id")) return("micro")
  if (name %in% c("coursename", "course_name")) return("Microeconomics")
  "mock-value"
}


ullme_mock_latest_text = function(messages, role = "user") {
  restore.point("ullme_mock_latest_text")
  if (is.null(messages) || length(messages) == 0) return("")
  roles = vapply(messages, function(message) {
    ullme_mock_value(message$role, "")
  }, character(1))
  idx = which(roles == role)
  if (length(idx) == 0) return("")
  ullme_mock_content_text(messages[[idx[[length(idx)]]]]$content)
}


ullme_mock_latest_response_text = function(input) {
  restore.point("ullme_mock_latest_response_text")
  if (is.null(input) || length(input) == 0) return("")
  texts = vapply(input, function(item) {
    if (!is.null(item$content)) return(ullme_mock_content_text(item$content))
    ""
  }, character(1))
  texts = texts[nzchar(texts)]
  if (length(texts) == 0) return("")
  texts[[length(texts)]]
}


ullme_mock_latest_response_tool_text = function(input) {
  restore.point("ullme_mock_latest_response_tool_text")
  if (is.null(input) || length(input) == 0) return("")
  texts = vapply(input, function(item) {
    if (identical(item$type, "function_call_output")) {
      return(ullme_mock_value(item$output, ""))
    }
    ""
  }, character(1))
  texts = texts[nzchar(texts)]
  if (length(texts) == 0) return("")
  texts[[length(texts)]]
}


ullme_mock_content_text = function(content) {
  restore.point("ullme_mock_content_text")
  if (is.null(content)) return("")
  if (is.character(content)) return(paste0(content, collapse = "\n"))
  if (!is.list(content)) return(paste0(content))

  parts = vapply(content, function(part) {
    if (is.null(part)) return("")
    part = ullme_mock_first_record(part)
    if (is.null(part)) return("")
    if (is.character(part)) return(paste0(part, collapse = " "))
    if (!is.list(part)) return(paste0(part))
    if (!is.null(part$text)) return(paste0(part$text, collapse = " "))
    if (!is.null(part$image_url)) return("[image]")
    if (!is.null(part$file)) return("[file]")
    ullme_mock_content_text(part)
  }, character(1))
  paste0(parts[nzchar(parts)], collapse = "\n")
}


ullme_mock_has_tool_result = function(messages) {
  restore.point("ullme_mock_has_tool_result")
  if (is.null(messages) || length(messages) == 0) return(FALSE)
  any(vapply(messages, function(message) identical(message$role, "tool"), logical(1)))
}


ullme_mock_has_response_tool_result = function(input) {
  restore.point("ullme_mock_has_response_tool_result")
  if (is.null(input) || length(input) == 0) return(FALSE)
  any(vapply(input, function(item) identical(item$type, "function_call_output"), logical(1)))
}


ullme_mock_find_chat_tool = function(tools, name) {
  restore.point("ullme_mock_find_chat_tool")
  for (tool in tools) {
    fn = ullme_mock_first_record(ullme_mock_value(tool$`function`, tool$unction))
    if (identical(fn$name, name)) return(tool)
  }
  NULL
}


ullme_mock_find_response_tool = function(tools, name) {
  restore.point("ullme_mock_find_response_tool")
  for (tool in tools) {
    if (identical(tool$name, name)) return(tool)
  }
  NULL
}


ullme_mock_models = function(model) {
  restore.point("ullme_mock_models")
  list(
    object = "list",
    data = list(list(
      id = model,
      object = "model",
      created = as.integer(Sys.time()),
      owned_by = "ullme"
    ))
  )
}


ullme_mock_status = function(model) {
  restore.point("ullme_mock_status")
  list(
    ok = TRUE,
    name = "ullme mock OpenAI API",
    model = model,
    endpoints = c(
      "/v1/models",
      "/v1/chat/completions",
      "/v1/responses"
    )
  )
}


ullme_mock_chat_usage = function(messages, message) {
  restore.point("ullme_mock_chat_usage")
  prompt_text = paste0(vapply(messages, function(x) {
    ullme_mock_content_text(x$content)
  }, character(1)), collapse = "\n")
  completion_text = ullme_mock_content_text(message$content)
  list(
    prompt_tokens = ullme_mock_token_count(prompt_text),
    completion_tokens = ullme_mock_token_count(completion_text),
    total_tokens = ullme_mock_token_count(prompt_text) + ullme_mock_token_count(completion_text),
    prompt_tokens_details = list(cached_tokens = 0)
  )
}


ullme_mock_response_usage = function(input, output) {
  restore.point("ullme_mock_response_usage")
  input_text = ullme_mock_latest_response_text(input)
  output_text = if (identical(output[[1]]$type, "message")) {
    output[[1]]$content[[1]]$text
  } else {
    output[[1]]$arguments
  }
  list(
    input_tokens = ullme_mock_token_count(input_text),
    output_tokens = ullme_mock_token_count(output_text),
    total_tokens = ullme_mock_token_count(input_text) + ullme_mock_token_count(output_text),
    input_tokens_details = list(cached_tokens = 0)
  )
}


ullme_mock_token_count = function(x) {
  restore.point("ullme_mock_token_count")
  max(1L, as.integer(ceiling(nchar(paste0(x), type = "chars") / 4)))
}


ullme_mock_json = function(x) {
  restore.point("ullme_mock_json")
  paste0(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}


ullme_mock_id = function(prefix) {
  restore.point("ullme_mock_id")
  paste0(prefix, "_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", as.integer(runif(1, 1, 1e8)))
}


ullme_mock_value = function(x, default) {
  restore.point("ullme_mock_value")
  if (is.null(x)) return(default)
  x
}


ullme_mock_require_namespace = function(package) {
  restore.point("ullme_mock_require_namespace")
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Package '", package, "' is required for this mock API helper.")
  }
  invisible(TRUE)
}
