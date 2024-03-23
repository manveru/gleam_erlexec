//// OS shell command runner. It communicates with a separate C++ port process
//// exec-port spawned by this module, which is responsible for starting,
//// killing, listing, terminating, and notifying of state changes.
////
//// For more detailed documentation, please refer to
//// https://hexdocs.pm/erlexec/exec.html

import gleam/dynamic.{type Dynamic, from}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}

// Just a bunch of symbols used all over the place
type ExecAtom {
  Cd
  Args
  LimitUsers
  Portexe
  Verbose
  Root
  Alarm
  Clear
  Close
  Debug
  Env
  Executable
  Group
  Kill
  Winsz
  KillGroup
  KillTimeout
  Link
  Monitor
  Nice
  Null
  Print
  Pty
  PtyEcho
  Stdin
  String
  SuccessExitCode
  Sync
  User
}

/// Representation of OS process ID
pub type OsPid =
  Int

/// Representation of OS group ID
pub type OsGid =
  Int

/// Keeps track of all the options that will be passed to
/// [run_async](#run_async) or [run_sync](#run_sync)
pub opaque type Options {
  Options(
    cd: Option(String),
    debug: Option(Int),
    verbose: Option(Bool),
    env: EnvOptions,
    executable: Option(String),
    group: Option(Int),
    kill_group: Bool,
    kill: Option(String),
    kill_timeout: Option(Int),
    link: Bool,
    monitor: Bool,
    nice: Option(Int),
    pty: Bool,
    pty_echo: Bool,
    stderr: Option(StderrOptions),
    stdin: Option(StdinOptions),
    stdout: Option(StdoutOptions),
    success_exit_code: Option(Int),
    sync: Bool,
    user: Option(String),
    winsz: Option(WinszOptions),
    // this is used in `get_server:call`, not the actual command execution
    timeout: Int,
  )
}

/// Initial constructor for Options. Changing these settings is done with the
/// `with_*` functions.
pub fn new() -> Options {
  Options(
    cd: None,
    debug: None,
    verbose: None,
    env: [],
    executable: None,
    group: None,
    kill_group: False,
    kill: None,
    kill_timeout: None,
    link: False,
    monitor: False,
    nice: None,
    pty_echo: False,
    pty: False,
    stderr: None,
    stdin: None,
    stdout: None,
    success_exit_code: None,
    sync: False,
    user: None,
    winsz: None,
    timeout: 30_000,
  )
}

/// Command to be executed.
pub type Command {
  /// The specified command will be executed through the shell. The current shell
  /// is obtained from environment variable `SHELL`.
  ///
  /// This can be useful primarily for the enhanced control flow it offers over
  /// most system shells and still want convenient access to other shell features
  /// such as shell pipes, filename wildcards, environment variable expansion,
  /// and expansion of `~` to a user's home directory. All command arguments must
  /// be properly escaped including whitespace and shell metacharacters.
  ///
  /// Warning: Executing shell commands that incorporate unsanitized input from
  /// an untrusted source makes a program vulnerable to shell injection, a
  /// serious security flaw which can result in arbitrary command execution. For
  /// this reason, the use of shell is strongly discouraged in cases where the
  /// command string is constructed from external input. 
  Shell(String)
  /// Command is passed to `execve(3)` library call directly without involving
  /// the shell process, so the list of strings represents the program to be
  /// executed with arguments. In this case all shell-based features are disabled
  /// and there's no shell injection vulnerability.
  Execve(List(String))
}

pub type EnvOption {
  EnvString(String)
  EnvClear
  EnvKV(String, String)
  EnvUnset(String)
}

pub type EnvOptions =
  List(EnvOption)

pub type StdoutOptions {
  StdoutCapture
  StdoutClose
  StdoutFun(fn(Atom, Int, String) -> Nil)
  StdoutNull
  StdoutPid(Pid)
  StdoutPrint
  StdoutStderr
  StdoutString(String)
}

