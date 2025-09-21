import dotenv
import envoy
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn parses_basic_test() {
  let text =
    "
  # comment
  export FOO=bar
  EMPTY=
  SPACED =  value with spaces   # trailing comment
  QUOTED=\"hello\\nworld\"
  SQUOTED='a # b'
  ESC_HASH=\"val\\#ue\"
  SOME_HARDURI=db://root:passw@url.nett.dasd.kk/?retryWrites=true&w=majority
  "
  let assert Ok(pairs) = dotenv.parse(text)
  pairs
  |> should.equal([
    dotenv.Pair("FOO", "bar"),
    dotenv.Pair("EMPTY", ""),
    dotenv.Pair("SPACED", "value with spaces"),
    dotenv.Pair("QUOTED", "hello\nworld"),
    dotenv.Pair("SQUOTED", "a # b"),
    dotenv.Pair("ESC_HASH", "val#ue"),
    dotenv.Pair(
      "SOME_HARDURI",
      "db://root:passw@url.nett.dasd.kk/?retryWrites=true&w=majority",
    ),
  ])
}

// gleeunit test functions end in `_test`
pub fn should_set_env_from_file_test() {
  let _ = dotenv.load()
  check()
}

pub fn should_set_env_from_file_selected_test() {
  let _ = dotenv.load_file(".env.test")
  check()
}

pub fn should_return_error_when_file_not_found_test() {
  let assert Error(_) = dotenv.load_file(".env.notfound")
}

fn check() {
  let assert Ok(foo) = envoy.get("FOO")
  let assert Ok(empty) = envoy.get("EMPTY")
  let assert Ok(spaced) = envoy.get("SPACED")
  let assert Ok(quoted) = envoy.get("QUOTED")
  let assert Ok(squoted) = envoy.get("SQUOTED")
  let assert Ok(escaped) = envoy.get("ESC_HASH")
  let assert Ok(harduri) = envoy.get("SOME_HARDURI")

  should.equal(foo, "bar")
  should.equal(empty, "")
  should.equal(spaced, "value with spaces")
  should.equal(quoted, "hello\nworld")
  should.equal(squoted, "a # b")
  should.equal(escaped, "val#ue")
  should.equal(
    harduri,
    "db://root:passw@url.nett.dasd.kk/?retryWrites=true&w=majority",
  )
}
