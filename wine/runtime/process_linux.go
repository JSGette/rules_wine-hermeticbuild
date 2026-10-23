package main

import (
 "os"
 "os/exec"
 "syscall"
)

func isolate(cmd *exec.Cmd) { cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} }
func terminate(cmd *exec.Cmd) { _ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
func cancellationSignals() []os.Signal { return []os.Signal{syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP} }
func signalNumber(sig os.Signal) int { return int(sig.(syscall.Signal)) }
func setupReaper() { _, _, _ = syscall.Syscall6(syscall.SYS_PRCTL, 36, 1, 0, 0, 0, 0) }
func reapChildren() { for { var status syscall.WaitStatus; pid, _ := syscall.Wait4(-1, &status, syscall.WNOHANG, nil); if pid <= 0 { return } } }
