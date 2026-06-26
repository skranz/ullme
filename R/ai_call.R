ullme_ask_ai = function(input, uses_fake_ai = ullme_uses_fake_ai()) {
  restore.point("ullme_ask_ai")
  if (uses_fake_ai) {
    return(paste0("Fake AI answer to:\n",  input))
  }
  stop("Actual AI use not yet implement.")
}
