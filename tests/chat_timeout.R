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
