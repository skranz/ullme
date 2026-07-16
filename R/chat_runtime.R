ullme_chat_debug = function(app=NULL, ...) {
  if (is.null(app) || !isTRUE(app$chat_debug)) return(invisible(FALSE))
  tryCatch({
    cat(
      format(Sys.time(), "%Y-%m-%d %H:%M:%OS3"),
      " ullme chat debug: ", paste0(..., collapse=""), "\n",
      sep="", file=stderr()
    )
    flush.console()
  }, error=function(e) NULL)
  invisible(TRUE)
}


ullme_ai_connection_status = function(model=NULL, waiting=FALSE,
                                       app=getApp()) {
  config = app$api_config
  model = paste0(model %||% config$model %||% "configured model")[1]
  provider = switch(
    paste0(config$provider %||% "")[1],
    nvidia="NVIDIA NIM",
    local="the local model server",
    fake="the test model",
    paste0(config$provider %||% "the model provider")[1]
  )
  base_url = sub("^https?://", "", paste0(config$base_url %||% "")[1])
  host = sub("/.*$", "", base_url)
  destination = paste0(
    provider,
    if (nzchar(host)) paste0(" at ", host) else ""
  )
  if (isTRUE(waiting)) {
    return(paste0(
      "Still waiting for ", model, " through ", destination,
      ". No model output has arrived yet."
    ))
  }
  paste0(
    "Trying to connect to ", model, " through ", destination, "… ",
    "If no model output arrives within ",
    format(app$chat_connect_timeout_seconds %||% 60, trim=TRUE),
    " seconds, this request will stop."
  )
}


ullme_await_promise = function(promise, seconds=180,
                                on_timeout=function() NULL) {
  seconds = suppressWarnings(as.numeric(seconds)[1])
  if (is.na(seconds) || seconds <= 0) stop("seconds must be positive.")
  settled = FALSE
  value = NULL
  error = NULL
  promises::then(
    promise,
    onFulfilled=function(result) {
      value <<- result
      settled <<- TRUE
      NULL
    },
    onRejected=function(condition) {
      error <<- condition
      settled <<- TRUE
      NULL
    }
  )
  deadline = as.numeric(Sys.time()) + seconds
  while (!settled && as.numeric(Sys.time()) < deadline) {
    remaining = deadline - as.numeric(Sys.time())
    later::run_now(timeoutSecs=max(0, min(0.1, remaining)), all=TRUE)
  }
  if (!settled) {
    try(on_timeout(), silent=TRUE)
    stop(paste0(
      "The model request timed out after ", format(seconds, trim=TRUE),
      " seconds."
    ))
  }
  if (!is.null(error)) stop(error)
  value
}


ullme_promise_timeout = function(promise, seconds=180,
                                  is_paused=function() FALSE) {
  seconds = suppressWarnings(as.numeric(seconds)[1])
  if (is.na(seconds) || seconds <= 0) return(promise)
  promises::promise(function(resolve, reject) {
    settled = FALSE
    remaining = seconds
    last_check = as.numeric(Sys.time())
    check_timeout = NULL
    check_timeout = function() {
      if (settled) return(invisible(NULL))
      now = as.numeric(Sys.time())
      paused = tryCatch(isTRUE(is_paused()), error=function(e) FALSE)
      if (!paused) remaining <<- remaining - max(0, now - last_check)
      last_check <<- now
      if (remaining <= 0) {
        settled <<- TRUE
        reject(simpleError(paste0(
          "The model request timed out after ", format(seconds, trim=TRUE),
          " active seconds."
        )))
        return(invisible(NULL))
      }
      later::later(check_timeout, delay=max(0.05, min(1, remaining)))
      invisible(NULL)
    }
    later::later(check_timeout, delay=max(0.05, min(1, remaining)))
    promises::then(
      promise,
      onFulfilled=function(value) {
        if (settled) return(invisible(NULL))
        settled <<- TRUE
        resolve(value)
        invisible(NULL)
      },
      onRejected=function(error) {
        if (settled) return(invisible(NULL))
        settled <<- TRUE
        reject(error)
        invisible(NULL)
      }
    )
  })
}


ullme_request_stream_state = function(request) {
  list(
    text=if (is.null(request$state)) "" else request$state$text %||% "",
    thinking=if (is.null(request$state)) "" else
      request$state$thinking %||% ""
  )
}


ullme_send_tool_activity = function(request, activity="",
                                     waiting_for_approval=FALSE,
                                     app=getApp()) {
  if (is.null(request) || !isTRUE(request$active)) return(invisible(FALSE))
  state = ullme_request_stream_state(request)
  ullme_send_chat_stream_update(
    message_id=request$message_id,
    text=state$text,
    thinking=state$thinking,
    done=FALSE,
    activity=activity,
    waiting_for_user=isTRUE(waiting_for_approval),
    app=app
  )
  invisible(TRUE)
}


ullme_set_request_approval_wait = function(request, waiting, operation_id="",
                                            app=getApp()) {
  if (is.null(request)) return(invisible(FALSE))
  request$waiting_for_approval = isTRUE(waiting)
  if (!isTRUE(request$active)) return(invisible(FALSE))
  activity = if (isTRUE(waiting)) {
    "Waiting for your approval…"
  } else {
    "Approval decision received. Continuing…"
  }
  ullme_ai_interaction_tool_event(
    request$interaction_dir,
    list(
      event=if (isTRUE(waiting)) "approval_wait" else "approval_resolved",
      operation_id=paste0(operation_id)[1],
      at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
    ),
    request=request
  )
  ullme_send_tool_activity(
    request,
    activity=activity,
    waiting_for_approval=isTRUE(waiting),
    app=app
  )
}
