import gleam/erlexec as exec
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub type Fixture {
  Foreach
  Kill
  Setup
  Timeout
}

pub fn gleam_erlexec_test_() {
  let tests = [
    test_monitor,
    test_sync,
    test_winsz,
    test_stdin,
    test_stdin_eof,
    test_stderr,
    test_stdout,
  ]
  #(
    Setup,
    fn() {
      case exec.start([]) {
        Ok(pid) -> pid
        Error(exec.AlreadyStarted(pid)) -> pid
      }
    },
    list.map(tests, ff),
  )
}

fn ff(f) {
  #(Timeout, 20, f)
}

pub fn test_monitor() {
  let assert Ok(name) = exec.find_executable("echo")
  let assert Ok(exec.Pids(pid, _)) =
    exec.new()
    |> exec.with_monitor(True)
    |> exec.with_stdout(exec.StdoutNull)
    |> exec.run_async(exec.Execve([name, "hi"]))
  let assert Ok(exec.ObtainDown(exit_pid, _)) = exec.obtain(5000)
  let assert True = exit_pid == pid
}

pub fn test_sync() {
  exec.new()
  |> exec.with_stdout(exec.StdoutCapture)
  |> exec.with_stderr(exec.StderrCapture)
  |> exec.run_sync(exec.Shell("echo Test; echo ERR 1>&2"))
  |> should.equal(
    Ok(exec.Output([exec.Stdout(["Test\n"]), exec.Stderr(["ERR\n"])])),
  )

  let assert Ok(name) = exec.find_executable("echo")
  exec.new()
  |> exec.with_stdout(exec.StdoutCapture)
  |> exec.run_sync(exec.Execve([name]))
  |> should.equal(Ok(exec.Output([exec.Stdout(["\n"])])))
  True
}

pub fn test_winsz() {
  let assert Ok(bash) = exec.find_executable("bash")

  let assert Ok(exec.Pids(first_pid, first_ospid)) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_stderr(exec.StderrStdout)
    |> exec.with_monitor(True)
    |> exec.with_pty(True)
    |> exec.with_env([exec.EnvKV("TERM", "xterm")])
    |> exec.run_async(
      exec.Execve([
        bash,
        "-i",
        "-c",
        "echo started; read x; echo LINES=$(tput lines) COLUMNS=$(tput cols)",
      ]),
    )
  let assert Ok(exec.ObtainStdout(ospid, "started\r\n")) = exec.obtain(3000)
  let assert True = ospid == first_ospid
  let assert Ok(Nil) = exec.winsz(first_ospid, 99, 88)
  let assert Ok(Nil) = exec.send(first_ospid, "\n")
  let assert Ok(exec.ObtainStdout(ospid, "LINES=99 COLUMNS=88\r\n")) =
    exec.obtain(3000)
  let assert True = ospid == first_ospid
  let assert Ok(exec.ObtainDown(pid, ospid)) = exec.obtain(3000)
  let assert True = pid == first_pid
  let assert True = ospid == first_ospid

  // can set size on run
  let assert Ok(exec.Pids(second_pid, second_ospid)) =
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
        bash,
        "-i",
        "-c",
        "echo LINES=$(tput lines) COLUMNS=$(tput cols)",
      ]),
    )

  let assert Ok(exec.ObtainStdout(gotpid4, "LINES=99 COLUMNS=88\r\n")) =
    exec.obtain(5000)
  let assert True = gotpid4 == second_ospid

  let assert Ok(exec.ObtainDown(pid, ospid)) = exec.obtain(5000)
  let assert True = pid == second_pid
  let assert True = ospid == second_ospid
  True
}

pub fn test_stdin() {
  let assert Ok(bash) = exec.find_executable("bash")
  let assert Ok(exec.Pids(expected_pid, expected_ospid)) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_monitor(True)
    |> exec.run_async(exec.Execve([bash, "-c", "read x; echo \"Got $x\""]))

  let assert Ok(Nil) = exec.send(expected_ospid, "Test data\n")

  let assert Ok(exec.ObtainStdout(ospid, "Got Test data\n")) = exec.obtain(500)
  ospid
  |> should.equal(expected_ospid)

  let assert Ok(exec.ObtainDown(pid, ospid)) = exec.obtain(500)
  pid
  |> should.equal(expected_pid)
  ospid
  |> should.equal(expected_ospid)
  True
}

pub fn test_stdin_eof() {
  let assert Ok(tac) = exec.find_executable("tac")
  let assert Ok(exec.Pids(expected_pid, expected_ospid)) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_monitor(True)
    |> exec.run_async(exec.Execve([tac]))
  ["foo\n", "bar\n", "baz\n"]
  |> list.each(fn(line) {
    let assert Ok(Nil) = exec.send(expected_ospid, line)
  })
  let assert Ok(Nil) = exec.send_eof(expected_ospid)
  let assert Ok(exec.ObtainStdout(ospid, "baz\nbar\nfoo\n")) = exec.obtain(500)
  ospid
  |> should.equal(expected_ospid)

  let assert Ok(exec.ObtainDown(pid, ospid)) = exec.obtain(500)
  pid
  |> should.equal(expected_pid)
  ospid
  |> should.equal(expected_ospid)
  True
}

pub fn test_stderr() {
  test_std(
    exec.new()
    |> exec.with_stderr(exec.StderrCapture),
  )
}

pub fn test_stdout() {
  test_std(
    exec.new()
    |> exec.with_stdout(exec.StdoutCapture),
  )
}

