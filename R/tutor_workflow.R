ullme_render_prompt_once = function(text, values=list(), strict=TRUE) {
  text = paste0(text %||% "", collapse="\n")
  pattern = "\\{\\{[A-Za-z][A-Za-z0-9_]*\\}\\}"
  hits = gregexpr(pattern, text, perl=TRUE)[[1]]
  if (length(hits) == 1L && hits[[1]] < 0L) return(text)
  lengths = attr(hits, "match.length")
  for (i in rev(seq_along(hits))) {
    start = hits[[i]]
    end = start + lengths[[i]] - 1L
    token = substr(text, start, end)
    key = substr(token, 3L, nchar(token) - 2L)
    value = values[[key]]
    if (is.null(value)) {
      if (isTRUE(strict)) stop("Missing prompt value: ", key)
      next
    }
    text = paste0(
      if (start > 1L) substr(text, 1L, start - 1L) else "",
      paste0(value, collapse="\n"),
      if (end < nchar(text)) substr(text, end + 1L, nchar(text)) else ""
    )
  }
  text
}


ullme_tutor_workflow_init_prompt = function(tutor, app=getApp()) {
  values = ullme_student_tutor_values(tutor=tutor, app=app)
  if (is.null(values$personality)) {
    values$personality = tutor$default_personality %||% ""
  }
  ullme_render_prompt_once(
    tutor$prompt_fragments$init_prompt %||% "",
    values=values,
    strict=TRUE
  )
}


ullme_tutor_workflow_conversation_text = function(messages) {
  if (!length(messages)) return("")
  paste(vapply(messages, function(message) {
    role = if (identical(message$role %||% "", "assistant")) {
      "Tutor"
    } else {
      "Student"
    }
    paste0(role, ":\n", paste0(message$text %||% "", collapse="\n"))
  }, character(1)), collapse="\n\n")
}


ullme_tutor_workflow_history_text = function(state) {
  parts = character(0)
  conversation = ullme_tutor_workflow_conversation_text(
    state$conversation %||% list()
  )
  if (nzchar(conversation)) {
    parts = c(parts, paste0("Conversation so far:\n\n", conversation))
  }
  internal = state$internal_history %||% list()
  if (length(internal)) {
    rendered = vapply(internal, function(item) {
      paste0(
        "Internal output from node ", item$node %||% "unknown", ":\n",
        item$output %||% ""
      )
    }, character(1))
    parts = c(parts, paste0(
      "Internal workflow history:\n\n",
      paste(rendered, collapse="\n\n")
    ))
  }
  paste(parts, collapse="\n\n")
}


ullme_tutor_workflow_prompt = function(state, node) {
  tutor = state$tutor
  documents = ullme_student_tutor_values(tutor=tutor, app=state$app)
  fragments = lapply(tutor$prompt_fragments %||% list(), function(fragment) {
    ullme_render_prompt_once(fragment, documents, strict=FALSE)
  })
  history = ullme_tutor_workflow_history_text(state)
  values = c(fragments, list(
    input=state$input %||% "",
    output=state$output %||% "",
    hist=history,
    hist_or_init_prompt=history,
    image_uploaded=if (length(state$uploads %||% list())) "TRUE" else "FALSE"
  ))
  ullme_render_prompt_once(node$prompt %||% "", values=values, strict=TRUE)
}


ullme_tutor_workflow_new = function(tutor, input, uploads=list(),
                                     conversation=list(), model=NULL,
                                     app=getApp()) {
  state = new.env(parent=emptyenv())
  state$tutor = tutor
  state$app = app
  state$model = model
  state$node = tutor$start_node
  state$input = paste0(input %||% "", collapse="\n")
  state$uploads = uploads %||% list()
  state$conversation = conversation %||% list()
  state$internal_history = list()
  state$output = ""
  state$resuming = FALSE
  state$current_input_recorded = FALSE
  state$steps = 0L
  state$controllers = list()
  state$interaction_dir = NULL
  state$node_call_seq = 0L
  state
}


ullme_tutor_workflow_resume = function(state, input, uploads=list(),
                                        conversation=list()) {
  state$input = paste0(input %||% "", collapse="\n")
  state$uploads = c(state$uploads %||% list(), uploads %||% list())
  state$conversation = conversation %||% list()
  state$resuming = TRUE
  state$current_input_recorded = FALSE
  state
}


