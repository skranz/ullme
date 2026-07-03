library(ullme)

request_content = ellmer::ContentToolRequest(
  id="call-1",
  name="read_course_file",
  arguments=list(courseid="micro", path="notes.md")
)
request_record = ullme_tool_request_record(request_content)
stopifnot(
  identical(request_record$call_id, "call-1"),
  identical(request_record$tool, "read_course_file"),
  identical(request_record$arguments$courseid, "micro")
)

result_content = ellmer::ContentToolResult(
  value=list(ok=FALSE, status="rejected", message="No"),
  request=request_content
)
result_record = ullme_tool_result_record(result_content)
stopifnot(
  identical(result_record$call_id, "call-1"),
  identical(result_record$tool, "read_course_file"),
  identical(result_record$status, "rejected")
)

trace_value = ullme_tool_trace_value(list(
  api_key="do-not-store",
  content=paste(rep("x", 2100), collapse="")
))
stopifnot(
  identical(trace_value$api_key, "[redacted]"),
  grepl("[truncated]", trace_value$content, fixed=TRUE)
)

app = new.env(parent=emptyenv())
app$pending_changes = list(
  operation_1=list(id="operation_1")
)
app$change_waiters = list()
request = new.env(parent=emptyenv())
request$active = FALSE
request$waiting_for_approval = FALSE
request$message_id = "assistant_1"
app$active_chat_request = request

approval_value = NULL
approval_promise = ullme_wait_for_change_approval(
  list(
    ok=TRUE,
    status="pending_approval",
    operation_id="operation_1",
    validation=list(valid=TRUE)
  ),
  app=app
)
promises::then(
  approval_promise,
  onFulfilled=function(value) approval_value <<- value
)
stopifnot(
  isTRUE(request$waiting_for_approval),
  !is.null(app$change_waiters$operation_1)
)
ullme_resolve_change_waiter(
  "operation_1",
  list(ok=TRUE, status="committed", operation_id="operation_1"),
  app=app
)
deadline = Sys.time() + 2
while (is.null(approval_value) && Sys.time() < deadline) {
  later::run_now(timeoutSecs=0.02)
}
stopifnot(
  identical(approval_value$status, "committed"),
  isTRUE(approval_value$validation$valid),
  !isTRUE(request$waiting_for_approval),
  is.null(app$change_waiters$operation_1)
)

paused = TRUE
resolve_source = NULL
source_promise = promises::promise(function(resolve, reject) {
  resolve_source <<- resolve
})
timeout_value = NULL
timeout_error = NULL
promises::then(
  ullme_promise_timeout(
    source_promise,
    seconds=0.05,
    is_paused=function() paused
  ),
  onFulfilled=function(value) timeout_value <<- value,
  onRejected=function(error) timeout_error <<- conditionMessage(error)
)
pause_deadline = Sys.time() + 0.12
while (Sys.time() < pause_deadline) {
  later::run_now(timeoutSecs=0.01)
}
stopifnot(is.null(timeout_value), is.null(timeout_error))
paused = FALSE
resolve_source("continued")
deadline = Sys.time() + 2
while (is.null(timeout_value) && Sys.time() < deadline) {
  later::run_now(timeoutSecs=0.02)
}
stopifnot(identical(timeout_value, "continued"), is.null(timeout_error))
