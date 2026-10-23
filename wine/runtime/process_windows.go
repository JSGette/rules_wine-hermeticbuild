package main

import (
 "os"
 "os/exec"
)

func isolate(cmd *exec.Cmd) {}
func terminate(cmd *exec.Cmd) { _ = cmd.Process.Kill() }
func cancellationSignals() []os.Signal { return []os.Signal{os.Interrupt} }
func signalNumber(sig os.Signal) int { return 2 }
func setupReaper() {}
func reapChildren() {}
