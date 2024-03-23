import gleam/erlang/atom.{type Atom}
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/otp/task
import gleeunit
import gleeunit/should
import glexec as exec

pub fn main() {
  gleeunit.main()
}

fn find_executable(name) {
  exec.find_executable(name)
  |> should.be_ok()
}

pub fn glexec_monitor_test() {
  let exec.Pids(pid, os_pid) =
    exec.new()
    |> exec.with_monitor(True)
    |> exec.with_stdout(exec.StdoutNull)
    |> exec.run_async(exec.Execve([find_executable("echo"), "hi"]))
    |> should.be_ok()

  exec.obtain(5000)
  |> should.equal(Error(exec.ObtainDownNormal(pid, os_pid)))
}

pub fn glexec_sync_test() {
  exec.new()
  |> exec.with_stdout(exec.StdoutCapture)
  |> exec.with_stderr(exec.StderrCapture)
  |> exec.run_sync(exec.Shell("echo Test; echo ERR 1>&2"))
  |> should.equal(
    Ok(exec.Output([exec.Stdout(["Test\n"]), exec.Stderr(["ERR\n"])])),
  )

  exec.new()
  |> exec.with_stdout(exec.StdoutCapture)
  |> exec.run_sync(exec.Execve([find_executable("echo")]))
  |> should.equal(Ok(exec.Output([exec.Stdout(["\n"])])))
}

pub fn glexec_winsz_interactive_test() {
  let exec.Pids(pid, os_pid) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_stderr(exec.StderrStdout)
    |> exec.with_monitor(True)
    |> exec.with_pty(True)
    |> exec.with_env([exec.EnvKV("TERM", "xterm")])
    |> exec.run_async(
      exec.Execve([
        find_executable("bash"),
        "-i",
        "-c",
        "echo -n started; read x; echo -n LINES=$(tput lines) COLUMNS=$(tput cols)",
      ]),
    )
    |> should.be_ok()

  exec.obtain(3000)
  |> should.equal(Ok(exec.ObtainStdout(os_pid, "started")))

  exec.winsz(os_pid, 99, 88)
  |> should.equal(Ok(Nil))

  exec.send(os_pid, "\n")
  |> should.equal(Ok(Nil))

  exec.obtain(3000)
  |> should.equal(Ok(exec.ObtainStdout(os_pid, "LINES=99 COLUMNS=88")))

  exec.obtain(3000)
  |> should.equal(Error(exec.ObtainDownNormal(pid, os_pid)))
}

pub fn glexec_winsz_initial_test() {
  let exec.Pids(pid, os_pid) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_stderr(exec.StderrStdout)
    |> exec.with_monitor(True)
    |> exec.with_pty(True)
    |> exec.with_env([exec.EnvKV("TERM", "xterm")])
    |> exec.with_winsz(99, 88)
    |> exec.run_async(
      exec.Execve([
        find_executable("bash"),
        "-i",
        "-c",
        "echo -n LINES=$(tput lines) COLUMNS=$(tput cols)",
      ]),
    )
    |> should.be_ok()

  exec.obtain(3000)
  |> should.equal(Ok(exec.ObtainStdout(os_pid, "LINES=99 COLUMNS=88")))

  exec.obtain(5000)
  |> should.equal(Error(exec.ObtainDownNormal(pid, os_pid)))
}

pub fn glexec_stdin_async_test() {
  let exec.Pids(pid, os_pid) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_monitor(True)
    |> exec.run_async(
      exec.Execve([find_executable("bash"), "-c", "read x; echo -n \"Got $x\""]),
    )
    |> should.be_ok()

  exec.send(os_pid, "Test data\n")
  |> should.equal(Ok(Nil))

  exec.obtain(500)
  |> should.equal(Ok(exec.ObtainStdout(os_pid, "Got Test data")))

  exec.obtain(500)
  |> should.equal(Error(exec.ObtainDownNormal(pid, os_pid)))
}

pub fn glexec_stdin_eof_test() {
  let exec.Pids(pid, os_pid) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_monitor(True)
    |> exec.run_async(exec.Execve([find_executable("tac")]))
    |> should.be_ok()

  ["foo\n", "bar\n", "baz\n"]
  |> list.each(fn(line) {
    exec.send(os_pid, line)
    |> should.equal(Ok(Nil))
  })

  exec.send_eof(os_pid)
  |> should.equal(Ok(Nil))

  exec.obtain(500)
  |> should.equal(Ok(exec.ObtainStdout(os_pid, "baz\nbar\nfoo\n")))

  exec.obtain(500)
  |> should.equal(Error(exec.ObtainDownNormal(pid, os_pid)))
}

pub fn glexec_stderr_test() {
  exec.new()
  |> exec.with_stderr(exec.StderrCapture)
  |> test_std()
}

pub fn glexec_stdout_test() {
  exec.new()
  |> exec.with_stdout(exec.StdoutCapture)
  |> test_std()
}