ullme_tutor_workflow_route_value = function(state, node) {
  input = node$switch_input %||% ""
  if (identical(input, "image_uploaded")) {
    return(if (length(state$uploads %||% list())) "TRUE" else "FALSE")
  }
  if (identical(input, "output")) return(trimws(state$output %||% ""))
  stop("Unsupported switch_input: ", input)
}


ullme_tutor_workflow_route = function(state, node) {
  routes = node$switch_to %||% list()
  value = ullme_tutor_workflow_route_value(state, node)
  target = routes[[value]]
  if (is.null(target)) {
    lower_names = tolower(names(routes) %||% character(0))
    found = which(lower_names == tolower(value))
    if (length(found)) target = routes[[found[[1]]]]
  }
  target = target %||% routes$DEFAULT
  if (is.null(target) || !nzchar(paste0(target)[1])) {
    stop("No workflow route for value '", value, "'.")
  }
  paste0(target)[1]
}


ullme_tutor_workflow_vote = function(outputs, node) {
  values = tolower(trimws(paste0(unlist(outputs, use.names=FALSE))))
  allowed = setdiff(tolower(names(node$switch_to %||% list())), "default")
  values = values[values %in% allowed]
  if (!length(values)) stop("The workflow vote produced no valid values.")
  counts = table(values)
  winner = names(counts)[which.max(counts)]
  if (unname(counts[[winner]]) <= length(outputs) / 2) {
    stop("The workflow vote did not produce a majority.")
  }
  winner
}


ullme_tutor_workflow_model_call = function(state, node, node_id, prompt,
                                            attempt=1L, parallel_call=1L,
                                            on_update=function(...) NULL) {
  system_prompt = ullme_tutor_workflow_init_prompt(
    state$tutor,
    app=state$app
  )
  debug_record = ullme_debug_session_model_call_start(
    state=state,
    node_id=node_id,
    attempt=attempt,
    parallel_call=parallel_call
  )
  job = NULL
  if (ullme_uses_fake_ai(app=state$app)) {
    value = if (identical(node$aggregate %||% "", "majority_vote")) {
      choices = setdiff(names(node$switch_to %||% list()), "DEFAULT")
      if (length(choices)) choices[[1]] else "ok"
    } else {
      paste0("Fake AI answer to:\n", prompt)
    }
    call = promises::promise(function(resolve, reject) resolve(list(
      text=value,
      thinking=""
    )))
  } else {
    job = ullme_start_custom_ai_stream(
      input=prompt,
      model=state$model,
      system_prompt_override=system_prompt,
      include_thinking=isTRUE(state$app$chat_debug),
      task_profile="",
      uploads=state$uploads,
      on_update=on_update,
      app=state$app
    )
    state$controllers[[length(state$controllers) + 1L]] = job$controller
    call = job$promise
  }
  promises::then(
    call,
    onFulfilled=function(result) {
      ullme_debug_session_model_call_finish(
        record=debug_record,
        state=state,
        system_prompt=system_prompt,
        prompt=prompt,
        answer=result$text %||% "",
        thinking=result$thinking %||% ""
      )
      result
    },
    onRejected=function(error) {
      partial_text = if (is.null(job)) "" else job$state$text %||% ""
      partial_thinking = if (is.null(job)) "" else
        job$state$thinking %||% ""
      ullme_debug_session_model_call_finish(
        record=debug_record,
        state=state,
        system_prompt=system_prompt,
        prompt=prompt,
        answer=partial_text,
        thinking=partial_thinking,
        error=conditionMessage(error)
      )
      stop(error)
    }
  )
}


ullme_tutor_workflow_call_node = function(state, node, node_id, prompt,
                                           on_final_update=function(...) NULL) {
  attempts_left = as.integer(node$n_retries %||% 0L)
  attempt = 0L
  run_attempt = NULL
  run_attempt = function() {
    attempt <<- attempt + 1L
    n = as.integer(node$n_parallel %||% 1L)
    calls = lapply(seq_len(n), function(i) {
      callback = if (n == 1L) on_final_update else function(...) NULL
      ullme_tutor_workflow_model_call(
        state, node, node_id, prompt,
        attempt=attempt,
        parallel_call=i,
        on_update=callback
      )
    })
    combined = promises::promise_all(.list=calls)
    promises::then(
      combined,
      onFulfilled=function(results) {
        outputs = lapply(results, function(result) result$text %||% "")
        if (identical(node$aggregate %||% "", "majority_vote")) {
          voted = tryCatch(
            ullme_tutor_workflow_vote(outputs, node),
            error=function(error) error
          )
          if (inherits(voted, "error")) {
            if (attempts_left <= 0L) stop(voted)
            attempts_left <<- attempts_left - 1L
            return(run_attempt())
          }
          voted
        } else {
          paste0(outputs[[1]] %||% "")
        }
      },
      onRejected=function(error) {
        if (attempts_left <= 0L) stop(error)
        attempts_left <<- attempts_left - 1L
        run_attempt()
      }
    )
  }
  run_attempt()
}


