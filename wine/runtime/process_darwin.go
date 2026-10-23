package main

import (
	"os"
	"os/exec"
	"syscall"
)

func isolate(cmd *exec.Cmd)   { cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} }
func terminate(cmd *exec.Cmd) { _ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
func cancellationSignals() []os.Signal {
	return []os.Signal{syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP}
}
func signalNumber(sig os.Signal) int { return int(sig.(syscall.Signal)) }
func setupReaper()                   {}
func reapChildren()                  {}

func processExitStatus(state *os.ProcessState) int {
	if status, ok := state.Sys().(syscall.WaitStatus); ok && status.Signaled() {
		return 128 + int(status.Signal())
	}
	return state.ExitCode()
}