pub type StderrOptions {
  StderrCapture
  StderrClose
  StderrFun(fn(Atom, Int, String) -> Nil)
  StderrNull
  StderrPid(Pid)
  StderrPrint
  StderrStdout
  StderrString(String)
}

pub type PtyOptions {
  PtyEnable
  PtyOpts(List(PtyOption))
}

/// For documentation please check:
/// - [termios(3)](https://man7.org/linux/man-pages/man3/termios.3.html)
/// - [RFC4254](https://datatracker.ietf.org/doc/html/rfc4254#section-8)
pub type PtyOption {
  // tty_char
  Vintr(Int)
  Vquit(Int)
  Verase(Int)
  Vkill(Int)
  Veof(Int)
  Veol(Int)
  Veol2(Int)
  Vstart(Int)
  Vstop(Int)
  Vsusp(Int)
  Vdsusp(Int)
  Vreprint(Int)
  Vwerase(Int)
  Vlnext(Int)
  Vflush(Int)
  Vswtch(Int)
  Vstatus(Int)
  Vdiscard(Int)
  // tty_mode
  Ignpar(Bool)
  Parmrk(Bool)
  Inpck(Bool)
  Istrip(Bool)
  Inlcr(Bool)
  Igncr(Bool)
  Icrnl(Bool)
  Xcase(Bool)
  Iuclc(Bool)
  Ixon(Bool)
  Ixany(Bool)
  Ixoff(Bool)
  Imaxbel(Bool)
  Iutf8(Bool)
  Isig(Bool)
  Icanon(Bool)
  Echo(Bool)
  Echoe(Bool)
  Echok(Bool)
  Echonl(Bool)
  Noflsh(Bool)
  Tostop(Bool)
  Iexten(Bool)
  Echoctl(Bool)
  Echoke(Bool)
  Pendin(Bool)
  Opost(Bool)
  Olcuc(Bool)
  Onlcr(Bool)
  Ocrnl(Bool)
  Onocr(Bool)
  Onlret(Bool)
  Cs7(Bool)
  Cs8(Bool)
  Parenb(Bool)
  Parodd(Bool)
  // tty_speed
  TtyOpIspeed(Int)
  TtyOpOspeed(Int)
}

pub type StdinOptions {
  // Close the `stdin` stream
  StdinClose
  // Redirect from `/dev/null`
  StdinNull
  // Enable communication with an OS process via its `stdin`.
  // The input to the process is sent by `exec.send(OsPid, String)`.
  StdinPipe
  // Take input from a file.
  StdinFrom(String)
}

type WinszOptions {
  PseudoTerminalSize(rows: Int, columns: Int)
}

/// Set the global debug level
@external(erlang, "exec", "debug")
pub fn debug(level: Int) -> Result(Int, Atom)

pub type StartError {
  AlreadyStarted(Pid)
}

pub type StartOption {
  StartDebug(level: Int)
  StartRoot(enable: Bool)
  StartVerbose
  StartArgs(List(String))
  StartAlarm(seconds: Int)
  StartUser(String)
  StartLimitUsers(List(String))
  StartPortexe(String)
  StartEnv(EnvOptions)
}

@external(erlang, "exec", "start")
fn do_exec_start(a: List(Dynamic)) -> Result(Pid, StartError)

/// Start the `exec` application
pub fn start(options: List(StartOption)) -> Result(Pid, StartError) {
  do_exec_start(start_options_to_list(options))
}

