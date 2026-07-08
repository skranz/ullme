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
for (pkg in c("ullme", "ellmer", "httr2", "promises", "coro",
              "restorepoint", "stringi")) {
  message(pkg, ": ", as.character(utils::packageVersion(pkg)))
}

config = ullme_api_config(
  api_provider=api_provider,
  api_key_file=api_key_file,
  api_model=api_model,
  api_base_url=api_base_url
)

chat = ullme_api_chat(
  config=config,
  model=config$model,
  system_prompt="You are a minimal connectivity test. Answer briefly."
)

answer = chat$chat(question, echo="none")

cat("\n--- AI response ---\n")
cat(answer, "\n")
cat("--- end ---\n")
