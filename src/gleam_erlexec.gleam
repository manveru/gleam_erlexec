import gleam/erlexec as exec

pub fn main() {
  assert Ok(bash) = exec.find_executable("bash")

  assert Ok(exec.Pids(_pid, ospid)) =
    exec.new()
    |> exec.with_stdin(exec.StdinPipe)
    |> exec.with_stdout(exec.StdoutCapture)
    |> exec.with_stderr(exec.StderrStdout)
    |> exec.with_monitor(True)
    |> exec.with_pty(True)
    |> exec.run_async(exec.Execve([bash, "-c", "echo started && cat"]))

  assert Ok(exec.ObtainStdout(_, "started\r\n")) = exec.obtain(500)
  assert Ok(Nil) = exec.send(ospid, "test\n")
  assert Ok(exec.ObtainStdout(_, "test\r\n")) = exec.obtain(500)
  assert Ok(Nil) = exec.kill_ospid(ospid, 9)
}