fn start_options_to_list(options) {
  options
  |> list.map(fn(o) {
    case o {
      StartDebug(v) -> from(#(Debug, v))
      StartAlarm(v) -> from(#(Alarm, v))
      StartArgs(v) -> from(#(Args, v))
      StartLimitUsers(v) -> from(#(LimitUsers, v))
      StartPortexe(v) -> from(#(Portexe, v))
      StartRoot(v) -> from(#(Root, v))
      StartUser(v) -> from(#(User, v))
      StartVerbose -> from(Verbose)
      StartEnv(v) -> env_to_dynamic(v)
    }
  })
}

pub type StopError {
  NoProcess
}

/// Terminate a managed `Pid`, `OsPid`, or Port process.
/// The OS process is terminated gracefully. If it was given a `{kill, Cmd}`
/// option at startup, that command is executed and a timer is started. If the
/// program doesn't exit, then the default termination is performed. Default
/// termination implies sending a `SIGTERM` command followed by a `SIGKILL` in 5
/// seconds, if the program doesn't get killed.
@external(erlang, "glexec_ffi", "stop")
pub fn stop(pid: Int) -> Result(Nil, String)

@external(erlang, "exec", "manage")
fn do_manage(a: Dynamic, b: List(Dynamic), c: Int) -> Dynamic

pub fn manage_pid(pid: Pid, options: Options) {
  do_manage(from(pid), options_to_list(options), options.timeout)
}

/// Get a list of children OsPids managed by the port program.
@external(erlang, "exec", "which_children")
pub fn which_children() -> List(OsPid)

@external(erlang, "glexec_ffi", "kill")
fn do_kill(a: Dynamic, b: Int) -> Result(Nil, Dynamic)

/// Send a signal to a child Pid.
pub fn kill_pid(pid: Pid, signal: Int) -> Result(Nil, Dynamic) {
  do_kill(from(pid), signal)
}

/// Send a signal to an OsPid.
pub fn kill_ospid(ospid: OsPid, signal: Int) -> Result(Nil, Dynamic) {
  do_kill(from(ospid), signal)
}

/// Set up a monitor for the spawned process.
///
/// The monitor is not a standard `erlang:monitor/2` function call, but
/// it's emulated by ensuring that the monitoring process receives
/// notifications in the form:
/// `{'DOWN', OsPid::integer(), process, Pid::pid(), Reason}`.
///
/// If the `Reason` is `normal`, then process exited with status `0`,
/// otherwise there was an error. If the Reason is `{status, Status}` the
/// returned `Status` can be decoded with the [status](#status) function to
/// determine the exit code of the process and if it was killed by signal.
pub fn with_monitor(old: Options, given: Bool) -> Options {
  Options(..old, monitor: given)
}

pub fn get_monitor(options: Options) {
  options.monitor
}

fn set_monitor(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.monitor {
    True -> [from(Monitor), ..old]
    False -> old
  }
}

pub fn with_verbose(old: Options, enabled: Bool) -> Options {
  Options(..old, verbose: Some(enabled))
}

fn set_sync(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.sync {
    True -> [from(Sync), ..old]
    False -> old
  }
}

/// Link to the OsPid. If OsPid exits, the calling process will be killed or if
/// it's trapping exits, it'll get {'EXIT', OsPid, Status} message.  If the
/// calling process dies the OsPid will be killed.
/// The `Status` can be decoded with [status](#status) to determine the
/// process's exit code and if it was killed by signal.
pub fn with_link(old: Options, given: Bool) -> Options {
  Options(..old, link: given)
}

pub fn get_link(options: Options) {
  options.link
}

fn set_link(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.link {
    True -> [from(Link), ..old]
    False -> old
  }
}

/// Specifies a replacement program to execute.
///
/// It is very seldom needed. When the port program executes a child process
/// using `execve(3)` call, the call takes the following arguments:
/// `(executable, args, env)`.
/// When the `command` argument is specified as the list of strings, the
/// executable replaces the first parameter in the call, and the original
/// `args` provided in the `command` parameter are passed as as the second
/// parameter.
/// Most programs treat the program specified by `args` as the command name,
/// which can then be different from the program actually executed.
/// 
/// ### Unix specific:
///
/// The `args` name becomes the display name for the executable in utilities
/// such as `ps`.
///
/// If the `command` argument is a Shell, the `Executable` specifies a
/// replacement shell for the default `/bin/sh`.
pub fn with_executable(old: Options, given: String) -> Options {
  Options(..old, executable: Some(given))
}

pub fn get_executable(options: Options) {
  options.executable
}

fn set_executable(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.executable {
    Some(executable) -> [from(#(Executable, executable)), ..old]
    None -> old
  }
}

/// Set a working directory
pub fn with_cd(old: Options, given: String) -> Options {
  Options(..old, cd: Some(given))
}

pub fn get_cd(options: Options) {
  options.cd
}

fn set_cd(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.cd {
    Some(cd) -> [from(#(Cd, cd)), ..old]
    None -> old
  }
}

/// Modify the program environment. See [EnvOption](#EnvOption)
pub fn with_env(old: Options, given: EnvOptions) -> Options {
  Options(..old, env: given)
}

pub fn get_env(options: Options) {
  options.env
}

fn set_env(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case list.length(option.env) {
    0 -> old
    _ -> [env_to_dynamic(option.env), ..old]
  }
}

fn env_to_dynamic(env: EnvOptions) {
  from(#(Env, list.map(env, env_element_to_dynamic)))
}

fn env_element_to_dynamic(element) {
  case element {
    EnvString(s) -> from(s)
    EnvClear -> from(Clear)
    EnvKV(k, v) -> from(#(k, v))
    EnvUnset(k) -> from(#(k, False))
  }
}

/// Configure `stdout` communication with the OS process.
/// See [StdoutOptions](#StdoutOptions)
pub fn with_stdout(old: Options, given: StdoutOptions) -> Options {
  Options(..old, stdout: Some(given))
}

pub fn get_stdout(options: Options) {
  options.stdout
}

fn set_stdout(old: List(Dynamic), option: Options) -> List(Dynamic) {
  let stdout = atom.create_from_string("stdout")
  let stderr = atom.create_from_string("stderr")
  case option.stdout {
    Some(value) -> [
      case value {
        StdoutCapture -> from(stdout)
        StdoutNull -> from(#(stdout, Null))
        StdoutClose -> from(#(stdout, Close))
        StdoutPid(pid) -> from(#(stdout, pid))
        StdoutPrint -> from(#(stdout, Print))
        StdoutStderr -> from(#(stdout, stderr))
        StdoutString(s) -> from(#(stdout, s))
        StdoutFun(f) -> from(#(stdout, f))
      },
      ..old
    ]
    None -> old
  }
}

/// Configure `stderr` communication with the OS process.
/// See [StderrOptions](#StderrOptions)
pub fn with_stderr(old: Options, given: StderrOptions) -> Options {
  Options(..old, stderr: Some(given))
}

pub fn get_stderr(options: Options) {
  options.stderr
}

fn set_stderr(old: List(Dynamic), option: Options) -> List(Dynamic) {
  let stdout = atom.create_from_string("stdout")
  let stderr = atom.create_from_string("stderr")
  case option.stderr {
    Some(value) -> [
      case value {
        StderrCapture -> from(stderr)
        StderrNull -> from(#(stderr, Null))
        StderrClose -> from(#(stderr, Close))
        StderrPid(pid) -> from(#(stderr, pid))
        StderrPrint -> from(#(stderr, Print))
        StderrStdout -> from(#(stderr, stdout))
        StderrString(s) -> from(#(stderr, s))
        StderrFun(f) -> from(#(stderr, f))
      },
      ..old
    ]
    None -> old
  }
}

/// Configure `stdin` communication with the OS process.
/// See [StdinOptions](#StdinOptions)
pub fn with_stdin(old: Options, given: StdinOptions) -> Options {
  Options(..old, stdin: Some(given))
}

pub fn get_stdin(options: Options) {
  options.stdin
}

fn set_stdin(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.stdin {
    Some(stdin) -> [
      case stdin {
        StdinClose -> from(#(Stdin, Close))
        StdinNull -> from(#(Stdin, Null))
        StdinPipe -> from(Stdin)
        StdinFrom(s) -> from(#(Stdin, s))
      },
      ..old
    ]
    None -> old
  }
}

/// Use pseudo terminal for the process's stdin, stdout and stderr
pub fn with_pty(old: Options, enable_pty: Bool) -> Options {
  Options(..old, pty: enable_pty)
}

pub fn get_pty(options: Options) {
  options.pty
}

fn set_pty(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.pty {
    True -> [from(Pty), ..old]
    False -> old
  }
}

/// This command will be used for killing the process.
///
/// If the process is still alive after 5 seconds, it receives a `SIGKILL`.
///
/// The kill command will have a `CHILD_PID` environment variable set to the
/// pid of the process it is expected to kill.
///
/// If the `kill` option is not specified, by default first the command is sent
/// a `SIGTERM` signal, followed by `SIGKILL` after a default timeout.
pub fn with_kill(old: Options, command: String) -> Options {
  Options(..old, kill: Some(command))
}

pub fn get_kill(options: Options) {
  options.kill
}

fn set_kill(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.kill {
    Some(kill) -> [from(#(Kill, kill)), ..old]
    None -> old
  }
}

/// Number of seconds to wait after issuing a SIGTERM or
/// executing the custom `kill` command (if specified) before
/// killing the process with the `SIGKILL` signal
pub fn with_kill_timeout(old: Options, given: Int) -> Options {
  Options(..old, kill_timeout: Some(given))
}

fn set_kill_timeout(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.kill_timeout {
    Some(kill_timeout) -> [from(#(KillTimeout, kill_timeout)), ..old]
    None -> old
  }
}

/// Sets the effective group ID of the spawned process. The value `0` means to
/// create a new group ID equal to the OS pid of the process.
pub fn with_group(old: Options, given: Int) -> Options {
  Options(..old, group: Some(given))
}

fn set_group(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.group {
    Some(group) -> [from(#(Group, group)), ..old]
    None -> old
  }
}

/// When `exec-port` was compiled with capability (Linux) support enabled
/// and has a suid bit set, it's capable of running commands with a
/// different effective user. The value "root" is prohibited.
pub fn with_user(old: Options, given: String) -> Options {
  Options(..old, user: Some(given))
}

fn set_user(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.user {
    Some(user) -> [from(#(User, user)), ..old]
    None -> old
  }
}

// Set the (psudo) terminal's dimensions.
pub fn with_winsz(old: Options, rows: Int, columns: Int) -> Options {
  Options(..old, winsz: Some(PseudoTerminalSize(rows: rows, columns: columns)))
}

fn set_winsz(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.winsz {
    Some(PseudoTerminalSize(rows: rows, columns: columns)) -> [
      from(#(Winsz, #(rows, columns))),
      ..old
    ]
    None -> old
  }
}

@external(erlang, "glexec_ffi", "winsz")
fn do_winsz(a: Int, b: Int, c: Int) -> Result(Nil, Nil)

pub fn winsz(pid, rows, columns) -> Result(Nil, Nil) {
  do_winsz(pid, rows, columns)
}

/// Set process priority between `-20` and `20`. Note that negative values
/// can be specified only when `exec-port` is started with a root suid bit
/// set.
pub fn with_nice(old: Options, priority: Int) -> Options {
  Options(..old, nice: Some(priority))
}

fn set_nice(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.nice {
    Some(nice) -> [from(#(Nice, nice)), ..old]
    None -> old
  }
}

/// Configure debug printing for this command.
///
/// The `level` should be `0 <= level =< 10`
pub fn with_debug(old: Options, level: Int) -> Options {
  Options(..old, debug: Some(level))
}

fn set_debug(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.debug {
    Some(debug) -> [from(#(Debug, debug)), ..old]
    None -> old
  }
}

/// Return value on success.
pub fn with_success_exit_code(old: Options, given: Int) -> Options {
  Options(..old, success_exit_code: Some(given))
}

fn set_success_exit_code(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.success_exit_code {
    Some(success_exit_code) -> [
      from(#(SuccessExitCode, success_exit_code)),
      ..old
    ]
    None -> old
  }
}

/// At process exit kill the whole process group associated with this pid.
/// The process group is obtained by the call to `getpgid(3)`.
pub fn with_kill_group(old: Options, given: Bool) -> Options {
  Options(..old, kill_group: given)
}

fn set_kill_group(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.kill_group {
    True -> [from(KillGroup), ..old]
    False -> old
  }
}

/// Allow the pty to run in echo mode, disabled by default.
pub fn with_pty_echo(old: Options, given: Bool) -> Options {
  Options(..old, pty_echo: given)
}

fn set_pty_echo(old: List(Dynamic), option: Options) -> List(Dynamic) {
  case option.pty_echo {
    True -> [from(PtyEcho), ..old]
    False -> old
  }
}

pub type Pids {
  /// `Pid` is the Erlang process identifier.
  /// `OsPid` is the OS process identifier of the new process.
  Pids(Pid, OsPid)
}

pub type Output {
  Output(List(StdoutOrStderr))
}

pub type StdoutOrStderr {
  Stdout(List(String))
  Stderr(List(String))
}

@external(erlang, "glexec_ffi", "run")
fn do_run_async(a: Dynamic, b: List(Dynamic), c: Int) -> Result(Pids, String)

@external(erlang, "glexec_ffi", "run")
fn do_run_sync(a: Dynamic, b: List(Dynamic), c: Int) -> Result(Output, String)

/// Run command with the given options, don't wait for it to finish.
pub fn run_async(options: Options, command: Command) -> Result(Pids, String) {
  let cmd_options = options_to_list(Options(..options, sync: False))
  case command {
    Execve(cmd) -> do_run_async(from(cmd), cmd_options, options.timeout)
    Shell(cmd) -> do_run_async(from(cmd), cmd_options, options.timeout)
  }
}

/// Run command with the given options, block the caller until it exits.
pub fn run_sync(options: Options, command: Command) -> Result(Output, String) {
  let cmd_options = options_to_list(Options(..options, sync: True))
  case command {
    Execve(cmd) -> do_run_sync(from(cmd), cmd_options, options.timeout)
    Shell(cmd) -> do_run_sync(from(cmd), cmd_options, options.timeout)
  }
}

pub fn options_to_list(options: Options) -> List(Dynamic) {
  let setters = [
    set_monitor,
    set_sync,
    set_link,
    set_executable,
    set_cd,
    set_env,
    set_group,
    set_kill,
    set_kill_timeout,
    set_kill_group,
    set_group,
    set_user,
    set_nice,
    set_success_exit_code,
    set_stdout,
    set_stdin,
    set_stderr,
    set_winsz,
    set_pty,
    set_pty_echo,
    set_debug,
  ]

  setters
  |> list.fold([], fn(acc, fun) {
    acc
    |> fun(options)
  })
}

@external(erlang, "glexec_ffi", "send")
fn do_send(a: OsPid, b: String) -> Result(Nil, Dynamic)

pub fn send(ospid: OsPid, data: String) -> Result(Nil, Dynamic) {
  do_send(ospid, data)
}

type Eof {
  Eof
}

@external(erlang, "glexec_ffi", "send")
fn do_send_eof(a: OsPid, b: Eof) -> Result(Nil, Dynamic)

/// This will close `stdin`.
pub fn send_eof(ospid: OsPid) -> Result(Nil, Dynamic) {
  do_send_eof(ospid, Eof)
}

@external(erlang, "glexec_ffi", "ospid")
fn do_ospid(a: Pid) -> Result(OsPid, Dynamic)

pub fn to_ospid(ospid: Pid) -> Result(OsPid, Dynamic) {
  do_ospid(ospid)
}

pub type FindExecutableError {
  ExecutableNotFound
}

/// Tries to find the given executable name and returns the full path to it.
@external(erlang, "glexec_ffi", "find_executable")
pub fn find_executable(name: String) -> Result(String, FindExecutableError)

pub type ExitStatusOrSignal {
  ExitStatus(Int)
  Signal(
    // The exit status
    status: Signal,
    // Whether a core file was generated
    core_dump: Bool,
  )
}

@external(erlang, "erlang", "band")
fn and(a: Int, b: Int) -> Int

@external(erlang, "erlang", "bsr")
fn bsr(a: Int, b: Int) -> Int

///  Decode the program's exit_status.
///
///  If the program exited by signal the function returns [Signal](#Signal),
///  otherwise it will return an [ExitStatus](#ExitStatus)
pub fn status(status: Int) -> ExitStatusOrSignal {
  let term_signal = and(status, 0x7f)
  let if_signaled = bsr(term_signal + 1, 1) > 0
  case if_signaled {
    True ->
      Signal(
        status: int_to_signal(term_signal),
        core_dump: and(status, 0x80) == 0x80,
      )
    False -> ExitStatus(bsr(and(status, 0xFF00), 8))
  }
}

pub type Signal {
  SIGHUP
  SIGINT
  SIGQUIT
  SIGILL
  SIGTRAP
  SIGABRT
  SIGBUS
  SIGFPE
  SIGKILL
  SIGUSR1
  SIGSEGV
  SIGUSR2
  SIGPIPE
  SIGALRM
  SIGTERM
  SIGSTKFLT
  SIGCHLD
  SIGCONT
  SIGSTOP
  SIGTSTP
  SIGTTIN
  SIGTTOU
  SIGURG
  SIGXCPU
  SIGXFSZ
  SIGVTALRM
  SIGPROF
  SIGWINCH
  SIGIO
  SIGPWR
  SIGSYS
  Other(Int)
}

pub fn signal_to_int(signal: Signal) -> Int {
  case signal {
    SIGHUP -> 1
    SIGINT -> 2
    SIGQUIT -> 3
    SIGILL -> 4
    SIGTRAP -> 5
    SIGABRT -> 6
    SIGBUS -> 7
    SIGFPE -> 8
    SIGKILL -> 9
    SIGUSR1 -> 10
    SIGSEGV -> 11
    SIGUSR2 -> 12
    SIGPIPE -> 13
    SIGALRM -> 14
    SIGTERM -> 15
    SIGSTKFLT -> 16
    SIGCHLD -> 17
    SIGCONT -> 18
    SIGSTOP -> 19
    SIGTSTP -> 20
    SIGTTIN -> 21
    SIGTTOU -> 22
    SIGURG -> 23
    SIGXCPU -> 24
    SIGXFSZ -> 25
    SIGVTALRM -> 26
    SIGPROF -> 27
    SIGWINCH -> 28
    SIGIO -> 29
    SIGPWR -> 30
    SIGSYS -> 31
    Other(other) -> other
  }
}

pub fn int_to_signal(signal: Int) -> Signal {
  case signal {
    1 -> SIGHUP
    2 -> SIGINT
    3 -> SIGQUIT
    4 -> SIGILL
    5 -> SIGTRAP
    6 -> SIGABRT
    7 -> SIGBUS
    8 -> SIGFPE
    9 -> SIGKILL
    10 -> SIGUSR1
    11 -> SIGSEGV
    12 -> SIGUSR2
    13 -> SIGPIPE
    14 -> SIGALRM
    15 -> SIGTERM
    16 -> SIGSTKFLT
    17 -> SIGCHLD
    18 -> SIGCONT
    19 -> SIGSTOP
    20 -> SIGTSTP
    21 -> SIGTTIN
    22 -> SIGTTOU
    23 -> SIGURG
    24 -> SIGXCPU
    25 -> SIGXFSZ
    26 -> SIGVTALRM
    27 -> SIGPROF
    28 -> SIGWINCH
    29 -> SIGIO
    30 -> SIGPWR
    31 -> SIGSYS
    other -> Other(other)
  }
}

pub type ObtainOk {
  ObtainStdout(Int, String)
  ObtainStderr(Int, String)
}

pub type ObtainError {
  ObtainTimeout
  ObtainDownStatus(Pid, OsPid, Int)
  ObtainDownNormal(Pid, OsPid)
  ObtainDownNoproc(Pid, OsPid)
}

// a wrapper around `receive`.
@external(erlang, "glexec_ffi", "obtain")
pub fn obtain(timeout_in_milliseconds: Int) -> Result(ObtainOk, ObtainError)
