# Minimal ullme AI test without the Shiny app.
# Edit these values on the server, then run:
# source("scripts/test_ai_minimal.R")

api_provider = "nvidia"
api_key_file = "~/.nvidia_api_key"
api_model = NULL
api_base_url = NULL

question = "Please reply with exactly: ullme-ai-ok"

library(ullme)

message("R: ", R.version.string)
print(Cstack_info())
for (pkg in c("ullme", "curl", "jsonlite", "promises", "coro",
              "restorepoint", "stringi")) {
  message(pkg, ": ", as.character(utils::packageVersion(pkg)))
}

config = ullme_api_config(
  api_provider=api_provider,
  api_key_file=api_key_file,
  api_model=api_model,
  api_base_url=api_base_url
)

app = new.env(parent=emptyenv())
app$role = "student"
app$api_config = config
app$enable_ai_tools = FALSE
app$chat_debug = FALSE
app$chat_connect_timeout_seconds = 60
app$chat_timeout_seconds = 180

request = ullme_start_custom_ai_stream(
  input=question,
  model=config$model,
  system_prompt_override=
    "You are a minimal connectivity test. Answer briefly.",
  app=app
)
answer = ullme_await_promise(request$promise, seconds=180)

cat("\n--- AI response ---\n")
cat(answer, "\n")
cat("--- end ---\n")
