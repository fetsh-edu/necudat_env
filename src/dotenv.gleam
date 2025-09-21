import envoy
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type Error {
  IoError(simplifile.FileError)
  ParseError(String)
}

pub type Pair {
  Pair(key: String, value: String)
}

pub fn parse(input: String) -> Result(List(Pair), String) {
  input
  |> string.replace("\r\n", "\n")
  |> string.replace("\r", "\n")
  |> string.split("\n")
  |> list.map(string.trim)
  |> list.map(fn(line) {
    case string.starts_with(line, "export ") {
      True -> string.drop_start(line, 7) |> string.trim_start
      False -> line
    }
  })
  |> list.filter(fn(line) {
    line != ""
    && !string.starts_with(line, "#")
    && !string.starts_with(line, "=")
  })
  |> list.map(parse_line)
  |> result.all()
}

pub fn load() -> Result(Nil, Error) {
  load_file(".env")
}

pub fn load_file(path: String) -> Result(Nil, Error) {
  case simplifile.read(path) {
    Ok(bin) ->
      case parse(bin) {
        Ok(pairs) -> {
          pairs
          |> list.each(fn(p) {
            let Pair(k, v) = p
            let _ = envoy.set(k, v)
            Nil
          })
          Ok(Nil)
        }
        Error(e) -> Error(ParseError(e))
      }
    Error(e) -> Error(IoError(e))
  }
}

pub fn require_string(key: String) -> String {
  case envoy.get(key) {
    Ok(v) if v != "" -> v
    _ -> panic as { "Missing required env var: " <> key }
  }
}

pub fn get_string_or(key: String, default: String) -> String {
  case envoy.get(key) {
    Ok(v) if v != "" -> v
    _ -> default
  }
}

pub fn require_int(key: String) -> Int {
  case int.parse(require_string(key)) {
    Ok(n) -> n
    Error(_) -> panic as { "Invalid integer env var: " <> key }
  }
}

pub fn get_int_or(key: String, default: Int) -> Int {
  case envoy.get(key) {
    Ok(v) if v != "" ->
      case int.parse(v) {
        Ok(n) -> n
        Error(_) -> default
      }
    _ -> default
  }
}

fn parse_line(line: String) -> Result(Pair, String) {
  case string.split_once(line, "=") {
    Ok(#(key, value)) ->
      Ok(Pair(parse_key(key), parse_value(string.trim(value))))
    Error(_) -> Error(line <> ": missing =")
  }
}

fn parse_key(key: String) -> String {
  key
  |> string.trim
}

fn parse_value(value: String) -> String {
  let trimmed = string.trim(value)
  let #(k, body) = unquote(trimmed)
  case k {
    Double -> unescape_double(body)
    Single -> body
    None -> string.trim(cut_comment(body))
  }
}

pub type Quote {
  Double
  Single
  None
}

fn quote_kind(s: String) -> Quote {
  let len = string.length(s)
  let has = fn(ch: String) {
    len >= 2 && string.starts_with(s, ch) && string.ends_with(s, ch)
  }
  case has("\""), has("'") {
    True, _ -> Double
    _, True -> Single
    _, _ -> None
  }
}

fn unquote(s: String) -> #(Quote, String) {
  let len = string.length(s)
  case quote_kind(s) {
    Double -> #(Double, string.slice(s, 1, len - 2))
    Single -> #(Single, string.slice(s, 1, len - 2))
    None -> #(None, s)
  }
}

fn unescape_double(s: String) -> String {
  unescape_double_loop(s, 0, "")
}

fn unescape_double_loop(s: String, i: Int, acc: String) -> String {
  let len = string.length(s)
  case i < len {
    False -> acc

    True -> {
      let curr = string.slice(s, i, 1)
      case curr {
        "\\" ->
          case i + 1 < len {
            False -> acc <> "\\"
            True -> {
              let nxt = string.slice(s, i + 1, 1)
              let mapped = case nxt {
                "n" -> "\n"
                "r" -> "\r"
                "t" -> "\t"
                "\"" -> "\""
                "#" -> "#"
                "\\" -> "\\"
                _ -> nxt
              }
              unescape_double_loop(s, i + 2, acc <> mapped)
            }
          }

        _ -> unescape_double_loop(s, i + 1, acc <> curr)
      }
    }
  }
}

