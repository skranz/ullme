library(ullme)

fulfilled = NULL
fulfilled_task = promises::then(
  ullme_promise_timeout(promises::promise_resolve("ok"), seconds=1),
  onFulfilled=function(value) fulfilled <<- value
)
deadline = Sys.time() + 2
while (is.null(fulfilled) && Sys.time() < deadline) {
  later::run_now(timeoutSecs=0.05)
}
stopifnot(identical(fulfilled, "ok"))

timeout_error = NULL
never = promises::promise(function(resolve, reject) NULL)
timeout_task = promises::then(
  ullme_promise_timeout(never, seconds=0.02),
  onRejected=function(error) timeout_error <<- conditionMessage(error)
)
deadline = Sys.time() + 2
while (is.null(timeout_error) && Sys.time() < deadline) {
  later::run_now(timeoutSecs=0.05)
}
stopifnot(
  is.character(timeout_error),
  grepl("timed out", timeout_error, fixed=TRUE),
  identical(
    ullme_safe_ai_error("no connection"),
    "no connection"
  )
)

controller = ellmer::stream_controller()
stopifnot(!controller$cancelled)
controller$cancel("Stopped by test")
stopifnot(
  controller$cancelled,
  identical(controller$reason, "Stopped by test")
)

resolved = promises::promise_resolve("ready")
stopifnot(identical(ullme_await_promise(resolved, seconds=1), "ready"))

cancelled = FALSE
never = promises::promise(function(resolve, reject) NULL)
await_error = tryCatch(
  ullme_await_promise(
    never,
    seconds=0.02,
    on_timeout=function() cancelled <<- TRUE
  ),
  error=identity
)
stopifnot(
  inherits(await_error, "error"),
  isTRUE(cancelled),
  grepl("timed out after", conditionMessage(await_error), fixed=TRUE)
)

status_app = new.env(parent=emptyenv())
status_app$api_config = list(
  provider="nvidia",
  model="google/gemma-4-31b-it",
  base_url="https://integrate.api.nvidia.com/v1"
)
status_app$chat_connect_timeout_seconds = 60
connection_status = ullme_ai_connection_status(app=status_app)
waiting_status = ullme_ai_connection_status(waiting=TRUE, app=status_app)
stopifnot(
  grepl("google/gemma-4-31b-it", connection_status, fixed=TRUE),
  grepl("NVIDIA NIM", connection_status, fixed=TRUE),
  grepl("60 seconds", connection_status, fixed=TRUE),
  grepl("Still waiting", waiting_status, fixed=TRUE)
)
