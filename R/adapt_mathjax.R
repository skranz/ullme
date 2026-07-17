example = function() {
  replace_math_delimiters("$3 - x$ $x^2+2$")
  replace_math_delimiters("$I own a house + many more things and you?\nWas it math$")
}

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
    paste0(
      r"{(?:}",
      r"{(?![[:space:]$[:digit:]])}",
      r"{|}",
      r"{(?=[[:digit:]])}",
      r"{(?=(?:\\.|[^$\\\r\n])*(?:[-+*/=<>^_]|\\[[:alpha:]]+))}",
      r"{)}"
    )
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

