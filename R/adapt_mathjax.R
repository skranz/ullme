replace_math_delimiters = function(x, allow_numeric_start = FALSE) {
  x = replace_double_dollar_math(x)

  replace_dollar_math(
    x = x,
    allow_numeric_start = allow_numeric_start
  )
}

replace_dollar_math = function(x, allow_numeric_start = FALSE) {
  start_guard = if (allow_numeric_start) {
    r"{(?![[:space:]$])}"
  } else {
    r"{(?![[:space:]$[:digit:]])}"
  }

  pattern = paste0(
    r"{(?<![\\$])(?<![[:alnum:]_])\$}",
    start_guard,
    r"{((?:\\.|[^$\\\r\n])*?(?:\\.|[^[:space:]$\\\r\n]))}",
    r"{\$(?!\$)(?=$|[[:space:][:punct:]])}"
  )

  stringi::stri_replace_all_regex(
    str = x,
    pattern = pattern,
    replacement = "\\\\($1\\\\)"
  )
}


replace_double_dollar_math = function(x) {
  pattern = paste0(
    r"{(?<![\\$])\$\$(?!\$)}",
    r"{((?:(?!\$\$)[\s\S])*?\S(?:(?!\$\$)[\s\S])*?)}",
    r"{(?<!\\)\$\$(?!\$)}"
  )

  stringi::stri_replace_all_regex(
    str = x,
    pattern = pattern,
    replacement = "\\\\[$1\\\\]"
  )
}

