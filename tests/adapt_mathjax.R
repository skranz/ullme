library(ullme)

stopifnot(
  identical(
    replace_math_delimiters("Use $x + 1$ here."),
    "Use \\(x + 1\\) here."
  ),
  identical(
    replace_math_delimiters("Before $$x^2 + y^2$$ after"),
    "Before \\[x^2 + y^2\\] after"
  ),
  identical(
    replace_math_delimiters("It costs $20 today."),
    "It costs $20 today."
  ),
  identical(
    replace_math_delimiters("Already \\(x\\) and \\[y\\]."),
    "Already \\(x\\) and \\[y\\]."
  )
)

app = new.env(parent=emptyenv())
app$render_chat_markdown = TRUE
app$adapt_mathjax = TRUE
adapted = ullme_chat_output_html("Inline $x$ and display $$y$$.", app=app)
stopifnot(
  grepl("\\(x\\)", adapted, fixed=TRUE),
  grepl("\\[y\\]", adapted, fixed=TRUE)
)

app$adapt_mathjax = FALSE
unchanged = ullme_chat_output_html("Inline $x$.", app=app)
stopifnot(grepl("$x$", unchanged, fixed=TRUE))