// In unquoted values, cut at first unescaped '#'
fn cut_comment(s: String) -> String {
  cut_comment_loop(s, 0, False)
}

fn cut_comment_loop(s: String, i: Int, escaped: Bool) -> String {
  case char_at(s, i) {
    Error(_) -> s

    Ok("#") ->
      case escaped {
        True -> cut_comment_loop(s, i + 1, False)
        False -> string.slice(s, 0, i)
      }

    Ok("\\") ->
      // Toggle escaped for next char
      cut_comment_loop(s, i + 1, !escaped)

    Ok(_) -> cut_comment_loop(s, i + 1, False)
  }
}

fn char_at(s: String, i: Int) -> Result(String, Nil) {
  case i >= 0 && i < string.length(s) {
    True -> Ok(string.slice(s, i, 1))
    False -> Error(Nil)
  }
}

fn escape_double(s: String) -> String {
  escape_double_loop(s, 0, "")
}

fn escape_double_loop(s: String, i: Int, acc: String) -> String {
  let len = string.length(s)
  case i < len {
    False -> acc

    True -> {
      let ch = string.slice(s, i, 1)
      let esc = case ch {
        "\\" -> "\\\\"
        "\"" -> "\\\""
        "\n" -> "\\n"
        "\r" -> "\\r"
        "\t" -> "\\t"
        "#" -> "\\#"
        // so comments don't cut unquoted tokens if someone later unquotes
        _ -> ch
      }
      escape_double_loop(s, i + 1, acc <> esc)
    }
  }
}

fn normalise_newlines(s: String) -> String {
  s
  |> string.replace("\r\n", "\n")
  |> string.replace("\r", "\n")
}

fn build_line(key: String, value: String) -> String {
  key <> "=\"" <> escape_double(value) <> "\""
}

fn line_key(line: String) -> Result(String, Nil) {
  let trimmed = string.trim(line)
  case trimmed {
    "" -> Error(Nil)

    _ -> {
      case string.starts_with(trimmed, "#") {
        True -> Error(Nil)
        False -> {
          // drop optional "export "
          let body = case string.starts_with(trimmed, "export ") {
            True -> string.drop_start(trimmed, 7) |> string.trim_start
            False -> trimmed
          }

          case string.split_once(body, "=") {
            Ok(#(k, _v)) -> Ok(parse_key(k))
            Error(_) -> Error(Nil)
          }
        }
      }
    }
  }
}

pub fn set_string(key: String, value: String) -> Result(Nil, Error) {
  let path = ".env"
  let new_line = build_line(key, value)

  // Read current .env (if missing, we’ll create it)
  let current = case simplifile.read(path) {
    Ok(bin) -> normalise_newlines(bin)
    Error(_e) -> ""
    // treat as empty file; we will attempt to create
  }

  let lines = case current == "" {
    True -> []
    False -> string.split(current, "\n")
  }

  // Walk lines, replace the first assignment for `key`
  let #(replaced, out_rev) =
    list.fold(lines, #(False, []), fn(acc, line) {
      let #(done, acc_lines) = acc
      case done {
        True -> #(True, [line, ..acc_lines])

        // already replaced, keep as is
        False ->
          case line_key(line) {
            Ok(k) if k == key -> #(True, [new_line, ..acc_lines])
            _ -> #(False, [line, ..acc_lines])
          }
      }
    })

  let new_content = {
    let body = case replaced {
      True -> list.reverse(out_rev) |> string.join("\n")
      False -> {
        let base = list.reverse(out_rev) |> string.join("\n")
        let sep = case base == "" || string.ends_with(base, "\n") {
          True -> ""
          False -> "\n"
        }
        base <> sep <> new_line
      }
    }
    // Ensure trailing newline for POSIX-style files
    case string.ends_with(body, "\n") {
      True -> body
      False -> body <> "\n"
    }
  }

  // Write back
  case simplifile.write(path, new_content) {
    Ok(Nil) -> {
      // Update process env (ignore envoy errors to match existing style)
      let _ = envoy.set(key, value)
      Ok(Nil)
    }
    Error(e) -> Error(IoError(e))
  }
}
