-module(glexec_ffi).
-export([
    stop/1,
    send/2,
    run/3,
    ospid/1,
    find_executable/1,
    kill/2,
    obtain/1,
    stop_and_wait/1,
    winsz/3
]).

winsz(Pid, Rows, Columns) ->
    case exec:winsz(Pid, Rows, Columns) of
        ok -> {ok, nil};
        Error -> Error
    end.

stop(Pid) ->
    case exec:stop(Pid) of
        ok -> {ok, nil};
        {error, Error} -> {error, binary:list_to_bin(Error)};
        Error -> Error
    end.

stop_and_wait(Pid) ->
    case exec:stop_and_wait(Pid) of
        ok -> {ok, nil};
        Error -> Error
    end.

send(OsPid, Data) ->
    case exec:send(OsPid, Data) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason};
        Other -> {error, Other}
    end.

run(Exe, Options, Timeout) ->
    case exec:run(Exe, Options, Timeout) of
        {ok, Pid, OsPid} -> {ok, {pids, Pid, OsPid}};
        {ok, List} -> {ok, {output, List}};
        Error -> Error
    end.

ospid(Pid) ->
    case exec:ospid(Pid) of
        {error, Reason} -> {error, Reason};
        OsPid -> {ok, OsPid}
    end.

find_executable(Name) ->
    case os:find_executable(binary:bin_to_list(Name)) of
        false -> {error, executable_not_found};
        Found -> {ok, Found}
    end.

kill(Pid, Signal) ->
    case exec:kill(Pid, Signal) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

obtain(Timeout) ->
    receive
        {stdout, OsPid, Data} ->
            {ok, {obtain_stdout, OsPid, Data}};
        {stderr, OsPid, Data} ->
            {ok, {obtain_stderr, OsPid, Data}};
        {'DOWN', OsPid, process, Pid, normal} ->
            {error, {obtain_down_normal, Pid, OsPid}};
        {'DOWN', OsPid, process, Pid, noproc} ->
            {error, {obtain_down_noproc, Pid, OsPid}};
        {'DOWN', OsPid, process, Pid, {status, Status}} ->
            {error, {obtain_down_status, Pid, OsPid, Status}}
    after Timeout ->
        case flush() of
            [] -> {error, obtain_timeout};
            LL -> {error, LL}
        end
    end.

flush() ->
    receive
        B -> [B | flush()]
    after 0 ->
        []
    end.
