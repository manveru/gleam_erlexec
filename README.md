# glexec

[![Package Version](https://img.shields.io/hexpm/v/glexec)](https://hex.pm/packages/glexec)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glexec/)

A wrapper around the functions found in
[erlexec](https://hexdocs.pm/erlexec/exec.html).

It probably goes without saying, but this functionality is only available when
runnning on BEAM.

## Quick start

```gleam
import glexec as exec

pub fn main() {
  let assert Ok(bash) = exec.find_executable("bash")

  let assert Ok(exec.Pids(_pid, ospid)) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_stderr(exec.StderrStdout)
    |> exec.with_monitor(True)
    |> exec.with_pty(True)
    |> exec.run_async(exec.Execve([bash, "-c", "echo started && cat"]))

  let assert Ok(exec.ObtainStdout(_, "started\r\n")) = exec.obtain(500)
  let assert Ok(Nil) = exec.send(ospid, "test\n")
  let assert Ok(exec.ObtainStdout(_, "test\r\n")) = exec.obtain(500)
  let assert Ok(Nil) = exec.kill_ospid(ospid, 9)
}
```

## Installation

This package can be added to your Gleam project:

```sh
gleam add glexec
```

## Development

```sh
gleam test  # Run the tests
gleam run   # Run a small example
gleam shell # Run an Erlang shell
```

## TODO

The test suite is still fairly incomplete, but without code coverage it is a
bit hard to ensure all cases are covered and the main functionality is tested
in `erlexec` itself.

Happy for any PRs though.