fn test_std(options) {
  let script = "for i in 1 2; do echo TEST$i; sleep 0.05; done"
  let suffix = case exec.get_stderr(options) {
    Some(exec.StderrCapture) -> " 1>&2"
    _ -> ""
  }
  let assert Ok(bash) = exec.find_executable("bash")
  let assert Ok(exec.Pids(_expected_pid, _expected_ospid)) =
    exec.run_async(
      options,
      exec.Execve([bash, "-c", string.append(script, suffix)]),
    )

  let _ = case exec.get_stderr(options) {
    Some(exec.StderrCapture) -> {
      let assert Ok(exec.ObtainStderr(_, "TEST1\n")) = exec.obtain(5000)
      let assert Ok(exec.ObtainStderr(_, "TEST2\n")) = exec.obtain(5000)
    }
    _ -> {
      let assert Ok(exec.ObtainStdout(_, "TEST1\n")) = exec.obtain(5000)
      let assert Ok(exec.ObtainStdout(_, "TEST2\n")) = exec.obtain(5000)
    }
  }
  True
}

// pub fn send_check() {
//   let assert Ok(Pids(_pid, ospid)) =
//     new()
//     |> with_stdout(StdoutFun(fn(kind: Atom, pid: Int, line: String) -> Nil {
//       io.debug(#(kind, pid, line))
//       Nil
//     }))
//     |> with_stderr(StderrFun(fn(kind: Atom, pid: Int, line: String) -> Nil {
//       io.debug(#(kind, pid, line))
//       Nil
//     }))
//     |> with_stdin(StdinPipe)
//     |> run_async(Shell("cat -"))
// 
//   erlexec.which_children()
//   |> list.length
//   |> should.equal(1)
// 
//   send(ospid, "hello")
//   |> should.be_ok
// 
//   send_eof(ospid)
//   |> should.be_ok
// 
//   send(ospid, "hello")
//   |> should.be_ok
// 
//   stop(ospid)
//   |> should.be_ok
// }
// 
// pub fn stop_check() {
//   let result =
//     new()
//     |> with_stdout(StdoutCapture)
//     |> with_stderr(StderrCapture)
//     |> with_monitor(True)
//     |> run_async(Shell("echo hi; echo there >&2; sleep 1000"))
// 
//   let assert Ok(erlexec.ObtainStdout(_, "hi\n")) = erlexec.obtain(1000)
//   let assert Ok(erlexec.ObtainStderr(_, "there\n")) = erlexec.obtain(1000)
// 
//   result
//   |> should.be_ok
// 
//   let assert Ok(Pids(pid, ospid)) = result
//   stop(ospid)
//   |> should.be_ok
//   stop(9999999)
//   |> should.be_error
// 
//   let assert Ok(got_os_pid) = to_ospid(pid)
//   got_os_pid
//   |> should.equal(ospid)
// }
// 
// pub fn stdin_check() {
//   let assert Ok(bash) = find_executable("bash")
//   let cmd = Execve([bash, "-c", "read x; echo \"Got $x\""])
//   let options =
//     new()
//     |> with_stdin(erlexec.StdinPipe)
//     |> with_stdout(erlexec.StdoutCapture)
//     |> with_monitor(True)
//     |> with_debug(10)
// 
//   let assert Ok(Pids(_pid, ospid)) = run_async(options, cmd)
//   let assert Ok(erlexec.ObtainStdout(_, "started\r\n")) = erlexec.obtain(5000)
//   let assert Ok(_) = erlexec.send(ospid, "test\n")
//   let assert Ok(erlexec.ObtainStdout(_, "started\r\n")) = erlexec.obtain(5000)
//   Nil
// }
// 
// pub fn pty_echo_check() {
//   let assert Ok(bash) = find_executable("bash")
//   let cmd = Execve([bash, "-c", "echo started && cat"])
// 
//   let options =
//     new()
//     |> with_stdin(erlexec.StdinPipe)
//     |> with_stdout(erlexec.StdoutCapture)
//     |> with_stderr(erlexec.StderrStdout)
//     |> with_monitor(True)
//     |> with_pty(True)
//     |> with_debug(10)
// 
//   // options
//   // |> erlexec.options_to_list
//   // |> string.inspect
//   // |> should.equal("")
//   // without echo
//   let assert Ok(Pids(_pid, ospid)) = run_async(options, cmd)
// 
//   let assert Ok(erlexec.ObtainStdout(_, "started\r\n")) = erlexec.obtain(5000)
//   let assert Ok(_) = erlexec.send(ospid, "test\n")
//   let assert Ok(erlexec.ObtainStdout(_, "test\r\n")) = erlexec.obtain(5000)
//   let _ = erlexec.kill_ospid(ospid, 9)
// 
//   // with echo
//   let assert Ok(Pids(_pid, ospid2)) =
//     options
//     |> with_pty_echo(True)
//     |> run_async(cmd)
// 
//   let assert Ok(erlexec.ObtainStdout(_, "started\r\n")) = erlexec.obtain(1000)
//   let assert Ok(_) = erlexec.send(ospid2, "test\n")
//   let assert Ok(erlexec.ObtainStdout(_, "test\r\n")) = erlexec.obtain(1000)
//   let assert Ok(_) = erlexec.kill_ospid(ospid2, 9)
// }
// 
// pub fn env_check() {
//   let assert Ok(env) = find_executable("env")
//   let assert Ok(Output(output)) =
//     new()
//     |> with_env([EnvClear, EnvKV("Hello", "World!"), EnvKV("Foo", "Bar")])
//     |> with_stdout(StdoutCapture)
//     |> run_sync(Execve([env]))
// 
//   output
//   |> should.equal([Stdout(["Foo=Bar\nHello=World!\n"])])
// }
// 
pub fn signal_to_int_check() {
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