ullme_tutor_workflow_advance = function(state,
                                        on_waiting=function(...) NULL,
                                        on_final_update=function(...) NULL) {
  repeat {
    state$steps = state$steps + 1L
    if (state$steps > 40L) stop("The Tutor workflow exceeded 40 node steps.")
    node_id = state$node
    node = state$tutor$nodes[[node_id]]
    if (is.null(node)) stop("Unknown Tutor workflow node: ", node_id)

    if (isTRUE(node$ask_for_input) && !isTRUE(state$resuming)) {
      text = ullme_render_prompt_once(
        node$show_text %||% "",
        ullme_student_tutor_values(tutor=state$tutor, app=state$app),
        strict=FALSE
      )
      return(list(status="waiting", text=text, state=state, node=node_id))
    }
    state$resuming = FALSE
    prompt = node$prompt %||% ""
    if (nzchar(trimws(prompt))) {
      waiting = node$waiting_message %||% ""
      if (nzchar(waiting)) on_waiting(waiting, node_id)
      rendered = ullme_tutor_workflow_prompt(state, node)
      call = ullme_tutor_workflow_call_node(
        state, node, node_id, rendered,
        on_final_update=if (
          !nzchar(node[["next"]] %||% "") && is.null(node$switch_to)
        ) on_final_update else function(...) NULL
      )
      return(promises::then(call, onFulfilled=function(output) {
        state$output = paste0(output %||% "", collapse="\n")
        state$node_call_seq = state$node_call_seq + 1L
        ullme_ai_interaction_workflow_node(
          state$interaction_dir,
          index=state$node_call_seq,
          node=node_id,
          prompt=rendered,
          output=state$output
        )
        if (!isTRUE(state$current_input_recorded)) {
          state$conversation[[length(state$conversation) + 1L]] = list(
            role="user",
            text=state$input %||% ""
          )
          state$current_input_recorded = TRUE
        }
        if (!identical(node$add_to_history, FALSE)) {
          state$internal_history[[length(state$internal_history) + 1L]] = list(
            node=node_id,
            output=state$output
          )
        }
        if (!is.null(node$switch_to)) {
          state$node = ullme_tutor_workflow_route(state, node)
          return(ullme_tutor_workflow_advance(
            state,
            on_waiting=on_waiting,
            on_final_update=on_final_update
          ))
        }
        if (nzchar(node[["next"]] %||% "")) {
          state$node = node[["next"]]
          return(ullme_tutor_workflow_advance(
            state,
            on_waiting=on_waiting,
            on_final_update=on_final_update
          ))
        }
        list(status="completed", text=state$output, state=state, node=node_id)
      }))
    }
    if (!is.null(node$switch_to)) {
      state$node = ullme_tutor_workflow_route(state, node)
      next
    }
    stop("Tutor workflow node '", node_id, "' has no executable action.")
  }
}


ullme_tutor_workflow_cancel = function(state, reason="Stopped by user") {
  for (controller in state$controllers %||% list()) {
    try(controller$cancel(reason), silent=TRUE)
  }
  invisible(TRUE)
}