fn test_std(options) {
  let script = "for i in 1 2; do echo TEST$i; sleep 0.05; done"
  let suffix = case exec.get_stderr(options) {
    Some(exec.StderrCapture) -> " 1>&2"
    _ -> ""
  }

  let exec.Pids(_pid, os_pid) =
    options
    |> exec.run_async(
      exec.Execve([find_executable("bash"), "-c", script <> suffix]),
    )
    |> should.be_ok()

  case exec.get_stderr(options) {
    Some(exec.StderrCapture) -> {
      exec.obtain(600)
      |> should.equal(Ok(exec.ObtainStderr(os_pid, "TEST1\n")))
      exec.obtain(600)
      |> should.equal(Ok(exec.ObtainStderr(os_pid, "TEST2\n")))
    }
    _ -> {
      exec.obtain(600)
      |> should.equal(Ok(exec.ObtainStdout(os_pid, "TEST1\n")))
      exec.obtain(600)
      |> should.equal(Ok(exec.ObtainStdout(os_pid, "TEST2\n")))
    }
  }
}

pub fn send_test() {
  let exec.Pids(_pid, os_pid) =
    exec.new()
    |> exec.with_stdout(
      exec.StdoutFun(fn(kind: Atom, pid: Int, line: String) -> Nil {
        io.debug(#(kind, pid, line))
        Nil
      }),
    )
    |> exec.with_stderr(
      exec.StderrFun(fn(kind: Atom, pid: Int, line: String) -> Nil {
        io.debug(#(kind, pid, line))
        Nil
      }),
    )
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.run_async(exec.Shell("cat -"))
    |> should.be_ok()

  exec.which_children()
  |> list.length
  |> should.equal(2)

  exec.send(os_pid, "hello")
  |> should.equal(Ok(Nil))

  exec.send_eof(os_pid)
  |> should.equal(Ok(Nil))

  exec.send(os_pid, "hello")
  |> should.equal(Ok(Nil))

  exec.stop(os_pid)
  |> should.equal(Ok(Nil))
}

pub fn stop_test() {
  let exec.Pids(pid, os_pid) =
    exec.new()
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_stderr(exec.StderrCapture)
    |> exec.with_monitor(True)
    |> exec.run_async(exec.Shell("echo hi; echo there >&2; sleep 1000"))
    |> should.be_ok()

  exec.obtain(500)
  |> should.equal(Ok(exec.ObtainStdout(os_pid, "hi\n")))
  exec.obtain(500)
  |> should.equal(Ok(exec.ObtainStderr(os_pid, "there\n")))

  exec.stop(os_pid)
  |> should.be_ok()

  exec.stop(9_999_999)
  |> should.equal(Error("pid not alive"))

  exec.to_ospid(pid)
  |> should.equal(Ok(os_pid))
}

// For some reason this test keeps failing, it works in normal programs.
pub fn glexec_with_pty_echo_test() {
  task.async(fn() {
    let assert Ok(bash) = exec.find_executable("bash")
    let assert Ok(exec.Pids(_, os_pid)) =
      exec.new()
      |> exec.with_stdin(exec.StdinPipe)
      |> exec.with_stdout(exec.StdoutCapture)
      |> exec.with_monitor(True)
      |> exec.with_pty_echo(True)
      |> exec.with_pty(True)
      |> exec.run_async(
        exec.Execve([bash, "--norc", "-i", "-c", "echo started && cat"]),
      )

    exec.obtain(500)
    |> should.equal(Ok(exec.ObtainStdout(os_pid, "started\r\n")))

    exec.send(os_pid, "testing\n")
    |> should.equal(Ok(Nil))

    // we should see the input here
    exec.obtain(500)
    |> should.equal(Ok(exec.ObtainStdout(os_pid, "testing\r\n")))

    exec.obtain(500)
    |> should.equal(Ok(exec.ObtainStdout(os_pid, "testing\r\n")))
  })
  |> task.await(1000)
}

pub fn glexec_with_env_test() {
  exec.new()
  |> exec.with_env([
    exec.EnvClear,
    exec.EnvKV("Hello", "World!"),
    exec.EnvKV("Foo", "Bar"),
  ])
  |> exec.with_stdout(exec.StdoutCapture)
  |> exec.run_sync(exec.Execve([find_executable("env")]))
  |> should.equal(Ok(exec.Output([exec.Stdout(["Foo=Bar\nHello=World!\n"])])))
}

pub fn signal_to_int_test() {
  exec.signal_to_int(exec.SIGSEGV)
  |> should.equal(11)
}

pub fn status_test() {
  should.equal(exec.status(0), exec.ExitStatus(0))
  should.equal(exec.status(1), exec.Signal(exec.SIGHUP, False))
  should.equal(exec.status(2), exec.Signal(exec.SIGINT, False))
  should.equal(exec.status(4), exec.Signal(exec.SIGILL, False))
  should.equal(exec.status(8), exec.Signal(exec.SIGFPE, False))
  should.equal(exec.status(32), exec.Signal(exec.Other(32), False))
  should.equal(exec.status(64), exec.Signal(exec.Other(64), False))
  should.equal(exec.status(127), exec.Signal(exec.Other(127), False))
  should.equal(exec.status(128), exec.ExitStatus(0))
  should.equal(exec.status(129), exec.Signal(exec.SIGHUP, True))
}