ullme_handle_student_tutor_submit = function(text, model, uploads=NULL,
                                              clientMessageId=NULL,
                                              assistantMessageId=NULL,
                                              app=getApp()) {
  tutor = ullme_student_selected_tutor(app=app)
  if (is.null(tutor)) stop("No AI Tutor is selected.")
  if (!length(tutor$nodes %||% list())) {
    stop("The selected AI Tutor has no workflow nodes.")
  }
  ai_input = if (nzchar(trimws(text))) text else "[uploaded image]"
  prior_conversation = app$student_live_messages %||% list()
  ullme_student_live_history_append(
    "user", ai_input, clientMessageId %||% "", app=app
  )
  pending = app$student_pending_workflow
  workflow = if (is.environment(pending)) {
    ullme_tutor_workflow_resume(
      pending,
      input=ai_input,
      uploads=uploads %||% list(),
      conversation=prior_conversation
    )
  } else {
    ullme_tutor_workflow_new(
      tutor=tutor,
      input=ai_input,
      uploads=uploads %||% list(),
      conversation=prior_conversation,
      model=model,
      app=app
    )
  }
  stats = ullme_student_stats_request(model=model, app=app)
  interaction_dir = ullme_ai_interaction_start(
    input=ai_input,
    visible_text=text,
    model=model,
    kind="tutor_workflow",
    app=app
  )
  request = new.env(parent=emptyenv())
  request$active = TRUE
  request$message_id = assistantMessageId
  request$interaction_dir = interaction_dir
  request$tool_event_seq = 0L
  request$stats_request = stats
  request$workflow_state = workflow
  workflow$interaction_dir = interaction_dir
  request$state = new.env(parent=emptyenv())
  request$state$text = ""
  request$state$thinking = ""
  request$controller = list(cancel=function(reason="Stopped by user") {
    ullme_tutor_workflow_cancel(workflow, reason)
  })
  app$chat_response_active = TRUE
  app$chat_requests[[assistantMessageId]] = request
  app$active_chat_request = request
  ullme_send_chat_stream_update(
    message_id=assistantMessageId,
    text="Preparing your Tutor\u2026",
    done=FALSE,
    app=app
  )

  finish = function(result) {
    if (!isTRUE(request$active)) return(invisible(result))
    text_out = paste0(result$text %||% "", collapse="\n")
    request$state$text = text_out
    waiting = identical(result$status %||% "", "waiting")
    app$student_pending_workflow = if (waiting) result$state else NULL
    request$active = FALSE
    app$chat_response_active = FALSE
    app$chat_requests[[assistantMessageId]] = NULL
    app$chat_tasks[[assistantMessageId]] = NULL
    if (identical(app$active_chat_request, request)) {
      app$active_chat_request = NULL
    }
    ullme_student_stats_mark_output(stats)
    ullme_send_chat_stream_update(
      message_id=assistantMessageId,
      text=text_out,
      done=TRUE,
      app=app
    )
    if (nzchar(text_out)) {
      ullme_student_live_history_append(
        "assistant", text_out, assistantMessageId, app=app
      )
    }
    ullme_send_student_chat_history(app=app)
    ullme_ai_interaction_finish(
      interaction_dir,
      status=if (waiting) "waiting_for_input" else "completed",
      text=text_out
    )
    ullme_student_stats_append(stats, reply=text_out, app=app)
    result
  }
  fail = function(error) {
    if (!isTRUE(request$active)) return(invisible(NULL))
    message = paste0(
      "I could not complete the Tutor workflow: ",
      ullme_safe_ai_error(error, app$api_config)
    )
    request$active = FALSE
    app$chat_response_active = FALSE
    app$chat_requests[[assistantMessageId]] = NULL
    app$chat_tasks[[assistantMessageId]] = NULL
    if (identical(app$active_chat_request, request)) {
      app$active_chat_request = NULL
    }
    ullme_send_chat_stream_update(
      message_id=assistantMessageId,
      done=TRUE,
      error=message,
      app=app
    )
    ullme_ai_interaction_finish(
      interaction_dir, status="error", error=message
    )
    ullme_student_stats_append(
      stats, error_code="workflow_error", app=app
    )
    NULL
  }
  on_waiting = function(message, node_id) {
    if (!isTRUE(request$active)) return(invisible(NULL))
    ullme_send_chat_stream_update(
      message_id=assistantMessageId,
      text=message,
      done=FALSE,
      app=app
    )
  }
  on_final_update = function(text, thinking="", done=FALSE) {
    if (!isTRUE(request$active)) return(invisible(NULL))
    request$state$text = text
    request$state$thinking = thinking
    if (nzchar(trimws(text))) ullme_student_stats_mark_output(stats)
    if (!isTRUE(done)) {
      ullme_send_chat_stream_update(
        message_id=assistantMessageId,
        text=text,
        thinking=thinking,
        done=FALSE,
        app=app
      )
    }
  }
  started = tryCatch(
    ullme_tutor_workflow_advance(
      workflow,
      on_waiting=on_waiting,
      on_final_update=on_final_update
    ),
    error=function(error) error
  )
  if (inherits(started, "error")) return(invisible(fail(started)))
  if (!inherits(started, "promise")) return(invisible(finish(started)))
  task = promises::then(
    ullme_promise_timeout(
      started,
      seconds=app$tutor_workflow_timeout_seconds %||% 600
    ),
    onFulfilled=finish,
    onRejected=fail
  )
  app$chat_tasks[[assistantMessageId]] = task
  invisible(task)
}
